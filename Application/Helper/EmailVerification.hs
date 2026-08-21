module Application.Helper.EmailVerification where

import Application.AccountSecurityEmail.Enqueue (enqueueEmailVerificationDelivery)
import Control.Monad (void)
import qualified Data.UUID as UUID
import qualified Data.UUID.V4 as UUIDv4
import System.Environment (lookupEnv)
import Web.Controller.Prelude

verificationTokenLifetime :: NominalDiffTime
verificationTokenLifetime = 60 * 60 * 24

issueEmailVerification :: (?modelContext :: ModelContext) => User -> IO EmailVerificationToken
issueEmailVerification user =
    withTransaction do
        token <- UUID.toText <$> UUIDv4.nextRandom
        now <- getCurrentTime
        verificationToken <-
            newRecord @EmailVerificationToken
                |> set #userId (unpackId user.id)
                |> set #token token
                |> set #sentToEmail user.email
                |> set #expiresAt (addUTCTime verificationTokenLifetime now)
                |> createRecord
        void (enqueueEmailVerificationDelivery verificationToken user)
        pure verificationToken

sendEmailVerification :: (?modelContext :: ModelContext) => User -> IO EmailVerificationToken
sendEmailVerification = issueEmailVerification

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
