{-# LANGUAGE OverloadedStrings #-}

{- | Pruebas de integración contra @solana-test-validator@.

Se omiten salvo con @SOLANA_INTEGRATION=1@ (no hay validador en CI). La
propia suite arranca y detiene el validador, porque su RPC escucha en
@0.0.0.0@ y no debe quedarse abierto. Variables:

* @SOLANA_INTEGRATION=1@: activa la suite.
* @SOLANA_TEST_VALIDATOR@: ruta al binario (por defecto, el del @PATH@).

Usa los puertos 8899 (RPC) y 8900 (WebSocket). Si ya hay un nodo en 8899,
aborta en lugar de mezclar pruebas con un estado ajeno.
-}
module Main (main) where

import Control.Concurrent (threadDelay)
import Control.Exception (SomeException, try)
import Control.Monad (when)
import Data.Either (isRight)
import Data.Maybe (fromMaybe)
import Data.Text qualified as T
import Data.Time.Clock.POSIX (getPOSIXTime)
import Network.Solana.Core.Crypto (SolanaPublicKey, SolanaSignature, createSolanaKeyPair)
import Network.Solana.RPC.HTTP.Account qualified as SDK (getBalance)
import Network.Solana.RPC.HTTP.Transaction (requestAirdrop)
import Network.Solana.RPC.WebSocket
import Network.Web3.Provider (Provider (HttpProvider), runWeb3')
import Network.WebSockets qualified as WS
import Solpus.Client.Class (MonadSolanaRead (..))
import Solpus.Client.Config (Config (..), localConfig)
import Solpus.Client.Rpc
import Solpus.Core.Error (SolpusError)
import Solpus.Core.Lamports (Lamports (..))
import Solpus.Core.Types (Address, Commitment (..))
import Solpus.Core.Validate (parseAddress)
import System.Directory (createDirectory, getTemporaryDirectory, removeDirectoryRecursive)
import System.Environment (lookupEnv)
import System.Exit (exitFailure, exitSuccess)
import System.FilePath ((</>))
import System.IO (IOMode (WriteMode), hPutStrLn, hSetEncoding, openFile, stderr, stdout, utf8)
import System.Process
  ( CreateProcess (..)
  , ProcessHandle
  , StdStream (..)
  , createProcess
  , getCurrentPid
  , getProcessExitCode
  , proc
  , terminateProcess
  , waitForProcess
  )
import Test.Tasty (TestTree, defaultMain, localOption, testGroup, withResource)
import Test.Tasty.HUnit (assertBool, assertFailure, testCase, (@?=))
import Test.Tasty.Runners (NumThreads (..))

-- | Un validador en marcha y dónde está su ledger.
data Validator = Validator ProcessHandle FilePath

rpcUrl :: String
rpcUrl = "http://127.0.0.1:8899"

provider :: Provider
provider = HttpProvider rpcUrl

main :: IO ()
main = do
  hSetEncoding stdout utf8
  enabled <- lookupEnv "SOLANA_INTEGRATION"
  case enabled of
    Just "1" -> run
    _ -> do
      putStrLn "Pruebas de integración omitidas (define SOLANA_INTEGRATION=1 para ejecutarlas)."
      exitSuccess

run :: IO ()
run = do
  confirmedEnv <- newEnv localConfig
  finalizedEnv <- newEnv localConfig{configCommitment = Finalized}
  defaultMain $
    localOption (NumThreads 1) $
      withResource (startValidator confirmedEnv) stopValidator $ \_ ->
        tests confirmedEnv finalizedEnv

tests :: Env -> Env -> TestTree
tests confirmedEnv finalizedEnv =
  testGroup
    "integración (validador local)"
    [ testCase "una cuenta nunca usada tiene saldo cero" $ do
        (_, address) <- newKey
        balanceOf confirmedEnv address >>= (@?= Right (Lamports 0))
    , testCase "el saldo a confirmed es correcto justo tras confirmar un airdrop" $ do
        (key, address) <- newKey
        signature <- airdrop key 2_000_000_000
        awaitConfirmed signature
        -- El caso que motivó la llamada propia a getBalance (issue #7).
        balanceOf confirmedEnv address >>= (@?= Right (Lamports 2_000_000_000))
        -- Informativo: lo que habría devuelto el getBalance del SDK, que no
        -- admite commitment, y una lectura de este cliente a finalized.
        sdkDefault <- runWeb3' provider (SDK.getBalance key)
        putStrLn ("  [informativo] getBalance del SDK justo después: " <> show sdkDefault)
        finalizedNow <- balanceOf finalizedEnv address
        putStrLn ("  [informativo] lectura a finalized justo después: " <> show finalizedNow)
    , testCase "tras finalizar, la lectura a finalized coincide con la de confirmed" $ do
        (key, address) <- newKey
        signature <- airdrop key 1_000_000_000
        awaitConfirmed signature
        eventually 60 $ do
          finalized <- balanceOf finalizedEnv address
          pure (finalized == Right (Lamports 1_000_000_000))
        balanceOf confirmedEnv address >>= (@?= Right (Lamports 1_000_000_000))
    ]

-- | Clave nueva del SDK y su dirección en el dominio de Solpus.
newKey :: IO (SolanaPublicKey, Address)
newKey = do
  (key, _secret) <- createSolanaKeyPair
  case parseAddress (T.pack (show key)) of
    Left err -> assertFailure ("dirección generada inválida: " <> show err)
    Right address -> pure (key, address)

balanceOf :: Env -> Address -> IO (Either SolpusError Lamports)
balanceOf env address = runSolpusIO env (getBalance address)

airdrop :: SolanaPublicKey -> Integer -> IO SolanaSignature
airdrop key lamports = do
  result <- runWeb3' provider (requestAirdrop key (fromInteger lamports))
  either (\e -> assertFailure ("airdrop falló: " <> show e)) pure result

-- | Espera por WebSocket a que la firma llegue a @confirmed@.
awaitConfirmed :: SolanaSignature -> IO ()
awaitConfirmed signature = do
  result <- WS.runClient "127.0.0.1" 8900 "/" $ \connection ->
    awaitSignature
      (WsTransport (WS.sendTextData connection) (WS.receiveData connection))
      (RequestId 1)
      (Just "confirmed")
      30
      signature
  either (\e -> assertFailure ("no se confirmó la firma: " <> show e)) (const (pure ())) result

-- | Repite una comprobación cada segundo hasta que sea cierta o se agote el plazo.
eventually :: Int -> IO Bool -> IO ()
eventually seconds check
  | seconds <= 0 = assertFailure "la condición no se cumplió a tiempo"
  | otherwise = do
      ok <- check
      if ok then pure () else threadDelay 1_000_000 >> eventually (seconds - 1) check

-- | Arranca un validador con un ledger desechable y espera a que responda.
startValidator :: Env -> IO Validator
startValidator env = do
  occupied <- isRight <$> balanceOf env probeAddress
  when occupied $ do
    hPutStrLn stderr "Ya hay un nodo escuchando en 127.0.0.1:8899; no se arranca otro."
    exitFailure
  binary <- fromMaybe "solana-test-validator" <$> lookupEnv "SOLANA_TEST_VALIDATOR"
  tmp <- getTemporaryDirectory
  pid <- getCurrentPid
  now <- getPOSIXTime
  let dir = tmp </> ("solpus-it-" <> show pid <> "-" <> show (round now :: Integer))
  createDirectory dir
  logHandle <- openFile (dir </> "validator.log") WriteMode
  (_, _, _, handle) <-
    createProcess
      (proc binary ["--ledger", dir </> "ledger", "--reset", "--quiet"])
        { std_in = NoStream
        , std_out = UseHandle logHandle
        , std_err = UseHandle logHandle
        }
  let validator = Validator handle dir
  ready <- waitReady handle
  if ready
    then pure validator
    else do
      stopValidator validator
      assertFailure ("el validador no respondió a tiempo; log en " <> (dir </> "validator.log"))
 where
  probeAddress = either (error . show) id (parseAddress "11111111111111111111111111111111")
  waitReady handle = go (90 :: Int)
   where
    go 0 = pure False
    go n = do
      exited <- getProcessExitCode handle
      case exited of
        Just _ -> pure False
        Nothing -> do
          up <- isRight <$> balanceOf env probeAddress
          if up then pure True else threadDelay 1_000_000 >> go (n - 1)

-- | Detiene el validador y borra su ledger.
stopValidator :: Validator -> IO ()
stopValidator (Validator handle dir) = do
  terminateProcess handle
  _ <- waitForProcess handle
  cleanup <- try (removeDirectoryRecursive dir) :: IO (Either SomeException ())
  assertBool "no se pudo borrar el ledger temporal" (isRight cleanup)
