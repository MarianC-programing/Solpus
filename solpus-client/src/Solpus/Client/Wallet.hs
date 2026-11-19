{-# LANGUAGE OverloadedStrings #-}

{- | Carga de la clave que firma las transacciones.

Es, junto con @Rpc@ y @Tx@, uno de los pocos módulos que importan el SDK
(comprobado por @scripts/check-boundaries.sh@).

Una clave privada es la operación más sensible del proyecto, así que:

* 'Wallet' es abstracto, no tiene @Eq@ y su 'Show' solo enseña la dirección
  pública. El @Show@ de la clave del SDK imprime la clave en base58; aquí
  nunca se invoca.
* Ningún error contiene la clave, su contenido, el texto de la variable de
  entorno ni la ruta del archivo ('WalletError' son constructores sin datos).
* El archivo se abre sin seguir enlaces simbólicos y todas las comprobaciones
  (tipo, dueño, permisos y tamaño) se hacen sobre el descriptor ya abierto,
  de modo que no hay carrera entre comprobar y leer.
* Se rechaza cualquier permiso de grupo u otros, y también bits de ejecución:
  solo vale @0600@ o más estricto.

Formato aceptado: el de @solana-keygen@, un arreglo JSON de 64 enteros entre 0
y 255 (semilla de 32 bytes más clave pública de 32). Solo POSIX.
-}
module Solpus.Client.Wallet
  ( Wallet
  , walletAddress
  , signInstructions
  , loadWalletFile
  , loadWalletEnv
  , parseKeyBytes
  , maxKeyFileBytes
  ) where

import Control.Exception (IOException, try)
import Data.Bits ((.&.))
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BC
import Data.Char (isAscii, isDigit)
import Foreign.C.Error (Errno (..), eLOOP)
import GHC.IO.Exception (IOException (ioe_errno))
import Network.Solana.Core.Block (BlockHash)
import Network.Solana.Core.Crypto
  ( SolanaPrivateKey
  , fromBase64String
  , mkPrivateKeyFromBytes
  , toSolanaPublicKey
  )
import Network.Solana.Core.Instruction (Instruction)
import Network.Solana.Core.Message (newTransactionIntentWithPayer)
import Solpus.Core.Error (SolpusError (..), WalletError (..))
import Solpus.Core.Types (Address, Signature, addressFromBytes, signatureFromBytes)
import System.Environment (lookupEnv)
import System.IO (hClose)
import System.IO.Error (isDoesNotExistError)
import System.Posix.Files
  ( FileStatus
  , fileMode
  , fileOwner
  , fileSize
  , getFdStatus
  , isRegularFile
  )
import System.Posix.IO
  ( OpenFileFlags (nofollow)
  , OpenMode (ReadOnly)
  , closeFd
  , defaultFileFlags
  , fdToHandle
  , openFd
  )
import System.Posix.Types (UserID)
import System.Posix.User (getEffectiveUserID)

{- | Clave de firma cargada y su dirección pública. La clave no se expone: lo
único que sale de este módulo es una transacción ya firmada
('signInstructions').
-}
data Wallet = Wallet !SolanaPrivateKey !Address

-- | Solo la dirección pública; nunca la clave.
instance Show Wallet where
  show (Wallet _ address) = "Wallet " <> show address

-- | Dirección pública de la wallet.
walletAddress :: Wallet -> Address
walletAddress (Wallet _ address) = address

{- | Firma una transacción cuyo pagador es la wallet. Devuelve la transacción
serializada en base64, lista para @sendTransaction@, y su firma: la firma de
una transacción se conoce antes de enviarla, y es lo que permite consultar su
estado si el envío resulta incierto. Es la única vía por la que la clave se
usa fuera de la carga; nunca sale de este módulo.
-}
signInstructions :: Wallet -> BlockHash -> [Instruction] -> Either SolpusError (String, Signature)
signInstructions (Wallet key _) blockhash instructions =
  case newTransactionIntentWithPayer (toSolanaPublicKey key) [key] instructions blockhash of
    Left _ -> Left (InternalError "no se pudo compilar la transacción")
    Right payload ->
      -- Formato de red: contador compacto (1 byte con una sola firma) y la firma.
      let raw = fromBase64String payload
       in case signatureFromBytes (BS.take 64 (BS.drop 1 raw)) of
            Right signature | BS.length raw > 65 -> Right (payload, signature)
            _ -> Left (InternalError "la transacción firmada no tiene el formato esperado")

-- | Tamaño máximo del archivo de clave, en bytes (un keypair ocupa ~230).
maxKeyFileBytes :: Int
maxKeyFileBytes = 1024

{- | Carga una wallet desde un archivo de keypair. Falla con un error tipado si
el archivo no es regular, es un enlace simbólico, no es del usuario actual,
tiene permisos de grupo u otros, es demasiado grande o su contenido no es una
clave válida.
-}
loadWalletFile :: FilePath -> IO (Either SolpusError Wallet)
loadWalletFile path = do
  opened <- try (openFd path ReadOnly defaultFileFlags{nofollow = True})
  case opened of
    Left err -> pure (Left (WalletFailed (classifyOpen err)))
    Right fd -> do
      status <- getFdStatus fd
      uid <- getEffectiveUserID
      case checkStatus uid status of
        Just refusal -> closeFd fd >> pure (Left (WalletFailed refusal))
        Nothing -> do
          handle <- fdToHandle fd
          contents <- try (BS.hGet handle (maxKeyFileBytes + 1))
          hClose handle
          pure $ case contents of
            Left (_ :: IOException) -> Left (WalletFailed WalletUnreadable)
            Right bytes
              | BS.length bytes > maxKeyFileBytes -> Left (WalletFailed WalletFileTooLarge)
              | otherwise -> buildWallet bytes

{- | Carga una wallet desde una variable de entorno que contiene el mismo
arreglo JSON que el archivo. Es más débil que el archivo: otros procesos del
mismo usuario pueden leer el entorno (@/proc/<pid>/environ@).
-}
loadWalletEnv :: String -> IO (Either SolpusError Wallet)
loadWalletEnv name = do
  value <- lookupEnv name
  pure $ case value of
    Nothing -> Left (WalletFailed WalletEnvNotSet)
    Just text
      | length text > maxKeyFileBytes -> Left (WalletFailed WalletFileTooLarge)
      | not (all isAscii text) -> Left (WalletFailed WalletInvalidFormat)
      | otherwise -> buildWallet (BC.pack text)

-- | Un error de apertura: ausente, enlace simbólico (ELOOP) u otro fallo.
classifyOpen :: IOException -> WalletError
classifyOpen err
  | isDoesNotExistError err = WalletFileNotFound
  | ioe_errno err == Just (let Errno n = eLOOP in n) = WalletNotRegularFile
  | otherwise = WalletUnreadable

{- | Comprueba tipo, dueño, permisos y tamaño de un archivo ya abierto. Los
permisos válidos son @0600@ o más estrictos: cualquier otro bit es un error.
-}
checkStatus :: UserID -> FileStatus -> Maybe WalletError
checkStatus uid status
  | not (isRegularFile status) = Just WalletNotRegularFile
  | fileOwner status /= uid = Just WalletWrongOwner
  | fromIntegral (fileMode status) .&. (0o7177 :: Integer) /= 0 = Just WalletInsecurePermissions
  | fromIntegral (fileSize status) > toInteger maxKeyFileBytes = Just WalletFileTooLarge
  | otherwise = Nothing

-- | Del texto JSON a una 'Wallet', validando la clave con el SDK.
buildWallet :: ByteString -> Either SolpusError Wallet
buildWallet text = case parseKeyBytes text of
  Nothing -> Left (WalletFailed WalletInvalidFormat)
  Just bytes -> case (mkPrivateKeyFromBytes bytes, addressFromBytes (BS.drop 32 bytes)) of
    (Right key, Right address) -> Right (Wallet key address)
    _ -> Left (WalletFailed WalletKeyMismatch)

{- | Lee un arreglo JSON de exactamente 64 enteros entre 0 y 255. Es total,
no conserva el texto en ningún error, rechaza ceros a la izquierda (como JSON)
y no admite nada más que espacios fuera del arreglo.
-}
parseKeyBytes :: ByteString -> Maybe ByteString
parseKeyBytes input = do
  afterOpen <- BC.stripPrefix "[" (dropSpaces input)
  values <- go [] (dropSpaces afterOpen)
  if length values == 64 then Just (BS.pack values) else Nothing
 where
  go acc rest = do
    let (digits, afterDigits) = BC.span isDigit rest
    n <- byteValue digits
    let acc' = n : acc
    if length acc' > 64
      then Nothing
      else case BC.uncons (dropSpaces afterDigits) of
        Just (',', more) -> go acc' (dropSpaces more)
        Just (']', trailing) | BC.all isSpace' trailing -> Just (reverse acc')
        _ -> Nothing
  dropSpaces = BC.dropWhile isSpace'
  isSpace' c = c `elem` (" \t\r\n" :: String)
  byteValue digits
    | BS.null digits || BS.length digits > 3 = Nothing
    | BS.length digits > 1 && BC.head digits == '0' = Nothing -- JSON no admite ceros a la izquierda
    | otherwise =
        let n = BC.foldl' (\acc c -> acc * 10 + fromEnum c - fromEnum '0') 0 digits
         in if n <= 255 then Just (fromIntegral n) else Nothing
