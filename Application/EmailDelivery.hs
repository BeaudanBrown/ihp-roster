{-# LANGUAGE RankNTypes #-}

module Application.EmailDelivery
    ( EmailDeliveryEnqueueResult (..)
    , EmailDeliveryRequest (..)
    , EmailDeliveryRuntime (..)
    , emailDeliveryJobKind
    , enqueueEmailDelivery
    , enqueueEmailDeliveryWithStatus
    , handleEmailDeliveryFailureAfterFinalAttempt
    , performEmailDeliveryJob
    , performEmailDeliveryJobWith
    ) where

import Application.AccountSecurityEmail.Email
import Application.AccountSecurityEmail.Mutations
import Application.AccountSecurityEmail.TokenCipher (AccountSecurityTokenCipherError (..))
import Application.AccountSecurityEmail.Types
import Application.Async.Boundary (throwAppJobError, trySynchronousAppJobAction)
import Application.Async.Error (AppJobError (..))
import Application.Async.Queue (appJobMaxAttempts)
import Application.Billing.NotificationEmail
import Application.EmailDelivery.Enqueue
import Application.Feedback.Email (feedbackSubmittedMailKind,
                                   loadFeedbackNotificationMail)
import Application.Helper.EmailVerification (isEmailDeliveryDisabled)
import Application.Helper.FrontendContract.Surface.Admin.Resource (adminInvitesResource)
import Application.Helper.Mail
import Application.Helper.SurfaceResource (liveMutationResult)
import Application.InvitationDelivery.Email
import Application.InvitationDelivery.Types
import Application.RosterNotification.Email
import Application.StaffDocuments.Rsa.Email
import Application.VenueInvitation.Mutations (withVenueInvitationLockInCurrentTransaction)
import Application.VenueOnboardingInvitation.Mutations (withVenueOnboardingInvitationLock)
import Application.WageSourceAlert.Email
import Application.WageSourceNotification.Email
import qualified Control.Exception as Exception
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import qualified Data.Set as Set
import Generated.Types
import IHP.ControllerPrelude
import IHP.EnvVar (envOrDefault)
import IHP.FrameworkConfig (ConfigProvider, FrameworkConfig)
import IHP.Job.Types (JobStatus (JobStatusSucceeded))
import IHP.Mail (sendMail)
import IHP.MailPrelude (BuildMail)
import IHP.ModelSupport (withTransaction)
import Web.SurfaceInvalidation (withDurableLiveMutationOutcomeWithoutContext,
                                withDurableLiveMutationWithoutContext)

data EmailDeliveryPayload = EmailDeliveryPayload
    { payloadMailKind           :: !Text
    , payloadRecipientAccountId :: !UUID
    , payloadRecipientAddress   :: !Text
    , payloadDomainReferenceId  :: !UUID
    }
    deriving (Eq, Show)

instance Aeson.FromJSON EmailDeliveryPayload where
    parseJSON = Aeson.withObject "EmailDeliveryPayload" \object ->
        EmailDeliveryPayload
            <$> object Aeson..: "mailKind"
            <*> object Aeson..: "recipientAccountId"
            <*> object Aeson..: "recipientAddress"
            <*> object Aeson..: "domainReferenceId"

data EmailDeliveryRuntime = EmailDeliveryRuntime
    { deliveryIsDisabled :: !(IO Bool)
    , deliverMail        :: !(forall mail. BuildMail mail => mail -> IO ())
    }

performEmailDeliveryJob ::
    (?context :: FrameworkConfig, ?modelContext :: ModelContext) =>
    AppJob ->
    IO ()
performEmailDeliveryJob =
    performEmailDeliveryJobWith
        EmailDeliveryRuntime
            { deliveryIsDisabled = isEmailDeliveryDisabled
            , deliverMail = sendMail
            }

performEmailDeliveryJobWith ::
    (?context :: context, ConfigProvider context, ?modelContext :: ModelContext) =>
    EmailDeliveryRuntime ->
    AppJob ->
    IO ()
performEmailDeliveryJobWith runtime@EmailDeliveryRuntime { deliverMail } appJob
    | appJob.payloadSchemaVersion /= 1 =
        throwAppJobError JobUnsupportedPayloadSchemaVersion
    | otherwise =
        case Aeson.fromJSON appJob.payload of
            Aeson.Error _ -> throwAppJobError JobMalformedPersistedPayload
            Aeson.Success payload ->
                performPayload (runtime { deliverMail = deliverJobMail deliverMail }) appJob payload
                    `Exception.catch` handleAccountSecurityCipherError

handleAccountSecurityCipherError :: AccountSecurityTokenCipherError -> IO value
handleAccountSecurityCipherError = \case
    AccountSecurityTokenCipherConfigurationUnavailable -> throwAppJobError JobConfigurationUnavailable
    AccountSecurityTokenCipherOperationFailed -> throwAppJobError JobCryptoUnavailable

-- SMTP diagnostics remain local to the provider boundary. Only the closed safe
-- transport classification reaches IHP.
deliverJobMail :: BuildMail mail => (forall value. BuildMail value => value -> IO ()) -> mail -> IO ()
deliverJobMail deliver mail =
    trySynchronousAppJobAction (deliver mail) >>= \case
        Left _ -> throwAppJobError JobTransportUnavailable
        Right () -> pure ()

performPayload ::
    (?context :: context, ConfigProvider context, ?modelContext :: ModelContext) =>
    EmailDeliveryRuntime ->
    AppJob ->
    EmailDeliveryPayload ->
    IO ()
performPayload EmailDeliveryRuntime { deliveryIsDisabled, deliverMail } appJob payload = do
    unless (knownEmailDeliveryMailKind payload.payloadMailKind) (throwAppJobError JobMalformedPersistedPayload)
    unless
        ( appJob.relatedId == Just payload.payloadDomainReferenceId
            && maybe False (emailDeliveryRelatedTableAllowed payload.payloadMailKind) appJob.relatedTable
        )
        (throwAppJobError JobInvalidProvenance)
    AppMailSettings { .. } <- loadAppMailSettings
    appBaseUrl :: Text <- envOrDefault "APP_BASE_URL" "http://localhost:8000"
    disabled <- deliveryIsDisabled
    if disabled
        then performDisabledPayload appJob payload AppMailSettings { .. } appBaseUrl
        else case payload.payloadMailKind of
            mailKind | mailKind == feedbackSubmittedMailKind -> do
                maybeMail <-
                    loadFeedbackNotificationMail
                        payload.payloadRecipientAddress
                        payload.payloadDomainReferenceId
                        AppMailSettings { .. }
                        appBaseUrl
                case maybeMail of
                    Nothing -> completeEmailDelivery appJob payload "delivery_skipped" (Just "domain_reference_missing")
                    Just mail -> do
                        deliverMail mail
                        completeEmailDelivery appJob payload "sent" Nothing
            mailKind | isWageSourceAlertMailKind mailKind -> do
                maybeMail <-
                    loadWageSourceAlertMail
                        mailKind
                        payload.payloadRecipientAddress
                        payload.payloadDomainReferenceId
                        AppMailSettings { .. }
                        appBaseUrl
                case maybeMail of
                    Nothing -> completeEmailDelivery appJob payload "delivery_skipped" (Just "domain_reference_missing")
                    Just mail -> do
                        deliverMail mail
                        completeEmailDelivery appJob payload "sent" Nothing
            mailKind | isAwardDriftMailKind mailKind -> do
                projection <-
                    loadAwardDriftMail
                        mailKind
                        payload.payloadRecipientAccountId
                        payload.payloadRecipientAddress
                        payload.payloadDomainReferenceId
                        AppMailSettings { .. }
                case projection of
                    AwardDriftMailSkipped reason -> completeEmailDelivery appJob payload "delivery_skipped" (Just reason)
                    AwardDriftMailReady mail -> do
                        deliverMail mail
                        completeEmailDelivery appJob payload "sent" Nothing
            mailKind | isBillingNotificationMailKind mailKind -> do
                projection <-
                    loadBillingNotificationMail
                        mailKind
                        payload.payloadRecipientAccountId
                        payload.payloadRecipientAddress
                        payload.payloadDomainReferenceId
                        AppMailSettings { .. }
                        appBaseUrl
                case projection of
                    BillingMailSkipped reason -> completeEmailDelivery appJob payload "delivery_skipped" (Just reason)
                    BillingMailReady mail -> do
                        deliverMail mail
                        completeEmailDelivery appJob payload "sent" Nothing
            mailKind | isRosterNotificationMailKind mailKind -> do
                validateRelatedTable appJob "roster_notification_runs" payload.payloadDomainReferenceId
                projection <-
                    loadRosterNotificationMail
                        mailKind
                        payload.payloadRecipientAccountId
                        payload.payloadRecipientAddress
                        payload.payloadDomainReferenceId
                        appJob.venueId
                        AppMailSettings { .. }
                        appBaseUrl
                case projection of
                    RosterNotificationMailSkipped reason -> completeEmailDelivery appJob payload "delivery_skipped" (Just reason)
                    RosterNotificationMailReady mail -> do
                        deliverMail mail
                        completeRosterNotificationDelivery appJob payload "sent"
            mailKind | isRsaReminderMailKind mailKind -> do
                validateRelatedTable appJob "staff_documents" payload.payloadDomainReferenceId
                projection <-
                    loadRsaReminderMail
                        mailKind
                        payload.payloadRecipientAccountId
                        payload.payloadRecipientAddress
                        payload.payloadDomainReferenceId
                        appJob.venueId
                        AppMailSettings { .. }
                case projection of
                    RsaReminderMailSkipped reason -> completeEmailDelivery appJob payload "delivery_skipped" (Just reason)
                    RsaReminderMailReady mail -> do
                        deliverMail mail
                        completeRsaReminderEmail appJob payload "sent"
            mailKind | isAccountSecurityMailKind mailKind ->
                performAccountSecurityPayload deliverMail "sent" appJob payload AppMailSettings { .. } appBaseUrl
            mailKind | mailKind == venueInvitationMailKind ->
                performVenueInvitationPayload deliverMail "sent" appJob payload AppMailSettings { .. } appBaseUrl
            mailKind | mailKind == venueOnboardingInvitationMailKind ->
                performVenueOnboardingInvitationPayload deliverMail "sent" appJob payload AppMailSettings { .. } appBaseUrl
            _ -> throwAppJobError JobMalformedPersistedPayload

knownEmailDeliveryMailKind :: Text -> Bool
knownEmailDeliveryMailKind mailKind =
    mailKind == feedbackSubmittedMailKind
        || isWageSourceAlertMailKind mailKind
        || isAwardDriftMailKind mailKind
        || isBillingNotificationMailKind mailKind
        || isRosterNotificationMailKind mailKind
        || isRsaReminderMailKind mailKind
        || isAccountSecurityMailKind mailKind
        || mailKind == venueInvitationMailKind
        || mailKind == venueOnboardingInvitationMailKind

emailDeliveryRelatedTableAllowed :: Text -> Text -> Bool
emailDeliveryRelatedTableAllowed mailKind relatedTable
    | mailKind == feedbackSubmittedMailKind = relatedTable == "user_feedback_items"
    | isWageSourceAlertMailKind mailKind = relatedTable == "app_jobs"
    | isAwardDriftMailKind mailKind = relatedTable == "fwc_mapd_awards"
    | isBillingNotificationMailKind mailKind = billingNotificationReferenceTable mailKind == Just relatedTable
    | isRosterNotificationMailKind mailKind = relatedTable == "roster_notification_runs"
    | isRsaReminderMailKind mailKind = relatedTable == "staff_documents"
    | isAccountSecurityMailKind mailKind = relatedTable == accountSecurityRelatedTable mailKind
    | mailKind == venueInvitationMailKind = relatedTable == "venue_invitations"
    | mailKind == venueOnboardingInvitationMailKind = relatedTable == "venue_onboarding_invitations"
    | otherwise = False

performDisabledPayload ::
    (?modelContext :: ModelContext) =>
    AppJob ->
    EmailDeliveryPayload ->
    AppMailSettings ->
    Text ->
    IO ()
performDisabledPayload appJob payload settings appBaseUrl
    | isRosterNotificationMailKind payload.payloadMailKind = do
        validateRelatedTable appJob "roster_notification_runs" payload.payloadDomainReferenceId
        projection <-
            loadRosterNotificationMail
                payload.payloadMailKind
                payload.payloadRecipientAccountId
                payload.payloadRecipientAddress
                payload.payloadDomainReferenceId
                appJob.venueId
                settings
                appBaseUrl
        case projection of
            RosterNotificationMailSkipped _ -> completeEmailDelivery appJob payload "delivery_disabled" Nothing
            RosterNotificationMailReady _ -> completeRosterNotificationDelivery appJob payload "delivery_disabled"
    | isRsaReminderMailKind payload.payloadMailKind = do
        validateRelatedTable appJob "staff_documents" payload.payloadDomainReferenceId
        projection <-
            loadRsaReminderMail
                payload.payloadMailKind
                payload.payloadRecipientAccountId
                payload.payloadRecipientAddress
                payload.payloadDomainReferenceId
                appJob.venueId
                settings
        case projection of
            RsaReminderMailSkipped _ -> completeEmailDelivery appJob payload "delivery_disabled" Nothing
            RsaReminderMailReady _ -> completeRsaReminderEmail appJob payload "delivery_disabled"
    | isAccountSecurityMailKind payload.payloadMailKind =
        performAccountSecurityPayload (\_ -> pure ()) "delivery_disabled" appJob payload settings appBaseUrl
    | payload.payloadMailKind == venueInvitationMailKind =
        performVenueInvitationPayload (\_ -> pure ()) "delivery_disabled" appJob payload settings appBaseUrl
    | payload.payloadMailKind == venueOnboardingInvitationMailKind =
        performVenueOnboardingInvitationPayload (\_ -> pure ()) "delivery_disabled" appJob payload settings appBaseUrl
    | otherwise = completeEmailDelivery appJob payload "delivery_disabled" Nothing

performAccountSecurityPayload ::
    (?modelContext :: ModelContext) =>
    (forall mail. BuildMail mail => mail -> IO ()) ->
    Text ->
    AppJob ->
    EmailDeliveryPayload ->
    AppMailSettings ->
    Text ->
    IO ()
performAccountSecurityPayload deliverMail deliveryStatus appJob payload settings appBaseUrl = do
    validateRelatedTable appJob (accountSecurityRelatedTable payload.payloadMailKind) payload.payloadDomainReferenceId
    lockedResult <- accountSecurityTokenLock payload.payloadMailKind payload.payloadDomainReferenceId do
        projection <-
            loadAccountSecurityMail
                payload.payloadMailKind
                payload.payloadRecipientAccountId
                payload.payloadRecipientAddress
                payload.payloadDomainReferenceId
                appJob.venueId
                settings
                appBaseUrl
        case projection of
            AccountSecurityMailSkipped reason
                | deliveryStatus == "delivery_disabled" ->
                    completeAccountSecurityDelivery appJob payload "delivery_disabled" Nothing
                | otherwise ->
                    completeAccountSecurityDelivery appJob payload "delivery_skipped" (Just reason)
            AccountSecurityMailReady mail -> do
                deliverAccountSecurityMail deliverMail mail
                completeAccountSecurityDelivery appJob payload deliveryStatus Nothing
    when (isNothing lockedResult) $
        completeEmailDelivery appJob payload "delivery_skipped" (Just "domain_reference_missing")

completeAccountSecurityDelivery ::
    (?modelContext :: ModelContext) =>
    AppJob ->
    EmailDeliveryPayload ->
    Text ->
    Maybe Text ->
    IO ()
completeAccountSecurityDelivery appJob payload deliveryStatus maybeReason = do
    -- The per-token lock owns the surrounding transaction so domain cleanup and
    -- shared completion commit together without nesting IHP transactions.
    completeAccountSecurityEmail payload.payloadMailKind payload.payloadDomainReferenceId
    completeEmailDelivery appJob payload deliveryStatus maybeReason

deliverAccountSecurityMail ::
    (forall mail. BuildMail mail => mail -> IO ()) ->
    AccountSecurityMail ->
    IO ()
deliverAccountSecurityMail deliverMail = \case
    VerificationDelivery mail -> deliverMail mail
    PasswordResetDelivery mail -> deliverMail mail
    PasskeySetupDelivery mail -> deliverMail mail

accountSecurityTokenLock ::
    (?modelContext :: ModelContext) =>
    Text ->
    UUID ->
    ((?modelContext :: ModelContext) => IO result) ->
    IO (Maybe result)
accountSecurityTokenLock mailKind
    | mailKind == emailVerificationMailKind = withEmailVerificationTokenLock
    | mailKind == passwordResetMailKind = withPasswordResetTokenLock
    | mailKind == passkeySetupMailKind = withPasskeySetupTokenLock
    | otherwise = \_ _ -> pure Nothing

accountSecurityRelatedTable :: Text -> Text
accountSecurityRelatedTable mailKind
    | mailKind == emailVerificationMailKind = "email_verification_tokens"
    | mailKind == passwordResetMailKind = "password_reset_tokens"
    | mailKind == passkeySetupMailKind = "passkey_setup_tokens"
    | otherwise = ""

performVenueInvitationPayload ::
    (?modelContext :: ModelContext) =>
    (forall mail. BuildMail mail => mail -> IO ()) ->
    Text ->
    AppJob ->
    EmailDeliveryPayload ->
    AppMailSettings ->
    Text ->
    IO ()
performVenueInvitationPayload deliverMail deliveryStatus appJob payload settings appBaseUrl = do
    validateRelatedTable appJob "venue_invitations" payload.payloadDomainReferenceId
    lockedResult <-
        withDurableLiveMutationOutcomeWithoutContext publicationFor $
            withVenueInvitationLockInCurrentTransaction payload.payloadDomainReferenceId do
                projection <-
                    loadVenueInvitationMail
                        payload.payloadRecipientAccountId
                        payload.payloadRecipientAddress
                        payload.payloadDomainReferenceId
                        appJob.venueId
                        settings
                        appBaseUrl
                case projection of
                    VenueInvitationMailSkipped reason ->
                        completeEmailDelivery appJob payload "delivery_skipped" (Just reason)
                    VenueInvitationMailReady mail -> do
                        deliverMail mail
                        void (completeVenueInvitationEmail payload.payloadDomainReferenceId)
                        completeEmailDelivery appJob payload deliveryStatus Nothing
                invitation <- fetch (Id payload.payloadDomainReferenceId :: Id VenueInvitation)
                pure invitation.venueId
    when (isNothing lockedResult) $
        completeEmailDelivery appJob payload "delivery_skipped" (Just "domain_reference_missing")
  where
    publicationFor = fmap (\venueId -> ("admin.invites.delivery", Set.singleton (adminInvitesResource venueId)))

performVenueOnboardingInvitationPayload ::
    (?modelContext :: ModelContext) =>
    (forall mail. BuildMail mail => mail -> IO ()) ->
    Text ->
    AppJob ->
    EmailDeliveryPayload ->
    AppMailSettings ->
    Text ->
    IO ()
performVenueOnboardingInvitationPayload deliverMail deliveryStatus appJob payload settings appBaseUrl = do
    validateRelatedTable appJob "venue_onboarding_invitations" payload.payloadDomainReferenceId
    lockedResult <- withVenueOnboardingInvitationLock payload.payloadDomainReferenceId do
        projection <-
            loadVenueOnboardingInvitationMail
                payload.payloadRecipientAccountId
                payload.payloadRecipientAddress
                payload.payloadDomainReferenceId
                appJob.venueId
                settings
                appBaseUrl
        case projection of
            VenueOnboardingInvitationMailSkipped reason ->
                completeEmailDelivery appJob payload "delivery_skipped" (Just reason)
            VenueOnboardingInvitationMailReady mail -> do
                deliverMail mail
                void (completeVenueOnboardingInvitationEmail payload.payloadDomainReferenceId)
                completeEmailDelivery appJob payload deliveryStatus Nothing
    when (isNothing lockedResult) $
        completeEmailDelivery appJob payload "delivery_skipped" (Just "domain_reference_missing")

handleEmailDeliveryFailureAfterFinalAttempt ::
    (?modelContext :: ModelContext) =>
    AppJob ->
    IO ()
handleEmailDeliveryFailureAfterFinalAttempt appJob
    | appJob.jobKind /= emailDeliveryJobKind = pure ()
    | appJob.attemptsCount < appJobMaxAttempts = pure ()
    | otherwise = do
        persistedJob <- fetch appJob.id
        unless (persistedJob.status == JobStatusSucceeded) $
            case Aeson.fromJSON appJob.payload :: Aeson.Result EmailDeliveryPayload of
                Aeson.Error _ -> pure ()
                Aeson.Success payload -> do
                    when (isAccountSecurityMailKind payload.payloadMailKind) $
                        completeAccountSecurityEmail payload.payloadMailKind payload.payloadDomainReferenceId
                    if payload.payloadMailKind == venueInvitationMailKind
                        then do
                            void $
                                withDurableLiveMutationOutcomeWithoutContext invitationFailurePublication do
                                    markInvitationDeliveryFailed payload.payloadMailKind payload.payloadDomainReferenceId
                                    query @VenueInvitation
                                        |> filterWhere (#id, Id payload.payloadDomainReferenceId)
                                        |> fetchOneOrNothing
                        else when (payload.payloadMailKind == venueOnboardingInvitationMailKind) $
                            markInvitationDeliveryFailed payload.payloadMailKind payload.payloadDomainReferenceId
                    when (isRosterNotificationMailKind payload.payloadMailKind) $
                        void $
                            withDurableLiveMutationOutcomeWithoutContext rosterFailurePublication $
                                rosterNotificationStatusResources payload.payloadDomainReferenceId
  where
    invitationFailurePublication = fmap (\invitation -> ("admin.invites.delivery", Set.singleton (adminInvitesResource invitation.venueId)))
    rosterFailurePublication resources
        | null resources = Nothing
        | otherwise = Just ("roster.notification.delivery.failed", Set.fromList resources)

completeRosterNotificationDelivery ::
    (?modelContext :: ModelContext) =>
    AppJob ->
    EmailDeliveryPayload ->
    Text ->
    IO ()
completeRosterNotificationDelivery appJob payload deliveryStatus =
    void $
        withDurableLiveMutationWithoutContext "roster.notification.delivery.complete" do
            completeEmailDelivery appJob payload deliveryStatus Nothing
            resources <- rosterNotificationStatusResources payload.payloadDomainReferenceId
            pure (liveMutationResult () resources)

completeRsaReminderEmail ::
    (?modelContext :: ModelContext) =>
    AppJob ->
    EmailDeliveryPayload ->
    Text ->
    IO ()
completeRsaReminderEmail appJob payload deliveryStatus =
    withTransaction do
        completeRsaReminderDelivery payload.payloadMailKind payload.payloadDomainReferenceId
        completeEmailDelivery appJob payload deliveryStatus Nothing

validateRelatedTable :: AppJob -> Text -> UUID -> IO ()
validateRelatedTable appJob expectedTable expectedId =
    unless (appJob.relatedTable == Just expectedTable && appJob.relatedId == Just expectedId) $
        throwAppJobError JobInvalidProvenance

completeEmailDelivery ::
    (?modelContext :: ModelContext) =>
    AppJob ->
    EmailDeliveryPayload ->
    Text ->
    Maybe Text ->
    IO ()
completeEmailDelivery appJob payload deliveryStatus maybeReason =
    void $
        appJob
            |> set #status JobStatusSucceeded
            |> set #lastError Nothing
            |> set #lockedAt Nothing
            |> set #lockedBy Nothing
            |> set #result
                ( Aeson.object
                    ( [ "deliveryStatus" Aeson..= deliveryStatus
                      , "mailKind" Aeson..= payload.payloadMailKind
                      , "domainReferenceId" Aeson..= payload.payloadDomainReferenceId
                      ]
                        <> maybe [] (\reason -> ["reason" Aeson..= reason]) maybeReason
                    )
                )
            |> updateRecord
