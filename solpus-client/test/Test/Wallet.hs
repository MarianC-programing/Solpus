{-# LANGUAGE OverloadedStrings #-}

module Test.Wallet (tests, withTestWallet) where

import Control.Exception (bracket)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BC
import Data.List (intercalate, isInfixOf)
import Hedgehog (forAll, property, (===))
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import Network.Solana.Core.Crypto
  ( createSolanaKeypairFromSeed
  , getSolanaPrivateKeyRaw
  , toBase58String
  )
import Solpus.Client.Wallet
import Solpus.Core.Error (SolpusError (..), WalletError (..))
import Solpus.Core.Types (addressBytes)
import System.Directory (createDirectory, removeDirectoryRecursive)
import System.Environment (setEnv, unsetEnv)
import System.FilePath ((</>))
import System.Posix.Files (createSymbolicLink, setFileMode)
import System.Posix.Temp (mkdtemp)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, assertFailure, testCase, (@?=))
import Test.Tasty.Hedgehog (testProperty)

-- | Clave de prueba con una semilla fija; nunca se usa fuera de las pruebas.
secretBytes :: ByteString
secretBytes = case createSolanaKeypairFromSeed (BS.pack [100 .. 131]) of
  Just (_, sk) -> getSolanaPrivateKeyRaw sk
  Nothing -> error "semilla de prueba inválida"

json :: ByteString -> String
json bytes = "[" <> intercalate "," (map show (BS.unpack bytes)) <> "]"

validJson :: String
validJson = json secretBytes

-- | Textos que no deben aparecer en ningún error ni en el 'show' de la wallet.
sentinels :: [String]
sentinels =
  [ validJson
  , toBase58String secretBytes
  , toBase58String (BS.take 32 secretBytes)
  , intercalate "," (map show (BS.unpack (BS.take 8 secretBytes)))
  ]

-- | Ejecuta una acción con una wallet cargada desde un archivo temporal válido.
withTestWallet :: (Wallet -> IO a) -> IO a
withTestWallet action = withTempDir $ \dir -> do
  let path = dir </> "id.json"
  writeKey path validJson
  loadWalletFile path >>= either (assertFailure . show) action

withTempDir :: (FilePath -> IO a) -> IO a
withTempDir = bracket (mkdtemp "/tmp/solpus-wallet-") removeDirectoryRecursive

writeKey :: FilePath -> String -> IO ()
writeKey path text = BC.writeFile path (BC.pack text) >> setFileMode path 0o600

expectError :: WalletError -> Either SolpusError a -> IO ()
expectError wanted result = case result of
  Left (WalletFailed got) -> got @?= wanted
  Left other -> assertFailure ("error inesperado: " <> show other)
  Right _ -> assertFailure "se esperaba un error y se cargó la wallet"

assertNoLeak :: String -> IO ()
assertNoLeak text =
  assertBool
    ("la salida contiene un secreto: " <> take 40 text)
    (not (any (`isInfixOf` text) sentinels))

tests :: TestTree
tests =
  testGroup
    "Wallet"
    [ fileTests
    , formatTests
    , envTests
    , leakTests
    , testGroup
        "parseKeyBytes"
        [ testProperty "es total y solo devuelve 64 bytes" $ property $ do
            junk <- forAll (Gen.bytes (Range.linear 0 400))
            case parseKeyBytes junk of
              Nothing -> pure ()
              Just out -> BS.length out === 64
        , testProperty "recupera los bytes de cualquier arreglo bien formado" $ property $ do
            bytes <- forAll (Gen.bytes (Range.singleton 64))
            parseKeyBytes (BC.pack (json bytes)) === Just bytes
        ]
    ]

fileTests :: TestTree
fileTests =
  testGroup
    "archivo"
    [ testCase "0600 y 0400 se cargan y la dirección es la mitad pública" $
        withTempDir $ \dir -> do
          let path = dir </> "id.json"
          writeKey path validJson
          r1 <- loadWalletFile path
          fmap (addressBytes . walletAddress) r1 @?= Right (BS.drop 32 secretBytes)
          setFileMode path 0o400
          r2 <- loadWalletFile path
          fmap (addressBytes . walletAddress) r2 @?= Right (BS.drop 32 secretBytes)
    , testCase "permisos de grupo, otros o ejecución se rechazan" $
        withTempDir $ \dir -> do
          let path = dir </> "id.json"
          writeKey path validJson
          mapM_
            ( \mode -> do
                setFileMode path mode
                loadWalletFile path >>= expectError WalletInsecurePermissions
            )
            [0o644, 0o640, 0o660, 0o604, 0o606, 0o700, 0o601, 0o666]
    , testCase "un enlace simbólico se rechaza aunque apunte a un archivo válido" $
        withTempDir $ \dir -> do
          let target = dir </> "id.json"
              link = dir </> "link.json"
          writeKey target validJson
          createSymbolicLink target link
          loadWalletFile link >>= expectError WalletNotRegularFile
    , testCase "un directorio se rechaza" $
        withTempDir $ \dir -> do
          let sub = dir </> "carpeta"
          createDirectory sub
          loadWalletFile sub >>= expectError WalletNotRegularFile
    , testCase "un archivo ausente da WalletFileNotFound" $
        withTempDir $
          \dir -> loadWalletFile (dir </> "no-existe.json") >>= expectError WalletFileNotFound
    , testCase "un archivo demasiado grande se rechaza" $
        withTempDir $ \dir -> do
          let path = dir </> "id.json"
          writeKey path (validJson <> replicate (maxKeyFileBytes + 10) ' ')
          loadWalletFile path >>= expectError WalletFileTooLarge
    ]

formatTests :: TestTree
formatTests =
  testGroup
    "formato del contenido"
    [ testCase "contenido inválido da WalletInvalidFormat" $
        withTempDir $ \dir -> do
          let path = dir </> "id.json"
              bad =
                [ ""
                , "no es json"
                , "[]"
                , json (BS.take 63 secretBytes)
                , json (secretBytes <> BS.pack [1])
                , "[" <> intercalate "," (replicate 63 "1" <> ["256"]) <> "]"
                , "[" <> intercalate "," (replicate 63 "1" <> ["-1"]) <> "]"
                , "[" <> intercalate "," (replicate 63 "1" <> ["1.5"]) <> "]"
                , validJson <> " basura"
                , "[" <> intercalate "," (replicate 63 "1" <> ["007"]) <> "]"
                ]
          mapM_ (\text -> writeKey path text >> loadWalletFile path >>= expectError WalletInvalidFormat) bad
    , testCase "una mitad pública que no corresponde da WalletKeyMismatch" $
        withTempDir $ \dir -> do
          let path = dir </> "id.json"
              wrong = BS.take 32 secretBytes <> BS.replicate 32 7
          writeKey path (json wrong)
          loadWalletFile path >>= expectError WalletKeyMismatch
    ]

envTests :: TestTree
envTests =
  testGroup
    "variable de entorno"
    [ testCase "ausente da WalletEnvNotSet" $ do
        unsetEnv varName
        loadWalletEnv varName >>= expectError WalletEnvNotSet
    , testCase "un arreglo válido se carga" $ do
        setEnv varName validJson
        result <- loadWalletEnv varName
        unsetEnv varName
        fmap (addressBytes . walletAddress) result @?= Right (BS.drop 32 secretBytes)
    , testCase "contenido inválido, no ASCII o excesivo se rechaza" $ do
        mapM_
          ( \(text, wanted) -> do
              setEnv varName text
              result <- loadWalletEnv varName
              unsetEnv varName
              expectError wanted result
          )
          [ ("no es json", WalletInvalidFormat)
          , ("[1,2,3]", WalletInvalidFormat)
          , ("[é]", WalletInvalidFormat)
          , (replicate (maxKeyFileBytes + 1) ' ', WalletFileTooLarge)
          ]
    ]
 where
  varName = "SOLPUS_TEST_WALLET_KEY"

leakTests :: TestTree
leakTests =
  testGroup
    "no filtración"
    [ testCase "ningún error ni el show de la wallet contiene la clave" $
        withTempDir $ \dir -> do
          let path = dir </> "id.json"
          writeKey path validJson
          Right wallet <- loadWalletFile path
          assertNoLeak (show wallet)
          assertNoLeak (show (walletAddress wallet))
          -- Todas las rutas de error, con el secreto presente en la entrada.
          setFileMode path 0o644
          errs1 <- loadWalletFile path
          assertNoLeak (either show (const "") errs1)
          writeKey path (validJson <> " basura")
          loadWalletFile path >>= assertNoLeak . either show (const "")
          writeKey path (json (BS.take 32 secretBytes <> BS.replicate 32 7))
          loadWalletFile path >>= assertNoLeak . either show (const "")
          setEnv "SOLPUS_TEST_WALLET_LEAK" (validJson <> "x")
          loadWalletEnv "SOLPUS_TEST_WALLET_LEAK" >>= assertNoLeak . either show (const "")
          unsetEnv "SOLPUS_TEST_WALLET_LEAK"
    , testCase "los errores no contienen la ruta del archivo" $
        withTempDir $ \dir -> do
          let path = dir </> "id.json"
          writeKey path "no es json"
          result <- loadWalletFile path
          assertBool "el error contiene la ruta" (not (dir `isInfixOf` either show (const "") result))
    ]
