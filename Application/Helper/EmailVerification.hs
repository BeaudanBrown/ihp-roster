module Application.Helper.EmailVerification where

import Application.AccountSecurityEmail.Enqueue (enqueueEmailVerificationDelivery)
import Application.AccountSecurityEmail.Types (accountRecoveryRequestCooldown)
import Application.PasswordReset.Mutations (withPasswordResetUserLock)
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
        now <- getCurrentTime
        issueEmailVerificationInCurrentTransaction user now

issueEmailVerificationWithCooldown :: (?modelContext :: ModelContext) => User -> IO Bool
issueEmailVerificationWithCooldown user = do
    now <- getCurrentTime
    maybeIssued <- withPasswordResetUserLock (unpackId user.id) do
        latestToken <- query @EmailVerificationToken
            |> filterWhere (#userId, unpackId user.id)
            |> orderByDesc #createdAt
            |> limit 1
            |> fetchOneOrNothing
        case latestToken of
            Just token | diffUTCTime now token.createdAt < accountRecoveryRequestCooldown -> pure False
            _ -> True <$ issueEmailVerificationInCurrentTransaction user now
    pure (fromMaybe False maybeIssued)

issueEmailVerificationInCurrentTransaction :: (?modelContext :: ModelContext) => User -> UTCTime -> IO EmailVerificationToken
issueEmailVerificationInCurrentTransaction user now = do
    token <- UUID.toText <$> UUIDv4.nextRandom
    verificationToken <-
        newRecord @EmailVerificationToken
            |> set #userId (unpackId user.id)
            |> set #token token
            |> set #sentToEmail user.email
            |> set #expiresAt (addUTCTime verificationTokenLifetime now)
            |> createRecord
    void (enqueueEmailVerificationDelivery verificationToken user)
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
