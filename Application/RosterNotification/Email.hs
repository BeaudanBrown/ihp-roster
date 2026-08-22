module Application.RosterNotification.Email
    ( RosterNotificationMailProjection (..)
    , isRosterNotificationMailKind
    , loadRosterNotificationMail
    , rosterNotificationStatusResources
    , rosterNotificationMailKind
    ) where

import Application.Helper.FrontendContract.Surface.Resource (SurfaceResourceValue)
import Application.Helper.FrontendContract.Surface.Roster.Resource (rosterNotificationStatusResource)
import Application.Helper.Mail
import Application.RosterNotification
import Data.List (find)
import Data.Time.Calendar (addDays)
import Generated.Types
import IHP.ControllerPrelude
import Web.Mail.RosterNotification
import Web.RosterWeeks.Paths (rosterWindowUrl)

isRosterNotificationMailKind :: Text -> Bool
isRosterNotificationMailKind = (== rosterNotificationMailKind)

data RosterNotificationMailProjection
    = RosterNotificationMailSkipped !Text
    | RosterNotificationMailReady !RosterNotificationMail

loadRosterNotificationMail ::
    (?modelContext :: ModelContext) =>
    Text ->
    UUID ->
    Text ->
    UUID ->
    Maybe UUID ->
    AppMailSettings ->
    Text ->
    IO RosterNotificationMailProjection
loadRosterNotificationMail mailKind recipientAccountId recipientAddress runId jobVenueId settings appBaseUrl
    | not (isRosterNotificationMailKind mailKind) = pure (RosterNotificationMailSkipped "unknown_mail_kind")
    | otherwise = do
        maybeRun <- query @RosterNotificationRun
            |> filterWhere (#id, Id runId)
            |> fetchOneOrNothing
        case maybeRun of
            Nothing -> pure (RosterNotificationMailSkipped "domain_reference_missing")
            Just run -> do
                snapshot <- decodeRosterNotificationSnapshot run
                recipients <- decodeRosterNotificationRecipients run
                validateRunIdentity run snapshot jobVenueId
                recipient <- validateRecipient recipientAccountId recipientAddress recipients
                pure $ RosterNotificationMailReady RosterNotificationMail
                    { notificationSnapshot = snapshot
                    , notificationRecipient = recipient
                    , rosterUrl = appBaseUrl <> rosterWindowUrl snapshot.snapshotWeekStart (Id snapshot.snapshotRosterGroupId)
                    , fromAddress = settings.mailFromAddress
                    , replyToAddress = settings.mailReplyToAddress
                    , supportEmail = settings.mailSupportEmail
                    }

validateRunIdentity :: RosterNotificationRun -> RosterNotificationSnapshot -> Maybe UUID -> IO ()
validateRunIdentity run snapshot jobVenueId = do
    unless (run.snapshotSchemaVersion == rosterNotificationSnapshotSchemaVersion) $
        fail "Unsupported roster notification snapshot schema version"
    unless (jobVenueId == Just run.venueId) $
        fail "Roster notification job venue does not match its run"
    unless
        ( snapshot.snapshotVenueId == run.venueId
            && snapshot.snapshotRosterGroupId == run.rosterGroupId
            && snapshot.snapshotRosterWeekId == run.rosterWeekId
            && snapshot.snapshotWeekOffset == run.weekOffset
            && snapshot.snapshotWeekStart == run.weekStart
            && addDays 1 snapshot.snapshotWeekEnd == run.windowEnd
        ) $
        fail "Roster notification run identity does not match its snapshot"

validateRecipient :: UUID -> Text -> [RosterNotificationRecipient] -> IO RosterNotificationRecipient
validateRecipient recipientAccountId recipientAddress recipients =
    case find ((== recipientAccountId) . (.recipientUserId)) recipients of
        Just recipient
            | recipient.recipientEmail == recipientAddress -> pure recipient
        _ -> fail "Roster notification recipient does not match the immutable run snapshot"

rosterNotificationStatusResources ::
    (?modelContext :: ModelContext) =>
    UUID ->
    IO [SurfaceResourceValue]
rosterNotificationStatusResources runId = do
    maybeRun <- query @RosterNotificationRun
        |> filterWhere (#id, Id runId)
        |> fetchOneOrNothing
    pure $
        maybe [] (\run -> [rosterNotificationStatusResource run.rosterGroupId run.weekStart run.windowEnd]) maybeRun
