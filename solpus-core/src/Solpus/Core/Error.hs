{- | Errores del dominio. Cubren las tres familias observadas en el spike #4
(validación, RPC y red). Ningún constructor guarda secretos.
-}
module Solpus.Core.Error
  ( SolpusError (..)
  , ValidationError (..)
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

-- | Error de la API pública de Solpus.
data SolpusError
  = -- | Entrada inválida, detectada antes de enviar nada.
    ValidationFailed !ValidationError
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
