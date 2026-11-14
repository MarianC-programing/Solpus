{- | Interfaz de Solpus con la red de Solana.

Es la única cosa de @solpus-client@ que debe conocer @solpus-app@. La
implementación real (sobre el SDK) y el intérprete en memoria
("Solpus.Client.InMemory") la satisfacen por igual, de modo que los casos de
uso se prueban sin red.

Las claves privadas __no__ aparecen aquí: quién firma una transferencia lo
resuelve la implementación real con su wallet (issue #8).
-}
module Solpus.Client.Class
  ( MonadSolana (..)
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

{- | Operaciones sobre la red. Cada una devuelve un 'Either': los fallos de red
y del nodo son valores esperables, no excepciones.
-}
class (Monad m) => MonadSolana m where
  {- | Saldo de una cuenta. Una cuenta que no existe tiene saldo cero, igual
  que en el RPC de Solana.
  -}
  getBalance :: Address -> m (Either SolpusError Lamports)

  {- | Envía una transferencia y devuelve su firma. Que la firma llegue a un
  nivel de confirmación concreto es asunto de otra operación (issue #10).
  -}
  submitTransfer :: Transfer -> m (Either SolpusError Signature)
