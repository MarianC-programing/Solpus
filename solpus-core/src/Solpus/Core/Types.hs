{-# LANGUAGE OverloadedStrings #-}

{- | Tipos básicos del dominio de Solana.

'Address' y 'Signature' son abstractos: solo se construyen desde bytes con la
longitud correcta ('addressFromBytes', 'signatureFromBytes') o desde texto
con "Solpus.Core.Validate". Así una dirección inválida no puede existir.
-}
module Solpus.Core.Types
  ( -- * Direcciones
    Address
  , addressLength
  , addressFromBytes
  , addressBytes
  , addressText

    -- * Firmas
  , Signature
  , signatureLength
  , signatureFromBytes
  , signatureBytes
  , signatureText

    -- * Otros
  , Slot (..)
  , Commitment (..)
  , commitmentText
  ) where

import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Text (Text)
import Data.Word (Word64)
import Solpus.Core.Base58 (encodeBase58)
import Solpus.Core.Error (ValidationError (..))

-- | Dirección pública: exactamente 32 bytes.
newtype Address = Address ByteString
  deriving (Eq, Ord)

instance Show Address where
  show a = "Address " <> show (addressText a)

-- | Firma: exactamente 64 bytes.
newtype Signature = Signature ByteString
  deriving (Eq, Ord)

instance Show Signature where
  show s = "Signature " <> show (signatureText s)

-- | Longitud en bytes de una dirección.
addressLength :: Int
addressLength = 32

-- | Longitud en bytes de una firma.
signatureLength :: Int
signatureLength = 64

addressFromBytes :: ByteString -> Either ValidationError Address
addressFromBytes bytes
  | BS.length bytes == addressLength = Right (Address bytes)
  | otherwise = Left (InvalidByteLength addressLength (BS.length bytes))

signatureFromBytes :: ByteString -> Either ValidationError Signature
signatureFromBytes bytes
  | BS.length bytes == signatureLength = Right (Signature bytes)
  | otherwise = Left (InvalidByteLength signatureLength (BS.length bytes))

addressBytes :: Address -> ByteString
addressBytes (Address bytes) = bytes

signatureBytes :: Signature -> ByteString
signatureBytes (Signature bytes) = bytes

-- | Representación base58, la que muestran los exploradores.
addressText :: Address -> Text
addressText = encodeBase58 . addressBytes

signatureText :: Signature -> Text
signatureText = encodeBase58 . signatureBytes

-- | Número de slot.
newtype Slot = Slot {unSlot :: Word64}
  deriving (Eq, Ord, Show)

-- | Nivel de confirmación. Por defecto se usará 'Confirmed' (spike #4).
data Commitment = Processed | Confirmed | Finalized
  deriving (Eq, Ord, Show, Enum, Bounded)

-- | Nombre que entiende el RPC de Solana.
commitmentText :: Commitment -> Text
commitmentText Processed = "processed"
commitmentText Confirmed = "confirmed"
commitmentText Finalized = "finalized"
