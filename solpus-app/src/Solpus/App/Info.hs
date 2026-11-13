{-# LANGUAGE OverloadedStrings #-}

-- | Módulo mínimo que ancla el paquete y comprueba la arista de dependencia
-- con @solpus-client@. Se sustituye por los casos de uso reales (issue #9).
module Solpus.App.Info
  ( appInfo
  ) where

import Data.Text (Text)
import Solpus.Client.Info (clientInfo)

-- | Descripción de la capa de aplicación.
appInfo :: Text
appInfo = "solpus-app -> " <> clientInfo
