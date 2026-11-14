{-# LANGUAGE OverloadedStrings #-}

module Test.Lamports (tests) where

import Data.Char (isAscii)
import Data.Text qualified as T
import Hedgehog (forAll, property, (===))
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import Solpus.Core.Error (ValidationError (..))
import Solpus.Core.Lamports
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=))
import Test.Tasty.Hedgehog (testProperty)

tests :: TestTree
tests =
  testGroup
    "Lamports"
    [ testProperty "fromSol . toSol == Right" $ property $ do
        w <- forAll (Gen.word64 Range.constantBounded)
        fromSol (toSol (Lamports w)) === Right (Lamports w)
    , testCase "1 SOL son 10^9 lamports" $
        fromSol 1 @?= Right (Lamports 1_000_000_000)
    , testCase "un lamport es 0.000000001 SOL" $
        fromSol 0.000000001 @?= Right (Lamports 1)
    , testCase "rechaza negativos" $
        fromSol (-1) @?= Left NegativeAmount
    , testCase "rechaza lo que no cabe en 64 bits" $
        fromSol (toSol (Lamports maxBound) + 0.000000001) @?= Left AmountOverflow
    , testCase "suma con desbordamiento" $
        addLamports (Lamports maxBound) (Lamports 1) @?= Left AmountOverflow
    , testCase "resta que dejaría el saldo negativo" $
        subLamports (Lamports 1) (Lamports 2) @?= Left InsufficientLamports
    , testProperty "sumar y restar el mismo importe devuelve el original" $ property $ do
        let half = maxBound `div` 2
        a <- forAll (Gen.word64 (Range.linear 0 half))
        b <- forAll (Gen.word64 (Range.linear 0 half))
        (addLamports (Lamports a) (Lamports b) >>= (`subLamports` Lamports b))
          === Right (Lamports a)
    , testCase "formato sin ceros finales" $ do
        renderSol (Lamports 1_500_000_000) @?= "1.5 SOL"
        renderSol (Lamports 1_000_000_000) @?= "1 SOL"
        renderSol (Lamports 1) @?= "0.000000001 SOL"
        renderSol (Lamports 0) @?= "0 SOL"
    , testProperty "el formato es solo ASCII" $ property $ do
        w <- forAll (Gen.word64 Range.constantBounded)
        T.all isAscii (renderSol (Lamports w)) === True
    ]
