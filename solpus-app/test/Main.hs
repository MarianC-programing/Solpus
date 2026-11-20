{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Data.ByteString qualified as BS
import Solpus.App.Transfer (transferSol)
import Solpus.Client.Class (Transfer (..))
import Solpus.Client.InMemory (emptyLedger, ledgerBalance, ledgerFromBalances, runInMemory)
import Solpus.Core.Error (SolpusError (..), ValidationError (..))
import Solpus.Core.Lamports (Lamports (..))
import Solpus.Core.Types (Address, addressFromBytes)
import Test.Tasty (defaultMain, testGroup)
import Test.Tasty.HUnit (assertBool, assertFailure, testCase, (@?=))

address :: Int -> Address
address n = either (error . show) id (addressFromBytes (BS.replicate 32 (fromIntegral n)))

main :: IO ()
main =
  defaultMain $
    testGroup
      "solpus-app"
      [ testCase "una transferencia correcta mueve los fondos" $ do
          let ledger = ledgerFromBalances [(address 1, Lamports 5_000)]
              (result, after) = runInMemory ledger (transferSol (Transfer (address 1) (address 2) (Lamports 2_000)))
          assertBool ("debía tener éxito: " <> show result) (either (const False) (const True) result)
          ledgerBalance (address 1) after @?= Lamports 3_000
          ledgerBalance (address 2) after @?= Lamports 2_000
      , testCase "un importe cero se rechaza sin tocar nada" $ do
          let ledger = ledgerFromBalances [(address 1, Lamports 5_000)]
              (result, after) = runInMemory ledger (transferSol (Transfer (address 1) (address 2) (Lamports 0)))
          result @?= Left (ValidationFailed ZeroAmount)
          ledgerBalance (address 1) after @?= Lamports 5_000
          ledgerBalance (address 2) after @?= Lamports 0
      , testCase "fondos insuficientes: error del nodo y libro intacto" $ do
          let ledger = ledgerFromBalances [(address 1, Lamports 100)]
              (result, after) = runInMemory ledger (transferSol (Transfer (address 1) (address 2) (Lamports 500)))
          case result of
            Left (RpcError code _) -> code @?= (-32002)
            other -> assertFailure ("se esperaba RpcError: " <> show other)
          ledgerBalance (address 1) after @?= Lamports 100
      , testCase "un libro vacío no puede gastar" $ do
          let (result, _) = runInMemory emptyLedger (transferSol (Transfer (address 1) (address 2) (Lamports 1)))
          assertBool "debía fallar" (either (const True) (const False) result)
      ]
