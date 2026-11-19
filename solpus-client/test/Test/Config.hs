{-# LANGUAGE OverloadedStrings #-}

module Test.Config (tests) where

import Data.List (isInfixOf)
import Data.Text (Text)
import Data.Text qualified as T
import Hedgehog (annotateShow, forAll, property, (===))
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import Solpus.Client.Config
import Solpus.Core.Error (ValidationError (..))
import Solpus.Core.Types (Commitment (..))
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, testCase, (@?=))
import Test.Tasty.Hedgehog (testProperty)

accepted :: [Text]
accepted =
  [ "https://api.devnet.solana.com"
  , "https://host.example:8443/path?api-key=SECRET"
  , "http://localhost:8899"
  , "http://127.0.0.1:8899"
  , "http://[::1]:8899"
  , "https://[2001:db8::1]:443/"
  , "https://a-b.example.com/"
  ]

rejected :: [Text]
rejected =
  [ ""
  , "ftp://host"
  , "api.devnet.solana.com"
  , "http://api.mainnet-beta.solana.com"
  , "http://10.0.0.5:8899"
  , "https://user:pass@host.example"
  , "https://token@host.example"
  , "https://"
  , "https://:8899"
  , "https://host.example:0"
  , "https://host.example:65536"
  , "https://host.example:abc"
  , "https://host.example:123456"
  , "https://ho st.example"
  , "https://h\243st.example"
  , "HTTPS://host.example"
  , "http://[::1"
  , "http://[]:8899"
  , "https://.host.example"
  , "https://host.example."
  , "https://host.example/\n"
  , T.replicate 2049 "a"
  ]

tests :: TestTree
tests = testGroup "Config" [endpointTests, configTests]

endpointTests :: TestTree
endpointTests =
  testGroup
    "Endpoint"
    [ testCase "acepta URLs razonables" $
        mapM_ (\u -> fmap endpointText (mkEndpoint u) @?= Right u) accepted
    , testCase "rechaza URLs inválidas o inseguras" $
        mapM_ (\u -> fmap endpointText (mkEndpoint u) @?= Left InvalidEndpoint) rejected
    , testCase "el error no conserva el texto rechazado" $
        show (mkEndpoint "https://user:SECRET@host.example") @?= "Left InvalidEndpoint"
    , testCase "Show enseña el origen y oculta ruta y consulta" $ do
        fmap show (mkEndpoint "https://host.example:8443/v1/SECRETPATH?api-key=SECRETKEY")
          @?= Right "Endpoint \"https://host.example:8443/...\""
        fmap show (mkEndpoint "https://host.example") @?= Right "Endpoint \"https://host.example\""
    , testProperty "una clave en la ruta o la consulta nunca sale por Show" $ property $ do
        suffix <- forAll (Gen.text (Range.linear 4 20) Gen.alphaNum)
        let secret = "S3CR3T" <> suffix
            url = "https://node.example.com/" <> secret <> "?api-key=" <> secret
        annotateShow url
        case mkEndpoint url of
          Left e -> fail (show e)
          Right endpoint -> do
            (T.unpack secret `isInfixOf` show endpoint) === False
            (T.unpack secret `isInfixOf` show (Config endpoint Confirmed 5 False)) === False
            endpointText endpoint === url
    ]

configTests :: TestTree
configTests =
  testGroup
    "Config"
    [ testCase "mkConfig acepta timeouts en el rango" $ do
        fmap configTimeoutSeconds (mkConfig "http://localhost:8899" Confirmed 1) @?= Right 1
        fmap configTimeoutSeconds (mkConfig "http://localhost:8899" Confirmed 300) @?= Right 300
    , testCase "mkConfig rechaza timeouts fuera del rango" $ do
        fmap configTimeoutSeconds (mkConfig "http://localhost:8899" Confirmed 0)
          @?= Left (InvalidTimeout 1 300)
        fmap configTimeoutSeconds (mkConfig "http://localhost:8899" Confirmed 301)
          @?= Left (InvalidTimeout 1 300)
        fmap configTimeoutSeconds (mkConfig "http://localhost:8899" Confirmed (-5))
          @?= Left (InvalidTimeout 1 300)
    , testCase "mkConfig valida el endpoint antes que el timeout" $
        fmap configTimeoutSeconds (mkConfig "ftp://x" Confirmed 0) @?= Left InvalidEndpoint
    , testCase "localConfig apunta al validador local con confirmed" $ do
        endpointText (configEndpoint localConfig) @?= "http://127.0.0.1:8899"
        configCommitment localConfig @?= Confirmed
        assertBool "timeout dentro del rango" $
          configTimeoutSeconds localConfig >= minTimeoutSeconds
            && configTimeoutSeconds localConfig <= maxTimeoutSeconds
    ]
