{-# LANGUAGE OverloadedStrings #-}

module Test.Validate (tests) where

import Data.ByteString qualified as BS
import Data.Either (isLeft)
import Data.Text (Text)
import Data.Text qualified as T
import Hedgehog (forAll, property, (===))
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import Solpus.Core.Error (ValidationError (..))
import Solpus.Core.Lamports (Lamports (..), renderSol)
import Solpus.Core.Types
  ( addressBytes
  , addressFromBytes
  , addressText
  , signatureBytes
  )
import Solpus.Core.Validate
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, testCase, (@?=))
import Test.Tasty.Hedgehog (testProperty)

base58Alphabet :: String
base58Alphabet = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"

tests :: TestTree
tests = testGroup "Validate" [addressTests, signatureTests, solTests, lamportTests]

addressTests :: TestTree
addressTests =
  testGroup
    "parseAddress"
    [ testCase "System Program (32 unos) son 32 bytes cero" $
        fmap addressBytes (parseAddress (T.replicate 32 "1")) @?= Right (BS.replicate 32 0)
    , testCase "carácter fuera del alfabeto" $
        parseAddress (T.replicate 32 "0") @?= Left InvalidBase58
    , testCase "longitud incorrecta" $ do
        parseAddress "1" @?= Left (InvalidByteLength 32 1)
        parseAddress "" @?= Left (InvalidByteLength 32 0)
    , testCase "texto demasiado largo se rechaza antes de decodificar" $
        parseAddress (T.replicate 45 "1") @?= Left (InputTooLong 44)
    , testProperty "dirección -> texto -> dirección" $ property $ do
        bytes <- forAll (Gen.bytes (Range.singleton 32))
        case addressFromBytes bytes of
          Left e -> fail (show e)
          Right a -> parseAddress (addressText a) === Right a
    , testProperty "todo lo que se acepta vuelve al mismo texto" $ property $ do
        t <- forAll (Gen.text (Range.linear 0 60) (Gen.element base58Alphabet))
        case parseAddress t of
          Right a -> addressText a === t
          Left _ -> pure ()
    , testProperty "nunca falla con texto arbitrario" $ property $ do
        t <- forAll (Gen.text (Range.linear 0 200) Gen.unicode)
        case parseAddress t of
          Left _ -> pure ()
          Right a -> addressText a === t
    ]

signatureTests :: TestTree
signatureTests =
  testGroup
    "parseSignature"
    [ testCase "64 unos son 64 bytes cero" $
        fmap signatureBytes (parseSignature (T.replicate 64 "1")) @?= Right (BS.replicate 64 0)
    , testCase "una dirección no es una firma" $
        parseSignature (T.replicate 32 "1") @?= Left (InvalidByteLength 64 32)
    , testCase "texto demasiado largo" $
        parseSignature (T.replicate 89 "1") @?= Left (InputTooLong 88)
    ]

solTests :: TestTree
solTests =
  testGroup
    "parseSolAmount"
    [ testCase "valores válidos" $ do
        parseSolAmount "1" @?= Right (Lamports 1_000_000_000)
        parseSolAmount "1.5" @?= Right (Lamports 1_500_000_000)
        parseSolAmount "0.000000001" @?= Right (Lamports 1)
        parseSolAmount "0" @?= Right (Lamports 0)
        parseSolAmount "007.10" @?= Right (Lamports 7_100_000_000)
    , testCase "límite superior exacto" $
        parseSolAmount "18446744073.709551615" @?= Right (Lamports maxBound)
    , testCase "un lamport por encima del límite" $
        parseSolAmount "18446744073.709551616" @?= Left AmountOverflow
    , testCase "demasiados decimales" $
        parseSolAmount "0.0000000001" @?= Left (TooManyDecimals 9)
    , testCase "sintaxis inválida" $
        mapM_
          (\t -> parseSolAmount t @?= Left InvalidAmountSyntax)
          ["", ".", ".5", "1.", "-1", "+1", "1e3", "1.5.2", " 1", "1 ", "\65297"]
    , testCase "entrada demasiado larga" $
        parseSolAmount (T.replicate 41 "1") @?= Left (InputTooLong 40)
    , testProperty "el formato de salida se puede volver a leer" $ property $ do
        w <- forAll (Gen.word64 Range.constantBounded)
        let l = Lamports w
        parseSolAmount (T.dropEnd 4 (renderSol l)) === Right l
    ]

lamportTests :: TestTree
lamportTests =
  testGroup
    "parseLamports"
    [ testCase "valores válidos" $ do
        parseLamports "0" @?= Right (Lamports 0)
        parseLamports "1500" @?= Right (Lamports 1500)
        parseLamports "18446744073709551615" @?= Right (Lamports maxBound)
    , testCase "desbordamiento" $
        parseLamports "18446744073709551616" @?= Left AmountOverflow
    , testCase "sintaxis inválida" $
        mapM_
          (\t -> parseLamports t @?= Left InvalidAmountSyntax)
          ["", "-1", "1.5", "abc", " 1"]
    , testCase "entrada demasiado larga" $
        parseLamports (T.replicate 41 "1") @?= Left (InputTooLong 40)
    , testProperty "entero -> texto -> entero" $ property $ do
        w <- forAll (Gen.word64 Range.constantBounded)
        parseLamports (T.pack (show w)) === Right (Lamports w)
    , testCase "los errores son valores, no excepciones" $
        assertBool "debería ser Left" (isLeft (parseLamports ("x" :: Text)))
    ]
