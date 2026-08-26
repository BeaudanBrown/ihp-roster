module Application.Xero.Timesheets.Preview
    ( XeroTimesheetPreview (..)
    , XeroTimesheetPreviewInput (..)
    , XeroTimesheetPreviewLine (..)
    , XeroTimesheetPreviewRun (..)
    , buildXeroTimesheetPreviewRun
    , createPersistedXeroTimesheetPreview
    , fetchPreviewInput
    , fetchPreparedPreviewInput
    , periodDays
    , xeroReadinessSnapshotJson
    , xeroTimesheetPreviewRunJson
    )
where

import Application.Helper.TimesheetPayLedger (loadApprovedTimesheetPayCalculations)
import Application.Helper.WeekBoundaries (WeekdayIndex)
import Application.Helper.Xero (XeroTimesheetRef (..))
import Application.Helper.XeroTimesheetReadiness
import Application.WageEngine
import Application.WagePublication (datedEarningsComponentsWithOrdinal)
import Application.WageSourceEnforcement (enforceFinalWageEntries,
                                          renderWageEntryFailures)
import Application.Xero.Timesheets.Buckets (XeroComponentBucketContext (..),
                                            componentBucketKey)
import Application.Xero.Timesheets.LateBindings
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Types as AesonTypes
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
    { previewVenueId                  :: !(Id Venue)
    , previewPeriodStart              :: !Day
    , previewPeriodEnd                :: !Day
    , previewTimesheetEntries         :: ![TimesheetEntry]
    , previewStaff                    :: ![Staff]
    , previewStaffMappings            :: ![XeroStaffMapping]
    , previewStaffPayVersions         :: ![StaffPayVersion]
    , previewShiftTypePayVersions     :: ![ShiftTypePayVersion]
    , previewImportedPayItems         :: ![XeroImportedPayItem]
    , previewEarningsMappings         :: ![XeroEarningsRateMapping]
    , previewPayItemRequirements      :: ![XeroPayItemRequirementRecord]
    , previewCalculationsByEntryId    :: !(Map.Map UUID WageCalculation)
    , previewPayCalculationsByEntryId :: !(Map.Map UUID TimesheetPayCalculation)
    , previewComponentRowsByCalculationId :: !(Map.Map UUID [TimesheetPayEarningsComponent])
    , previewLateBindingsByComponentId :: !(Map.Map UUID TimesheetPayComponentXeroBinding)
    , previewAwardLevels              :: ![AwardLevel]
    , previewRemoteTimesheets         :: ![XeroTimesheetRef]
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
    { previewStaffIds                :: ![UUID]
    , previewXeroEmployeeId          :: !Text
    , previewPayPeriodStart          :: !Day
    , previewPayPeriodEnd            :: !Day
    , previewSourceEntryIds          :: ![UUID]
    , previewStaffPayVersionIds      :: ![UUID]
    , previewShiftPayVersionIds      :: ![UUID]
    , previewLines                   :: ![XeroTimesheetPreviewLine]
    , previewExistingXeroTimesheetId :: !(Maybe Text)
    , previewRequestObjectJson       :: !Aeson.Value
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
    { contributionStaffId         :: !UUID
    , contributionXeroEmployeeId  :: !Text
    , contributionEntryId         :: !UUID
    , contributionStaffVersionId  :: !UUID
    , contributionShiftVersionId  :: !UUID
    , contributionOperationalDate :: !Day
    , contributionLocalBucketKey  :: !Text
    , contributionEarningsRateId  :: !Text
    , contributionUnit            :: !EarningsUnit
    , contributionUnits           :: !Rational
    }
    deriving (Eq, Show)

data LineAggregation = LineAggregation
    { lineAggregationLocalBucketKey  :: !Text
    , lineAggregationEarningsRateId  :: !Text
    , lineAggregationUnit            :: !EarningsUnit
    , lineAggregationUnitsByDay      :: !(Map.Map Day Rational)
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
createPersistedXeroTimesheetPreview submittedByUserId =
    createPersistedXeroTimesheetPreviewWithPreparation submittedByUserId Nothing

createPersistedXeroTimesheetPreviewWithPreparation ::
    (?modelContext :: ModelContext) =>
    Id User ->
    Maybe (Id XeroTimesheetPreparationRun) ->
    XeroTimesheetReadinessRequest ->
    XeroTimesheetReadiness ->
    Aeson.Value ->
    IO (Either Text XeroSubmissionRun)
createPersistedXeroTimesheetPreviewWithPreparation submittedByUserId maybePreparationRunId request readiness duplicateCheckJson
    | not readiness.xeroTimesheetReady =
        pure (Left "Xero timesheet readiness must pass before a preview can be persisted.")
    | otherwise = do
        maybeConnection <- fetchActivePreviewXeroConnection request.readinessVenueId
        case maybeConnection of
            Nothing -> pure (Left "Active Xero connection was not found.")
            Just connection -> do
                fetchPreparedPreviewInput request connection >>= \case
                    Left message -> pure (Left message)
                    Right previewInput -> do
                        wageBoundary <- enforceFinalWageEntries previewInput.previewTimesheetEntries
                        case wageBoundary of
                            Left failures -> pure (Left (renderWageEntryFailures "Xero preview blocked: " failures))
                            Right _ -> case buildXeroTimesheetPreviewRun previewInput of
                                Left err -> pure (Left err)
                                Right previewRun -> do
                                    run <-
                                        newRecord @XeroSubmissionRun
                                            |> set #venueId (unpackId request.readinessVenueId)
                                            |> set #xeroConnectionId (unpackId connection.id)
                                            |> set #submittedByUserId (unpackId submittedByUserId)
                                            |> set #payPeriodStart request.readinessPeriodStart
                                            |> set #payPeriodEnd request.readinessPeriodEnd
                                            |> set #xeroTimesheetPreparationRunId maybePreparationRunId
                                            |> set #selectedPayrollCalendarId request.readinessPayrollCalendarId
                                            |> set #selectedPayrollCalendarName request.readinessPayrollCalendarName
                                            |> set #selectedPeriodKey request.readinessSelectedPeriodKey
                                            |> set #paymentDate request.readinessPaymentDate
                                            |> set #xeroPayRunId request.readinessXeroPayRunId
                                            |> set #xeroPayRunStatus request.readinessXeroPayRunStatus
                                            |> set #sourceKind ApprovedTimesheets
                                            |> set #status XeroSubmissionRunStatusEnumPreviewed
                                            |> set #previewPayloadJson (xeroTimesheetPreviewRunJson previewRun)
                                            |> set #readinessSnapshotJson (xeroReadinessSnapshotJson readiness)
                                            |> set #xeroDuplicateCheckJson duplicateCheckJson
                                            |> createRecord
                                    pure (Right run)

fetchPreparedPreviewInput ::
    (?modelContext :: ModelContext) =>
    XeroTimesheetReadinessRequest ->
    XeroConnection ->
    IO (Either Text XeroTimesheetPreviewInput)
fetchPreparedPreviewInput request connection = do
    input <- fetchPreviewInput request connection
    case lateBindingProposals input of
        Left message -> pure (Left message)
        Right [] -> pure (Right input)
        Right proposals ->
            persistLateXeroBindings connection.id proposals >>= \case
                Left message -> pure (Left message)
                Right _ -> Right <$> fetchPreviewInput request connection

fetchPreviewInput ::
    (?modelContext :: ModelContext) =>
    XeroTimesheetReadinessRequest ->
    XeroConnection ->
    IO XeroTimesheetPreviewInput
fetchPreviewInput request connection = do
    approvedEntries <-
        query @TimesheetEntry
            |> filterWhere (#venueId, unpackId request.readinessVenueId)
            |> filterWhereGreaterThanOrEqualTo (#operationalDate, request.readinessPeriodStart)
            |> filterWhereLessThan (#operationalDate, addDays 1 request.readinessPeriodEnd)
            |> filterWhere (#isApproved, True)
            |> filterWhere (#deletedAt, Nothing)
            |> orderBy #operationalDate
            |> orderBy #startsAt
            |> fetch
    let includedEntries =
            approvedEntries
                |> filter (\entry -> entry.staffId `notElem` request.readinessSkippedStaffIds)
    staffMappings <-
        query @XeroStaffMapping
            |> filterWhere (#xeroConnectionId, unpackId connection.id)
            |> filterWhereIn (#staffId, map (.staffId) includedEntries)
            |> filterWhere (#mappingStatus, XeroStaffMappingStatusEnumVerified)
            |> fetch
    xeroEmployees <-
        query @XeroEmployee
            |> filterWhere (#xeroConnectionId, unpackId connection.id)
            |> filterWhereIn (#xeroEmployeeId, List.nub (mapMaybe (.xeroEmployeeId) staffMappings))
            |> filterWhere (#providerAvailable, True)
            |> fetch
    let calendarEligibleEntries =
            includedEntries
                |> filter \entry ->
                    any (mappingIncludesEntry entry) staffMappings
                        && entryMatchesSelectedPayrollCalendar request staffMappings xeroEmployees entry
    previousConnectionEntryIds <- fetchPreviousConnectionImportedEntryIds connection calendarEligibleEntries
    let entries =
            calendarEligibleEntries
                |> filter (not . (`elem` previousConnectionEntryIds) . unpackId . (.id))
    staffMembers <-
        query @Staff
            |> filterWhere (#venueId, unpackId request.readinessVenueId)
            |> filterWhereIn (#id, map (Id . (.staffId)) entries)
            |> fetch
    staffPayVersions <-
        query @StaffPayVersion
            |> filterWhereIn (#id, mapMaybe (fmap Id . (.staffPayVersionId)) entries)
            |> fetch
    shiftTypePayVersions <-
        query @ShiftTypePayVersion
            |> filterWhereIn (#id, mapMaybe (fmap Id . (.shiftTypePayVersionId)) entries)
            |> fetch
    importedPayItems <-
        query @XeroImportedPayItem
            |> filterWhere (#xeroConnectionId, unpackId connection.id)
            |> filterWhereIn (#id, mapMaybe (.importedXeroPayItemId) staffPayVersions <> mapMaybe (.importedXeroPayItemId) shiftTypePayVersions)
            |> fetch
    earningsMappings <-
        query @XeroEarningsRateMapping
            |> filterWhere (#xeroConnectionId, unpackId connection.id)
            |> filterWhere (#mappingStatus, XeroEarningsRateMappingStatusEnumVerified)
            |> fetch
    payItemRequirements <-
        query @XeroPayItemRequirementRecord
            |> filterWhere (#xeroConnectionId, unpackId connection.id)
            |> filterWhereIn (#requirementStatus, [Matched, XeroPayItemRequirementStatusEnumCreated])
            |> fetch
    payCalculations <- query @TimesheetPayCalculation
        |> filterWhereIn (#id, mapMaybe (.activePayCalculationId) entries)
        |> fetch
    componentRows <- query @TimesheetPayEarningsComponent
        |> filterWhereIn (#timesheetPayCalculationId, map (unpackId . (.id)) payCalculations)
        |> orderBy #ordinal
        |> fetch
    lateBindings <- query @TimesheetPayComponentXeroBinding
        |> filterWhere (#xeroConnectionId, unpackId connection.id)
        |> filterWhereIn (#timesheetPayEarningsComponentId, map (unpackId . (.id)) componentRows)
        |> fetch
    loadedCalculations <- loadApprovedTimesheetPayCalculations entries
    let calculations = Map.mapMaybe (\case Left _ -> Nothing; Right calculation -> calculation) loadedCalculations
    awardLevels <- query @AwardLevel |> fetch
    pure XeroTimesheetPreviewInput
        { previewVenueId = request.readinessVenueId
        , previewPeriodStart = request.readinessPeriodStart
        , previewPeriodEnd = request.readinessPeriodEnd
        , previewTimesheetEntries = entries
        , previewStaff = staffMembers
        , previewStaffMappings = staffMappings
        , previewStaffPayVersions = staffPayVersions
        , previewShiftTypePayVersions = shiftTypePayVersions
        , previewImportedPayItems = importedPayItems
        , previewEarningsMappings = earningsMappings
        , previewPayItemRequirements = payItemRequirements
        , previewCalculationsByEntryId = calculations
        , previewPayCalculationsByEntryId = Map.fromList [(calculation.timesheetEntryId, calculation) | calculation <- payCalculations]
        , previewComponentRowsByCalculationId = Map.fromListWith (<>) [(row.timesheetPayCalculationId, [row]) | row <- componentRows]
        , previewLateBindingsByComponentId = Map.fromList [(binding.timesheetPayEarningsComponentId, binding) | binding <- lateBindings]
        , previewAwardLevels = awardLevels
        , previewRemoteTimesheets = request.readinessRemoteTimesheets
        }

mappingIncludesEntry :: TimesheetEntry -> XeroStaffMapping -> Bool
mappingIncludesEntry entry mapping =
    mapping.staffId == entry.staffId
        && isJust mapping.xeroEmployeeId

entryMatchesSelectedPayrollCalendar :: XeroTimesheetReadinessRequest -> [XeroStaffMapping] -> [XeroEmployee] -> TimesheetEntry -> Bool
entryMatchesSelectedPayrollCalendar request staffMappings xeroEmployees entry =
    case request.readinessPayrollCalendarId of
        Nothing -> True
        Just selectedCalendarId ->
            let employeeCalendarId = do
                    employeeId <- List.find (mappingIncludesEntry entry) staffMappings >>= (.xeroEmployeeId)
                    employee <- List.find (\candidate -> candidate.xeroEmployeeId == employeeId) xeroEmployees
                    xeroEmployeePayrollCalendarId employee
             in employeeCalendarId == Just selectedCalendarId

xeroEmployeePayrollCalendarId :: XeroEmployee -> Maybe Text
xeroEmployeePayrollCalendarId employee =
    join $ AesonTypes.parseMaybe parser employee.rawPayload
    where
        parser = AesonTypes.withObject "Xero employee" \object ->
            (object AesonTypes..:? "PayrollCalendarID") <|> (object AesonTypes..:? "payrollCalendarID") <|> (object AesonTypes..:? "payrollCalendarId")

fetchActivePreviewXeroConnection :: (?modelContext :: ModelContext) => Id Venue -> IO (Maybe XeroConnection)
fetchActivePreviewXeroConnection venueId =
    query @XeroConnection
        |> filterWhere (#venueId, unpackId venueId)
        |> filterWhere (#connectionStatus, "active" :: Text)
        |> orderByDesc #connectedAt
        |> fetchOneOrNothing

lateBindingProposals :: XeroTimesheetPreviewInput -> Either Text [LateXeroBindingProposal]
lateBindingProposals input = fmap concat (mapM entryProposals input.previewTimesheetEntries)
  where
    entryProposals entry = do
        staff <- maybeToEither ("Missing staff for timesheet entry " <> tshow (unpackId entry.id)) (find (\candidate -> unpackId candidate.id == entry.staffId) input.previewStaff)
        staffVersionId <- maybeToEither ("Missing staff pay version for timesheet entry " <> tshow (unpackId entry.id)) entry.staffPayVersionId
        shiftVersionId <- maybeToEither ("Missing shift type pay version for timesheet entry " <> tshow (unpackId entry.id)) entry.shiftTypePayVersionId
        calculation <- maybeToEither ("Missing sealed pay calculation for timesheet entry " <> tshow (unpackId entry.id)) (Map.lookup (unpackId entry.id) input.previewCalculationsByEntryId)
        payCalculation <- maybeToEither ("Missing sealed Operational-window facts for timesheet entry " <> tshow (unpackId entry.id)) (Map.lookup (unpackId entry.id) input.previewPayCalculationsByEntryId)
        rows <- maybeToEither ("Missing sealed earnings rows for timesheet entry " <> tshow (unpackId entry.id)) (Map.lookup (unpackId payCalculation.id) input.previewComponentRowsByCalculationId)
        fmap concat $ forM (zip [0 ..] calculation.earningsComponents) \(ordinal, component) -> do
            row <- maybeToEither ("Missing sealed earnings component ordinal " <> tshow ordinal <> " for entry " <> tshow (unpackId entry.id)) (find ((== ordinal) . (.ordinal)) rows)
            if component.quantity <= 0 || Map.member (unpackId row.id) input.previewLateBindingsByComponentId
                then pure []
                else case (component.publishedXeroLocalBucketKey, component.publishedXeroEarningsRateId) of
                    (Just _, Just _) -> pure []
                    (Nothing, Nothing)
                        | component.publishedXeroMappingLegacyFallback -> pure []
                        | otherwise -> do
                            let componentDate = fromMaybe payCalculation.operationalDate component.publishedComponentDate
                            localBucketKey <- componentBucketKey payCalculation.rosterWeekStartsOn (previewBucketContext input) entry staff component componentDate
                            (earningsRateId, resolutionSource) <- case component.sourceCondition of
                                ImportedFlatRateCondition itemId -> do
                                    item <- maybeToEither ("Missing approval-pinned imported Xero earnings rate for component " <> itemId) (approvedImportedPayItemForVersions input staffVersionId shiftVersionId)
                                    if inputValue item.id == itemId
                                        then pure (item.xeroEarningsRateId, "imported_pay_item")
                                        else Left ("Approved imported Xero pay item does not match component " <> itemId)
                                _ -> earningsRoutingForBucket input localBucketKey
                            pure
                                [ LateXeroBindingProposal
                                    { proposalComponentId = row.id
                                    , proposalLocalBucketKey = localBucketKey
                                    , proposalXeroEarningsRateId = earningsRateId
                                    , proposalResolutionSource = resolutionSource
                                    }
                                ]
                    _ -> Left ("Approved component has an incomplete sealed Xero earnings mapping for entry " <> tshow (unpackId entry.id))

entryContributions :: XeroTimesheetPreviewInput -> TimesheetEntry -> Either Text [SegmentContribution]
entryContributions input entry = do
    staff <- maybeToEither ("Missing staff for timesheet entry " <> tshow (unpackId entry.id)) (find (\candidate -> unpackId candidate.id == entry.staffId) input.previewStaff)
    xeroEmployeeId <- staffXeroEmployeeId input entry
    staffVersionId <- maybeToEither ("Missing staff pay version for timesheet entry " <> tshow (unpackId entry.id)) entry.staffPayVersionId
    shiftVersionId <- maybeToEither ("Missing shift type pay version for timesheet entry " <> tshow (unpackId entry.id)) entry.shiftTypePayVersionId
    calculation <- maybeToEither ("Missing sealed pay calculation for timesheet entry " <> tshow (unpackId entry.id)) (Map.lookup (unpackId entry.id) input.previewCalculationsByEntryId)
    payCalculation <- maybeToEither ("Missing sealed Operational-window facts for timesheet entry " <> tshow (unpackId entry.id)) (Map.lookup (unpackId entry.id) input.previewPayCalculationsByEntryId)
    componentRows <- maybeToEither ("Missing sealed earnings rows for timesheet entry " <> tshow (unpackId entry.id)) (Map.lookup (unpackId payCalculation.id) input.previewComponentRowsByCalculationId)
    unless
        (calculation.publishedOperationalDate == Just payCalculation.operationalDate && payCalculation.operationalDate == entry.operationalDate)
        (Left ("Sealed Operational-day facts do not match timesheet entry " <> tshow (unpackId entry.id)))
    entry.approvedAt |> maybeToEither ("Missing approval timestamp for timesheet entry " <> tshow (unpackId entry.id)) |> const (pure ())
    datedEarningsComponentsWithOrdinal calculation
        |> filter (\(_, _, component) -> component.quantity > 0)
        |> mapM (\dated@(ordinal, _, _) -> do
            componentRow <- maybeToEither ("Missing sealed earnings component ordinal " <> tshow ordinal <> " for entry " <> tshow (unpackId entry.id)) (find ((== ordinal) . (.ordinal)) componentRows)
            componentContribution input payCalculation entry staff xeroEmployeeId staffVersionId shiftVersionId componentRow dated)

componentContribution ::
    XeroTimesheetPreviewInput ->
    TimesheetPayCalculation ->
    TimesheetEntry ->
    Staff ->
    Text ->
    UUID ->
    UUID ->
    TimesheetPayEarningsComponent ->
    (Int, Day, EarningsComponent) ->
    Either Text SegmentContribution
componentContribution input payCalculation entry staff xeroEmployeeId staffVersionId shiftVersionId componentRow (_, componentDate, component) = do
    (localBucketKey, earningsRateId) <- case (component.publishedXeroLocalBucketKey, component.publishedXeroEarningsRateId) of
        (Just sealedBucketKey, Just sealedEarningsRateId) -> pure (sealedBucketKey, sealedEarningsRateId)
        (Nothing, Nothing)
            | component.publishedXeroMappingLegacyFallback -> do
                historicalBucketKey <- componentBucketKey payCalculation.rosterWeekStartsOn (previewBucketContext input) entry staff component componentDate
                historicalEarningsRateId <- case component.sourceCondition of
                    ImportedFlatRateCondition itemId -> do
                        item <- maybeToEither ("Missing approval-pinned imported Xero earnings rate for component " <> itemId) (approvedImportedPayItemForVersions input staffVersionId shiftVersionId)
                        if inputValue item.id == itemId
                            then pure item.xeroEarningsRateId
                            else Left ("Approved imported Xero pay item does not match component " <> itemId)
                    _ -> earningsRateIdForBucket input historicalBucketKey
                pure (historicalBucketKey, historicalEarningsRateId)
            | otherwise -> do
                binding <- maybeToEither ("Approved component has no Xero earnings routing for entry " <> tshow (unpackId entry.id)) (Map.lookup (unpackId componentRow.id) input.previewLateBindingsByComponentId)
                pure (binding.localBucketKey, binding.xeroEarningsRateId)
        _ -> Left ("Approved component has an incomplete sealed Xero earnings mapping for entry " <> tshow (unpackId entry.id))
    pure SegmentContribution
        { contributionStaffId = unpackId staff.id
        , contributionXeroEmployeeId = xeroEmployeeId
        , contributionEntryId = unpackId entry.id
        , contributionStaffVersionId = staffVersionId
        , contributionShiftVersionId = shiftVersionId
        , contributionOperationalDate = payCalculation.operationalDate
        , contributionLocalBucketKey = localBucketKey
        , contributionEarningsRateId = earningsRateId
        , contributionUnit = component.unitType
        , contributionUnits = component.quantity
        }

approvedImportedPayItemForVersions :: XeroTimesheetPreviewInput -> UUID -> UUID -> Maybe XeroImportedPayItem
approvedImportedPayItemForVersions input staffVersionId shiftVersionId = do
    importedPayItemId <- shiftImportedPayItemId <|> staffImportedPayItemId
    find (\item -> item.id == importedPayItemId) input.previewImportedPayItems
  where
    shiftImportedPayItemId = do
        version <- find (\candidate -> unpackId candidate.id == shiftVersionId) input.previewShiftTypePayVersions
        version.importedXeroPayItemId
    staffImportedPayItemId = do
        version <- find (\candidate -> unpackId candidate.id == staffVersionId) input.previewStaffPayVersions
        version.importedXeroPayItemId

previewBucketContext :: XeroTimesheetPreviewInput -> XeroComponentBucketContext
previewBucketContext input =
    XeroComponentBucketContext
        { bucketStaffPayVersions = Map.fromList [(unpackId version.id, version) | version <- input.previewStaffPayVersions]
        , bucketShiftTypePayVersions = Map.fromList [(unpackId version.id, version) | version <- input.previewShiftTypePayVersions]
        , bucketAwardLevels = input.previewAwardLevels
        }

staffXeroEmployeeId :: XeroTimesheetPreviewInput -> TimesheetEntry -> Either Text Text
staffXeroEmployeeId input entry =
    maybeToEither ("Missing verified Xero employee mapping for staff " <> tshow entry.staffId) do
        mapping <- find (\candidate -> candidate.staffId == entry.staffId) input.previewStaffMappings
        mapping.xeroEmployeeId

earningsRateIdForBucket :: XeroTimesheetPreviewInput -> Text -> Either Text Text
earningsRateIdForBucket input localBucketKey = fst <$> earningsRoutingForBucket input localBucketKey

earningsRoutingForBucket :: XeroTimesheetPreviewInput -> Text -> Either Text (Text, Text)
earningsRoutingForBucket input localBucketKey =
    maybeToEither ("Missing verified Xero earnings-rate mapping for bucket " <> localBucketKey) do
        mappedEarningsRouting <|> managedRequirementRouting
    where
        mappedEarningsRouting = do
            mapping <- find (\candidate -> candidate.localBucketKey == localBucketKey) input.previewEarningsMappings
            earningsRateId <- mapping.xeroEarningsRateId
            pure (earningsRateId, "verified_mapping")
        managedRequirementRouting = do
            requirement <- find (\candidate -> candidate.requirementKey == localBucketKey) input.previewPayItemRequirements
            earningsRateId <- requirement.xeroEarningsRateId
            pure (earningsRateId, "managed_pay_item")

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
                contribution.contributionLocalBucketKey
                (newLineAggregation input contribution)
        }

newLineAggregation :: XeroTimesheetPreviewInput -> SegmentContribution -> LineAggregation
newLineAggregation _ contribution =
    LineAggregation
        { lineAggregationLocalBucketKey = contribution.contributionLocalBucketKey
        , lineAggregationEarningsRateId = contribution.contributionEarningsRateId
        , lineAggregationUnit = contribution.contributionUnit
        , lineAggregationUnitsByDay = Map.singleton contribution.contributionOperationalDate contribution.contributionUnits
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
        maybeExistingTimesheetId = matchingDraftTimesheetId input aggregation.timesheetAggregationEmployeeId
        requestObject = timesheetRequestObject input maybeExistingTimesheetId aggregation.timesheetAggregationEmployeeId lines
     in XeroTimesheetPreview
            { previewStaffIds = aggregation.timesheetAggregationStaffIds
            , previewXeroEmployeeId = aggregation.timesheetAggregationEmployeeId
            , previewPayPeriodStart = input.previewPeriodStart
            , previewPayPeriodEnd = input.previewPeriodEnd
            , previewSourceEntryIds = aggregation.timesheetAggregationEntryIds
            , previewStaffPayVersionIds = aggregation.timesheetAggregationStaffVersionIds
            , previewShiftPayVersionIds = aggregation.timesheetAggregationShiftVersionIds
            , previewLines = lines
            , previewExistingXeroTimesheetId = maybeExistingTimesheetId
            , previewRequestObjectJson = requestObject
            }

toPreviewLine :: XeroTimesheetPreviewInput -> LineAggregation -> XeroTimesheetPreviewLine
toPreviewLine input aggregation =
    let unitsForDay day =
            let exactUnits = Map.findWithDefault 0 day aggregation.lineAggregationUnitsByDay
                outputUnits = case aggregation.lineAggregationUnit of
                    Hours          -> exactUnits
                    CommencedHours -> exactUnits
             in scientificFromRationalAt xeroUnitDecimalPlaces outputUnits
     in XeroTimesheetPreviewLine
            { previewLineLocalBucketKey = aggregation.lineAggregationLocalBucketKey
            , previewLineXeroEarningsRateId = aggregation.lineAggregationEarningsRateId
            , previewLineNumberOfUnits = map unitsForDay (periodDays input.previewPeriodStart input.previewPeriodEnd)
            , previewLineSourceEntryIds = aggregation.lineAggregationEntryIds
            , previewLineStaffPayVersionIds = aggregation.lineAggregationStaffVersionIds
            , previewLineShiftPayVersionIds = aggregation.lineAggregationShiftVersionIds
            }

matchingDraftTimesheetId :: XeroTimesheetPreviewInput -> Text -> Maybe Text
matchingDraftTimesheetId input employeeId = do
    remote <-
        input.previewRemoteTimesheets
            |> filter (\candidate -> candidate.xeroTimesheetEmployeeId == employeeId)
            |> filter (\candidate -> candidate.xeroTimesheetStartDate == input.previewPeriodStart)
            |> filter (\candidate -> candidate.xeroTimesheetEndDate == input.previewPeriodEnd)
            |> filter (\candidate -> maybe False ((== "draft") . Text.toCaseFold) candidate.xeroTimesheetStatus)
            |> listToMaybe
    remote.xeroTimesheetId

timesheetRequestObject :: XeroTimesheetPreviewInput -> Maybe Text -> Text -> [XeroTimesheetPreviewLine] -> Aeson.Value
timesheetRequestObject input maybeExistingTimesheetId employeeId lines =
    Aeson.object $
        maybe [] (\timesheetId -> ["TimesheetID" Aeson..= timesheetId]) maybeExistingTimesheetId
            <> [ "EmployeeID" Aeson..= employeeId
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
        , "existingXeroTimesheetId" Aeson..= preview.previewExistingXeroTimesheetId
        , "operation" Aeson..= timesheetPreviewOperation preview
        , "staffPayVersionIds" Aeson..= preview.previewStaffPayVersionIds
        , "shiftTypePayVersionIds" Aeson..= preview.previewShiftPayVersionIds
        , "requestObject" Aeson..= preview.previewRequestObjectJson
        , "lines" Aeson..= map linePreviewJson preview.previewLines
        ]

timesheetPreviewOperation :: XeroTimesheetPreview -> Text
timesheetPreviewOperation preview =
    if isJust preview.previewExistingXeroTimesheetId then "update" else "create"

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

xeroUnitDecimalPlaces :: Int
xeroUnitDecimalPlaces = 12

-- Xero accepts finite decimal units, so normalize once after exact
-- same-bucket aggregation rather than rounding each source segment.
scientificFromRationalAt :: Int -> Rational -> Scientific.Scientific
scientificFromRationalAt decimalPlaces value =
    Scientific.scientific (round (value * fromInteger scale)) (negate decimalPlaces)
    where
        scale :: Integer
        scale = 10 ^ decimalPlaces

maybeToEither :: Text -> Maybe value -> Either Text value
maybeToEither message =
    maybe (Left message) Right

sortNub :: Ord value => [value] -> [value]
sortNub =
    List.sort . List.nub
