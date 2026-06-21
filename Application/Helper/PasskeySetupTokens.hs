{-# LANGUAGE PackageImports #-}

module Application.Helper.PasskeySetupTokens
    ( PasskeySetupTokenPurpose (..)
    , findActivePasskeySetupToken
    , issuePasskeySetupToken
    , passkeySetupTokenLifetime
    , sendPasskeySetupTokenEmail
    ) where

import Application.Helper.EmailVerification (isEmailDeliveryDisabled)
import Application.Helper.Mail
import Application.Helper.Url (appendQueryParams)
import qualified "crypton" Crypto.Hash as Hash
import "crypton" Crypto.Random (getRandomBytes)
import qualified Data.ByteArray as ByteArray
import qualified Data.ByteString as ByteString
import qualified Data.ByteString.Base64 as Base64
import qualified Data.Char as Char
import qualified Data.Text as Text
import qualified Data.Text.Encoding as TextEncoding
import IHP.EnvVar
import IHP.Mail
import Web.Controller.Prelude
import Web.Mail.Users.PasskeySetupLink
import Web.Types

data PasskeySetupTokenPurpose
    = SelfNewDevicePasskeySetup
    | StaffNewDevicePasskeySetup
    | StaffPasskeyRecovery
    deriving (Eq, Show)

passkeySetupTokenLifetime :: NominalDiffTime
passkeySetupTokenLifetime = 60 * 60

issuePasskeySetupToken ::
    (?modelContext :: ModelContext) =>
    PasskeySetupTokenPurpose ->
    User ->
    Maybe (Id User) ->
    Maybe (Id Venue) ->
    IO (PasskeySetupToken, Text)
issuePasskeySetupToken purpose targetUser requestedByUserId venueId = do
    rawToken <- generatePasskeySetupToken
    now <- getCurrentTime
    let expiresAt = addUTCTime passkeySetupTokenLifetime now
    setupToken <- newRecord @PasskeySetupToken
        |> set #userId (unpackId targetUser.id)
        |> set #requestedByUserId (unpackId <$> requestedByUserId)
        |> set #venueId (unpackId <$> venueId)
        |> set #tokenHash (hashPasskeySetupToken rawToken)
        |> set #purpose (passkeySetupTokenPurposeText purpose)
        |> set #sentToEmail targetUser.email
        |> set #expiresAt expiresAt
        |> createRecord
    pure (setupToken, rawToken)

sendPasskeySetupTokenEmail ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    User ->
    PasskeySetupTokenPurpose ->
    Text ->
    IO ()
sendPasskeySetupTokenEmail targetUser purpose rawToken = do
    AppMailSettings { .. } <- loadAppMailSettings
    appBaseUrl :: Text <- envOrDefault "APP_BASE_URL" "http://localhost:8000"
    emailDeliveryDisabled <- isEmailDeliveryDisabled
    let setupUrl = appBaseUrl <> appendQueryParams (pathTo NewPasskeySetupAction) [("token", rawToken)]
    unless emailDeliveryDisabled do
        sendMail PasskeySetupLinkMail
            { user = targetUser
            , setupUrl = setupUrl
            , fromAddress = mailFromAddress
            , replyToAddress = mailReplyToAddress
            , supportEmail = mailSupportEmail
            , purposeLabel = passkeySetupTokenPurposeEmailLabel purpose
            }

findActivePasskeySetupToken :: (?modelContext :: ModelContext) => Text -> IO (Maybe PasskeySetupToken)
findActivePasskeySetupToken rawToken =
    query @PasskeySetupToken
        |> filterWhere (#tokenHash, hashPasskeySetupToken rawToken)
        |> filterWhere (#consumedAt, Nothing)
        |> filterWhereFuture #expiresAt
        |> fetchOneOrNothing

generatePasskeySetupToken :: IO Text
generatePasskeySetupToken = do
    randomBytes <- getRandomBytes 32 :: IO ByteString.ByteString
    pure (TextEncoding.decodeUtf8 (Base64.encode randomBytes))

hashPasskeySetupToken :: Text -> Text
hashPasskeySetupToken rawToken =
    bytesToHex (ByteArray.convert (Hash.hash (TextEncoding.encodeUtf8 rawToken) :: Hash.Digest Hash.SHA256))

passkeySetupTokenPurposeText :: PasskeySetupTokenPurpose -> Text
passkeySetupTokenPurposeText SelfNewDevicePasskeySetup = "self_new_device"
passkeySetupTokenPurposeText StaffNewDevicePasskeySetup = "staff_new_device"
passkeySetupTokenPurposeText StaffPasskeyRecovery = "staff_recovery"

passkeySetupTokenPurposeEmailLabel :: PasskeySetupTokenPurpose -> Text
passkeySetupTokenPurposeEmailLabel SelfNewDevicePasskeySetup = "Set up a new passkey"
passkeySetupTokenPurposeEmailLabel StaffNewDevicePasskeySetup = "Set up a staff passkey"
passkeySetupTokenPurposeEmailLabel StaffPasskeyRecovery = "Recover passkey access"

bytesToHex :: ByteString.ByteString -> Text
bytesToHex =
    Text.concat . map byteToHex . ByteString.unpack
    where
        byteToHex byte =
            let high = fromIntegral byte `div` (16 :: Int)
                low = fromIntegral byte `mod` (16 :: Int)
             in Text.pack [hexDigit high, hexDigit low]

        hexDigit value
            | value < 10 = Char.chr (Char.ord '0' + value)
            | otherwise = Char.chr (Char.ord 'a' + value - 10)
