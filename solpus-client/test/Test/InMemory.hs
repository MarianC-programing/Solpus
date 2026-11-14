module Test.InMemory (tests) where

import Control.Monad (void)
import Data.ByteString qualified as BS
import Data.Either (isRight)
import Data.Word (Word8)
import Hedgehog (Gen, annotateShow, forAll, property, (===))
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import Solpus.Client.Class (MonadSolana (..), Transfer (..))
import Solpus.Client.InMemory
import Solpus.Core.Error (SolpusError (..), ValidationError (..))
import Solpus.Core.Lamports (Lamports (..))
import Solpus.Core.Types (Address, addressFromBytes)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, assertFailure, testCase, (@?=))
import Test.Tasty.Hedgehog (testProperty)

-- | Dirección de prueba: 32 bytes iguales.
addr :: Word8 -> Address
addr n = case addressFromBytes (BS.replicate 32 n) of
  Right a -> a
  Left e -> error ("dirección de prueba inválida: " <> show e)

alice, bob :: Address
alice = addr 1
bob = addr 2

genAddress :: Gen Address
genAddress = addr <$> Gen.element [1 .. 4]

genLamports :: Word -> Gen Lamports
genLamports top = Lamports . fromIntegral <$> Gen.word (Range.linear 0 top)

genLedger :: Gen Ledger
genLedger = do
  balances <- Gen.list (Range.linear 0 8) ((,) <$> genAddress <*> genLamports 150)
  pure (ledgerFromBalances balances)

genTransfer :: Gen Transfer
genTransfer = Transfer <$> genAddress <*> genAddress <*> genLamports 200

tests :: TestTree
tests =
  testGroup
    "InMemory"
    [ testCase "una cuenta desconocida tiene saldo cero" $
        fst (runInMemory emptyLedger (getBalance alice)) @?= Right (Lamports 0)
    , testCase "una transferencia correcta mueve los fondos" $ do
        let ledger = ledgerFromBalances [(alice, Lamports 100)]
            (result, after) = runInMemory ledger (submitTransfer (Transfer alice bob (Lamports 30)))
        assertBool "debería devolver una firma" (isRight result)
        ledgerBalance alice after @?= Lamports 70
        ledgerBalance bob after @?= Lamports 30
    , testCase "getBalance refleja una transferencia previa" $ do
        let ledger = ledgerFromBalances [(alice, Lamports 100)]
            action = do
              void (submitTransfer (Transfer alice bob (Lamports 40)))
              getBalance bob
        fst (runInMemory ledger action) @?= Right (Lamports 40)
    , testCase "dos transferencias devuelven firmas distintas" $ do
        let ledger = ledgerFromBalances [(alice, Lamports 100)]
            transfer = submitTransfer (Transfer alice bob (Lamports 1))
            (first', second') = fst (runInMemory ledger ((,) <$> transfer <*> transfer))
        assertBool "las firmas deben diferir" (first' /= second')
    , testCase "fondos insuficientes: error RPC -32002 y libro intacto" $ do
        let ledger = ledgerFromBalances [(alice, Lamports 10)]
            (result, after) = runInMemory ledger (submitTransfer (Transfer alice bob (Lamports 11)))
        case result of
          Left (RpcError code _) -> code @?= (-32002)
          other -> assertFailure ("se esperaba RpcError, llegó " <> show other)
        after @?= ledger
    , testCase "transferirse a uno mismo no cambia el saldo" $ do
        let ledger = ledgerFromBalances [(alice, Lamports 50)]
            (result, after) = runInMemory ledger (submitTransfer (Transfer alice alice (Lamports 20)))
        assertBool "debería aceptarse" (isRight result)
        ledgerBalance alice after @?= Lamports 50
    , testCase "desbordar el saldo del destino falla y deja el libro intacto" $ do
        let ledger = ledgerFromBalances [(alice, Lamports 1), (bob, Lamports maxBound)]
            (result, after) = runInMemory ledger (submitTransfer (Transfer alice bob (Lamports 1)))
        result @?= Left (ValidationFailed AmountOverflow)
        after @?= ledger
    , testProperty "una transferencia conserva el total y, si falla, no toca el libro" $ property $ do
        ledger <- forAll genLedger
        transfer <- forAll genTransfer
        let (result, after) = runInMemory ledger (submitTransfer transfer)
        annotateShow result
        ledgerTotal after === ledgerTotal ledger
        case result of
          Left _ -> after === ledger
          Right _ -> pure ()
    , testProperty "una secuencia de transferencias conserva el total" $ property $ do
        ledger <- forAll genLedger
        transfers <- forAll (Gen.list (Range.linear 0 30) genTransfer)
        let (_, after) = runInMemory ledger (mapM_ submitTransfer transfers)
        ledgerTotal after === ledgerTotal ledger
    ]
