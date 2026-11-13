{-# LANGUAGE OverloadedStrings #-}

{- | Módulo mínimo que ancla el paquete y comprueba la arista de dependencia
con @solpus-core@. Se sustituye por la interfaz real en los issues #6 y #7.
-}
module Solpus.Client.Info
  ( clientInfo
  ) where

import Data.Text (Text)
import Solpus.Core.Version (solpusVersion)

-- | Descripción de la capa de cliente.
clientInfo :: Text
clientInfo = "solpus-client " <> solpusVersion
