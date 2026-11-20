{-# LANGUAGE OverloadedStrings #-}

{- | Construcción de una transferencia firmada, sin red.

Es una función pura: dada la wallet, un blockhash y la transferencia, devuelve
la transacción serializada y su firma. Junto con @Rpc@ y @Wallet@ es uno de
los módulos que importan el SDK (comprobado por @scripts/check-boundaries.sh@).
Las comprobaciones que no necesitan la red van aquí, para que fallen antes de
tocar el nodo:

* el origen debe ser la dirección de la wallet;
* el importe no puede ser cero.
-}
module Solpus.Client.Tx
  ( SignedTransfer (..)
  , buildTransfer
  ) where

import Data.Text qualified as T
import Network.Solana.Core.Account (Lamport (..))
import Network.Solana.Core.Block (BlockHash)
import Network.Solana.Core.Crypto (SolanaPublicKey, mkPublicKeyFromString)
import Network.Solana.NativePrograms.SystemProgram qualified as System
import Solpus.Client.Class (Transfer (..))
import Solpus.Client.Wallet (Wallet, signInstructions, walletAddress)
import Solpus.Core.Error (SolpusError (..), ValidationError (..))
import Solpus.Core.Lamports (Lamports (..))
import Solpus.Core.Types (Address, Signature, addressText)

-- | Transacción lista para enviar y su firma, que se conoce de antemano.
data SignedTransfer = SignedTransfer
  { signedPayload :: !String
  -- ^ Transacción serializada en base64.
  , signedSignature :: !Signature
  }
  deriving (Show)

-- | Arma y firma una transferencia de SOL pagada por la wallet.
buildTransfer :: Wallet -> BlockHash -> Transfer -> Either SolpusError SignedTransfer
buildTransfer wallet blockhash (Transfer from to amount)
  | from /= walletAddress wallet = Left (ValidationFailed TransferSourceNotWallet)
  | unLamports amount == 0 = Left (ValidationFailed ZeroAmount)
  | otherwise = do
      fromKey <- publicKey from
      toKey <- publicKey to
      let instruction = System.transfer fromKey toKey (Lamport (unLamports amount))
      (payload, signature) <- signInstructions wallet blockhash [instruction]
      pure (SignedTransfer payload signature)

publicKey :: Address -> Either SolpusError SolanaPublicKey
publicKey address =
  case mkPublicKeyFromString (T.unpack (addressText address)) of
    Left why -> Left (InternalError ("el SDK rechazó una dirección válida: " <> T.pack why))
    Right key -> Right key
