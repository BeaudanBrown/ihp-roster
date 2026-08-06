module Application.RosterNotification.Delivery
    ( RosterNotificationDeliveryRuntime (..)
    , rosterNotificationDeliveryJobKind
    , performRosterNotificationDeliveryJob
    , performRosterNotificationDeliveryJobWith
    ) where

import Application.Async.Queue (appJobMaxAttempts)
import Application.Helper.EmailVerification (isEmailDeliveryDisabled)
import Application.Helper.FrontendContract.Surface.Roster.Resource (rosterNotificationStatusResource)
import Application.Helper.Mail
import Application.Helper.SurfaceResource (liveMutationResult)
import Application.RosterNotification
import qualified Control.Exception as Exception
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import Data.List (find)
import qualified Data.Text as Text
import Generated.Types
import IHP.ControllerPrelude
import IHP.EnvVar (envOrDefault)
import IHP.FrameworkConfig (ConfigProvider, FrameworkConfig)
import IHP.Mail (sendMail)
import Web.Mail.RosterNotification
import Web.RosterWeeks.Paths (rosterWeekUrl)
import Web.SurfaceInvalidation (invalidateTouchedResourcesWithoutContext)

data RosterNotificationDeliveryRuntime = RosterNotificationDeliveryRuntime
    { deliveryBaseUrl               :: !Text
    , deliveryMailSettings          :: !AppMailSettings
    , deliverRosterNotificationMail :: RosterNotificationMail -> IO ()
    , invalidateRosterNotificationStatus :: Text -> RosterNotificationRun -> IO ()
    }

performRosterNotificationDeliveryJob ::
    (?context :: FrameworkConfig, ?modelContext :: ModelContext) =>
    AppJob ->
    IO ()
performRosterNotificationDeliveryJob appJob = do
    deliveryMailSettings <- loadAppMailSettings
    deliveryBaseUrl <- envOrDefault "APP_BASE_URL" "http://localhost:8000"
    emailDeliveryDisabled <- isEmailDeliveryDisabled
    let deliverRosterNotificationMail mail =
            unless emailDeliveryDisabled (sendMail mail)
    let invalidateRosterNotificationStatus = invalidateRosterNotificationStatusResource
    performRosterNotificationDeliveryJobWith RosterNotificationDeliveryRuntime { .. } appJob

performRosterNotificationDeliveryJobWith ::
    (?modelContext :: ModelContext) =>
    RosterNotificationDeliveryRuntime ->
    AppJob ->
    IO ()
performRosterNotificationDeliveryJobWith runtime appJob = do
    payload <- decodeAndValidatePayload appJob
    run <- fetchRelatedRun appJob payload
    snapshot <- decodeRosterNotificationSnapshot run
    recipients <- decodeRosterNotificationRecipients run
    validateRunIdentity appJob run snapshot
    recipient <- validateRecipient payload recipients
    let settings = runtime.deliveryMailSettings
    let mail = RosterNotificationMail
            { notificationSnapshot = snapshot
            , notificationRecipient = recipient
            , rosterUrl = runtime.deliveryBaseUrl <> rosterWeekUrl snapshot.snapshotWeekOffset (Id snapshot.snapshotRosterGroupId)
            , fromAddress = settings.mailFromAddress
            , replyToAddress = settings.mailReplyToAddress
            , supportEmail = settings.mailSupportEmail
            }
    deliveryResult <- Exception.try @Exception.SomeException (runtime.deliverRosterNotificationMail mail)
    case deliveryResult of
        Left exception -> do
            recordRosterNotificationDeliveryFailure runtime appJob run exception
            Exception.throwIO exception
        Right () -> completeRosterNotificationDelivery runtime appJob run payload

completeRosterNotificationDelivery ::
    (?modelContext :: ModelContext) =>
    RosterNotificationDeliveryRuntime ->
    AppJob ->
    RosterNotificationRun ->
    RosterNotificationDeliveryPayload ->
    IO ()
completeRosterNotificationDelivery runtime appJob run payload = do
    void $
        appJob
            |> set #result
                ( Aeson.object
                    [ "runId" Aeson..= payload.payloadRunId
                    , "recipientStaffId" Aeson..= payload.payloadRecipientStaffId
                    , "recipientUserId" Aeson..= payload.payloadRecipientUserId
                    , "deliveryStatus" Aeson..= ("sent" :: Text)
                    ]
                )
            |> set #status JobStatusSucceeded
            |> set #lastError Nothing
            |> set #lockedAt Nothing
            |> set #lockedBy Nothing
            |> updateRecord
    runtime.invalidateRosterNotificationStatus "roster.notification.delivery.complete" run

recordRosterNotificationDeliveryFailure ::
    (?modelContext :: ModelContext) =>
    RosterNotificationDeliveryRuntime ->
    AppJob ->
    RosterNotificationRun ->
    Exception.SomeException ->
    IO ()
recordRosterNotificationDeliveryFailure runtime appJob run exception = do
    let nextStatus =
            if appJob.attemptsCount < appJobMaxAttempts
                then JobStatusRetry
                else JobStatusFailed
    void $
        appJob
            |> set #status nextStatus
            |> set #lastError (Just (Text.take 2000 (tshow exception)))
            |> set #lockedAt Nothing
            |> set #lockedBy Nothing
            |> updateRecord
    runtime.invalidateRosterNotificationStatus "roster.notification.delivery.failed" run

invalidateRosterNotificationStatusResource ::
    (?modelContext :: ModelContext) =>
    Text ->
    RosterNotificationRun ->
    IO ()
invalidateRosterNotificationStatusResource label run =
    void $
        invalidateTouchedResourcesWithoutContext label $
            liveMutationResult () [rosterNotificationStatusResource run.rosterGroupId run.weekOffset]

decodeAndValidatePayload :: AppJob -> IO RosterNotificationDeliveryPayload
decodeAndValidatePayload appJob = do
    unless (appJob.jobKind == rosterNotificationDeliveryJobKind) $
        failDelivery appJob "unexpected job kind"
    unless (appJob.payloadSchemaVersion == rosterNotificationPayloadSchemaVersion) $
        failDelivery appJob "unsupported payload schema version"
    case Aeson.fromJSON appJob.payload of
        Aeson.Error message -> failDelivery appJob ("invalid payload: " <> Text.pack message)
        Aeson.Success payload -> pure payload

fetchRelatedRun ::
    (?modelContext :: ModelContext) =>
    AppJob ->
    RosterNotificationDeliveryPayload ->
    IO RosterNotificationRun
fetchRelatedRun appJob payload =
    case (appJob.relatedTable, appJob.relatedId) of
        (Just "roster_notification_runs", Just runId)
            | runId == payload.payloadRunId -> fetch (Id runId :: Id RosterNotificationRun)
        _ -> failDelivery appJob "invalid related roster notification run"

validateRunIdentity ::
    AppJob ->
    RosterNotificationRun ->
    RosterNotificationSnapshot ->
    IO ()
validateRunIdentity appJob run snapshot = do
    unless (run.snapshotSchemaVersion == rosterNotificationSnapshotSchemaVersion) $
        failDelivery appJob "unsupported roster snapshot schema version"
    unless (appJob.venueId == Just run.venueId) $
        failDelivery appJob "job venue does not match notification run"
    unless
        ( snapshot.snapshotVenueId == run.venueId
            && snapshot.snapshotRosterGroupId == run.rosterGroupId
            && snapshot.snapshotRosterWeekId == run.rosterWeekId
            && snapshot.snapshotWeekOffset == run.weekOffset
            && snapshot.snapshotWeekStart == run.weekStart
        ) $
        failDelivery appJob "notification run identity does not match its snapshot"

validateRecipient ::
    RosterNotificationDeliveryPayload ->
    [RosterNotificationRecipient] ->
    IO RosterNotificationRecipient
validateRecipient payload recipients =
    case find ((== payload.payloadRecipientUserId) . (.recipientUserId)) recipients of
        Just recipient
            | recipient.recipientStaffId == payload.payloadRecipientStaffId
                && recipient.recipientEmail == payload.payloadRecipientEmail -> pure recipient
        _ -> fail "Roster notification delivery recipient does not match the immutable run snapshot"

failDelivery :: AppJob -> Text -> IO value
failDelivery appJob message =
    fail ("Roster notification delivery job " <> cs (tshow appJob.id) <> " failed validation: " <> cs message)
