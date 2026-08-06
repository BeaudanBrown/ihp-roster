module Application.RosterNotification
    ( RosterNotificationSnapshot (..)
    , RosterNotificationShiftSnapshot (..)
    , RosterNotificationRecipient (..)
    , RosterNotificationSkippedRecipient (..)
    , RosterNotificationSkippedReason (..)
    , RosterNotificationAudience (..)
    , RosterNotificationRunSummary (..)
    , RosterNotificationPanelData (..)
    , RosterNotificationDeliveryPayload (..)
    , CreateRosterNotificationRunResult (..)
    , rosterNotificationDeliveryJobKind
    , rosterNotificationPayloadSchemaVersion
    , rosterNotificationSnapshotSchemaVersion
    , createRosterNotificationRun
    , createRosterNotificationRunUnlessActive
    , fetchRosterNotificationAudience
    , fetchLatestRosterNotificationRunSummary
    , rosterNotificationRecipientCountLabel
    , decodeRosterNotificationSnapshot
    , decodeRosterNotificationRecipients
    , decodeRosterNotificationSkippedRecipients
    ) where

import Application.Async.Queue
import Application.Helper.WeekBoundaries (venueWeekStartDate)
import qualified Application.RosterNotification.Mutations as Mutations
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified Data.Text as Text
import Data.Time.Calendar (Day, addDays)
import Generated.Types hiding (createRosterNotificationRun)
import IHP.ControllerPrelude
import IHP.Job.Types (JobStatus (..))
import IHP.ModelSupport (withTransaction)

rosterNotificationDeliveryJobKind :: Text
rosterNotificationDeliveryJobKind = "roster_notification_delivery"

rosterNotificationPayloadSchemaVersion :: Int
rosterNotificationPayloadSchemaVersion = 1

rosterNotificationSnapshotSchemaVersion :: Int
rosterNotificationSnapshotSchemaVersion = 1

data RosterNotificationSnapshot = RosterNotificationSnapshot
    { snapshotVenueId         :: !UUID
    , snapshotVenueName       :: !Text
    , snapshotRosterGroupId   :: !UUID
    , snapshotRosterGroupName :: !Text
    , snapshotRosterWeekId    :: !UUID
    , snapshotWeekOffset      :: !Int
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
    deriving (Eq, Show)

data RosterNotificationDeliveryPayload = RosterNotificationDeliveryPayload
    { payloadRunId            :: !UUID
    , payloadRecipientStaffId :: !UUID
    , payloadRecipientUserId  :: !UUID
    , payloadRecipientEmail   :: !Text
    }
    deriving (Eq, Show)

instance Aeson.ToJSON RosterNotificationSnapshot where
    toJSON snapshot =
        Aeson.object
            [ "venueId" Aeson..= snapshot.snapshotVenueId
            , "venueName" Aeson..= snapshot.snapshotVenueName
            , "rosterGroupId" Aeson..= snapshot.snapshotRosterGroupId
            , "rosterGroupName" Aeson..= snapshot.snapshotRosterGroupName
            , "rosterWeekId" Aeson..= snapshot.snapshotRosterWeekId
            , "weekOffset" Aeson..= snapshot.snapshotWeekOffset
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
            <*> object Aeson..: "rosterWeekId"
            <*> object Aeson..: "weekOffset"
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

instance Aeson.ToJSON RosterNotificationDeliveryPayload where
    toJSON payload =
        Aeson.object
            [ "runId" Aeson..= payload.payloadRunId
            , "recipientStaffId" Aeson..= payload.payloadRecipientStaffId
            , "recipientUserId" Aeson..= payload.payloadRecipientUserId
            , "recipientEmail" Aeson..= payload.payloadRecipientEmail
            ]

instance Aeson.FromJSON RosterNotificationDeliveryPayload where
    parseJSON = Aeson.withObject "RosterNotificationDeliveryPayload" \object ->
        RosterNotificationDeliveryPayload
            <$> object Aeson..: "runId"
            <*> object Aeson..: "recipientStaffId"
            <*> object Aeson..: "recipientUserId"
            <*> object Aeson..: "recipientEmail"

createRosterNotificationRunUnlessActive ::
    (?modelContext :: ModelContext) =>
    User ->
    RosterWeek ->
    IO CreateRosterNotificationRunResult
createRosterNotificationRunUnlessActive actor rosterWeek =
    withTransaction do
        Mutations.lockRosterNotificationWeek rosterWeek.id
        runs <- query @RosterNotificationRun
            |> filterWhere (#rosterWeekId, unpackId rosterWeek.id)
            |> fetch
        let runIds = map (Just . unpackId . (.id)) runs
        activeDeliveryExists <-
            if null runIds
                then pure False
                else query @AppJob
                    |> filterWhere (#relatedTable, Just "roster_notification_runs")
                    |> filterWhereIn (#relatedId, runIds)
                    |> filterWhereIn (#status, activeAppJobStatuses)
                    |> fetchExists
        if activeDeliveryExists
            then pure RosterNotificationRunAlreadyActive
            else do
                createdRun <- createRosterNotificationRunInCurrentTransaction actor rosterWeek
                pure $ maybe RosterNotificationRunHasNoEligibleRecipients RosterNotificationRunCreated createdRun

createRosterNotificationRun ::
    (?modelContext :: ModelContext) =>
    User ->
    RosterWeek ->
    IO RosterNotificationRun
createRosterNotificationRun actor suppliedRosterWeek =
    withTransaction do
        createdRun <- createRosterNotificationRunInCurrentTransaction actor suppliedRosterWeek
        maybe (fail "Roster notification runs require at least one eligible recipient") pure createdRun

createRosterNotificationRunInCurrentTransaction ::
    (?modelContext :: ModelContext) =>
    User ->
    RosterWeek ->
    IO (Maybe RosterNotificationRun)
createRosterNotificationRunInCurrentTransaction actor suppliedRosterWeek = do
    persistedActor <- fetch actor.id
    rosterWeek <- fetch suppliedRosterWeek.id
    unless rosterWeek.isLive (fail "Roster notification runs require a live roster")
    venue <- fetch (Id rosterWeek.venueId :: Id Venue)
    rosterGroup <- fetch (Id rosterWeek.rosterGroupId :: Id RosterGroup)
    unless (rosterGroup.venueId == unpackId venue.id) (fail "Roster notification roster group is outside the venue")
    venueConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
    let weekStart = venueWeekStartDate venueConfig rosterWeek.weekOffset
    snapshot <- buildRosterSnapshot venue rosterGroup rosterWeek weekStart
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
                    |> set #rosterWeekId (unpackId rosterWeek.id)
                    |> set #weekOffset rosterWeek.weekOffset
                    |> set #weekStart weekStart
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
    RosterWeek ->
    Day ->
    IO RosterNotificationSnapshot
buildRosterSnapshot venue rosterGroup rosterWeek weekStart = do
    rosterDays <- query @RosterDay
        |> filterWhere (#rosterWeekId, unpackId rosterWeek.id)
        |> orderByAsc #dayOffset
        |> fetch
    definitions <- query @RosterWeekSlotDefinition
        |> filterWhere (#rosterWeekId, unpackId rosterWeek.id)
        |> filterWhere (#deletedAt, Nothing)
        |> fetch
    let rosterDayIds = map (unpackId . (.id)) rosterDays
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
    let definitionById = Map.fromList [(unpackId definition.id, definition) | definition <- definitions]
    let shiftTypeById = Map.fromList [(unpackId shiftType.id, shiftType) | shiftType <- shiftTypes]
    let snapshotShifts = mapMaybe (snapshotShift weekStart dayById definitionById shiftTypeById) shifts
    pure RosterNotificationSnapshot
        { snapshotVenueId = unpackId venue.id
        , snapshotVenueName = venue.name
        , snapshotRosterGroupId = unpackId rosterGroup.id
        , snapshotRosterGroupName = rosterGroup.name
        , snapshotRosterWeekId = unpackId rosterWeek.id
        , snapshotWeekOffset = rosterWeek.weekOffset
        , snapshotWeekStart = weekStart
        , snapshotWeekEnd = addDays 6 weekStart
        , snapshotShifts
        }

snapshotShift ::
    Day ->
    Map.Map UUID RosterDay ->
    Map.Map UUID RosterWeekSlotDefinition ->
    Map.Map UUID ShiftType ->
    RosterSlot ->
    Maybe RosterNotificationShiftSnapshot
snapshotShift weekStart dayById definitionById shiftTypeById slot = do
    rosterDay <- Map.lookup slot.rosterDayId dayById
    definition <- Map.lookup slot.rosterWeekSlotDefinitionId definitionById
    pure RosterNotificationShiftSnapshot
        { shiftRosterSlotId = unpackId slot.id
        , shiftStaffId = slot.staffId
        , shiftDate = addDays (toInteger rosterDay.dayOffset) weekStart
        , shiftStartsAt = slot.startsAt
        , shiftEndsAt = slot.endsAt
        , shiftTimezone = slot.timezone
        , shiftLaneName = definition.name
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

fetchLatestRosterNotificationRunSummary ::
    (?modelContext :: ModelContext) =>
    RosterWeek ->
    IO (Maybe RosterNotificationRunSummary)
fetchLatestRosterNotificationRunSummary rosterWeek = do
    latestRun <- query @RosterNotificationRun
        |> filterWhere (#rosterWeekId, unpackId rosterWeek.id)
        |> orderByDesc #createdAt
        |> fetchOneOrNothing
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
            , summaryDeliveredCount = length (filter (== JobStatusSucceeded) statuses)
            , summaryInProgressCount = length (filter (`elem` activeAppJobStatuses) statuses)
            , summaryFailedCount = length (filter (`elem` [JobStatusFailed, JobStatusTimedOut]) statuses)
            }

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
enqueueRosterNotificationDelivery run actor venue recipient = do
    let payload = RosterNotificationDeliveryPayload
            { payloadRunId = unpackId run.id
            , payloadRecipientStaffId = recipient.recipientStaffId
            , payloadRecipientUserId = recipient.recipientUserId
            , payloadRecipientEmail = recipient.recipientEmail
            }
    void $ enqueueAppJob AppJobRequest
        { jobKind = rosterNotificationDeliveryJobKind
        , payload = Aeson.toJSON payload
        , payloadSchemaVersion = rosterNotificationPayloadSchemaVersion
        , requestedByUserId = Just (unpackId actor.id)
        , venueId = Just (unpackId venue.id)
        , relatedTable = Just "roster_notification_runs"
        , relatedId = Just (unpackId run.id)
        , dedupeKey = Just ("roster-notification-delivery:" <> tshow run.id <> ":" <> tshow recipient.recipientUserId)
        , runAt = Nothing
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
