{- | Errores del dominio. Cubren las tres familias observadas en el spike #4
(validación, RPC y red). Ningún constructor guarda secretos.
-}
module Solpus.Core.Error
  ( SolpusError (..)
  , ValidationError (..)
  , WalletError (..)
  ) where

import Data.Text (Text)

-- | Error de entrada que se detecta sin tocar la red.
data ValidationError
  = -- | Carácter fuera del alfabeto base58.
    InvalidBase58
  | -- | Longitud en bytes distinta de la esperada.
    InvalidByteLength {expected :: !Int, actual :: !Int}
  | -- | Texto de entrada más largo de lo permitido.
    InputTooLong {maxAllowed :: !Int}
  | -- | Un importe que no es un número decimal sin signo.
    InvalidAmountSyntax
  | -- | Más decimales de los que admite la unidad.
    TooManyDecimals {maxDecimals :: !Int}
  | -- | Importe negativo.
    NegativeAmount
  | -- | Importe que no cabe en 64 bits.
    AmountOverflow
  | -- | Resta que dejaría el saldo por debajo de cero.
    InsufficientLamports
  | {- | Endpoint que no es una URL http(s) válida, que lleva credenciales
    (@usuario:clave@) o que usa http fuera de localhost. No se guarda el texto
    recibido: puede contener una clave de API.
    -}
    InvalidEndpoint
  | -- | Timeout fuera del rango permitido, en segundos.
    InvalidTimeout {minSeconds :: !Int, maxSeconds :: !Int}
  deriving (Eq, Show)

{- | Fallo al cargar la clave de firma. Ningún constructor lleva datos: ni la
clave, ni su contenido, ni la ruta ni el texto de la variable de entorno.
-}
data WalletError
  = -- | El archivo no existe.
    WalletFileNotFound
  | -- | El archivo existe pero no se pudo abrir o leer.
    WalletUnreadable
  | -- | No es un archivo regular (directorio, dispositivo o enlace simbólico).
    WalletNotRegularFile
  | -- | Tiene permisos de grupo u otros; solo se admite 0600 o más estricto.
    WalletInsecurePermissions
  | -- | No pertenece al usuario que ejecuta el proceso.
    WalletWrongOwner
  | -- | Supera el tamaño máximo permitido.
    WalletFileTooLarge
  | -- | La variable de entorno no está definida.
    WalletEnvNotSet
  | -- | El contenido no es un arreglo JSON de 64 bytes.
    WalletInvalidFormat
  | -- | La mitad pública no corresponde a la semilla.
    WalletKeyMismatch
  deriving (Eq, Show)

-- | Error de la API pública de Solpus.
data SolpusError
  = -- | Entrada inválida, detectada antes de enviar nada.
    ValidationFailed !ValidationError
  | -- | No se pudo cargar la clave de firma.
    WalletFailed !WalletError
  | -- | El nodo respondió con un error JSON-RPC.
    RpcError {rpcCode :: !Int, rpcMessage :: !Text}
  | {- | No se pudo hablar con el nodo. El texto es una descripción fija del
    fallo: nunca incluye la URL, que puede llevar una clave de API.
    -}
    NetworkFailure !Text
  | -- | El nodo respondió algo que Solpus no sabe interpretar.
    InvalidResponse !Text
  | {- | Defecto de Solpus, por ejemplo una incoherencia con el SDK. No es un
    error del usuario ni de la red.
    -}
    InternalError !Text
  deriving (Eq, Show)
