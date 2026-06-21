module Application.Helper.EmailVerification where

import Application.Helper.Mail
import Application.Helper.Url (appendQueryParams)
import qualified Data.UUID as UUID
import qualified Data.UUID.V4 as UUIDv4
import IHP.EnvVar
import IHP.Mail
import System.Environment (lookupEnv)
import Web.Controller.Prelude
import Web.Mail.Users.EmailVerification
import Web.Types

verificationTokenLifetime :: NominalDiffTime
verificationTokenLifetime = 60 * 60 * 24

issueEmailVerification :: (?context :: ControllerContext, ?modelContext :: ModelContext) => User -> IO EmailVerificationToken
issueEmailVerification user = do
    token <- UUID.toText <$> UUIDv4.nextRandom
    now <- getCurrentTime
    let expiresAt = addUTCTime verificationTokenLifetime now
    let verificationToken =
            newRecord @EmailVerificationToken
                |> set #userId (unpackId user.id)
                |> set #token token
                |> set #sentToEmail user.email
                |> set #expiresAt expiresAt
    verificationToken |> createRecord

sendEmailVerification :: (?context :: ControllerContext, ?modelContext :: ModelContext) => User -> IO EmailVerificationToken
sendEmailVerification user = do
    verificationToken <- issueEmailVerification user
    AppMailSettings { .. } <- loadAppMailSettings
    appBaseUrl :: Text <- envOrDefault "APP_BASE_URL" "http://localhost:8000"
    emailDeliveryDisabled <- isEmailDeliveryDisabled
    let verificationUrl =
            appBaseUrl <> appendQueryParams (pathTo VerifyEmailAction) [("token", verificationToken.token)]
    unless emailDeliveryDisabled do
        sendMail EmailVerificationMail
            { user = user
            , verificationUrl = verificationUrl
            , fromAddress = mailFromAddress
            , replyToAddress = mailReplyToAddress
            , supportEmail = mailSupportEmail
            }
    pure verificationToken

findActiveVerificationTokenByToken :: (?modelContext :: ModelContext) => Text -> IO (Maybe EmailVerificationToken)
findActiveVerificationTokenByToken token =
    query @EmailVerificationToken
        |> filterWhere (#token, token)
        |> filterWhere (#consumedAt, Nothing)
        |> filterWhereFuture #expiresAt
        |> fetchOneOrNothing

isEmailDeliveryDisabled :: IO Bool
isEmailDeliveryDisabled =
    lookupEnv "DISABLE_EMAIL_DELIVERY" >>= \case
        Just "1" -> pure True
        Just "true" -> pure True
        Just "TRUE" -> pure True
        _ -> pure False
