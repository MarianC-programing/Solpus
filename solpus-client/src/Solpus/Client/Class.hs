{- | Interfaz de Solpus con la red de Solana.

Es la única cosa de @solpus-client@ que debe conocer @solpus-app@. La
implementación real (sobre el SDK) y el intérprete en memoria
("Solpus.Client.InMemory") la satisfacen por igual, de modo que los casos de
uso se prueban sin red.

Está dividida en dos clases por /mínimo privilegio/: una función con la
restricción 'MonadSolanaRead' puede consultar la red pero __no puede gastar
dinero__; solo las que piden 'MonadSolana' pueden enviar transferencias. El
compilador lo hace cumplir.

Las claves privadas __no__ aparecen aquí: quién firma una transferencia lo
resuelve la implementación real con su wallet (issue #8).
-}
module Solpus.Client.Class
  ( MonadSolanaRead (..)
  , MonadSolana (..)
  , Transfer (..)
  ) where

import Solpus.Core.Error (SolpusError)
import Solpus.Core.Lamports (Lamports)
import Solpus.Core.Types (Address, Signature)

-- | Transferencia de SOL entre dos direcciones.
data Transfer = Transfer
  { transferFrom :: !Address
  , transferTo :: !Address
  , transferAmount :: !Lamports
  }
  deriving (Eq, Show)

{- | Consultas de solo lectura. Cada una devuelve un 'Either': los fallos de red
y del nodo son valores esperables, no excepciones.
-}
class (Monad m) => MonadSolanaRead m where
  {- | Saldo de una cuenta. Una cuenta que no existe tiene saldo cero, igual
  que en el RPC de Solana.
  -}
  getBalance :: Address -> m (Either SolpusError Lamports)

-- | Operaciones que cambian el estado de la red. Incluye las de solo lectura.
class (MonadSolanaRead m) => MonadSolana m where
  {- | Envía una transferencia y devuelve su firma. Que la firma llegue a un
  nivel de confirmación concreto es asunto de otra operación (issue #10).
  -}
  submitTransfer :: Transfer -> m (Either SolpusError Signature)
