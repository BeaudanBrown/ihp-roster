module Application.Helper.Pay where

import Application.Helper.Controller hiding (venueEffectiveRateDate,
                                      venueEffectiveRateEndDate)
import Application.Helper.WeekBoundaries (WeekdayIndex)
import qualified Application.Helper.WeekBoundaries as WeekBoundaries
import Control.Monad (void)
import Data.Aeson ((.:), (.:?))
import qualified Data.Aeson as Aeson
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import Data.Ord (Down (..))
import qualified Data.Scientific as Scientific
import qualified Data.Set as Set
import qualified Data.Text as Text
import Data.Text.Encoding (encodeUtf8)
import Data.Time.Calendar (Day)
import Data.Time.Clock (UTCTime)
import qualified Database.PostgreSQL.Simple as PG
import Generated.Types
import GHC.Records (HasField)
import IHP.ControllerPrelude
import IHP.ModelSupport (ModelContext, sqlQueryScalar, unpackId)
import IHP.Prelude

venueEffectiveRateDate :: WeekdayIndex -> Day -> Day
venueEffectiveRateDate = WeekBoundaries.venueEffectiveRateDate

venueEffectiveRateEndDate :: WeekdayIndex -> Maybe Day -> Maybe Day
venueEffectiveRateEndDate = WeekBoundaries.venueEffectiveRateEndDate

rateEffectiveOn :: (HasField "operativeFrom" record (Maybe Day), HasField "operativeTo" record (Maybe Day)) => WeekdayIndex -> Day -> record -> Bool
rateEffectiveOn weekStartsOn referenceDate record =
    maybe True ((<= referenceDate) . venueEffectiveRateDate weekStartsOn) record.operativeFrom
        && maybe True (>= referenceDate) (venueEffectiveRateEndDate weekStartsOn record.operativeTo)

latestVenueEffectiveRate :: (HasField "operativeFrom" record (Maybe Day), HasField "operativeTo" record (Maybe Day), HasField "createdAt" record UTCTime) => WeekdayIndex -> Day -> [record] -> Maybe record
latestVenueEffectiveRate weekStartsOn referenceDate =
    List.find (rateEffectiveOn weekStartsOn referenceDate)
        . List.sortOn (\record -> (Down (venueEffectiveRateDate weekStartsOn <$> record.operativeFrom), Down record.createdAt))

data PaySegment = PaySegment
    { segment           :: !Text
    , segmentDate       :: !(Maybe Day)
    , minutes           :: !Int
    , shiftTypeId       :: !(Maybe UUID)
    , shiftTypeName     :: !(Maybe Text)
    , payLevelId        :: !(Maybe UUID)
    , payLevelName      :: !(Maybe Text)
    , penaltyKind       :: !(Maybe Text)
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
            <*> obj .:? "segmentDate"
            <*> obj .: "minutes"
            <*> obj .:? "shiftTypeId"
            <*> obj .:? "shiftTypeName"
            <*> obj .:? "payLevelId"
            <*> obj .:? "payLevelName"
            <*> obj .:? "penaltyKind"
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
    { entryId               :: !Text
    , shiftTypeId           :: !(Maybe UUID)
    , shiftTypeName         :: !(Maybe Text)
    , payLevelId            :: !(Maybe UUID)
    , payLevelName          :: !(Maybe Text)
    , staffPayVersionId     :: !(Maybe UUID)
    , shiftTypePayVersionId :: !(Maybe UUID)
    , segments              :: ![PaySegment]
    , totals                :: !PayTotals
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
            <*> obj .:? "staffPayVersionId"
            <*> obj .:? "shiftTypePayVersionId"
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

payVersionManifestForEntry :: TimesheetEntry -> Maybe Text
payVersionManifestForEntry entry = do
    staffVersionId <- entry.staffPayVersionId
    shiftVersionId <- entry.shiftTypePayVersionId
    pure ("staff:" <> tshow staffVersionId <> ";shift:" <> tshow shiftVersionId)

payVersionManifestForEntries :: [TimesheetEntry] -> [Text]
payVersionManifestForEntries =
    List.sort . List.nub . mapMaybe payVersionManifestForEntry

collapsePayVersionManifests :: [Text] -> Maybe Text
collapsePayVersionManifests []        = Nothing
collapsePayVersionManifests manifests = Just (Text.intercalate " | " manifests)

ensureStaffPayVersionForStaff ::
    (?modelContext :: ModelContext) =>
    Id User ->
    Staff ->
    Day ->
    IO StaffPayVersion
ensureStaffPayVersionForStaff actorUserId staff effectiveFrom = do
    currentVersion <- query @StaffPayVersion
        |> filterWhere (#staffId, unpackId staff.id)
        |> filterWhere (#effectiveTo, Nothing :: Maybe Day)
        |> fetchOneOrNothing
    case currentVersion of
        Just version
            | version.defaultAwardLevelId == fmap unpackId staff.defaultAwardLevelId
                && version.importedXeroPayItemId == staff.importedXeroPayItemId
                && version.employmentBasis == staff.employmentBasis ->
                pure version
        _ -> do
            forM_ currentVersion \version ->
                void
                    ( version
                        |> set #effectiveTo (Just effectiveFrom)
                        |> updateRecord
                    )
            newRecord @StaffPayVersion
                |> set #venueId staff.venueId
                |> set #staffId (unpackId staff.id)
                |> set #defaultAwardLevelId (fmap unpackId staff.defaultAwardLevelId)
                |> set #importedXeroPayItemId staff.importedXeroPayItemId
                |> set #employmentBasis staff.employmentBasis
                |> set #effectiveFrom effectiveFrom
                |> set #createdByUserId (unpackId actorUserId)
                |> createRecord

ensureShiftTypePayVersionForShiftType ::
    (?modelContext :: ModelContext) =>
    Id User ->
    ShiftType ->
    Day ->
    IO ShiftTypePayVersion
ensureShiftTypePayVersionForShiftType actorUserId shiftType effectiveFrom = do
    currentVersion <- query @ShiftTypePayVersion
        |> filterWhere (#shiftTypeId, unpackId shiftType.id)
        |> filterWhere (#effectiveTo, Nothing :: Maybe Day)
        |> fetchOneOrNothing
    case currentVersion of
        Just version
            | version.overrideAwardLevelId == fmap unpackId shiftType.overrideAwardLevelId
                && version.importedXeroPayItemId == shiftType.importedXeroPayItemId
                && version.payrollLabel == shiftType.name ->
                pure version
        _ -> do
            forM_ currentVersion \version ->
                void
                    ( version
                        |> set #effectiveTo (Just effectiveFrom)
                        |> updateRecord
                    )
            newRecord @ShiftTypePayVersion
                |> set #venueId shiftType.venueId
                |> set #shiftTypeId (unpackId shiftType.id)
                |> set #overrideAwardLevelId (fmap unpackId shiftType.overrideAwardLevelId)
                |> set #importedXeroPayItemId shiftType.importedXeroPayItemId
                |> set #payrollLabel shiftType.name
                |> set #effectiveFrom effectiveFrom
                |> set #createdByUserId (unpackId actorUserId)
                |> createRecord

ensurePayVersionsForTimesheetApproval ::
    (?modelContext :: ModelContext) =>
    Id User ->
    TimesheetEntry ->
    IO (StaffPayVersion, ShiftTypePayVersion)
ensurePayVersionsForTimesheetApproval actorUserId entry = do
    staff <- fetch (Id entry.staffId :: Id Staff)
    shiftType <- fetch (Id entry.shiftTypeId :: Id ShiftType)
    staffVersion <- ensureStaffPayVersionForStaff actorUserId staff entry.workedOn
    shiftTypeVersion <- ensureShiftTypePayVersionForShiftType actorUserId shiftType entry.workedOn
    pure (staffVersion, shiftTypeVersion)

lockPayVersionsForApproval ::
    (?modelContext :: ModelContext) =>
    Id User ->
    UTCTime ->
    StaffPayVersion ->
    ShiftTypePayVersion ->
    IO ()
lockPayVersionsForApproval actorUserId lockedAt staffVersion shiftTypeVersion = do
    when (isNothing staffVersion.lockedAt) do
        void
            ( staffVersion
                |> set #lockedAt (Just lockedAt)
                |> set #lockedByUserId (Just (unpackId actorUserId))
                |> updateRecord
            )
    when (isNothing shiftTypeVersion.lockedAt) do
        void
            ( shiftTypeVersion
                |> set #lockedAt (Just lockedAt)
                |> set #lockedByUserId (Just (unpackId actorUserId))
                |> updateRecord
            )

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
