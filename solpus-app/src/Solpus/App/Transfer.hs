{- | Caso de uso: transferir SOL.

Solo conoce la interfaz 'MonadSolana' (comprobado por
@scripts/check-boundaries.sh@): no sabe si detrás hay un nodo real o el
intérprete en memoria, ni qué wallet firma.

Las reglas del dominio que no dependen de la red se aplican aquí, antes de
delegar: una transferencia de cero lamports no tiene sentido y se rechaza. El
resto (origen igual a la wallet, red permitida, saldo suficiente) lo decide
la implementación, que es quien conoce la wallet y el nodo.

__Un resultado incierto__ ('SubmissionUncertain') no es un fallo ni un éxito:
la transacción pudo haber entrado. Este caso de uso lo devuelve tal cual, con
la firma y la última altura válida, y __nunca reintenta__.
-}
module Solpus.App.Transfer
  ( transferSol
  ) where

import Solpus.Client.Class (MonadSolana (..), Transfer (..))
import Solpus.Core.Error (SolpusError (..), ValidationError (..))
import Solpus.Core.Lamports (Lamports (..))
import Solpus.Core.Types (Signature)

-- | Envía una transferencia de SOL. Devuelve la firma de la transacción.
transferSol :: (MonadSolana m) => Transfer -> m (Either SolpusError Signature)
transferSol transfer
  | transferAmount transfer == Lamports 0 = pure (Left (ValidationFailed ZeroAmount))
  | otherwise = submitTransfer transfer
