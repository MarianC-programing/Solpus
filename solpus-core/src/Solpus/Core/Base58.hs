{- | Codificación base58 (alfabeto de Bitcoin, el que usa Solana).

Implementación propia porque @solpus-core@ no puede depender del SDK. Es
cuadrática en el tamaño de la entrada: quien la use con texto externo debe
acotar la longitud antes (ver "Solpus.Core.Validate").
-}
module Solpus.Core.Base58
  ( encodeBase58
  , decodeBase58
  ) where

import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.List (elemIndex, foldl', unfoldr)
import Data.Text (Text)
import Data.Text qualified as T

alphabet :: String
alphabet = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"

-- | Codifica bytes en base58. Cada byte cero inicial se escribe como @'1'@.
encodeBase58 :: ByteString -> Text
encodeBase58 bytes = T.pack (replicate zeros '1' <> digits)
 where
  zeros = BS.length (BS.takeWhile (== 0) bytes)
  n = BS.foldl' (\acc w -> acc * 256 + toInteger w) 0 bytes
  digits = go n []
  go 0 acc = acc
  go k acc =
    let (q, r) = k `quotRem` 58
     in go q (alphabet !! fromInteger r : acc)

{- | Decodifica base58. Devuelve 'Nothing' si hay algún carácter fuera del
alfabeto (incluidos @0@, @O@, @I@, @l@ y cualquier carácter no ASCII).
-}
decodeBase58 :: Text -> Maybe ByteString
decodeBase58 text = do
  values <- traverse (`elemIndex` alphabet) (T.unpack text)
  let zeros = length (takeWhile (== 0) values)
      n = foldl' (\acc v -> acc * 58 + toInteger v) 0 values
  pure (BS.replicate zeros 0 <> integerToBytes n)

integerToBytes :: Integer -> ByteString
integerToBytes = BS.pack . reverse . unfoldr step
 where
  step 0 = Nothing
  step k = Just (fromInteger (k `mod` 256), k `div` 256)
