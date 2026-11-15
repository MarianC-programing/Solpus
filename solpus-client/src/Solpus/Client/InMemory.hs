{-# LANGUAGE OverloadedStrings #-}

{- | Intérprete en memoria de 'MonadSolana', para probar @solpus-app@ sin red.

Imita lo observado en el spike #4: una cuenta desconocida tiene saldo cero y
una transferencia sin fondos falla con el error RPC @-32002@.

__Limitaciones deliberadas__ (no es un nodo): no cobra comisiones, no modela
slots ni niveles de confirmación, y no valida que las cuentas existan. Las
diferencias con el nodo real se contrastan en las pruebas de integración.
-}
module Solpus.Client.InMemory
  ( InMemory
  , runInMemory

    -- * Libro mayor
  , Ledger
  , emptyLedger
  , ledgerFromBalances
  , ledgerBalance
  , ledgerTotal
  ) where

import Control.Monad.Trans.State.Strict (State, get, put, runState)
import Data.Bifunctor (first)
import Data.Bits (shiftR)
import Data.ByteString qualified as BS
import Data.Functor (($>))
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Word (Word64)
import Solpus.Client.Class (MonadSolana (..), MonadSolanaRead (..), Transfer (..))
import Solpus.Core.Error (SolpusError (..))
import Solpus.Core.Lamports (Lamports (..), addLamports, subLamports)
import Solpus.Core.Types (Address, Signature, signatureFromBytes)

-- | Saldos de todas las cuentas y contador para generar firmas distintas.
data Ledger = Ledger
  { ledgerBalances :: !(Map Address Lamports)
  , ledgerNextSignature :: !Word64
  }
  deriving (Eq, Show)

-- | Libro mayor sin cuentas.
emptyLedger :: Ledger
emptyLedger = Ledger Map.empty 0

-- | Libro mayor con saldos iniciales. Si una dirección se repite, gana la última.
ledgerFromBalances :: [(Address, Lamports)] -> Ledger
ledgerFromBalances balances = Ledger (Map.fromList balances) 0

-- | Saldo de una cuenta; cero si no existe.
ledgerBalance :: Address -> Ledger -> Lamports
ledgerBalance address = Map.findWithDefault (Lamports 0) address . ledgerBalances

{- | Suma de todos los saldos, como 'Integer' para que no pueda desbordar.
Sin comisiones, una transferencia nunca debe cambiarla.
-}
ledgerTotal :: Ledger -> Integer
ledgerTotal = sum . fmap (toInteger . unLamports) . Map.elems . ledgerBalances

-- | Mónada que ejecuta operaciones contra un 'Ledger' en memoria.
newtype InMemory a = InMemory (State Ledger a)
  deriving (Functor, Applicative, Monad)

-- | Ejecuta una acción y devuelve su resultado junto con el libro final.
runInMemory :: Ledger -> InMemory a -> (a, Ledger)
runInMemory ledger (InMemory action) = runState action ledger

instance MonadSolanaRead InMemory where
  getBalance address = InMemory (Right . ledgerBalance address <$> get)

instance MonadSolana InMemory where
  submitTransfer transfer = InMemory $ do
    ledger <- get
    case applyTransfer transfer ledger of
      Left err -> pure (Left err)
      Right (signature, ledger') -> put ledger' $> Right signature

-- | Lógica de una transferencia, sin monad. Si falla, el libro no cambia.
applyTransfer :: Transfer -> Ledger -> Either SolpusError (Signature, Ledger)
applyTransfer (Transfer from to amount) ledger = do
  debited <-
    either (const (Left insufficientFunds)) Right (subLamports (ledgerBalance from ledger) amount)
  let afterDebit = Map.insert from debited (ledgerBalances ledger)
  credited <-
    first ValidationFailed (addLamports (Map.findWithDefault (Lamports 0) to afterDebit) amount)
  signature <-
    first ValidationFailed (signatureFromBytes (signatureBytesFor (ledgerNextSignature ledger)))
  pure
    ( signature
    , Ledger
        { ledgerBalances = Map.insert to credited afterDebit
        , ledgerNextSignature = ledgerNextSignature ledger + 1
        }
    )

-- | El mismo error que devolvió el nodo en el spike #4 por fondos insuficientes.
insufficientFunds :: SolpusError
insufficientFunds =
  RpcError (-32002) "Transaction simulation failed: insufficient funds for transfer (in-memory)"

{- | 64 bytes: ceros y el contador en los últimos 8 (big endian). Distintos para
cada transferencia.
-}
signatureBytesFor :: Word64 -> BS.ByteString
signatureBytesFor n =
  BS.replicate 56 0 <> BS.pack [fromIntegral (n `shiftR` (8 * i)) | i <- [7, 6 .. 0]]
