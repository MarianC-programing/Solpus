{-# LANGUAGE OverloadedStrings #-}

{- | Importes en lamports (la unidad mínima de Solana: 1 SOL = 10^9 lamports).

Todo es exacto: la conversión usa 'Nano' (punto fijo con 9 decimales) y no
'Double'. El formato de salida es propio y solo ASCII; no se usa @show@ del
SDK, que imprime un símbolo no ASCII (spike #4).
-}
module Solpus.Core.Lamports
  ( Lamports (..)
  , lamportsPerSol
  , toSol
  , fromSol
  , addLamports
  , subLamports
  , renderSol
  ) where

import Data.Fixed (Fixed (MkFixed), Nano, showFixed)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Word (Word64)
import Solpus.Core.Error (ValidationError (..))

-- | Cantidad de lamports. Cualquier 'Word64' es un valor válido.
newtype Lamports = Lamports {unLamports :: Word64}
  deriving (Eq, Ord, Show)

-- | Lamports en un SOL.
lamportsPerSol :: Word64
lamportsPerSol = 1_000_000_000

-- | Convierte a SOL de forma exacta.
toSol :: Lamports -> Nano
toSol (Lamports w) = MkFixed (toInteger w)

-- | Convierte de SOL a lamports. Rechaza negativos y lo que no cabe en 64 bits.
fromSol :: Nano -> Either ValidationError Lamports
fromSol (MkFixed i)
  | i < 0 = Left NegativeAmount
  | i > toInteger (maxBound :: Word64) = Left AmountOverflow
  | otherwise = Right (Lamports (fromInteger i))

-- | Suma comprobada.
addLamports :: Lamports -> Lamports -> Either ValidationError Lamports
addLamports (Lamports a) (Lamports b)
  | s > toInteger (maxBound :: Word64) = Left AmountOverflow
  | otherwise = Right (Lamports (fromInteger s))
 where
  s = toInteger a + toInteger b

-- | Resta comprobada: falla si el resultado sería negativo.
subLamports :: Lamports -> Lamports -> Either ValidationError Lamports
subLamports (Lamports a) (Lamports b)
  | b > a = Left InsufficientLamports
  | otherwise = Right (Lamports (a - b))

{- | Texto legible, por ejemplo @1.5 SOL@ o @0.000000001 SOL@. Sin ceros
finales y solo ASCII.
-}
renderSol :: Lamports -> Text
renderSol l = T.pack (showFixed True (toSol l)) <> " SOL"
