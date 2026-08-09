{-# LANGUAGE PackageImports #-}

module Application.Helper.PasswordResetTokens
    ( activePasswordResetTokenById
    , findActivePasswordResetToken
    , issuePasswordResetToken
    , passwordResetTokenLifetime
    , sendPasswordResetTokenEmail
    ) where

import Application.Helper.EmailVerification (isEmailDeliveryDisabled)
import Application.Helper.Mail
import Application.Helper.Url (appendQueryParams)
import Application.PasswordReset.Mutations (withPasswordResetUserLock)
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
import Web.Mail.Users.PasswordReset
import Web.Types

passwordResetTokenLifetime :: NominalDiffTime
passwordResetTokenLifetime = 60 * 60

issuePasswordResetToken ::
    (?modelContext :: ModelContext) =>
    User ->
    Id User ->
    Id Venue ->
    IO (PasswordResetToken, Text)
issuePasswordResetToken targetUser requestedByUserId venueId = do
    rawToken <- generatePasswordResetToken
    now <- getCurrentTime
    maybeToken <- withPasswordResetUserLock (unpackId targetUser.id) do
        existingTokens <- query @PasswordResetToken
            |> filterWhere (#userId, unpackId targetUser.id)
            |> filterWhere (#consumedAt, Nothing)
            |> fetch
        forM_ existingTokens \token ->
            token
                |> set #consumedAt (Just now)
                |> updateRecordDiscardResult
        token <- newRecord @PasswordResetToken
            |> set #userId (unpackId targetUser.id)
            |> set #requestedByUserId (Just (unpackId requestedByUserId))
            |> set #venueId (unpackId venueId)
            |> set #tokenHash (hashPasswordResetToken rawToken)
            |> set #sentToEmail targetUser.email
            |> set #expiresAt (addUTCTime passwordResetTokenLifetime now)
            |> createRecord
        pure token
    case maybeToken of
        Just token -> pure (token, rawToken)
        Nothing -> error "Password reset target disappeared while issuing token"

sendPasswordResetTokenEmail ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    User ->
    Text ->
    IO ()
sendPasswordResetTokenEmail targetUser rawToken = do
    AppMailSettings { .. } <- loadAppMailSettings
    appBaseUrl :: Text <- envOrDefault "APP_BASE_URL" "http://localhost:8000"
    emailDeliveryDisabled <- isEmailDeliveryDisabled
    let resetUrl = appBaseUrl <> appendQueryParams (pathTo NewPasswordResetAction) [("token", rawToken)]
    unless emailDeliveryDisabled do
        sendMail PasswordResetMail
            { user = targetUser
            , resetUrl
            , fromAddress = mailFromAddress
            , replyToAddress = mailReplyToAddress
            , supportEmail = mailSupportEmail
            }

findActivePasswordResetToken :: (?modelContext :: ModelContext) => Text -> IO (Maybe PasswordResetToken)
findActivePasswordResetToken rawToken =
    query @PasswordResetToken
        |> filterWhere (#tokenHash, hashPasswordResetToken rawToken)
        |> filterWhere (#consumedAt, Nothing)
        |> filterWhereFuture #expiresAt
        |> fetchOneOrNothing

activePasswordResetTokenById :: (?modelContext :: ModelContext) => Id PasswordResetToken -> IO (Maybe PasswordResetToken)
activePasswordResetTokenById tokenId =
    query @PasswordResetToken
        |> filterWhere (#id, tokenId)
        |> filterWhere (#consumedAt, Nothing)
        |> filterWhereFuture #expiresAt
        |> fetchOneOrNothing

generatePasswordResetToken :: IO Text
generatePasswordResetToken = do
    randomBytes <- getRandomBytes 32 :: IO ByteString.ByteString
    pure (TextEncoding.decodeUtf8 (Base64.encode randomBytes))

hashPasswordResetToken :: Text -> Text
hashPasswordResetToken rawToken =
    bytesToHex (ByteArray.convert (Hash.hash (TextEncoding.encodeUtf8 rawToken) :: Hash.Digest Hash.SHA256))

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
