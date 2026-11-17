{-# LANGUAGE OverloadedStrings #-}

{- | Implementación real de 'MonadSolanaRead' sobre @solana-haskell-sdk@.

Es, junto con @Solpus.Client.Tx@, el único módulo que importa el SDK
(comprobado por @scripts/check-boundaries.sh@).

Decisiones tomadas tras el spike #4 y la lectura del SDK 1.4.0.0:

* __Los errores del SDK son excepciones__, no valores 'Left'. Cada llamada se
  envuelve y se traduce a 'SolpusError'; cualquier otra excepción se
  relanza, porque es un defecto y no debe ocultarse.
* __@getBalance@ del SDK no admite commitment__ y lee en el valor por
  defecto del nodo. Aquí se enlaza la misma llamada JSON-RPC con un objeto de
  configuración para leer al nivel pedido en 'Config'.
* __Nunca se escribe la URL del nodo__ en un error: puede llevar una clave de
  API, y @show@ de una 'HttpException' incluye la petición completa.
-}
module Solpus.Client.Rpc
  ( -- * Ejecución
    Env
  , newEnv
  , SolpusIO
  , runSolpusIO

    -- * Traducción de errores (expuesta para pruebas)
  , classifyJsonRpc
  , classifyHttp
  , classifyWeb3
  ) where

import Control.Exception (Handler (..), catches)
import Control.Monad.Trans.Reader (ReaderT (..))
import Data.Text (Text)
import Data.Text qualified as T
import Network.HTTP.Client
  ( HttpException (..)
  , HttpExceptionContent (..)
  , Manager
  , ManagerSettings (managerResponseTimeout)
  , newManager
  , responseStatus
  , responseTimeoutMicro
  )
import Network.HTTP.Client.TLS (tlsManagerSettings)
import Network.HTTP.Types.Status (statusCode)
import Network.JsonRpc.TinyClient (JsonRpc (..), JsonRpcException (..))
import Network.JsonRpc.TinyClient qualified as Rpc
import Network.Solana.Core.Account (Lamport (..))
import Network.Solana.Core.Crypto (SolanaPublicKey, mkPublicKeyFromString)
import Network.Solana.RPC.HTTP.Types
  ( ConfigurationObject (..)
  , RPCResponse (..)
  , defaultConfigObject
  )
import Network.Web3.Provider (Provider (HttpProvider), Web3Error (..), runWeb3With)
import Solpus.Client.Class (MonadSolanaRead (..))
import Solpus.Client.Config (Config (..), endpointText)
import Solpus.Core.Error (SolpusError (..))
import Solpus.Core.Lamports (Lamports (..))
import Solpus.Core.Types (Address, addressText, commitmentText)

-- | Configuración y gestor de conexiones HTTP compartidos entre llamadas.
data Env = Env
  { envConfig :: !Config
  , envManager :: !Manager
  }

{- | Crea el entorno. Aplica el timeout de respuesta de la configuración; el
de conexión lo fija el sistema operativo.
-}
newEnv :: Config -> IO Env
newEnv config = do
  manager <-
    newManager
      tlsManagerSettings
        { managerResponseTimeout =
            responseTimeoutMicro (configTimeoutSeconds config * 1_000_000)
        }
  pure (Env config manager)

-- | Mónada que ejecuta operaciones contra un nodo real.
newtype SolpusIO a = SolpusIO (ReaderT Env IO a)
  deriving (Functor, Applicative, Monad)

runSolpusIO :: Env -> SolpusIO a -> IO a
runSolpusIO env (SolpusIO action) = runReaderT action env

instance MonadSolanaRead SolpusIO where
  getBalance address = SolpusIO (ReaderT (`fetchBalance` address))

fetchBalance :: Env -> Address -> IO (Either SolpusError Lamports)
fetchBalance env address =
  case mkPublicKeyFromString (T.unpack (addressText address)) of
    Left why ->
      pure (Left (InternalError ("el SDK rechazó una dirección válida: " <> T.pack why)))
    Right key -> translating $ do
      result <- runWeb3With (envManager env) provider (getBalanceWith key options)
      pure (either (Left . classifyWeb3) (Right . toLamports) result)
 where
  config = envConfig env
  provider = HttpProvider (T.unpack (endpointText (configEndpoint config)))
  options =
    defaultConfigObject
      { commitment = Just (T.unpack (commitmentText (configCommitment config)))
      }
  toLamports response = Lamports (unLamport (value response))

{- | La misma llamada @getBalance@ del SDK, pero con objeto de configuración
(commitment). El SDK enlaza @remote "getBalance"@ solo con la clave pública.
-}
getBalanceWith ::
  (JsonRpc m) =>
  SolanaPublicKey ->
  ConfigurationObject ->
  m (RPCResponse Lamport)
getBalanceWith = remote "getBalance"

{- | Traduce las dos familias de excepciones que el SDK lanza. Cualquier otra
se relanza.
-}
translating :: IO (Either SolpusError a) -> IO (Either SolpusError a)
translating action =
  action
    `catches` [ Handler (pure . Left . classifyJsonRpc)
              , Handler (pure . Left . classifyHttp)
              ]

-- | Error JSON-RPC del nodo, o respuesta que no se pudo interpretar.
classifyJsonRpc :: JsonRpcException -> SolpusError
classifyJsonRpc (CallException err) =
  RpcError (Rpc.errCode err) (Rpc.errMessage err)
classifyJsonRpc (ParsingException why) = InvalidResponse (bounded why)

{- | Fallo de red. El texto es fijo por tipo de fallo y __no incluye la URL__
ni ninguna parte de la petición.
-}
classifyHttp :: HttpException -> SolpusError
classifyHttp (InvalidUrlException _ _) = NetworkFailure "la URL del nodo no es válida"
classifyHttp (HttpExceptionRequest _ content) = NetworkFailure $ case content of
  ConnectionTimeout -> "se agotó el tiempo para conectar con el nodo"
  ResponseTimeout -> "el nodo no respondió a tiempo"
  ConnectionFailure _ -> "no se pudo conectar con el nodo"
  TlsNotSupported -> "el nodo no admite TLS"
  StatusCodeException response _ ->
    "el nodo respondió con HTTP " <> T.pack (show (statusCode (responseStatus response)))
  _ -> "error de red al hablar con el nodo"

-- | Errores que el proveedor de @web3@ devuelve como valor.
classifyWeb3 :: Web3Error -> SolpusError
classifyWeb3 (JsonRpcFail why) = InvalidResponse ("fallo JSON-RPC: " <> bounded why)
classifyWeb3 (ParserFail why) = InvalidResponse ("respuesta ilegible: " <> bounded why)
classifyWeb3 (UserFail why) = InvalidResponse ("fallo del proveedor: " <> bounded why)

-- | Acota el texto que viene del nodo para que no pueda crecer sin límite.
bounded :: String -> Text
bounded = T.take 200 . T.pack
