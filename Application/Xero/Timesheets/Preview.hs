module Application.Xero.Timesheets.Preview
    ( XeroTimesheetPreview (..)
    , XeroTimesheetPreviewInput (..)
    , XeroTimesheetPreviewLine (..)
    , XeroTimesheetPreviewRun (..)
    , buildXeroTimesheetPreviewRun
    , createPersistedXeroTimesheetPreview
    , fetchPreviewInput
    , periodDays
    , xeroReadinessSnapshotJson
    , xeroTimesheetPreviewRunJson
    )
where

import Application.Helper.Pay
import Application.Helper.XeroTimesheetReadiness
import qualified Data.Aeson as Aeson
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import qualified Data.Scientific as Scientific
import qualified Data.Text as Text
import Data.Time.Calendar (Day, addDays, diffDays)
import Data.Time.Clock (UTCTime)
import qualified Data.Vector as Vector
import Generated.Types
import IHP.ControllerPrelude

data XeroTimesheetPreviewInput = XeroTimesheetPreviewInput
    { previewVenueId               :: !(Id Venue)
    , previewPeriodStart           :: !Day
    , previewPeriodEnd             :: !Day
    , previewTimesheetEntries      :: ![TimesheetEntry]
    , previewStaff                 :: ![Staff]
    , previewStaffMappings         :: ![XeroStaffMapping]
    , previewEarningsMappings      :: ![XeroEarningsRateMapping]
    , previewPayItemRequirements   :: ![XeroPayItemRequirementRecord]
    , previewPayResultsByEntryId   :: !(Map.Map Text TimesheetPayResult)
    , previewAwardLevels           :: ![AwardLevel]
    , previewAwardLevelBaseRates   :: ![AwardLevelBaseRate]
    , previewAwardLevelPenalties   :: ![AwardLevelPenaltyRate]
    , previewTimePenaltyAllowances :: ![AwardTimePenaltyAllowance]
    }
    deriving (Eq, Show)

data XeroTimesheetPreviewLine = XeroTimesheetPreviewLine
    { previewLineLocalBucketKey     :: !Text
    , previewLineXeroEarningsRateId :: !Text
    , previewLineNumberOfUnits      :: ![Scientific.Scientific]
    , previewLineSourceEntryIds     :: ![UUID]
    , previewLineStaffPayVersionIds :: ![UUID]
    , previewLineShiftPayVersionIds :: ![UUID]
    }
    deriving (Eq, Show)

data XeroTimesheetPreview = XeroTimesheetPreview
    { previewStaffIds           :: ![UUID]
    , previewXeroEmployeeId     :: !Text
    , previewPayPeriodStart     :: !Day
    , previewPayPeriodEnd       :: !Day
    , previewSourceEntryIds     :: ![UUID]
    , previewStaffPayVersionIds :: ![UUID]
    , previewShiftPayVersionIds :: ![UUID]
    , previewLines              :: ![XeroTimesheetPreviewLine]
    , previewRequestObjectJson  :: !Aeson.Value
    }
    deriving (Eq, Show)

data XeroTimesheetPreviewRun = XeroTimesheetPreviewRun
    { previewRunPeriodStart      :: !Day
    , previewRunPeriodEnd        :: !Day
    , previewRunTimesheets       :: ![XeroTimesheetPreview]
    , previewRunRequestArrayJson :: !Aeson.Value
    }
    deriving (Eq, Show)

data SegmentContribution = SegmentContribution
    { contributionStaffId        :: !UUID
    , contributionXeroEmployeeId :: !Text
    , contributionEntryId        :: !UUID
    , contributionStaffVersionId :: !UUID
    , contributionShiftVersionId :: !UUID
    , contributionWorkedOn       :: !Day
    , contributionLocalBucketKey :: !Text
    , contributionEarningsRateId :: !Text
    , contributionUnits          :: !Scientific.Scientific
    }
    deriving (Eq, Show)

data LineAggregation = LineAggregation
    { lineAggregationLocalBucketKey  :: !Text
    , lineAggregationEarningsRateId  :: !Text
    , lineAggregationUnitsByDay      :: !(Map.Map Day Scientific.Scientific)
    , lineAggregationEntryIds        :: ![UUID]
    , lineAggregationStaffVersionIds :: ![UUID]
    , lineAggregationShiftVersionIds :: ![UUID]
    }
    deriving (Eq, Show)

data TimesheetAggregation = TimesheetAggregation
    { timesheetAggregationEmployeeId      :: !Text
    , timesheetAggregationStaffIds        :: ![UUID]
    , timesheetAggregationEntryIds        :: ![UUID]
    , timesheetAggregationStaffVersionIds :: ![UUID]
    , timesheetAggregationShiftVersionIds :: ![UUID]
    , timesheetAggregationLines           :: !(Map.Map Text LineAggregation)
    }
    deriving (Eq, Show)

buildXeroTimesheetPreviewRun :: XeroTimesheetPreviewInput -> Either Text XeroTimesheetPreviewRun
buildXeroTimesheetPreviewRun input = do
    contributions <- fmap concat (mapM (entryContributions input) input.previewTimesheetEntries)
    let aggregated = foldl' (accumulateTimesheet input) Map.empty contributions
    let timesheets =
            aggregated
                |> Map.elems
                |> List.sortOn (.timesheetAggregationEmployeeId)
                |> map (toPreview input)
    pure XeroTimesheetPreviewRun
        { previewRunPeriodStart = input.previewPeriodStart
        , previewRunPeriodEnd = input.previewPeriodEnd
        , previewRunTimesheets = timesheets
        , previewRunRequestArrayJson = Aeson.Array (Vector.fromList (map (.previewRequestObjectJson) timesheets))
        }

createPersistedXeroTimesheetPreview ::
    (?modelContext :: ModelContext) =>
    Id User ->
    XeroTimesheetReadinessRequest ->
    XeroTimesheetReadiness ->
    Aeson.Value ->
    IO (Either Text XeroSubmissionRun)
createPersistedXeroTimesheetPreview submittedByUserId request readiness duplicateCheckJson
    | not readiness.xeroTimesheetReady =
        pure (Left "Xero timesheet readiness must pass before a preview can be persisted.")
    | otherwise = do
        maybeConnection <- fetchActivePreviewXeroConnection request.readinessVenueId
        case maybeConnection of
            Nothing -> pure (Left "Active Xero connection was not found.")
            Just connection -> do
                previewInput <- fetchPreviewInput request connection
                case buildXeroTimesheetPreviewRun previewInput of
                    Left err -> pure (Left err)
                    Right previewRun -> do
                        run <-
                            newRecord @XeroSubmissionRun
                                |> set #venueId (unpackId request.readinessVenueId)
                                |> set #xeroConnectionId (unpackId connection.id)
                                |> set #submittedByUserId (unpackId submittedByUserId)
                                |> set #payPeriodStart request.readinessPeriodStart
                                |> set #payPeriodEnd request.readinessPeriodEnd
                                |> set #status ("previewed" :: Text)
                                |> set #previewPayloadJson (xeroTimesheetPreviewRunJson previewRun)
                                |> set #readinessSnapshotJson (xeroReadinessSnapshotJson readiness)
                                |> set #xeroDuplicateCheckJson duplicateCheckJson
                                |> createRecord
                        pure (Right run)

fetchPreviewInput ::
    (?modelContext :: ModelContext) =>
    XeroTimesheetReadinessRequest ->
    XeroConnection ->
    IO XeroTimesheetPreviewInput
fetchPreviewInput request connection = do
    approvedEntries <-
        query @TimesheetEntry
            |> filterWhere (#venueId, unpackId request.readinessVenueId)
            |> filterWhereGreaterThanOrEqualTo (#workedOn, request.readinessPeriodStart)
            |> filterWhereLessThanOrEqualTo (#workedOn, request.readinessPeriodEnd)
            |> filterWhere (#isApproved, True)
            |> filterWhere (#deletedAt, Nothing)
            |> orderBy #workedOn
            |> fetch
    staffMappings <-
        query @XeroStaffMapping
            |> filterWhere (#xeroConnectionId, unpackId connection.id)
            |> filterWhereIn (#staffId, map (.staffId) approvedEntries)
            |> filterWhere (#mappingStatus, "verified" :: Text)
            |> fetch
    selectedPayrollCalendarEmployeeIds <- fetchSelectedPayrollCalendarEmployeeIds connection
    let entries =
            approvedEntries
                |> filter \entry ->
                    any (mappingIncludesEntry entry selectedPayrollCalendarEmployeeIds) staffMappings
    staffMembers <-
        query @Staff
            |> filterWhere (#venueId, unpackId request.readinessVenueId)
            |> filterWhereIn (#id, map (Id . (.staffId)) entries)
            |> fetch
    earningsMappings <-
        query @XeroEarningsRateMapping
            |> filterWhere (#xeroConnectionId, unpackId connection.id)
            |> filterWhere (#mappingStatus, "verified" :: Text)
            |> fetch
    payItemRequirements <-
        query @XeroPayItemRequirementRecord
            |> filterWhere (#xeroConnectionId, unpackId connection.id)
            |> filterWhereIn (#requirementStatus, ["matched" :: Text, "created"])
            |> fetch
    payResults <- fetchTimesheetPayResultsForEntries entries
    awardLevels <- query @AwardLevel |> fetch
    baseRates <- query @AwardLevelBaseRate |> fetch
    penaltyRates <- query @AwardLevelPenaltyRate |> fetch
    timeAllowances <- query @AwardTimePenaltyAllowance |> fetch
    pure XeroTimesheetPreviewInput
        { previewVenueId = request.readinessVenueId
        , previewPeriodStart = request.readinessPeriodStart
        , previewPeriodEnd = request.readinessPeriodEnd
        , previewTimesheetEntries = entries
        , previewStaff = staffMembers
        , previewStaffMappings = staffMappings
        , previewEarningsMappings = earningsMappings
        , previewPayItemRequirements = payItemRequirements
        , previewPayResultsByEntryId = payResults
        , previewAwardLevels = awardLevels
        , previewAwardLevelBaseRates = baseRates
        , previewAwardLevelPenalties = penaltyRates
        , previewTimePenaltyAllowances = timeAllowances
        }

fetchSelectedPayrollCalendarEmployeeIds :: (?modelContext :: ModelContext) => XeroConnection -> IO [Text]
fetchSelectedPayrollCalendarEmployeeIds connection = do
    maybeSelection <-
        query @XeroPayrollCalendarSelection
            |> filterWhere (#xeroConnectionId, unpackId connection.id)
            |> filterWhere (#calendarStatus, "verified" :: Text)
            |> fetchOneOrNothing
    case maybeSelection >>= (.xeroPayrollCalendarId) of
        Nothing -> pure []
        Just payrollCalendarId ->
            fmap (map (.xeroEmployeeId)) $
                query @XeroEmployee
                |> filterWhere (#xeroConnectionId, unpackId connection.id)
                |> filterWhere (#payrollCalendarId, Just payrollCalendarId)
                |> fetch

mappingIncludesEntry :: TimesheetEntry -> [Text] -> XeroStaffMapping -> Bool
mappingIncludesEntry entry selectedPayrollCalendarEmployeeIds mapping =
    mapping.staffId == entry.staffId
        && maybe False (`elem` selectedPayrollCalendarEmployeeIds) mapping.xeroEmployeeId

fetchActivePreviewXeroConnection :: (?modelContext :: ModelContext) => Id Venue -> IO (Maybe XeroConnection)
fetchActivePreviewXeroConnection venueId =
    query @XeroConnection
        |> filterWhere (#venueId, unpackId venueId)
        |> filterWhere (#connectionStatus, "active" :: Text)
        |> orderByDesc #connectedAt
        |> fetchOneOrNothing

entryContributions :: XeroTimesheetPreviewInput -> TimesheetEntry -> Either Text [SegmentContribution]
entryContributions input entry = do
    staff <- maybeToEither ("Missing staff for timesheet entry " <> tshow (unpackId entry.id)) (find (\staff -> unpackId staff.id == entry.staffId) input.previewStaff)
    xeroEmployeeId <- staffXeroEmployeeId input entry
    staffVersionId <- maybeToEither ("Missing staff pay version for timesheet entry " <> tshow (unpackId entry.id)) entry.staffPayVersionId
    shiftVersionId <- maybeToEither ("Missing shift type pay version for timesheet entry " <> tshow (unpackId entry.id)) entry.shiftTypePayVersionId
    payResult <- maybeToEither ("Missing pay result for timesheet entry " <> tshow (unpackId entry.id)) (Map.lookup (timesheetEntryIdKey entry.id) input.previewPayResultsByEntryId)
    entry.approvedAt |> maybeToEither ("Missing approval timestamp for timesheet entry " <> tshow (unpackId entry.id)) |> const (pure ())
    payResult.segments
        |> filter (\segment -> segment.minutes > 0)
        |> mapM (segmentContribution input entry staff xeroEmployeeId staffVersionId shiftVersionId payResult)

segmentContribution ::
    XeroTimesheetPreviewInput ->
    TimesheetEntry ->
    Staff ->
    Text ->
    UUID ->
    UUID ->
    TimesheetPayResult ->
    PaySegment ->
    Either Text SegmentContribution
segmentContribution input entry staff xeroEmployeeId staffVersionId shiftVersionId payResult segment = do
    segmentDate <- maybeToEither ("Missing pay segment date for timesheet entry " <> tshow (unpackId entry.id)) segment.segmentDate
    let workedOn = segmentDate
    localBucketKey <- localBucketKeyForSegment input staff payResult segment workedOn
    earningsRateId <- earningsRateIdForBucket input localBucketKey
    pure SegmentContribution
        { contributionStaffId = unpackId staff.id
        , contributionXeroEmployeeId = xeroEmployeeId
        , contributionEntryId = unpackId entry.id
        , contributionStaffVersionId = staffVersionId
        , contributionShiftVersionId = shiftVersionId
        , contributionWorkedOn = workedOn
        , contributionLocalBucketKey = localBucketKey
        , contributionEarningsRateId = earningsRateId
        , contributionUnits = minutesToUnits segment.minutes
        }

staffXeroEmployeeId :: XeroTimesheetPreviewInput -> TimesheetEntry -> Either Text Text
staffXeroEmployeeId input entry =
    maybeToEither ("Missing verified Xero employee mapping for staff " <> tshow entry.staffId) do
        mapping <- find (\candidate -> candidate.staffId == entry.staffId) input.previewStaffMappings
        mapping.xeroEmployeeId

earningsRateIdForBucket :: XeroTimesheetPreviewInput -> Text -> Either Text Text
earningsRateIdForBucket input localBucketKey =
    maybeToEither ("Missing verified Xero earnings-rate mapping for bucket " <> localBucketKey) do
        mappedEarningsRateId <|> managedRequirementEarningsRateId
    where
        mappedEarningsRateId = do
            mapping <- find (\candidate -> candidate.localBucketKey == localBucketKey) input.previewEarningsMappings
            mapping.xeroEarningsRateId
        managedRequirementEarningsRateId = do
            requirement <- find (\candidate -> candidate.requirementKey == localBucketKey) input.previewPayItemRequirements
            requirement.xeroEarningsRateId

localBucketKeyForSegment :: XeroTimesheetPreviewInput -> Staff -> TimesheetPayResult -> PaySegment -> Day -> Either Text Text
localBucketKeyForSegment input staff payResult segment segmentDate = do
    payLevelId <- maybeToEither "Missing award level for pay segment." (segment.payLevelId <|> payResult.payLevelId <|> fmap unpackId staff.defaultAwardLevelId)
    awardLevel <- maybeToEither ("Missing award level " <> tshow payLevelId) (find (\level -> unpackId level.id == payLevelId) input.previewAwardLevels)
    let condition = fromMaybe "ordinary" segment.penaltyKind
    effectiveFrom <-
        if condition == "ordinary"
            then ordinaryEffectiveFrom input payLevelId staff.employmentBasis segmentDate
            else penaltyEffectiveFrom input awardLevel payLevelId staff.employmentBasis condition segmentDate
    pure $
        "xero:pay-item:classification:"
            <> tshow awardLevel.classificationFixedId
            <> ":basis:"
            <> inputValue staff.employmentBasis
            <> ":effective:"
            <> maybe "undated" tshow effectiveFrom
            <> ":"
            <> if condition == "ordinary" then "ordinary" else "penalty:" <> condition

ordinaryEffectiveFrom :: XeroTimesheetPreviewInput -> UUID -> StaffEmploymentBasisEnum -> Day -> Either Text (Maybe Day)
ordinaryEffectiveFrom input payLevelId employmentBasis segmentDate =
    input.previewAwardLevelBaseRates
        |> filter (\rate -> rate.awardLevelId == payLevelId && rate.employmentBasis == employmentBasis && activeOn segmentDate rate.operativeFrom rate.operativeTo)
        |> List.sortOn (.operativeFrom)
        |> listToMaybe
        |> fmap (.operativeFrom)
        |> maybeToEither ("Missing active base rate for award level " <> tshow payLevelId)

penaltyEffectiveFrom :: XeroTimesheetPreviewInput -> AwardLevel -> UUID -> StaffEmploymentBasisEnum -> Text -> Day -> Either Text (Maybe Day)
penaltyEffectiveFrom input awardLevel payLevelId employmentBasis penaltyKindText segmentDate = do
    penaltyKind <- maybeToEither ("Unsupported Xero pay-item penalty kind " <> penaltyKindText) (parsePenaltyKind penaltyKindText)
    case delayedMealBreakSourcePenaltyKind penaltyKind of
        Just Nothing ->
            ordinaryEffectiveFrom input payLevelId employmentBasis segmentDate
        Just (Just sourcePenaltyKind) ->
            activeLevelPenaltyEffectiveFrom input payLevelId employmentBasis sourcePenaltyKind segmentDate
                |> maybeToEither ("Missing active pay item source for penalty kind " <> penaltyKindText)
        Nothing ->
            maybeToEither ("Missing active pay item source for penalty kind " <> penaltyKindText) do
                activeLevelPenaltyEffectiveFrom input payLevelId employmentBasis penaltyKind segmentDate
                    <|> activeTimeAllowanceEffectiveFrom input awardLevel.awardFixedId penaltyKind segmentDate

activeLevelPenaltyEffectiveFrom :: XeroTimesheetPreviewInput -> UUID -> StaffEmploymentBasisEnum -> AwardPenaltyKindEnum -> Day -> Maybe (Maybe Day)
activeLevelPenaltyEffectiveFrom input payLevelId employmentBasis penaltyKind segmentDate =
    input.previewAwardLevelPenalties
        |> filter (\rate -> rate.awardLevelId == payLevelId && rate.employmentBasis == employmentBasis && rate.penaltyKind == penaltyKind && activeOn segmentDate rate.operativeFrom rate.operativeTo)
        |> List.sortOn (.operativeFrom)
        |> listToMaybe
        |> fmap (.operativeFrom)

activeTimeAllowanceEffectiveFrom :: XeroTimesheetPreviewInput -> Int -> AwardPenaltyKindEnum -> Day -> Maybe (Maybe Day)
activeTimeAllowanceEffectiveFrom input awardFixedId penaltyKind segmentDate =
    input.previewTimePenaltyAllowances
        |> filter (\allowance -> allowance.awardFixedId == awardFixedId && allowance.penaltyKind == penaltyKind && activeOn segmentDate allowance.operativeFrom allowance.operativeTo)
        |> List.sortOn (.operativeFrom)
        |> listToMaybe
        |> fmap (.operativeFrom)

delayedMealBreakSourcePenaltyKind :: AwardPenaltyKindEnum -> Maybe (Maybe AwardPenaltyKindEnum)
delayedMealBreakSourcePenaltyKind DelayedMealBreakWeekday       = Just Nothing
delayedMealBreakSourcePenaltyKind DelayedMealBreakSaturday      = Just (Just SaturdayPenalty)
delayedMealBreakSourcePenaltyKind DelayedMealBreakSunday        = Just (Just SundayPenalty)
delayedMealBreakSourcePenaltyKind DelayedMealBreakPublicHoliday = Just (Just PublicHolidayPenalty)
delayedMealBreakSourcePenaltyKind _                             = Nothing

parsePenaltyKind :: Text -> Maybe AwardPenaltyKindEnum
parsePenaltyKind "evening_after_7pm"                 = Just EveningAfter7Pm
parsePenaltyKind "late_night_after_midnight"         = Just LateNightAfterMidnight
parsePenaltyKind "saturday_penalty"                  = Just SaturdayPenalty
parsePenaltyKind "sunday_penalty"                    = Just SundayPenalty
parsePenaltyKind "public_holiday_penalty"            = Just PublicHolidayPenalty
parsePenaltyKind "delayed_meal_break_weekday"        = Just DelayedMealBreakWeekday
parsePenaltyKind "delayed_meal_break_saturday"       = Just DelayedMealBreakSaturday
parsePenaltyKind "delayed_meal_break_sunday"         = Just DelayedMealBreakSunday
parsePenaltyKind "delayed_meal_break_public_holiday" = Just DelayedMealBreakPublicHoliday
parsePenaltyKind _                                   = Nothing

activeOn :: Day -> Maybe Day -> Maybe Day -> Bool
activeOn day effectiveFrom effectiveTo =
    maybe True (<= day) effectiveFrom && maybe True (>= day) effectiveTo

accumulateTimesheet :: XeroTimesheetPreviewInput -> Map.Map Text TimesheetAggregation -> SegmentContribution -> Map.Map Text TimesheetAggregation
accumulateTimesheet input acc contribution =
    Map.insertWith mergeTimesheet contribution.contributionXeroEmployeeId (newTimesheetAggregation input contribution) acc

newTimesheetAggregation :: XeroTimesheetPreviewInput -> SegmentContribution -> TimesheetAggregation
newTimesheetAggregation input contribution =
    TimesheetAggregation
        { timesheetAggregationEmployeeId = contribution.contributionXeroEmployeeId
        , timesheetAggregationStaffIds = [contribution.contributionStaffId]
        , timesheetAggregationEntryIds = [contribution.contributionEntryId]
        , timesheetAggregationStaffVersionIds = [contribution.contributionStaffVersionId]
        , timesheetAggregationShiftVersionIds = [contribution.contributionShiftVersionId]
        , timesheetAggregationLines =
            Map.singleton
                contribution.contributionEarningsRateId
                (newLineAggregation input contribution)
        }

newLineAggregation :: XeroTimesheetPreviewInput -> SegmentContribution -> LineAggregation
newLineAggregation _ contribution =
    LineAggregation
        { lineAggregationLocalBucketKey = contribution.contributionLocalBucketKey
        , lineAggregationEarningsRateId = contribution.contributionEarningsRateId
        , lineAggregationUnitsByDay = Map.singleton contribution.contributionWorkedOn contribution.contributionUnits
        , lineAggregationEntryIds = [contribution.contributionEntryId]
        , lineAggregationStaffVersionIds = [contribution.contributionStaffVersionId]
        , lineAggregationShiftVersionIds = [contribution.contributionShiftVersionId]
        }

mergeTimesheet :: TimesheetAggregation -> TimesheetAggregation -> TimesheetAggregation
mergeTimesheet new old =
    old
        { timesheetAggregationStaffIds = sortNub (old.timesheetAggregationStaffIds <> new.timesheetAggregationStaffIds)
        , timesheetAggregationEntryIds = sortNub (old.timesheetAggregationEntryIds <> new.timesheetAggregationEntryIds)
        , timesheetAggregationStaffVersionIds = sortNub (old.timesheetAggregationStaffVersionIds <> new.timesheetAggregationStaffVersionIds)
        , timesheetAggregationShiftVersionIds = sortNub (old.timesheetAggregationShiftVersionIds <> new.timesheetAggregationShiftVersionIds)
        , timesheetAggregationLines = Map.unionWith mergeLine old.timesheetAggregationLines new.timesheetAggregationLines
        }

mergeLine :: LineAggregation -> LineAggregation -> LineAggregation
mergeLine old new =
    old
        { lineAggregationUnitsByDay = Map.unionWith (+) old.lineAggregationUnitsByDay new.lineAggregationUnitsByDay
        , lineAggregationEntryIds = sortNub (old.lineAggregationEntryIds <> new.lineAggregationEntryIds)
        , lineAggregationStaffVersionIds = sortNub (old.lineAggregationStaffVersionIds <> new.lineAggregationStaffVersionIds)
        , lineAggregationShiftVersionIds = sortNub (old.lineAggregationShiftVersionIds <> new.lineAggregationShiftVersionIds)
        }

toPreview :: XeroTimesheetPreviewInput -> TimesheetAggregation -> XeroTimesheetPreview
toPreview input aggregation =
    let lines =
            aggregation.timesheetAggregationLines
                |> Map.elems
                |> List.sortOn (.lineAggregationEarningsRateId)
                |> map (toPreviewLine input)
        requestObject = timesheetRequestObject input aggregation.timesheetAggregationEmployeeId lines
     in XeroTimesheetPreview
            { previewStaffIds = aggregation.timesheetAggregationStaffIds
            , previewXeroEmployeeId = aggregation.timesheetAggregationEmployeeId
            , previewPayPeriodStart = input.previewPeriodStart
            , previewPayPeriodEnd = input.previewPeriodEnd
            , previewSourceEntryIds = aggregation.timesheetAggregationEntryIds
            , previewStaffPayVersionIds = aggregation.timesheetAggregationStaffVersionIds
            , previewShiftPayVersionIds = aggregation.timesheetAggregationShiftVersionIds
            , previewLines = lines
            , previewRequestObjectJson = requestObject
            }

toPreviewLine :: XeroTimesheetPreviewInput -> LineAggregation -> XeroTimesheetPreviewLine
toPreviewLine input aggregation =
    XeroTimesheetPreviewLine
        { previewLineLocalBucketKey = aggregation.lineAggregationLocalBucketKey
        , previewLineXeroEarningsRateId = aggregation.lineAggregationEarningsRateId
        , previewLineNumberOfUnits = map (\day -> Map.findWithDefault 0 day aggregation.lineAggregationUnitsByDay) (periodDays input.previewPeriodStart input.previewPeriodEnd)
        , previewLineSourceEntryIds = aggregation.lineAggregationEntryIds
        , previewLineStaffPayVersionIds = aggregation.lineAggregationStaffVersionIds
        , previewLineShiftPayVersionIds = aggregation.lineAggregationShiftVersionIds
        }

timesheetRequestObject :: XeroTimesheetPreviewInput -> Text -> [XeroTimesheetPreviewLine] -> Aeson.Value
timesheetRequestObject input employeeId lines =
    Aeson.object
        [ "EmployeeID" Aeson..= employeeId
        , "StartDate" Aeson..= input.previewPeriodStart
        , "EndDate" Aeson..= input.previewPeriodEnd
        , "Status" Aeson..= ("DRAFT" :: Text)
        , "TimesheetLines" Aeson..= map lineRequestObject lines
        ]

lineRequestObject :: XeroTimesheetPreviewLine -> Aeson.Value
lineRequestObject line =
    Aeson.object
        [ "EarningsRateID" Aeson..= line.previewLineXeroEarningsRateId
        , "NumberOfUnits" Aeson..= line.previewLineNumberOfUnits
        ]

xeroTimesheetPreviewRunJson :: XeroTimesheetPreviewRun -> Aeson.Value
xeroTimesheetPreviewRunJson previewRun =
    Aeson.object
        [ "periodStart" Aeson..= previewRun.previewRunPeriodStart
        , "periodEnd" Aeson..= previewRun.previewRunPeriodEnd
        , "requestPayload" Aeson..= previewRun.previewRunRequestArrayJson
        , "timesheets" Aeson..= map timesheetPreviewJson previewRun.previewRunTimesheets
        ]

timesheetPreviewJson :: XeroTimesheetPreview -> Aeson.Value
timesheetPreviewJson preview =
    Aeson.object
        [ "staffIds" Aeson..= preview.previewStaffIds
        , "xeroEmployeeId" Aeson..= preview.previewXeroEmployeeId
        , "periodStart" Aeson..= preview.previewPayPeriodStart
        , "periodEnd" Aeson..= preview.previewPayPeriodEnd
        , "sourceTimesheetEntryIds" Aeson..= preview.previewSourceEntryIds
        , "staffPayVersionIds" Aeson..= preview.previewStaffPayVersionIds
        , "shiftTypePayVersionIds" Aeson..= preview.previewShiftPayVersionIds
        , "requestObject" Aeson..= preview.previewRequestObjectJson
        , "lines" Aeson..= map linePreviewJson preview.previewLines
        ]

linePreviewJson :: XeroTimesheetPreviewLine -> Aeson.Value
linePreviewJson line =
    Aeson.object
        [ "localBucketKey" Aeson..= line.previewLineLocalBucketKey
        , "xeroEarningsRateId" Aeson..= line.previewLineXeroEarningsRateId
        , "numberOfUnits" Aeson..= line.previewLineNumberOfUnits
        , "sourceTimesheetEntryIds" Aeson..= line.previewLineSourceEntryIds
        , "staffPayVersionIds" Aeson..= line.previewLineStaffPayVersionIds
        , "shiftTypePayVersionIds" Aeson..= line.previewLineShiftPayVersionIds
        ]

xeroReadinessSnapshotJson :: XeroTimesheetReadiness -> Aeson.Value
xeroReadinessSnapshotJson readiness =
    Aeson.object
        [ "ready" Aeson..= readiness.xeroTimesheetReady
        , "periodStart" Aeson..= readiness.xeroReadinessPeriodStart
        , "periodEnd" Aeson..= readiness.xeroReadinessPeriodEnd
        , "staffCount" Aeson..= readiness.xeroReadinessStaffCount
        , "entryCount" Aeson..= readiness.xeroReadinessEntryCount
        , "payBucketCount" Aeson..= readiness.xeroReadinessPayBucketCount
        , "blockers" Aeson..= map blockerJson readiness.xeroReadinessBlockers
        , "warnings" Aeson..= map blockerJson readiness.xeroReadinessWarnings
        ]

blockerJson :: XeroReadinessBlocker -> Aeson.Value
blockerJson blocker =
    Aeson.object
        [ "code" Aeson..= blocker.xeroBlockerCode
        , "severity" Aeson..= xeroReadinessSeverityText blocker.xeroBlockerSeverity
        , "message" Aeson..= blocker.xeroBlockerMessage
        , "affectedStaffId" Aeson..= blocker.xeroBlockerAffectedStaffId
        , "timesheetEntryId" Aeson..= blocker.xeroBlockerTimesheetEntryId
        , "localBucketKey" Aeson..= blocker.xeroBlockerLocalBucketKey
        , "xeroObjectId" Aeson..= blocker.xeroBlockerXeroObjectId
        , "actionHint" Aeson..= blocker.xeroBlockerActionHint
        ]

periodDays :: Day -> Day -> [Day]
periodDays start end =
    [addDays offset start | offset <- [0 .. diffDays end start]]

minutesToUnits :: Int -> Scientific.Scientific
minutesToUnits minutes =
    fromIntegral minutes / 60

maybeToEither :: Text -> Maybe value -> Either Text value
maybeToEither message =
    maybe (Left message) Right

sortNub :: Ord value => [value] -> [value]
sortNub =
    List.sort . List.nub
