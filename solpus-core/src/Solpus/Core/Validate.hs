{-# LANGUAGE OverloadedStrings #-}

{- | Conversión de texto externo (CLI, archivos, red) a tipos del dominio.

Todas las funciones son totales y acotan la longitud de la entrada antes de
hacer ningún cálculo: base58 es cuadrático y un texto enorme no debe poder
consumir CPU.
-}
module Solpus.Core.Validate
  ( parseAddress
  , parseSignature
  , parseSolAmount
  , parseLamports
  ) where

import Data.ByteString (ByteString)
import Data.Char (digitToInt, isDigit)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Word (Word64)
import Solpus.Core.Base58 (decodeBase58)
import Solpus.Core.Error (ValidationError (..))
import Solpus.Core.Lamports (Lamports (..), lamportsPerSol)
import Solpus.Core.Types
  ( Address
  , Signature
  , addressFromBytes
  , signatureFromBytes
  )

-- | Máximo de caracteres base58 de 32 bytes.
maxAddressChars :: Int
maxAddressChars = 44

-- | Máximo de caracteres base58 de 64 bytes.
maxSignatureChars :: Int
maxSignatureChars = 88

{- | Máximo de caracteres de un importe (el mayor, 2^64-1 lamports, tiene 20
dígitos; el resto es margen para el punto decimal).
-}
maxAmountChars :: Int
maxAmountChars = 40

-- | Decimales de un SOL.
solDecimals :: Int
solDecimals = 9

-- | Dirección desde su texto base58.
parseAddress :: Text -> Either ValidationError Address
parseAddress text = decodeBounded maxAddressChars text >>= addressFromBytes

-- | Firma desde su texto base58.
parseSignature :: Text -> Either ValidationError Signature
parseSignature text = decodeBounded maxSignatureChars text >>= signatureFromBytes

decodeBounded :: Int -> Text -> Either ValidationError ByteString
decodeBounded limit text
  | T.length text > limit = Left (InputTooLong limit)
  | otherwise = maybe (Left InvalidBase58) Right (decodeBase58 text)

-- | Importe en lamports como entero decimal sin signo, por ejemplo @"1500"@.
parseLamports :: Text -> Either ValidationError Lamports
parseLamports text
  | T.length text > maxAmountChars = Left (InputTooLong maxAmountChars)
  | not (isDigits text) = Left InvalidAmountSyntax
  | otherwise = toLamports (digitsToInteger text)

{- | Importe en SOL como decimal sin signo, por ejemplo @"1.5"@ o @"0.000000001"@.
Exige al menos un dígito entero y, si hay punto, al menos un decimal.
Admite hasta 9 decimales (un lamport) y nunca pasa por 'Double'.
-}
parseSolAmount :: Text -> Either ValidationError Lamports
parseSolAmount text
  | T.length text > maxAmountChars = Left (InputTooLong maxAmountChars)
  | not (isDigits whole) = Left InvalidAmountSyntax
  | hasPoint && not (isDigits frac) = Left InvalidAmountSyntax
  | T.length frac > solDecimals = Left (TooManyDecimals solDecimals)
  | otherwise = toLamports (digitsToInteger whole * perSol + digitsToInteger padded)
 where
  (whole, rest) = T.breakOn "." text
  hasPoint = not (T.null rest)
  frac = T.drop 1 rest
  padded = T.justifyLeft solDecimals '0' frac
  perSol = toInteger lamportsPerSol

-- | Verdadero si el texto no está vacío y todo son dígitos ASCII.
isDigits :: Text -> Bool
isDigits t = not (T.null t) && T.all isDigit t

digitsToInteger :: Text -> Integer
digitsToInteger = T.foldl' (\acc c -> acc * 10 + toInteger (digitToInt c)) 0

toLamports :: Integer -> Either ValidationError Lamports
toLamports n
  | n > toInteger (maxBound :: Word64) = Left AmountOverflow
  | otherwise = Right (Lamports (fromInteger n))
