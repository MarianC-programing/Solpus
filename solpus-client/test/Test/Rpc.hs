{-# LANGUAGE OverloadedStrings #-}

module Test.Rpc (tests) where

import Control.Exception (toException)
import Control.Monad (void)
import Data.ByteString qualified as BS
import Data.Either (isRight)
import Data.Text (Text)
import Data.Text qualified as T
import Hedgehog (annotateShow, forAll, property, (===))
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import Network.HTTP.Client (HttpException (..), HttpExceptionContent (..), parseRequest)
import Network.JsonRpc.TinyClient qualified as JR
import Network.Solana.Core.Crypto (mkPublicKeyFromString)
import Network.Web3.Provider (Web3Error (..))
import Solpus.Client.Class (MonadSolanaRead (..))
import Solpus.Client.Config (mkConfig)
import Solpus.Client.Rpc
import Solpus.Core.Error (SolpusError (..))
import Solpus.Core.Types (Address, Commitment (..), addressFromBytes, addressText)
import Solpus.Core.Validate (parseAddress)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, assertFailure, testCase, (@?=))
import Test.Tasty.Hedgehog (testProperty)

base58Alphabet :: String
base58Alphabet = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"

secretUrl :: String
secretUrl = "https://nodo.example.com/v1/S3CR3T-PATH?api-key=S3CR3T-KEY"

-- | Un texto de error no debe contener nada de la URL del nodo.
leaksUrl :: Text -> Bool
leaksUrl t = any (`T.isInfixOf` t) ["S3CR3T", "nodo.example.com", "api-key", "https://"]

testAddress :: Address
testAddress = case addressFromBytes (BS.replicate 32 7) of
  Right a -> a
  Left e -> error ("dirección de prueba inválida: " <> show e)

tests :: TestTree
tests = testGroup "Rpc" [jsonRpcTests, httpTests, web3Tests, sdkParityTests, realCallTests]

jsonRpcTests :: TestTree
jsonRpcTests =
  testGroup
    "classifyJsonRpc"
    [ testCase "un error del nodo conserva código y mensaje" $
        classifyJsonRpc (JR.CallException (JR.RpcError (-32002) "Transaction simulation failed" Nothing))
          @?= RpcError (-32002) "Transaction simulation failed"
    , testCase "una respuesta ilegible es InvalidResponse" $
        classifyJsonRpc (JR.ParsingException "no es JSON") @?= InvalidResponse "no es JSON"
    , testCase "el texto que viene del nodo se acota a 200 caracteres" $
        case classifyJsonRpc (JR.ParsingException (replicate 5000 'x')) of
          InvalidResponse t -> T.length t @?= 200
          other -> assertFailure ("se esperaba InvalidResponse, llegó " <> show other)
    ]

httpTests :: TestTree
httpTests =
  testGroup
    "classifyHttp"
    [ testCase "ningún fallo de red incluye la URL ni su clave" $ do
        request <- parseRequest secretUrl
        let contents =
              [ ConnectionTimeout
              , ResponseTimeout
              , ConnectionFailure (toException (userError secretUrl))
              , TlsNotSupported
              , InternalException (toException (userError secretUrl))
              , NoResponseDataReceived
              , ConnectionClosed
              ]
        mapM_
          ( \content -> case classifyHttp (HttpExceptionRequest request content) of
              NetworkFailure t -> assertBool ("filtra la URL: " <> T.unpack t) (not (leaksUrl t))
              other -> assertFailure ("se esperaba NetworkFailure, llegó " <> show other)
          )
          contents
    , testCase "una URL inválida tampoco se incluye" $
        case classifyHttp (InvalidUrlException secretUrl "motivo") of
          NetworkFailure t -> assertBool ("filtra la URL: " <> T.unpack t) (not (leaksUrl t))
          other -> assertFailure ("se esperaba NetworkFailure, llegó " <> show other)
    , testCase "los textos distinguen timeout de conexión rechazada" $ do
        request <- parseRequest secretUrl
        classifyHttp (HttpExceptionRequest request ResponseTimeout)
          @?= NetworkFailure "el nodo no respondió a tiempo"
        classifyHttp (HttpExceptionRequest request (ConnectionFailure (toException (userError "x"))))
          @?= NetworkFailure "no se pudo conectar con el nodo"
    ]

web3Tests :: TestTree
web3Tests =
  testGroup
    "classifyWeb3"
    [ testCase "los tres errores del proveedor son InvalidResponse" $ do
        classifyWeb3 (JsonRpcFail "a") @?= InvalidResponse "fallo JSON-RPC: a"
        classifyWeb3 (ParserFail "b") @?= InvalidResponse "respuesta ilegible: b"
        classifyWeb3 (UserFail "c") @?= InvalidResponse "fallo del proveedor: c"
    ]

-- | Contraste de mi base58 con el parser del SDK (criterio del spike #4).
sdkParityTests :: TestTree
sdkParityTests =
  testGroup
    "paridad con el SDK"
    [ testProperty "el SDK lee mi codificación y la muestra igual" $ property $ do
        bytes <- forAll (Gen.bytes (Range.singleton 32))
        case addressFromBytes bytes of
          Left e -> fail (show e)
          Right a -> do
            let text = T.unpack (addressText a)
            fmap show (mkPublicKeyFromString text) === Right text
    , testProperty "acepto y rechazo lo mismo que el SDK (alfabeto base58)" $ property $ do
        t <- forAll (Gen.text (Range.linear 0 60) (Gen.element base58Alphabet))
        agree t
    , testProperty "acepto y rechazo lo mismo que el SDK (texto arbitrario)" $ property $ do
        t <- forAll (Gen.text (Range.linear 0 100) Gen.unicode)
        agree t
    , testProperty "las claves de 32 bytes cualesquiera, incluidas las que no están en la curva" $ property $ do
        bytes <- forAll (Gen.bytes (Range.singleton 32))
        let text = T.unpack (either (const "") addressText (addressFromBytes bytes))
        isRight (mkPublicKeyFromString text) === True
    ]
 where
  agree t = do
    let ours = parseAddress t
        theirs = mkPublicKeyFromString (T.unpack t)
    annotateShow (void ours, fmap show theirs)
    isRight ours === isRight theirs
    case (ours, theirs) of
      (Right a, Right k) -> show k === T.unpack (addressText a)
      _ -> pure ()

-- | Llamadas reales a un nodo inalcanzable: no necesitan validador ni internet.
realCallTests :: TestTree
realCallTests =
  testGroup
    "getBalance sin nodo"
    [ testCase "puerto cerrado: NetworkFailure" $ do
        result <- balanceAt "http://127.0.0.1:9"
        case result of
          Left (NetworkFailure _) -> pure ()
          other -> assertFailure ("se esperaba NetworkFailure, llegó " <> show other)
    , testCase "host que no existe: NetworkFailure sin filtrar la clave de API" $ do
        result <- balanceAt "https://nodo-inexistente.invalid/v1/S3CR3T-PATH?api-key=S3CR3T-KEY"
        case result of
          Left (NetworkFailure t) -> assertBool ("filtra la URL: " <> T.unpack t) (not (leaksUrl t))
          other -> assertFailure ("se esperaba NetworkFailure, llegó " <> show other)
    ]
 where
  balanceAt url = case mkConfig url Confirmed 3 of
    Left e -> assertFailure ("configuración inválida: " <> show e)
    Right config -> do
      env <- newEnv config
      runSolpusIO env (getBalance testAddress)
