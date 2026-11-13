-- | Punto de entrada de la CLI. Solo parseo y salida; sin lógica de negocio.
-- Se sustituye por los subcomandos reales en el issue #12.
module Main (main) where

import qualified Data.Text.IO as T
import Solpus.App.Info (appInfo)

main :: IO ()
main = T.putStrLn appInfo
