module Application.RosterNotification
    ( RosterNotificationSnapshot (..)
    , RosterNotificationShiftSnapshot (..)
    , RosterNotificationRecipient (..)
    , RosterNotificationSkippedRecipient (..)
    , RosterNotificationSkippedReason (..)
    , RosterNotificationAudience (..)
    , RosterNotificationRunSummary (..)
    , RosterNotificationPanelData (..)
    , CreateRosterNotificationRunResult (..)
    , rosterNotificationMailKind
    , rosterNotificationSnapshotSchemaVersion
    , createRosterNotificationRunForWindow
    , createRosterNotificationRunForWindowUnlessActiveAtRevision
    , fetchRosterNotificationAudience
    , fetchLatestRosterNotificationRunSummaryForWindow
    , rosterNotificationRecipientCountLabel
    , decodeRosterNotificationSnapshot
    , decodeRosterNotificationRecipients
    , decodeRosterNotificationSkippedRecipients
    ) where

import Application.Async.Queue (activeAppJobStatuses)
import Application.EmailDelivery.Enqueue
import qualified Application.RosterNotification.Mutations as Mutations
import Application.RosterPublication (rosterDaysArePublished)
import Application.RosterPublication.Mutations (withRosterWindowDateLock)
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Types as AesonTypes
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified Data.Text as Text
import Data.Time.Calendar (Day, addDays)
import Generated.Types hiding (createRosterNotificationRun)
import IHP.ControllerPrelude
import IHP.Job.Types (JobStatus (..))

rosterNotificationMailKind :: Text
rosterNotificationMailKind = "roster_notification_v1"

rosterNotificationSnapshotSchemaVersion :: Int
rosterNotificationSnapshotSchemaVersion = 1

data RosterNotificationSnapshot = RosterNotificationSnapshot
    { snapshotVenueId         :: !UUID
    , snapshotVenueName       :: !Text
    , snapshotRosterGroupId   :: !UUID
    , snapshotRosterGroupName :: !Text
    , snapshotWeekStart       :: !Day
    , snapshotWeekEnd         :: !Day
    , snapshotShifts          :: ![RosterNotificationShiftSnapshot]
    }
    deriving (Eq, Show)

data RosterNotificationShiftSnapshot = RosterNotificationShiftSnapshot
    { shiftRosterSlotId :: !UUID
    , shiftStaffId      :: !(Maybe UUID)
    , shiftDate         :: !Day
    , shiftStartsAt     :: !(Maybe UTCTime)
    , shiftEndsAt       :: !(Maybe UTCTime)
    , shiftTimezone     :: !Text
    , shiftLaneName     :: !Text
    , shiftTypeName     :: !(Maybe Text)
    }
    deriving (Eq, Show)

data RosterNotificationRecipient = RosterNotificationRecipient
    { recipientStaffId :: !UUID
    , recipientUserId  :: !UUID
    , recipientEmail   :: !Text
    , recipientName    :: !Text
    }
    deriving (Eq, Show)

data RosterNotificationSkippedReason
    = RosterNotificationSkippedUnlinked
    | RosterNotificationSkippedInactive
    | RosterNotificationSkippedMissingEmail
    | RosterNotificationSkippedInvalidScope
    deriving (Eq, Ord, Show)

data RosterNotificationSkippedRecipient = RosterNotificationSkippedRecipient
    { skippedStaffId :: !UUID
    , skippedName    :: !Text
    , skippedReason  :: !RosterNotificationSkippedReason
    }
    deriving (Eq, Show)

data RosterNotificationAudience = RosterNotificationAudience
    { audienceRecipients        :: ![RosterNotificationRecipient]
    , audienceSkippedRecipients :: ![RosterNotificationSkippedRecipient]
    }
    deriving (Eq, Show)

data RosterNotificationRunSummary = RosterNotificationRunSummary
    { summaryRun             :: !RosterNotificationRun
    , summaryRequesterEmail  :: !Text
    , summaryRecipientCount  :: !Int
    , summarySkippedCount    :: !Int
    , summaryDeliveredCount  :: !Int
    , summaryInProgressCount :: !Int
    , summaryFailedCount     :: !Int
    }
    deriving (Eq, Show)

data RosterNotificationPanelData = RosterNotificationPanelData
    { panelNotificationAudience  :: !RosterNotificationAudience
    , panelLatestNotificationRun :: !(Maybe RosterNotificationRunSummary)
    }
    deriving (Eq, Show)

data CreateRosterNotificationRunResult
    = RosterNotificationRunCreated !RosterNotificationRun
    | RosterNotificationRunAlreadyActive
    | RosterNotificationRunHasNoEligibleRecipients
    | RosterNotificationRunCalendarConflict
    deriving (Eq, Show)

instance Aeson.ToJSON RosterNotificationSnapshot where
    toJSON snapshot =
        Aeson.object
            [ "venueId" Aeson..= snapshot.snapshotVenueId
            , "venueName" Aeson..= snapshot.snapshotVenueName
            , "rosterGroupId" Aeson..= snapshot.snapshotRosterGroupId
            , "rosterGroupName" Aeson..= snapshot.snapshotRosterGroupName
            , "weekStart" Aeson..= snapshot.snapshotWeekStart
            , "weekEnd" Aeson..= snapshot.snapshotWeekEnd
            , "shifts" Aeson..= snapshot.snapshotShifts
            ]

instance Aeson.FromJSON RosterNotificationSnapshot where
    parseJSON = Aeson.withObject "RosterNotificationSnapshot" \object ->
        RosterNotificationSnapshot
            <$> object Aeson..: "venueId"
            <*> object Aeson..: "venueName"
            <*> object Aeson..: "rosterGroupId"
            <*> object Aeson..: "rosterGroupName"
            <*> object Aeson..: "weekStart"
            <*> object Aeson..: "weekEnd"
            <*> object Aeson..: "shifts"

instance Aeson.ToJSON RosterNotificationShiftSnapshot where
    toJSON shift =
        Aeson.object
            [ "rosterSlotId" Aeson..= shift.shiftRosterSlotId
            , "staffId" Aeson..= shift.shiftStaffId
            , "date" Aeson..= shift.shiftDate
            , "startsAt" Aeson..= shift.shiftStartsAt
            , "endsAt" Aeson..= shift.shiftEndsAt
            , "timezone" Aeson..= shift.shiftTimezone
            , "laneName" Aeson..= shift.shiftLaneName
            , "shiftTypeName" Aeson..= shift.shiftTypeName
            ]

instance Aeson.FromJSON RosterNotificationShiftSnapshot where
    parseJSON = Aeson.withObject "RosterNotificationShiftSnapshot" \object ->
        RosterNotificationShiftSnapshot
            <$> object Aeson..: "rosterSlotId"
            <*> object Aeson..:? "staffId"
            <*> object Aeson..: "date"
            <*> object Aeson..:? "startsAt"
            <*> object Aeson..:? "endsAt"
            <*> object Aeson..: "timezone"
            <*> object Aeson..: "laneName"
            <*> object Aeson..:? "shiftTypeName"

instance Aeson.ToJSON RosterNotificationRecipient where
    toJSON recipient =
        Aeson.object
            [ "staffId" Aeson..= recipient.recipientStaffId
            , "userId" Aeson..= recipient.recipientUserId
            , "email" Aeson..= recipient.recipientEmail
            , "name" Aeson..= recipient.recipientName
            ]

instance Aeson.FromJSON RosterNotificationRecipient where
    parseJSON = Aeson.withObject "RosterNotificationRecipient" \object ->
        RosterNotificationRecipient
            <$> object Aeson..: "staffId"
            <*> object Aeson..: "userId"
            <*> object Aeson..: "email"
            <*> object Aeson..: "name"

instance Aeson.ToJSON RosterNotificationSkippedReason where
    toJSON = Aeson.String . skippedReasonText

instance Aeson.FromJSON RosterNotificationSkippedReason where
    parseJSON = Aeson.withText "RosterNotificationSkippedReason" \case
        "unlinked" -> pure RosterNotificationSkippedUnlinked
        "inactive" -> pure RosterNotificationSkippedInactive
        "missing_email" -> pure RosterNotificationSkippedMissingEmail
        "invalid_scope" -> pure RosterNotificationSkippedInvalidScope
        _ -> fail "Unknown roster notification skipped reason"

instance Aeson.ToJSON RosterNotificationSkippedRecipient where
    toJSON skipped =
        Aeson.object
            [ "staffId" Aeson..= skipped.skippedStaffId
            , "name" Aeson..= skipped.skippedName
            , "reason" Aeson..= skipped.skippedReason
            ]

instance Aeson.FromJSON RosterNotificationSkippedRecipient where
    parseJSON = Aeson.withObject "RosterNotificationSkippedRecipient" \object ->
        RosterNotificationSkippedRecipient
            <$> object Aeson..: "staffId"
            <*> object Aeson..: "name"
            <*> object Aeson..: "reason"

createRosterNotificationRunForWindowUnlessActiveAtRevision ::
    (?modelContext :: ModelContext) =>
    User ->
    Venue ->
    RosterGroup ->
    Day ->
    Day ->
    Int ->
    IO CreateRosterNotificationRunResult
createRosterNotificationRunForWindowUnlessActiveAtRevision actor venue rosterGroup windowStart windowEnd expectedCalendarRevision =
    createRosterNotificationRunForWindowUnlessActive actor venue rosterGroup windowStart windowEnd (Just expectedCalendarRevision)

createRosterNotificationRunForWindowUnlessActive ::
    (?modelContext :: ModelContext) =>
    User ->
    Venue ->
    RosterGroup ->
    Day ->
    Day ->
    Maybe Int ->
    IO CreateRosterNotificationRunResult
createRosterNotificationRunForWindowUnlessActive actor venue rosterGroup windowStart windowEnd expectedCalendarRevision =
    withRosterWindowDateLock venue.id rosterGroup.id windowStart windowEnd do
        currentVenueConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
        if maybe False (/= currentVenueConfig.rosterCalendarRevision) expectedCalendarRevision
            then pure RosterNotificationRunCalendarConflict
            else do
                Mutations.lockRosterNotificationWindow venue.id rosterGroup.id windowStart windowEnd
                runs <- query @RosterNotificationRun
                    |> filterWhere (#rosterGroupId, unpackId rosterGroup.id)
                    |> filterWhere (#weekStart, windowStart)
                    |> filterWhere (#windowEnd, windowEnd)
                    |> fetch
                activeDeliveryExists <- activeRunDeliveryExists runs
                if activeDeliveryExists
                    then pure RosterNotificationRunAlreadyActive
                    else do
                        createdRun <- createRosterNotificationRunInCurrentTransaction actor venue rosterGroup windowStart windowEnd
                        pure $ maybe RosterNotificationRunHasNoEligibleRecipients RosterNotificationRunCreated createdRun

createRosterNotificationRunForWindow ::
    (?modelContext :: ModelContext) =>
    User ->
    Venue ->
    RosterGroup ->
    Day ->
    Day ->
    IO RosterNotificationRun
createRosterNotificationRunForWindow actor venue rosterGroup windowStart windowEnd =
    withRosterWindowDateLock venue.id rosterGroup.id windowStart windowEnd do
        Mutations.lockRosterNotificationWindow venue.id rosterGroup.id windowStart windowEnd
        createdRun <- createRosterNotificationRunInCurrentTransaction actor venue rosterGroup windowStart windowEnd
        maybe (fail "Roster notification runs require at least one eligible recipient") pure createdRun

activeRunDeliveryExists :: (?modelContext :: ModelContext) => [RosterNotificationRun] -> IO Bool
activeRunDeliveryExists runs = do
    let runIds = map (Just . unpackId . (.id)) runs
    if null runIds
        then pure False
        else query @AppJob
            |> filterWhere (#relatedTable, Just "roster_notification_runs")
            |> filterWhereIn (#relatedId, runIds)
            |> filterWhereIn (#status, activeAppJobStatuses)
            |> fetchExists

createRosterNotificationRunInCurrentTransaction ::
    (?modelContext :: ModelContext) =>
    User ->
    Venue ->
    RosterGroup ->
    Day ->
    Day ->
    IO (Maybe RosterNotificationRun)
createRosterNotificationRunInCurrentTransaction actor suppliedVenue suppliedRosterGroup windowStart windowEnd = do
    persistedActor <- fetch actor.id
    venue <- fetch suppliedVenue.id
    rosterGroup <- fetch suppliedRosterGroup.id
    unless (rosterGroup.venueId == unpackId venue.id) (fail "Roster notification roster group is outside the venue")
    unless (windowEnd == addDays 7 windowStart) (fail "Roster notification runs require an explicit seven-day window")
    rosterDays <- query @RosterDay
        |> filterWhere (#venueId, unpackId venue.id)
        |> filterWhere (#rosterGroupId, unpackId rosterGroup.id)
        |> filterWhereGreaterThanOrEqualTo (#operationalDate, windowStart)
        |> filterWhereLessThan (#operationalDate, windowEnd)
        |> orderByAsc #operationalDate
        |> fetch
    unless (map (.operationalDate) rosterDays == map (`addDays` windowStart) [0 .. 6] && rosterDaysArePublished rosterDays)
        (fail "Roster notification runs require a Published roster window")
    snapshot <- buildRosterSnapshot venue rosterGroup rosterDays windowStart windowEnd
    audience <- fetchRosterNotificationAudience venue rosterGroup
    let recipients = audience.audienceRecipients
    let skippedRecipients = audience.audienceSkippedRecipients
    if null recipients
        then pure Nothing
        else do
            run <-
                newRecord @RosterNotificationRun
                    |> set #venueId (unpackId venue.id)
                    |> set #rosterGroupId (unpackId rosterGroup.id)
                    |> set #weekStart windowStart
                    |> set #windowEnd windowEnd
                    |> set #snapshotSchemaVersion rosterNotificationSnapshotSchemaVersion
                    |> set #rosterSnapshot (Aeson.toJSON snapshot)
                    |> set #recipientSnapshot (Aeson.toJSON recipients)
                    |> set #skippedRecipientSnapshot (Aeson.toJSON skippedRecipients)
                    |> set #requestedByUserId (unpackId persistedActor.id)
                    |> createRecord
            forM_ recipients (enqueueRosterNotificationDelivery run persistedActor venue)
            pure (Just run)

buildRosterSnapshot ::
    (?modelContext :: ModelContext) =>
    Venue ->
    RosterGroup ->
    [RosterDay] ->
    Day ->
    Day ->
    IO RosterNotificationSnapshot
buildRosterSnapshot venue rosterGroup rosterDays windowStart windowEnd = do
    let rosterDayIds = map (unpackId . (.id)) rosterDays
    lanes <- if null rosterDayIds then pure [] else query @RosterLane
        |> filterWhereIn (#rosterDayId, rosterDayIds)
        |> filterWhere (#deletedAt, Nothing)
        |> fetch
    shifts <- if null rosterDayIds
        then pure []
        else query @RosterSlot
            |> filterWhereIn (#rosterDayId, rosterDayIds)
            |> filterWhere (#deletedAt, Nothing)
            |> orderByAsc #startsAt
            |> fetch
    let shiftTypeIds = mapMaybe (fmap Id . (.shiftTypeId)) shifts
    shiftTypes <- if null shiftTypeIds then pure [] else query @ShiftType |> filterWhereIn (#id, shiftTypeIds) |> fetch
    let dayById = Map.fromList [(unpackId day.id, day) | day <- rosterDays]
    let laneById = Map.fromList [(unpackId lane.id, lane) | lane <- lanes]
    let shiftTypeById = Map.fromList [(unpackId shiftType.id, shiftType) | shiftType <- shiftTypes]
    let snapshotShifts = mapMaybe (snapshotShift dayById laneById shiftTypeById) shifts
    pure RosterNotificationSnapshot
        { snapshotVenueId = unpackId venue.id
        , snapshotVenueName = venue.name
        , snapshotRosterGroupId = unpackId rosterGroup.id
        , snapshotRosterGroupName = rosterGroup.name
        , snapshotWeekStart = windowStart
        , snapshotWeekEnd = addDays (-1) windowEnd
        , snapshotShifts
        }

snapshotShift ::
    Map.Map UUID RosterDay ->
    Map.Map UUID RosterLane ->
    Map.Map UUID ShiftType ->
    RosterSlot ->
    Maybe RosterNotificationShiftSnapshot
snapshotShift dayById laneById shiftTypeById slot = do
    rosterDay <- Map.lookup slot.rosterDayId dayById
    laneName <- (.name) <$> Map.lookup slot.rosterLaneId laneById
    pure RosterNotificationShiftSnapshot
        { shiftRosterSlotId = unpackId slot.id
        , shiftStaffId = slot.staffId
        , shiftDate = rosterDay.operationalDate
        , shiftStartsAt = slot.startsAt
        , shiftEndsAt = slot.endsAt
        , shiftTimezone = slot.timezone
        , shiftLaneName = laneName
        , shiftTypeName = (.name) <$> (slot.shiftTypeId >>= (`Map.lookup` shiftTypeById))
        }

fetchRosterNotificationAudience ::
    (?modelContext :: ModelContext) =>
    Venue ->
    RosterGroup ->
    IO RosterNotificationAudience
fetchRosterNotificationAudience venue rosterGroup = do
    assignments <- query @StaffRosterGroup
        |> filterWhere (#rosterGroupId, unpackId rosterGroup.id)
        |> filterWhere (#deletedAt, Nothing)
        |> fetch
    let staffIds = map (Id . (.staffId)) assignments
    staffMembers <- if null staffIds then pure [] else query @Staff |> filterWhereIn (#id, staffIds) |> fetch
    let userIds = mapMaybe (fmap Id . (.userId)) staffMembers
    users <- if null userIds then pure [] else query @User |> filterWhereIn (#id, userIds) |> fetch
    memberships <- if null userIds
        then pure []
        else query @VenueMembership
            |> filterWhere (#venueId, unpackId venue.id)
            |> filterWhereIn (#userId, map unpackId userIds)
            |> fetch
    let userById = Map.fromList [(unpackId user.id, user) | user <- users]
    let activeMembershipUserIds = Set.fromList
            [ membership.userId
            | membership <- memberships
            , membership.isActive
            , isNothing membership.archivedAt
            ]
    let classified = map (classifyRecipient venue userById activeMembershipUserIds) staffMembers
    pure RosterNotificationAudience
        { audienceRecipients = List.sortOn (.recipientEmail) [recipient | Right recipient <- classified]
        , audienceSkippedRecipients = List.sortOn (.skippedName) [skipped | Left skipped <- classified]
        }

fetchLatestRosterNotificationRunSummaryForWindow ::
    (?modelContext :: ModelContext) =>
    Id Venue ->
    Id RosterGroup ->
    Day ->
    Day ->
    IO (Maybe RosterNotificationRunSummary)
fetchLatestRosterNotificationRunSummaryForWindow venueId rosterGroupId windowStart windowEnd = do
    latestRun <- query @RosterNotificationRun
        |> filterWhere (#venueId, unpackId venueId)
        |> filterWhere (#rosterGroupId, unpackId rosterGroupId)
        |> filterWhere (#weekStart, windowStart)
        |> filterWhere (#windowEnd, windowEnd)
        |> orderByDesc #createdAt
        |> fetchOneOrNothing
    summarizeLatestRosterNotificationRun latestRun

summarizeLatestRosterNotificationRun ::
    (?modelContext :: ModelContext) =>
    Maybe RosterNotificationRun ->
    IO (Maybe RosterNotificationRunSummary)
summarizeLatestRosterNotificationRun latestRun =
    forM latestRun \run -> do
        requester <- fetch (Id run.requestedByUserId :: Id User)
        recipients <- decodeRosterNotificationRecipients run
        skippedRecipients <- decodeRosterNotificationSkippedRecipients run
        jobs <- query @AppJob
            |> filterWhere (#relatedTable, Just "roster_notification_runs")
            |> filterWhere (#relatedId, Just (unpackId run.id))
            |> fetch
        let statuses = map (.status) jobs
        pure RosterNotificationRunSummary
            { summaryRun = run
            , summaryRequesterEmail = requester.email
            , summaryRecipientCount = length recipients
            , summarySkippedCount = length skippedRecipients
            , summaryDeliveredCount = length (filter isDeliveredRosterNotificationJob jobs)
            , summaryInProgressCount = length (filter (`elem` activeAppJobStatuses) statuses)
            , summaryFailedCount = length (filter (`elem` [JobStatusFailed, JobStatusTimedOut]) statuses)
            }

isDeliveredRosterNotificationJob :: AppJob -> Bool
isDeliveredRosterNotificationJob appJob =
    appJob.status == JobStatusSucceeded
        && deliveryStatus /= Just "retired_during_email_pipeline_migration"
  where
    deliveryStatus :: Maybe Text
    deliveryStatus =
        AesonTypes.parseMaybe
            (Aeson.withObject "roster notification result" (Aeson..:? "deliveryStatus"))
            appJob.result
            |> join

classifyRecipient ::
    Venue ->
    Map.Map UUID User ->
    Set.Set UUID ->
    Staff ->
    Either RosterNotificationSkippedRecipient RosterNotificationRecipient
classifyRecipient venue userById activeMembershipUserIds staff
    | staff.venueId /= unpackId venue.id = skipped RosterNotificationSkippedInvalidScope
    | not staff.isActive || isJust staff.archivedAt = skipped RosterNotificationSkippedInactive
    | Nothing <- staff.userId = skipped RosterNotificationSkippedUnlinked
    | Just userId <- staff.userId
    , Nothing <- Map.lookup userId userById = skipped RosterNotificationSkippedUnlinked
    | Just userId <- staff.userId
    , not (Set.member userId activeMembershipUserIds) = skipped RosterNotificationSkippedInactive
    | Just userId <- staff.userId
    , Just user <- Map.lookup userId userById
    , isJust user.deactivatedAt = skipped RosterNotificationSkippedInactive
    | Just userId <- staff.userId
    , Just user <- Map.lookup userId userById
    , Text.null (Text.strip user.email) = skipped RosterNotificationSkippedMissingEmail
    | Just userId <- staff.userId
    , Just user <- Map.lookup userId userById =
        Right RosterNotificationRecipient
            { recipientStaffId = unpackId staff.id
            , recipientUserId = userId
            , recipientEmail = user.email
            , recipientName = staffDisplayName staff
            }
    | otherwise = skipped RosterNotificationSkippedUnlinked
  where
    skipped reason = Left RosterNotificationSkippedRecipient
        { skippedStaffId = unpackId staff.id
        , skippedName = staffDisplayName staff
        , skippedReason = reason
        }

staffDisplayName :: Staff -> Text
staffDisplayName staff =
    Text.unwords (filter (not . Text.null) [fromMaybe staff.firstName staff.preferredName, staff.lastName])

enqueueRosterNotificationDelivery ::
    (?modelContext :: ModelContext) =>
    RosterNotificationRun ->
    User ->
    Venue ->
    RosterNotificationRecipient ->
    IO ()
enqueueRosterNotificationDelivery run actor venue recipient =
    void $
        enqueueEmailDelivery
            EmailDeliveryRequest
                { mailKind = rosterNotificationMailKind
                , recipientAccountId = recipient.recipientUserId
                , recipientAddress = recipient.recipientEmail
                , domainReferenceTable = "roster_notification_runs"
                , domainReferenceId = unpackId run.id
                , semanticEventKey = "roster-notification-run:" <> tshow run.id
                , requestedByUserId = Just (unpackId actor.id)
                , venueId = Just (unpackId venue.id)
                }

rosterNotificationRecipientCountLabel :: Int -> Text
rosterNotificationRecipientCountLabel count =
    tshow count <> if count == 1 then " recipient" else " recipients"

decodeRosterNotificationSnapshot :: RosterNotificationRun -> IO RosterNotificationSnapshot
decodeRosterNotificationSnapshot run = decodeSnapshotValue "roster snapshot" run.rosterSnapshot

decodeRosterNotificationRecipients :: RosterNotificationRun -> IO [RosterNotificationRecipient]
decodeRosterNotificationRecipients run = decodeSnapshotValue "recipient snapshot" run.recipientSnapshot

decodeRosterNotificationSkippedRecipients :: RosterNotificationRun -> IO [RosterNotificationSkippedRecipient]
decodeRosterNotificationSkippedRecipients run = decodeSnapshotValue "skipped recipient snapshot" run.skippedRecipientSnapshot

decodeSnapshotValue :: Aeson.FromJSON value => String -> Aeson.Value -> IO value
decodeSnapshotValue label value =
    case Aeson.fromJSON value of
        Aeson.Error message -> fail ("Invalid roster notification " <> label <> ": " <> message)
        Aeson.Success decoded -> pure decoded

skippedReasonText :: RosterNotificationSkippedReason -> Text
skippedReasonText = \case
    RosterNotificationSkippedUnlinked -> "unlinked"
    RosterNotificationSkippedInactive -> "inactive"
    RosterNotificationSkippedMissingEmail -> "missing_email"
    RosterNotificationSkippedInvalidScope -> "invalid_scope"
