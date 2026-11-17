{-# LANGUAGE OverloadedStrings #-}

{- | Configuración de la conexión con un nodo de Solana.

Un 'Endpoint' puede llevar una clave de API en la ruta o en la consulta
(@https://nodo.example/?api-key=...@). Por eso es abstracto y su 'Show' solo
enseña el origen: la URL completa ('endpointText') debe tratarse como secreto
y no escribirse en logs ni en mensajes de error.
-}
module Solpus.Client.Config
  ( -- * Endpoint
    Endpoint
  , mkEndpoint
  , endpointText

    -- * Configuración
  , Config (..)
  , mkConfig
  , localConfig
  , minTimeoutSeconds
  , maxTimeoutSeconds
  ) where

import Data.Char (isAscii, isAsciiLower, isAsciiUpper, isControl, isDigit, isHexDigit, isSpace)
import Data.Text (Text)
import Data.Text qualified as T
import Solpus.Core.Error (ValidationError (..))
import Solpus.Core.Types (Commitment (..))

{- | URL de un nodo. Solo http o https, sin credenciales en la URL, y http
únicamente hacia la propia máquina.
-}
newtype Endpoint = Endpoint Text
  deriving (Eq)

-- | Solo muestra esquema y autoridad; oculta ruta y consulta.
instance Show Endpoint where
  show (Endpoint url) = "Endpoint " <> show (originOnly url)

-- | URL completa. __Tratar como secreto.__
endpointText :: Endpoint -> Text
endpointText (Endpoint url) = url

data Scheme = Http | Https
  deriving (Eq)

{- | Valida una URL de nodo. El texto rechazado no se conserva en el error.

Reglas: máximo 2048 caracteres ASCII sin espacios ni control; esquema
@http://@ o @https://@ en minúsculas; host no vacío; puerto numérico entre 1
y 65535; nada de @usuario:clave\@@ en la autoridad; y @http@ solo hacia
@localhost@, @127.0.0.1@ o @[::1]@.
-}
mkEndpoint :: Text -> Either ValidationError Endpoint
mkEndpoint url
  | T.length url > maxEndpointChars = Left InvalidEndpoint
  | T.any (\c -> not (isAscii c) || isSpace c || isControl c) url = Left InvalidEndpoint
  | otherwise = do
      (scheme, rest) <- splitScheme url
      let authority = T.takeWhile (`notElem` ("/?#" :: String)) rest
      host <- parseAuthority authority
      if scheme == Http && not (isLocalHost host)
        then Left InvalidEndpoint
        else Right (Endpoint url)

maxEndpointChars :: Int
maxEndpointChars = 2048

splitScheme :: Text -> Either ValidationError (Scheme, Text)
splitScheme url = case (T.stripPrefix "https://" url, T.stripPrefix "http://" url) of
  (Just rest, _) -> Right (Https, rest)
  (_, Just rest) -> Right (Http, rest)
  _ -> Left InvalidEndpoint

-- | Devuelve el host (sin corchetes ni puerto) o rechaza la autoridad.
parseAuthority :: Text -> Either ValidationError Text
parseAuthority authority
  | T.null authority = Left InvalidEndpoint
  | T.any (== '@') authority = Left InvalidEndpoint
  | Just inner <- T.stripPrefix "[" authority = do
      let (literal, afterLiteral) = T.breakOn "]" inner
      rest <- maybe (Left InvalidEndpoint) Right (T.stripPrefix "]" afterLiteral)
      validIpv6 literal
      validPort rest
      Right literal
  | otherwise = do
      let (host, portPart) = T.breakOn ":" authority
      validHostname host
      validPort portPart
      Right host

validIpv6 :: Text -> Either ValidationError ()
validIpv6 literal
  | not (T.null literal) && T.any (== ':') literal && T.all (\c -> isHexDigit c || c == ':') literal =
      Right ()
  | otherwise = Left InvalidEndpoint

validHostname :: Text -> Either ValidationError ()
validHostname host
  | T.null host = Left InvalidEndpoint
  | T.head host == '.' || T.last host == '.' = Left InvalidEndpoint
  | T.all (\c -> isAscii c && (c == '-' || c == '.' || isDigit c || isAsciiLetter c)) host = Right ()
  | otherwise = Left InvalidEndpoint
 where
  isAsciiLetter c = isAsciiLower c || isAsciiUpper c

-- | El resto tras el host: vacío o @:puerto@.
validPort :: Text -> Either ValidationError ()
validPort rest
  | T.null rest = Right ()
  | Just digits <- T.stripPrefix ":" rest
  , not (T.null digits)
  , T.length digits <= 5
  , T.all isDigit digits
  , let port = T.foldl' (\acc c -> acc * 10 + fromEnum c - fromEnum '0') 0 digits
  , port >= 1
  , port <= 65535 =
      Right ()
  | otherwise = Left InvalidEndpoint

isLocalHost :: Text -> Bool
isLocalHost host = T.toLower host `elem` ["localhost", "127.0.0.1", "::1"]

-- | @esquema://autoridad@ y, si había más, @/...@.
originOnly :: Text -> Text
originOnly url =
  let (scheme, afterScheme) = T.breakOn "://" url
      body = T.drop 3 afterScheme
      authority = T.takeWhile (`notElem` ("/?#" :: String)) body
      hidden = T.length body > T.length authority
   in scheme <> "://" <> authority <> (if hidden then "/..." else "")

-- | Cómo hablar con el nodo.
data Config = Config
  { configEndpoint :: !Endpoint
  , configCommitment :: !Commitment
  -- ^ Nivel de commitment de las lecturas. Por defecto 'Confirmed'.
  , configTimeoutSeconds :: !Int
  -- ^ Tiempo máximo de espera de una respuesta.
  }
  deriving (Eq, Show)

-- | Timeout mínimo permitido, en segundos.
minTimeoutSeconds :: Int
minTimeoutSeconds = 1

-- | Timeout máximo permitido, en segundos.
maxTimeoutSeconds :: Int
maxTimeoutSeconds = 300

-- | Construye una configuración validando endpoint y timeout.
mkConfig :: Text -> Commitment -> Int -> Either ValidationError Config
mkConfig url commitment timeout = do
  endpoint <- mkEndpoint url
  if timeout < minTimeoutSeconds || timeout > maxTimeoutSeconds
    then Left (InvalidTimeout minTimeoutSeconds maxTimeoutSeconds)
    else Right (Config endpoint commitment timeout)

-- | Validador local en el puerto por defecto, con @confirmed@ y 30 s.
localConfig :: Config
localConfig = Config (Endpoint "http://127.0.0.1:8899") Confirmed 30
