{-# LANGUAGE OverloadedStrings #-}

-- | Versión de Solpus. Módulo mínimo que ancla el paquete mientras llegan los
-- tipos del dominio (issue #5).
module Solpus.Core.Version
  ( solpusVersion
  ) where

import Data.Text (Text)

-- | Versión actual de Solpus.
solpusVersion :: Text
solpusVersion = "0.1.0.0"
