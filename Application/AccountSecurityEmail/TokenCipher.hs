{-# LANGUAGE PackageImports #-}

module Application.AccountSecurityEmail.TokenCipher
    ( decryptAccountSecurityDeliveryToken
    , encryptAccountSecurityDeliveryToken
    ) where

import qualified "crypton" Crypto.Cipher.AES as AES
import qualified "crypton" Crypto.Cipher.Types as Cipher
import qualified "crypton" Crypto.Error as Crypto
import qualified "crypton" Crypto.Hash as Hash
import qualified "crypton" Crypto.MAC.HMAC as HMAC
import qualified "crypton" Crypto.Random as Random
import qualified Data.ByteArray as ByteArray
import qualified Data.ByteString as ByteString
import qualified Data.ByteString.Base64 as Base64
import qualified Data.Text as Text
import qualified Data.Text.Encoding as TextEncoding
import IHP.Prelude
import qualified System.Directory as Directory
import System.Environment (lookupEnv)

cipherVersion :: Text
cipherVersion = "v1"

authenticatedContext :: ByteString
authenticatedContext = "bepis-account-security-delivery-token-v1"

keyDerivationContext :: ByteString
keyDerivationContext = "bepis-account-security-delivery-token-key-v1"

encryptAccountSecurityDeliveryToken :: Text -> IO Text
encryptAccountSecurityDeliveryToken plaintext = do
    keyMaterial <- loadAccountSecurityKeyMaterial
    nonce <- Random.getRandomBytes 12
    cipher <- accountSecurityCipher keyMaterial
    aead <- cryptoOrFail "Could not initialize account-security token encryption" (Cipher.aeadInit Cipher.AEAD_GCM cipher nonce)
    let (authTag, ciphertext) =
            Cipher.aeadSimpleEncrypt
                aead
                authenticatedContext
                (TextEncoding.encodeUtf8 plaintext)
                16
    pure $
        Text.intercalate
            ":"
            [ cipherVersion
            , encodeBase64 nonce
            , encodeBase64 ciphertext
            , encodeBase64 (ByteArray.convert (Cipher.unAuthTag authTag) :: ByteString)
            ]

decryptAccountSecurityDeliveryToken :: Text -> IO (Either Text Text)
decryptAccountSecurityDeliveryToken encrypted = do
    keyMaterial <- loadAccountSecurityKeyMaterial
    pure do
        (nonce, ciphertext, authTagBytes) <- parseCiphertext encrypted
        cipher <- cryptoToEither "Could not initialize account-security token decryption" (Cipher.cipherInit (derivedKey keyMaterial) :: Crypto.CryptoFailable AES.AES256)
        aead <- cryptoToEither "Could not initialize account-security token decryption" (Cipher.aeadInit Cipher.AEAD_GCM cipher nonce)
        plaintext <-
            maybe
                (Left "Account-security delivery token authentication failed")
                Right
                ( Cipher.aeadSimpleDecrypt
                    aead
                    authenticatedContext
                    ciphertext
                    (Cipher.AuthTag (ByteArray.convert authTagBytes))
                )
        case TextEncoding.decodeUtf8' plaintext of
            Left _      -> Left "Account-security delivery token was not valid UTF-8"
            Right value -> Right value

parseCiphertext :: Text -> Either Text (ByteString, ByteString, ByteString)
parseCiphertext value =
    case Text.splitOn ":" value of
        [version, encodedNonce, encodedCiphertext, encodedAuthTag]
            | version == cipherVersion ->
                (,,)
                    <$> decodeBase64 encodedNonce
                    <*> decodeBase64 encodedCiphertext
                    <*> decodeBase64 encodedAuthTag
        _ -> Left "Unsupported account-security delivery token ciphertext"

accountSecurityCipher :: ByteString -> IO AES.AES256
accountSecurityCipher keyMaterial =
    cryptoOrFail
        "Could not initialize account-security token encryption"
        (Cipher.cipherInit (derivedKey keyMaterial))

derivedKey :: ByteString -> ByteString
derivedKey keyMaterial =
    ByteArray.convert (HMAC.hmac keyMaterial keyDerivationContext :: HMAC.HMAC Hash.SHA256)

loadAccountSecurityKeyMaterial :: IO ByteString
loadAccountSecurityKeyMaterial = do
    lookupEnv "IHP_SESSION_SECRET_FILE" >>= \case
        Just path -> ByteString.readFile path
        Nothing ->
            lookupEnv "IHP_SESSION_SECRET" >>= \case
                Just value ->
                    case Base64.decode (TextEncoding.encodeUtf8 (cs value)) of
                        Left _ -> ioError (userError "IHP session secret is not valid base64")
                        Right keyMaterial -> pure keyMaterial
                Nothing -> do
                    let developmentPath = "Config/client_session_key.aes"
                    exists <- Directory.doesFileExist developmentPath
                    if exists
                        then ByteString.readFile developmentPath
                        else ioError (userError "Account-security token encryption key is unavailable")

decodeBase64 :: Text -> Either Text ByteString
decodeBase64 encoded =
    case Base64.decode (TextEncoding.encodeUtf8 encoded) of
        Left _      -> Left "Account-security delivery token ciphertext is malformed"
        Right value -> Right value

encodeBase64 :: ByteString -> Text
encodeBase64 = TextEncoding.decodeUtf8 . Base64.encode

cryptoOrFail :: Text -> Crypto.CryptoFailable value -> IO value
cryptoOrFail message = \case
    Crypto.CryptoPassed value -> pure value
    Crypto.CryptoFailed _     -> ioError (userError (cs message))

cryptoToEither :: Text -> Crypto.CryptoFailable value -> Either Text value
cryptoToEither message = \case
    Crypto.CryptoPassed value -> Right value
    Crypto.CryptoFailed _     -> Left message
