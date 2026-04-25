module Application.Helper.Pay where

import Application.Helper.Controller
import Data.Aeson ((.:), (.:?))
import qualified Data.Aeson as Aeson
import qualified Data.Map.Strict as Map
import qualified Data.Scientific as Scientific
import qualified Data.Set as Set
import qualified Data.Text as Text
import Data.Text.Encoding (encodeUtf8)
import Data.Time.Calendar (Day)
import qualified Database.PostgreSQL.Simple as PG
import Generated.Types
import IHP.ControllerPrelude
import IHP.ModelSupport (ModelContext, sqlQueryScalar, unpackId)
import IHP.Prelude

data PaySegment = PaySegment
    { segment           :: !Text
    , minutes           :: !Int
    , shiftTypeId       :: !(Maybe UUID)
    , shiftTypeName     :: !(Maybe Text)
    , payLevelId        :: !(Maybe UUID)
    , payLevelName      :: !(Maybe Text)
    , multiplier        :: !Scientific.Scientific
    , dayRuleMultiplier :: !(Maybe Scientific.Scientific)
    , weekendMultiplier :: !(Maybe Scientific.Scientific)
    , baseRate          :: !Scientific.Scientific
    , amount            :: !Scientific.Scientific
    }
    deriving (Eq, Show)

instance Aeson.FromJSON PaySegment where
    parseJSON = Aeson.withObject "PaySegment" \obj ->
        PaySegment
            <$> obj .: "segment"
            <*> obj .: "minutes"
            <*> obj .:? "shiftTypeId"
            <*> obj .:? "shiftTypeName"
            <*> obj .:? "payLevelId"
            <*> obj .:? "payLevelName"
            <*> obj .: "multiplier"
            <*> obj .:? "dayRuleMultiplier"
            <*> obj .:? "weekendMultiplier"
            <*> obj .: "baseRate"
            <*> obj .: "amount"

data PayTotals = PayTotals
    { paidMinutes :: !Int
    , totalAmount :: !Scientific.Scientific
    }
    deriving (Eq, Show)

instance Aeson.FromJSON PayTotals where
    parseJSON = Aeson.withObject "PayTotals" \obj ->
        PayTotals
            <$> obj .: "paidMinutes"
            <*> obj .: "totalAmount"

data TimesheetPayResult = TimesheetPayResult
    { entryId                  :: !Text
    , shiftTypeId              :: !(Maybe UUID)
    , shiftTypeName            :: !(Maybe Text)
    , payLevelId               :: !(Maybe UUID)
    , payLevelName             :: !(Maybe Text)
    , payConfigSnapshotId      :: !(Maybe UUID)
    , payConfigSnapshotVersion :: !(Maybe Text)
    , segments                 :: ![PaySegment]
    , totals                   :: !PayTotals
    }
    deriving (Eq, Show)

instance Aeson.FromJSON TimesheetPayResult where
    parseJSON = Aeson.withObject "TimesheetPayResult" \obj ->
        TimesheetPayResult
            <$> obj .: "entryId"
            <*> obj .:? "shiftTypeId"
            <*> obj .:? "shiftTypeName"
            <*> obj .:? "payLevelId"
            <*> obj .:? "payLevelName"
            <*> obj .:? "payConfigSnapshotId"
            <*> obj .:? "payConfigSnapshotVersion"
            <*> obj .: "segments"
            <*> obj .: "totals"

data TimesheetPaySummary = TimesheetPaySummary
    { paidMinutes          :: !Int
    , totalAmount          :: !Scientific.Scientific
    , segmentCount         :: !Int
    , weekendApplied       :: !Bool
    , hasStackedMultiplier :: !Bool
    }
    deriving (Eq, Show)

decodeTimesheetPayResult :: Text -> Either Text TimesheetPayResult
decodeTimesheetPayResult payload =
    case Aeson.eitherDecodeStrict' (encodeUtf8 payload) of
        Left err -> Left ("Failed to decode calculate_timesheet_pay payload: " <> Text.pack err)
        Right value -> Right value

decodeTimesheetPayResults :: Text -> Either Text [TimesheetPayResult]
decodeTimesheetPayResults payload =
    case Aeson.eitherDecodeStrict' (encodeUtf8 payload) of
        Left err -> Left ("Failed to decode calculate_timesheet_pay_range payload: " <> Text.pack err)
        Right value -> Right value

timesheetEntryIdKey :: Id TimesheetEntry -> Text
timesheetEntryIdKey entryId = tshow (unpackId entryId)

buildTimesheetPaySummary :: TimesheetPayResult -> TimesheetPaySummary
buildTimesheetPaySummary result =
    TimesheetPaySummary
        { paidMinutes = result.totals.paidMinutes
        , totalAmount = result.totals.totalAmount
        , segmentCount = length result.segments
        , weekendApplied = any hasWeekend result.segments
        , hasStackedMultiplier = any hasStacked result.segments
        }
    where
        hasWeekend segment = maybe False (> 1) segment.weekendMultiplier
        hasStacked segment = maybe False (> 1) segment.weekendMultiplier && maybe False (/= 1) segment.dayRuleMultiplier

buildTimesheetPaySummariesByEntryId :: [TimesheetPayResult] -> Map.Map Text TimesheetPaySummary
buildTimesheetPaySummariesByEntryId results =
    Map.fromList (map (\result -> (result.entryId, buildTimesheetPaySummary result)) results)

buildTimesheetPayResultsByEntryId :: [TimesheetPayResult] -> Map.Map Text TimesheetPayResult
buildTimesheetPayResultsByEntryId results =
    Map.fromList (map (\result -> (result.entryId, result)) results)

snapshotVersionLabel :: Int -> Text
snapshotVersionLabel versionNumber = "v" <> tshow versionNumber

fetchCurrentVenuePayConfigSnapshots ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    IO [PayConfigSnapshot]
fetchCurrentVenuePayConfigSnapshots =
    query @PayConfigSnapshot
        |> filterWhere (#venueId, unpackId currentVenueId)
        |> orderByDesc #versionNumber
        |> fetch

fetchLatestCurrentVenuePayConfigSnapshot ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    IO (Maybe PayConfigSnapshot)
fetchLatestCurrentVenuePayConfigSnapshot =
    query @PayConfigSnapshot
        |> filterWhere (#venueId, unpackId currentVenueId)
        |> orderByDesc #versionNumber
        |> fetchOneOrNothing

createCurrentVenuePayConfigSnapshot ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    IO PayConfigSnapshot
createCurrentVenuePayConfigSnapshot = do
    latestSnapshot <- fetchLatestCurrentVenuePayConfigSnapshot
    snapshotPayload <- buildCurrentVenuePayConfigSnapshotPayload
    let versionNumber = maybe 1 ((+ 1) . (.versionNumber)) latestSnapshot
    newRecord @PayConfigSnapshot
        |> set #venueId (unpackId currentVenueId)
        |> set #versionNumber versionNumber
        |> set #versionLabel (snapshotVersionLabel versionNumber)
        |> set #createdByUserId (unpackId (get #id authenticatedCurrentUser))
        |> set #snapshot snapshotPayload
        |> createRecord

syncCurrentVenuePayConfigSnapshot ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    IO PayConfigSnapshot
syncCurrentVenuePayConfigSnapshot = do
    latestSnapshot <- fetchLatestCurrentVenuePayConfigSnapshot
    snapshotPayload <- buildCurrentVenuePayConfigSnapshotPayload

    case latestSnapshot of
        Just snapshot
            | snapshot.snapshot == snapshotPayload ->
                pure snapshot
        _ -> do
            let versionNumber = maybe 1 ((+ 1) . (.versionNumber)) latestSnapshot
            newRecord @PayConfigSnapshot
                |> set #venueId (unpackId currentVenueId)
                |> set #versionNumber versionNumber
                |> set #versionLabel (snapshotVersionLabel versionNumber)
                |> set #createdByUserId (unpackId (get #id authenticatedCurrentUser))
                |> set #snapshot snapshotPayload
                |> createRecord

ensureCurrentVenuePayConfigSnapshot ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    IO PayConfigSnapshot
ensureCurrentVenuePayConfigSnapshot =
    fetchLatestCurrentVenuePayConfigSnapshot >>= \case
        Just snapshot -> pure snapshot
        Nothing -> createCurrentVenuePayConfigSnapshot

buildCurrentVenuePayConfigSnapshotPayload ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    IO Aeson.Value
buildCurrentVenuePayConfigSnapshotPayload = do
    venueConfig <- fetchVenueConfig
    awardLevels <- query @AwardLevel |> orderByAsc #classification |> fetch
    awardLevelBaseRates <- query @AwardLevelBaseRate |> orderByAsc #createdAt |> fetch
    awardLevelPenaltyRates <- query @AwardLevelPenaltyRate |> orderByAsc #createdAt |> fetch
    shiftTypes <- query @ShiftType |> filterWhere (#venueId, unpackId currentVenueId) |> orderByAsc #createdAt |> fetch

    pure $
        Aeson.object
            [ "venueConfig" Aeson..= Aeson.object
                [ "id" Aeson..= unpackId (get #id venueConfig)
                , "timezone" Aeson..= venueConfig.timezone
                , "rosterWeekStartsOn" Aeson..= venueConfig.rosterWeekStartsOn
                , "weekOffsetEpoch" Aeson..= venueConfig.weekOffsetEpoch
                , "lateToEarlyMinStartGapMinutes" Aeson..= venueConfig.lateToEarlyMinStartGapMinutes
                , "staffTimesheetEditWindowDays" Aeson..= venueConfig.staffTimesheetEditWindowDays
                , "publicHolidayJurisdiction" Aeson..= venueConfig.publicHolidayJurisdiction
                ]
            , "awardLevels" Aeson..= map serializeAwardLevel awardLevels
            , "awardLevelBaseRates" Aeson..= map serializeAwardLevelBaseRate awardLevelBaseRates
            , "awardLevelPenaltyRates" Aeson..= map serializeAwardLevelPenaltyRate awardLevelPenaltyRates
            , "shiftTypes" Aeson..= map serializeShiftType shiftTypes
            ]
    where
        serializeAwardLevel awardLevel =
            Aeson.object
                [ "id" Aeson..= unpackId (get #id awardLevel)
                , "awardFixedId" Aeson..= awardLevel.awardFixedId
                , "classificationFixedId" Aeson..= awardLevel.classificationFixedId
                , "classification" Aeson..= awardLevel.classification
                , "classificationLevel" Aeson..= awardLevel.classificationLevel
                , "parentClassificationName" Aeson..= awardLevel.parentClassificationName
                , "isActive" Aeson..= awardLevel.isActive
                ]

        serializeAwardLevelBaseRate rate =
            Aeson.object
                [ "id" Aeson..= unpackId (get #id rate)
                , "awardLevelId" Aeson..= rate.awardLevelId
                , "employmentBasis" Aeson..= inputValue rate.employmentBasis
                , "hourlyRate" Aeson..= rate.hourlyRate
                , "rateLabel" Aeson..= rate.rateLabel
                , "operativeFrom" Aeson..= rate.operativeFrom
                , "operativeTo" Aeson..= rate.operativeTo
                ]

        serializeAwardLevelPenaltyRate rate =
            Aeson.object
                [ "id" Aeson..= unpackId (get #id rate)
                , "awardLevelId" Aeson..= rate.awardLevelId
                , "employmentBasis" Aeson..= inputValue rate.employmentBasis
                , "penaltyKind" Aeson..= inputValue rate.penaltyKind
                , "hourlyRate" Aeson..= rate.hourlyRate
                , "startsAtTime" Aeson..= rate.startsAtTime
                , "endsAtTime" Aeson..= rate.endsAtTime
                , "operativeFrom" Aeson..= rate.operativeFrom
                , "operativeTo" Aeson..= rate.operativeTo
                ]

        serializeShiftType shiftType =
            Aeson.object
                [ "id" Aeson..= unpackId (get #id shiftType)
                , "name" Aeson..= shiftType.name
                , "sortOrder" Aeson..= shiftType.sortOrder
                , "overrideAwardLevelId" Aeson..= shiftType.overrideAwardLevelId
                , "isActive" Aeson..= shiftType.isActive
                ]

fetchTimesheetPay :: (?modelContext :: ModelContext) => Id TimesheetEntry -> IO (Either Text TimesheetPayResult)
fetchTimesheetPay entryId = do
    payload :: Text <- sqlQueryScalar "SELECT calculate_timesheet_pay(?)::text" (PG.Only (unpackId entryId))
    pure (decodeTimesheetPayResult payload)

fetchTimesheetPayRange :: (?modelContext :: ModelContext) => UUID -> Day -> Day -> IO (Either Text [TimesheetPayResult])
fetchTimesheetPayRange staffId fromDate toDate = do
    payload :: Text <- sqlQueryScalar "SELECT calculate_timesheet_pay_range(?, ?, ?)::text" (staffId, fromDate, toDate)
    pure (decodeTimesheetPayResults payload)

fetchTimesheetPayResultsForEntries :: (?modelContext :: ModelContext) => [TimesheetEntry] -> IO (Map.Map Text TimesheetPayResult)
fetchTimesheetPayResultsForEntries entries = do
    let groupedEntries = groupByStaff entries
    resultMaps <- forM (Map.toList groupedEntries) \(staffId, staffEntries) -> do
        let fromDate = minimum (map (.workedOn) staffEntries)
        let toDate = maximum (map (.workedOn) staffEntries)
        let requestedEntryIds = Set.fromList (map (timesheetEntryIdKey . get #id) staffEntries)
        payResults <- fetchTimesheetPayRange staffId fromDate toDate
        case payResults of
            Left _ -> pure Map.empty
            Right results ->
                pure
                    ( buildTimesheetPayResultsByEntryId results
                        |> Map.filterWithKey (\entryId _ -> Set.member entryId requestedEntryIds)
                    )
    pure (Map.unions resultMaps)
    where
        groupByStaff :: [TimesheetEntry] -> Map.Map UUID [TimesheetEntry]
        groupByStaff =
            foldl' (\acc entry -> Map.insertWith (<>) entry.staffId [entry] acc) Map.empty

fetchTimesheetPaySummariesForEntries :: (?modelContext :: ModelContext) => [TimesheetEntry] -> IO (Map.Map Text TimesheetPaySummary)
fetchTimesheetPaySummariesForEntries entries = do
    let groupedEntries = groupByStaff entries
    resultMaps <- forM (Map.toList groupedEntries) \(staffId, staffEntries) -> do
        let fromDate = minimum (map (.workedOn) staffEntries)
        let toDate = maximum (map (.workedOn) staffEntries)
        payResults <- fetchTimesheetPayRange staffId fromDate toDate
        case payResults of
            Left _        -> pure Map.empty
            Right results -> pure (buildTimesheetPaySummariesByEntryId results)
    pure (Map.unions resultMaps)
    where
        groupByStaff :: [TimesheetEntry] -> Map.Map UUID [TimesheetEntry]
        groupByStaff =
            foldl' (\acc entry -> Map.insertWith (<>) entry.staffId [entry] acc) Map.empty
