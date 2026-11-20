{-# LANGUAGE OverloadedStrings #-}

{- | Implementación real de 'MonadSolanaRead' sobre @solana-haskell-sdk@.

Es, junto con @Solpus.Client.Tx@ y @Solpus.Client.Wallet@, uno de los pocos
módulos que importan el SDK (comprobado por @scripts/check-boundaries.sh@).

Decisiones tomadas tras el spike #4 y la lectura del SDK 1.4.0.0:

* __Los errores del SDK son excepciones__, no valores 'Left'. Cada llamada se
  envuelve y se traduce a 'SolpusError'; cualquier otra excepción se
  relanza, porque es un defecto y no debe ocultarse.
* __@getBalance@ del SDK no admite commitment__ y lee en el valor por
  defecto del nodo. Aquí se enlaza la misma llamada JSON-RPC con un objeto de
  configuración para leer al nivel pedido en 'Config'.
* __Nunca se escribe la URL del nodo__ en un error: puede llevar una clave de
  API, y @show@ de una 'HttpException' incluye la petición completa.
* __Enviar una transferencia__ ('submitTransfer') usa @confirmed@ tanto para
  el blockhash como para la comprobación previa del nodo (preflight): con los
  valores por defecto del SDK se lee a @finalized@, y tras un airdrop o una
  transferencia recién confirmados el nodo vería saldo cero. Antes de enviar
  se consulta el genesis hash y se rechaza mainnet-beta salvo permiso expreso.
  __Nunca se reintenta__ un envío: si el resultado es incierto se devuelve
  'SubmissionUncertain' con la firma y la última altura válida.
-}
module Solpus.Client.Rpc
  ( -- * Ejecución
    Env
  , newEnv
  , newEnvWith
  , SolpusIO
  , runSolpusIO

    -- * Traducción de errores (expuesta para pruebas)
  , classifyJsonRpc
  , classifyHttp
  , classifyWeb3
  , mainnetGenesisHash
  ) where

import Control.Exception (Handler (..), catches)
import Control.Monad.Trans.Except (ExceptT (..), except, runExceptT)
import Control.Monad.Trans.Reader (ReaderT (..))
import Data.Text (Text)
import Data.Text qualified as T
import Data.Word (Word64)
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
import Network.Solana.Core.Crypto
  ( SolanaPublicKey
  , getSolanaSignatureRaw
  , mkPublicKeyFromString
  , toBase58String
  )
import Network.Solana.RPC.HTTP.Block (LatestBlockHash (..))
import Network.Solana.RPC.HTTP.Ledger (getGenesisHash)
import Network.Solana.RPC.HTTP.Transaction
  ( defaultRpcSendTransactionConfig
  , sendTransaction'
  )
import Network.Solana.RPC.HTTP.Types
  ( ConfigurationObject (..)
  , RPCResponse (..)
  , defaultConfigObject
  )
import Network.Web3.Provider (Provider (HttpProvider), Web3Error (..), runWeb3With)
import Solpus.Client.Class (MonadSolana (..), MonadSolanaRead (..), Transfer (..))
import Solpus.Client.Config (Config (..), endpointText)
import Solpus.Client.Tx (SignedTransfer (..), buildTransfer)
import Solpus.Client.Wallet (Wallet, walletAddress)
import Solpus.Core.Error (SolpusError (..), ValidationError (..), WalletError (..))
import Solpus.Core.Lamports (Lamports (..))
import Solpus.Core.Types (Address, Signature, addressText, commitmentText, signatureText)

-- | Configuración y gestor de conexiones HTTP compartidos entre llamadas.
data Env = Env
  { envConfig :: !Config
  , envManager :: !Manager
  , envWallet :: !(Maybe Wallet)
  -- ^ Clave de firma. Sin ella solo funcionan las lecturas.
  }

{- | Crea el entorno. Aplica el timeout de respuesta de la configuración; el
de conexión lo fija el sistema operativo.
-}
newEnv :: Config -> IO Env
newEnv config = newEnvWith config Nothing

-- | Como 'newEnv', con una wallet opcional para poder enviar transferencias.
newEnvWith :: Config -> Maybe Wallet -> IO Env
newEnvWith config wallet = do
  manager <-
    newManager
      tlsManagerSettings
        { managerResponseTimeout =
            responseTimeoutMicro (configTimeoutSeconds config * 1_000_000)
        }
  pure (Env config manager wallet)

-- | Mónada que ejecuta operaciones contra un nodo real.
newtype SolpusIO a = SolpusIO (ReaderT Env IO a)
  deriving (Functor, Applicative, Monad)

runSolpusIO :: Env -> SolpusIO a -> IO a
runSolpusIO env (SolpusIO action) = runReaderT action env

instance MonadSolanaRead SolpusIO where
  getBalance address = SolpusIO (ReaderT (`fetchBalance` address))

instance MonadSolana SolpusIO where
  submitTransfer transfer = SolpusIO (ReaderT (`sendTransfer` transfer))

{- | Genesis hash de mainnet-beta (comprobado contra la documentación de la
Fundación Solana y un nodo de mainnet en vivo).
-}
mainnetGenesisHash :: String
mainnetGenesisHash = "5eykt4UsFv8P8NJdTREpY1vzqKqZKvdpKuc147dw2N9d"

{- | Envía una transferencia. Las comprobaciones locales (wallet presente,
origen correcto) fallan antes de tocar la red; después se comprueba que el
nodo no sea mainnet, se obtiene un blockhash a @confirmed@, se firma y se
envía con preflight a @confirmed@. No hay reintentos.
-}
sendTransfer :: Env -> Transfer -> IO (Either SolpusError Signature)
sendTransfer env transfer = case envWallet env of
  Nothing -> pure (Left (WalletFailed WalletNotLoaded))
  Just wallet
    | transferFrom transfer /= walletAddress wallet ->
        pure (Left (ValidationFailed TransferSourceNotWallet))
    | otherwise -> runExceptT $ do
        ExceptT (guardMainnet env)
        latest <- ExceptT (fetchLatestBlockhash env)
        signed <- except (buildTransfer wallet (blockhash latest) transfer)
        ExceptT (sendSigned env signed (lastValidBlockHeight latest))

{- | Rechaza mainnet-beta salvo permiso expreso. Si no se puede comprobar a qué
red pertenece el nodo, falla (no envía a ciegas).
-}
guardMainnet :: Env -> IO (Either SolpusError ())
guardMainnet env
  | configAllowMainnet (envConfig env) = pure (Right ())
  | otherwise = do
      result <-
        translating
          (either (Left . classifyWeb3) Right <$> runWeb3With (envManager env) (providerOf env) getGenesisHash)
      pure $ case result of
        Left err -> Left err
        Right genesis
          | show genesis == mainnetGenesisHash -> Left MainnetRefused
          | otherwise -> Right ()

-- | Blockhash a @confirmed@ (el del SDK usaría @finalized@ y vence antes).
fetchLatestBlockhash :: Env -> IO (Either SolpusError LatestBlockHash)
fetchLatestBlockhash env =
  translating $
    either (Left . classifyWeb3) (Right . value)
      <$> runWeb3With (envManager env) (providerOf env) (getLatestBlockhashWith confirmedOptions)

{- | Envía la transacción ya firmada. Un error JSON-RPC del nodo (por ejemplo
una comprobación previa fallida) significa que no entró; cualquier otro fallo
después de enviar es incierto y devuelve la firma y la última altura válida.
-}
sendSigned :: Env -> SignedTransfer -> Word64 -> IO (Either SolpusError Signature)
sendSigned env signed lastValid =
  action
    `catches` [ Handler onJsonRpc
              , Handler onHttp
              ]
 where
  signature = signedSignature signed
  uncertain = SubmissionUncertain (signatureText signature) lastValid
  options = defaultRpcSendTransactionConfig{preflightCommitment = Just "confirmed"}
  action = do
    result <-
      runWeb3With
        (envManager env)
        (providerOf env)
        (sendTransaction' (signedPayload signed) options)
    pure $ case result of
      Left _ -> Left uncertain
      Right nodeSignature
        | T.pack (toBase58String (getSolanaSignatureRaw nodeSignature)) == signatureText signature ->
            Right signature
        | otherwise -> Left (InternalError "el nodo devolvió una firma distinta de la calculada")
  onJsonRpc (CallException err) = pure (Left (classifyJsonRpc (CallException err)))
  onJsonRpc _ = pure (Left uncertain)
  onHttp err@(InvalidUrlException _ _) = pure (Left (classifyHttp err))
  onHttp _ = pure (Left uncertain)

providerOf :: Env -> Provider
providerOf = HttpProvider . T.unpack . endpointText . configEndpoint . envConfig

-- | Lecturas y envío a @confirmed@, independientemente de la configuración.
confirmedOptions :: ConfigurationObject
confirmedOptions = defaultConfigObject{commitment = Just "confirmed"}

-- | @getLatestBlockhash@ con objeto de configuración (commitment).
getLatestBlockhashWith ::
  (JsonRpc m) =>
  ConfigurationObject ->
  m (RPCResponse LatestBlockHash)
getLatestBlockhashWith = remote "getLatestBlockhash"

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
