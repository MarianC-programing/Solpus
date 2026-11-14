{-# LANGUAGE OverloadedStrings #-}

module Test.Base58 (tests) where

import Data.ByteString qualified as BS
import Data.Text qualified as T
import Hedgehog (forAll, property, (===))
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import Solpus.Core.Base58 (decodeBase58, encodeBase58)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=))
import Test.Tasty.Hedgehog (testProperty)

tests :: TestTree
tests =
  testGroup
    "Base58"
    [ testCase "vector conocido: Hello World!" $
        encodeBase58 (BS.pack [72, 101, 108, 108, 111, 32, 87, 111, 114, 108, 100, 33])
          @?= "2NEpo7TZRRrLZSi2U"
    , testCase "ceros iniciales" $ do
        encodeBase58 (BS.pack [0, 0, 1]) @?= "112"
        decodeBase58 "112" @?= Just (BS.pack [0, 0, 1])
    , testCase "entrada vacía" $ do
        encodeBase58 BS.empty @?= ""
        decodeBase58 "" @?= Just BS.empty
    , testCase "32 ceros: dirección del System Program" $
        encodeBase58 (BS.replicate 32 0) @?= T.replicate 32 "1"
    , testCase "rechaza 0, O, I, l, espacios y no ASCII" $
        mapM_ (\t -> decodeBase58 t @?= Nothing) ["0", "O", "I", "l", "1 2", "\233"]
    , testProperty "ida y vuelta" $ property $ do
        bytes <- forAll (Gen.bytes (Range.linear 0 64))
        decodeBase58 (encodeBase58 bytes) === Just bytes
    , testProperty "ida y vuelta con ceros iniciales" $ property $ do
        zeros <- forAll (Gen.int (Range.linear 1 8))
        rest <- forAll (Gen.bytes (Range.linear 0 32))
        let bytes = BS.replicate zeros 0 <> rest
        decodeBase58 (encodeBase58 bytes) === Just bytes
    ]
