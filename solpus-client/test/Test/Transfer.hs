{-# LANGUAGE OverloadedStrings #-}

module Test.Transfer (tests) where

import Control.Concurrent (forkIO, killThread)
import Control.Exception (bracket, finally)
import Control.Monad (forever)
import Crypto.Sign.Ed25519 qualified as Ed
import Data.Bits (shiftR)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BC
import Data.IORef (IORef, modifyIORef', newIORef, readIORef)
import Data.List (isInfixOf)
import Data.Maybe (fromMaybe)
import Data.Text qualified as T
import Network.Socket
  ( Family (AF_INET)
  , SockAddr (SockAddrInet)
  , Socket
  , SocketOption (ReuseAddr)
  , SocketType (Stream)
  , accept
  , bind
  , close
  , defaultProtocol
  , listen
  , setSocketOption
  , socket
  , socketPort
  , tupleToHostAddress
  )
import Network.Socket.ByteString (recv, sendAll)
import Network.Solana.Core.Block (BlockHash (..))
import Network.Solana.Core.Crypto (fromBase64String, toBase58String)
import Solpus.Client.Class (MonadSolana (..), Transfer (..))
import Solpus.Client.Config (Config (..), mkConfig)
import Solpus.Client.Rpc (mainnetGenesisHash, newEnvWith, runSolpusIO)
import Solpus.Client.Tx (SignedTransfer (..), buildTransfer)
import Solpus.Client.Wallet (Wallet, walletAddress)
import Solpus.Core.Error (SolpusError (..), ValidationError (..), WalletError (..))
import Solpus.Core.Lamports (Lamports (..))
import Solpus.Core.Types (Commitment (..), addressBytes, addressFromBytes, signatureText)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, assertFailure, testCase, (@?=))
import Test.Wallet (withTestWallet)

-- ---------------------------------------------------------------------------
-- Nodo falso: un servidor HTTP local que habla lo justo de JSON-RPC.

-- | Método, cuerpo de cada petición recibida, en orden de llegada.
type Seen = IORef [(String, String)]

{- | Arranca un nodo falso. El manejador recibe el método y el cuerpo; si
devuelve 'Nothing', cierra la conexión sin responder (un fallo de red).
-}
withFakeNode :: (String -> String -> Maybe String) -> (Config -> Seen -> IO a) -> IO a
withFakeNode handler action = bracket open close $ \sock -> do
  port <- socketPort sock
  seen <- newIORef []
  tid <- forkIO (forever (serve sock seen))
  config <-
    either (fail . show) pure (mkConfig (T.pack ("http://127.0.0.1:" <> show port)) Confirmed 5)
  action config seen `finally` killThread tid
 where
  open = do
    sock <- socket AF_INET Stream defaultProtocol
    setSocketOption sock ReuseAddr 1
    bind sock (SockAddrInet 0 (tupleToHostAddress (127, 0, 0, 1)))
    listen sock 8
    pure sock
  serve :: Socket -> Seen -> IO ()
  serve sock seen = do
    (conn, _) <- accept sock
    _ <- forkIO $ (`finally` close conn) $ do
      body <- BC.unpack <$> readRequest conn
      let method = fieldOf "\"method\":\"" body
      modifyIORef' seen (<> [(method, body)])
      case handler method body of
        Nothing -> pure ()
        Just reply ->
          sendAll conn . BC.pack $
            "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nConnection: close\r\nContent-Length: "
              <> show (length reply)
              <> "\r\n\r\n"
              <> reply
    pure ()

readRequest :: Socket -> IO ByteString
readRequest conn = go BS.empty
 where
  go acc = do
    chunk <- recv conn 4096
    let acc' = acc <> chunk
    if BS.null chunk || complete acc' then pure acc' else go acc'
  complete bytes =
    let (headers, rest) = BS.breakSubstring "\r\n\r\n" bytes
     in not (BS.null rest) && BS.length rest - 4 >= contentLength (BC.unpack headers)
  contentLength headers = case fieldOf "ontent-Length: " headers of
    "" -> 0
    n -> read (takeWhile (`elem` ['0' .. '9']) n)

-- | El texto que sigue a un marcador, hasta la siguiente comilla o salto.
fieldOf :: String -> String -> String
fieldOf marker text = case breakOn marker text of
  Nothing -> ""
  Just rest -> takeWhile (`notElem` ['"', '\r', '\n']) rest
 where
  breakOn needle haystack
    | needle `isInfixOf` take (length needle) haystack = Just (drop (length needle) haystack)
    | null haystack = Nothing
    | otherwise = breakOn needle (tail haystack)

rpcResult :: String -> String
rpcResult result = "{\"jsonrpc\":\"2.0\",\"result\":" <> result <> ",\"id\":1}"

rpcError :: Int -> String -> String
rpcError code message =
  "{\"jsonrpc\":\"2.0\",\"error\":{\"code\":"
    <> show code
    <> ",\"message\":\""
    <> message
    <> "\"},\"id\":1}"

blockhashText :: String
blockhashText = toBase58String (BS.replicate 32 5)

lastValid :: Int
lastValid = 4242

-- | Genesis hash de un validador local (distinto del de mainnet).
localGenesis :: String
localGenesis = toBase58String (BS.replicate 32 3)

-- | Firma de la transacción que viene en una petición @sendTransaction@.
signatureInRequest :: String -> String
signatureInRequest body =
  toBase58String (BS.take 64 (BS.drop 1 (fromBase64String (fieldOf "\"params\":[\"" body))))

-- | Un nodo local que acepta todo y devuelve la firma que le llega.
healthy :: String -> String -> Maybe String
healthy method body = case method of
  "getGenesisHash" -> Just (rpcResult ("\"" <> localGenesis <> "\""))
  "getLatestBlockhash" ->
    Just
      ( rpcResult
          ( "{\"context\":{\"slot\":1},\"value\":{\"blockhash\":\""
              <> blockhashText
              <> "\",\"lastValidBlockHeight\":"
              <> show lastValid
              <> "}}"
          )
      )
  "sendTransaction" -> Just (rpcResult ("\"" <> signatureInRequest body <> "\""))
  _ -> Nothing

methods :: Seen -> IO [String]
methods seen = map fst <$> readIORef seen

-- ---------------------------------------------------------------------------

other :: Transfer -> Transfer
other t = t{transferFrom = either (error . show) id (addressFromBytes (BS.replicate 32 9))}

mkTransfer :: Wallet -> Transfer
mkTransfer wallet =
  Transfer
    { transferFrom = walletAddress wallet
    , transferTo = either (error . show) id (addressFromBytes (BS.replicate 32 8))
    , transferAmount = Lamports 1_500_000
    }

submit :: Config -> Maybe Wallet -> Transfer -> IO (Either SolpusError String)
submit config wallet transfer = do
  env <- newEnvWith config wallet
  fmap (fmap (T.unpack . signatureText)) (runSolpusIO env (submitTransfer transfer))

tests :: TestTree
tests =
  testGroup
    "Transferencias"
    [ buildTests
    , guardTests
    , sendTests
    ]

buildTests :: TestTree
buildTests =
  testGroup
    "buildTransfer"
    [ testCase "la transacción contiene origen, destino e importe, y la firma es válida" $
        withTestWallet $ \wallet -> do
          let transfer = mkTransfer wallet
          signed <-
            either (assertFailure . show) pure (buildTransfer wallet (BlockHash (BS.replicate 32 5)) transfer)
          let raw = fromBase64String (signedPayload signed)
              signature = BS.take 64 (BS.drop 1 raw)
              message = BS.drop 65 raw
              amount = BS.pack [fromIntegral ((1_500_000 :: Integer) `shiftR` (8 * i)) | i <- [0 .. 7]]
              instructionData = BS.pack [2, 0, 0, 0] <> amount
          assertBool "falta el origen" (addressBytes (transferFrom transfer) `BS.isInfixOf` message)
          assertBool "falta el destino" (addressBytes (transferTo transfer) `BS.isInfixOf` message)
          assertBool "falta el importe" (instructionData `BS.isInfixOf` message)
          assertBool "la firma no es válida" $
            Ed.dverify (Ed.PublicKey (addressBytes (walletAddress wallet))) message (Ed.Signature signature)
          signatureText (signedSignature signed) @?= T.pack (toBase58String signature)
    , testCase "un origen distinto de la wallet se rechaza antes de firmar" $
        withTestWallet $ \wallet ->
          either
            (@?= ValidationFailed TransferSourceNotWallet)
            (const (assertFailure "debía fallar"))
            (buildTransfer wallet (BlockHash (BS.replicate 32 5)) (other (mkTransfer wallet)))
    , testCase "un importe cero se rechaza" $
        withTestWallet $ \wallet ->
          either
            (@?= ValidationFailed ZeroAmount)
            (const (assertFailure "debía fallar"))
            ( buildTransfer
                wallet
                (BlockHash (BS.replicate 32 5))
                ((mkTransfer wallet){transferAmount = Lamports 0})
            )
    , testCase "otro blockhash da otra firma" $
        withTestWallet $ \wallet -> do
          let sign' h =
                either
                  (error . show)
                  (signatureText . signedSignature)
                  (buildTransfer wallet (BlockHash (BS.replicate 32 h)) (mkTransfer wallet))
          assertBool "las firmas coinciden" (sign' 5 /= sign' 6)
    ]

guardTests :: TestTree
guardTests =
  testGroup
    "guardia y comprobaciones previas"
    [ testCase "sin wallet: WalletNotLoaded, sin tocar la red" $
        withTestWallet $ \wallet -> withFakeNode healthy $ \config seen -> do
          r <- submit config Nothing (mkTransfer wallet)
          r @?= Left (WalletFailed WalletNotLoaded)
          methods seen >>= (@?= [])
    , testCase "origen distinto de la wallet: error de validación, sin tocar la red" $
        withTestWallet $ \wallet -> withFakeNode healthy $ \config seen -> do
          r <- submit config (Just wallet) (other (mkTransfer wallet))
          r @?= Left (ValidationFailed TransferSourceNotWallet)
          methods seen >>= (@?= [])
    , testCase "genesis de mainnet: MainnetRefused y nunca se envía" $
        withTestWallet $ \wallet ->
          withFakeNode
            ( \m b ->
                if m == "getGenesisHash" then Just (rpcResult ("\"" <> mainnetGenesisHash <> "\"")) else healthy m b
            )
            $ \config seen -> do
              r <- submit config (Just wallet) (mkTransfer wallet)
              r @?= Left MainnetRefused
              methods seen >>= (@?= ["getGenesisHash"])
    , testCase "con permiso expreso no se consulta el genesis" $
        withTestWallet $ \wallet ->
          withFakeNode
            ( \m b ->
                if m == "getGenesisHash" then Just (rpcResult ("\"" <> mainnetGenesisHash <> "\"")) else healthy m b
            )
            $ \config seen -> do
              r <- submit config{configAllowMainnet = True} (Just wallet) (mkTransfer wallet)
              assertBool ("debía enviar: " <> show r) (either (const False) (const True) r)
              methods seen >>= (@?= ["getLatestBlockhash", "sendTransaction"])
    , testCase "si no se puede comprobar la red, no se envía" $
        withTestWallet $ \wallet ->
          withFakeNode (\m b -> if m == "getGenesisHash" then Nothing else healthy m b) $ \config seen -> do
            r <- submit config (Just wallet) (mkTransfer wallet)
            assertBool ("debía fallar: " <> show r) (either (const True) (const False) r)
            methods seen >>= (\ms -> assertBool "se envió igualmente" ("sendTransaction" `notElem` ms))
    , testCase "el genesis de mainnet configurado en el código es el publicado" $
        mainnetGenesisHash @?= "5eykt4UsFv8P8NJdTREpY1vzqKqZKvdpKuc147dw2N9d"
    ]

sendTests :: TestTree
sendTests =
  testGroup
    "envío"
    [ testCase "camino feliz: orden de llamadas, commitment confirmed y firma coherente" $
        withTestWallet $ \wallet -> withFakeNode healthy $ \config seen -> do
          r <- submit config (Just wallet) (mkTransfer wallet)
          sig <- either (\e -> assertFailure (show e) >> pure "") pure r
          calls <- readIORef seen
          map fst calls @?= ["getGenesisHash", "getLatestBlockhash", "sendTransaction"]
          let body m = fromMaybe "" (lookup m calls)
          assertBool
            "el blockhash no se pidió a confirmed"
            ("\"commitment\":\"confirmed\"" `isInfixOf` body "getLatestBlockhash")
          assertBool
            "el preflight no es confirmed"
            ("\"preflightCommitment\":\"confirmed\"" `isInfixOf` body "sendTransaction")
          sig @?= signatureInRequest (body "sendTransaction")
    , testCase "conexión cortada tras enviar: SubmissionUncertain con firma y altura, sin reintento" $
        withTestWallet $ \wallet ->
          withFakeNode (\m b -> if m == "sendTransaction" then Nothing else healthy m b) $ \config seen -> do
            r <- submit config (Just wallet) (mkTransfer wallet)
            calls <- readIORef seen
            case r of
              Left (SubmissionUncertain sig height) -> do
                height @?= fromIntegral lastValid
                T.unpack sig @?= signatureInRequest (fromMaybe "" (lookup "sendTransaction" calls))
              other' -> assertFailure ("se esperaba SubmissionUncertain: " <> show other')
            length (filter ((== "sendTransaction") . fst) calls) @?= 1
    , testCase "respuesta ilegible tras enviar: también incierto" $
        withTestWallet $ \wallet ->
          withFakeNode (\m b -> if m == "sendTransaction" then Just "esto no es json" else healthy m b) $ \config _ -> do
            r <- submit config (Just wallet) (mkTransfer wallet)
            assertBool ("se esperaba SubmissionUncertain: " <> show r) $ case r of
              Left (SubmissionUncertain _ _) -> True
              _ -> False
    , testCase "preflight rechazado por el nodo: RpcError, no incierto, un solo envío" $
        withTestWallet $ \wallet ->
          withFakeNode
            ( \m b ->
                if m == "sendTransaction"
                  then Just (rpcError (-32002) "Transaction simulation failed")
                  else healthy m b
            )
            $ \config seen -> do
              r <- submit config (Just wallet) (mkTransfer wallet)
              case r of
                Left (RpcError code _) -> code @?= (-32002)
                other' -> assertFailure ("se esperaba RpcError: " <> show other')
              calls <- readIORef seen
              length (filter ((== "sendTransaction") . fst) calls) @?= 1
    , testCase "firma del nodo distinta de la calculada: InternalError" $
        withTestWallet $ \wallet ->
          withFakeNode
            ( \m b ->
                if m == "sendTransaction"
                  then Just (rpcResult ("\"" <> toBase58String (BS.replicate 64 1) <> "\""))
                  else healthy m b
            )
            $ \config _ -> do
              r <- submit config (Just wallet) (mkTransfer wallet)
              assertBool ("se esperaba InternalError: " <> show r) $ case r of
                Left (InternalError _) -> True
                _ -> False
    ]
