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

import Application.Async.Queue (appJobMaxAttempts)
import Application.Billing.NotificationEmail
import Application.EmailDelivery.Enqueue
import Application.Feedback.Email (feedbackSubmittedMailKind,
                                   loadFeedbackNotificationMail)
import Application.Helper.EmailVerification (isEmailDeliveryDisabled)
import Application.Helper.Mail
import Application.InvitationDelivery.Email
import Application.InvitationDelivery.Types
import Application.RosterNotification.Email
import Application.StaffDocuments.Rsa.Email
import Application.VenueInvitation.Mutations (withVenueInvitationLock)
import Application.VenueOnboardingInvitation.Mutations (withVenueOnboardingInvitationLock)
import Application.WageSourceAlert.Email
import Application.WageSourceNotification.Email
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import Generated.Types
import IHP.ControllerPrelude
import IHP.EnvVar (envOrDefault)
import IHP.FrameworkConfig (ConfigProvider, FrameworkConfig)
import IHP.Job.Types (JobStatus (JobStatusSucceeded))
import IHP.Mail (sendMail)
import IHP.MailPrelude (BuildMail)
import IHP.ModelSupport (withTransaction)

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
performEmailDeliveryJobWith runtime appJob
    | appJob.payloadSchemaVersion /= 1 =
        fail ("Unsupported email delivery payload schema version: " <> cs (tshow appJob.payloadSchemaVersion))
    | otherwise =
        case Aeson.fromJSON appJob.payload of
            Aeson.Error parseError -> fail ("Invalid email delivery payload: " <> parseError)
            Aeson.Success payload -> performPayload runtime appJob payload

performPayload ::
    (?context :: context, ConfigProvider context, ?modelContext :: ModelContext) =>
    EmailDeliveryRuntime ->
    AppJob ->
    EmailDeliveryPayload ->
    IO ()
performPayload EmailDeliveryRuntime { deliveryIsDisabled, deliverMail } appJob payload = do
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
            mailKind | mailKind == venueInvitationMailKind ->
                performVenueInvitationPayload deliverMail "sent" appJob payload AppMailSettings { .. } appBaseUrl
            mailKind | mailKind == venueOnboardingInvitationMailKind ->
                performVenueOnboardingInvitationPayload deliverMail "sent" appJob payload AppMailSettings { .. } appBaseUrl
            unknownKind -> fail ("Unknown email delivery mail kind: " <> cs unknownKind)

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
    | payload.payloadMailKind == venueInvitationMailKind =
        performVenueInvitationPayload (\_ -> pure ()) "delivery_disabled" appJob payload settings appBaseUrl
    | payload.payloadMailKind == venueOnboardingInvitationMailKind =
        performVenueOnboardingInvitationPayload (\_ -> pure ()) "delivery_disabled" appJob payload settings appBaseUrl
    | otherwise = completeEmailDelivery appJob payload "delivery_disabled" Nothing

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
    lockedResult <- withVenueInvitationLock payload.payloadDomainReferenceId do
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
    when (isNothing lockedResult) $
        completeEmailDelivery appJob payload "delivery_skipped" (Just "domain_reference_missing")
    publishVenueInvitationDeliveryStatus payload.payloadDomainReferenceId

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
                Aeson.Success payload ->
                    when (isInvitationMailKind payload.payloadMailKind) do
                        markInvitationDeliveryFailed payload.payloadMailKind payload.payloadDomainReferenceId
                        when (payload.payloadMailKind == venueInvitationMailKind) $
                            publishVenueInvitationDeliveryStatus payload.payloadDomainReferenceId

completeRosterNotificationDelivery ::
    (?modelContext :: ModelContext) =>
    AppJob ->
    EmailDeliveryPayload ->
    Text ->
    IO ()
completeRosterNotificationDelivery appJob payload deliveryStatus = do
    completeEmailDelivery appJob payload deliveryStatus Nothing
    publishRosterNotificationStatusResource
        "roster.notification.delivery.complete"
        payload.payloadDomainReferenceId

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
        fail ("Email delivery job has invalid related " <> cs expectedTable <> " reference")

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
