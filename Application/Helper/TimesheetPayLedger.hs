module Application.Helper.TimesheetPayLedger
    ( ApprovedPayLedgerError (..)
    , backfillApprovedTimesheetPayCalculations
    , loadApprovedTimesheetPayCalculation
    , loadApprovedTimesheetPayCalculationResults
    , loadApprovedTimesheetPayCalculations
    , renderApprovedPayLedgerError
    , persistApprovedTimesheetPayCalculation
    , persistDevSeedApprovedTimesheetPayCalculation
    , roundWageLedgerRational
    ) where

import Application.Helper.WeekBoundaries (startOfWeekFor,
                                          venueEffectiveRateDate)
import Application.VenueTime.Model
import Application.WageEngine
import Application.WageEvaluation
import Application.WagePublication (datedEarningsComponents)
import Application.Xero.Timesheets.BucketKey
import Control.Exception (Exception)
import qualified Control.Exception as Exception
import Control.Monad (void)
import qualified Data.Bifunctor as Bifunctor
import Data.Either (lefts, rights)
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import qualified Data.Scientific as Scientific
import qualified Data.Text as Text
import Data.Time.Calendar (toGregorian)
import Data.Time.Clock (getCurrentTime)
import Data.Traversable (traverse)
import qualified Database.PostgreSQL.Simple as PG
import Generated.Types
import IHP.ControllerPrelude
import IHP.ModelSupport (ModelContext, sqlQuery, unpackId)
import IHP.Prelude

data ApprovedPayLedgerError
    = ApprovedPayLedgerResultNotLoaded
    | ApprovedPayLedgerActiveCalculationMissing
    | ApprovedPayLedgerCalculationBelongsToDifferentEntry
    | ApprovedPayLedgerCalculationNotSealed
    | ApprovedPayLedgerUnknownPaidTimeKind !Text
    | ApprovedPayLedgerUnknownEarningsUnit !Text
    | ApprovedPayLedgerUnknownCalculationSource !Text
    | ApprovedPayLedgerUnknownSourceCondition !Text
    deriving (Eq, Show)

renderApprovedPayLedgerError :: ApprovedPayLedgerError -> Text
renderApprovedPayLedgerError = \case
    ApprovedPayLedgerResultNotLoaded -> "Approved pay calculation result was not loaded."
    ApprovedPayLedgerActiveCalculationMissing -> "Active pay calculation does not exist."
    ApprovedPayLedgerCalculationBelongsToDifferentEntry -> "Active pay calculation belongs to a different timesheet entry."
    ApprovedPayLedgerCalculationNotSealed -> "Active pay calculation is not sealed."
    ApprovedPayLedgerUnknownPaidTimeKind value -> "Unknown persisted paid-time kind: " <> value
    ApprovedPayLedgerUnknownEarningsUnit value -> "Unknown persisted earnings unit: " <> value
    ApprovedPayLedgerUnknownCalculationSource value -> "Unknown persisted calculation source: " <> value
    ApprovedPayLedgerUnknownSourceCondition value -> "Unknown persisted source condition: " <> value

-- | Compatibility renderer for callers not yet migrated to typed outcomes.
loadApprovedTimesheetPayCalculation ::
    (?modelContext :: ModelContext) =>
    TimesheetEntry ->
    IO (Either Text (Maybe WageCalculation))
loadApprovedTimesheetPayCalculation entry = do
    results <- loadApprovedTimesheetPayCalculationResults [entry]
    pure $ Bifunctor.first renderApprovedPayLedgerError $
        fromMaybe (Left ApprovedPayLedgerResultNotLoaded) (Map.lookup (unpackId entry.id) results)

loadApprovedTimesheetPayCalculations ::
    (?modelContext :: ModelContext) =>
    [TimesheetEntry] ->
    IO (Map.Map UUID (Either Text (Maybe WageCalculation)))
loadApprovedTimesheetPayCalculations entries =
    fmap (fmap (Bifunctor.first renderApprovedPayLedgerError)) (loadApprovedTimesheetPayCalculationResults entries)

-- | Bulk approved-ledger read. The three persisted ledger relations are each
-- queried at most once, regardless of entry count; reconstruction and error
-- selection are deterministic in entry/ordinal order.
loadApprovedTimesheetPayCalculationResults ::
    (?modelContext :: ModelContext) =>
    [TimesheetEntry] ->
    IO (Map.Map UUID (Either ApprovedPayLedgerError (Maybe WageCalculation)))
loadApprovedTimesheetPayCalculationResults entries
    | null calculationIds = pure resultWithoutRows
    | otherwise = do
        calculations <- query @TimesheetPayCalculation
            |> filterWhereIn (#id, map Id calculationIds)
            |> fetch
        segments <- query @TimesheetPayTimeSegment
            |> filterWhereIn (#timesheetPayCalculationId, calculationIds)
            |> fetch
        components <- query @TimesheetPayEarningsComponent
            |> filterWhereIn (#timesheetPayCalculationId, calculationIds)
            |> fetch
        let calculationById = Map.fromList [(unpackId calculation.id, calculation) | calculation <- calculations]
            segmentsByCalculation = groupRows (.timesheetPayCalculationId) segments
            componentsByCalculation = groupRows (.timesheetPayCalculationId) components
        pure $ Map.fromList
            [ (unpackId entry.id, reconstruct calculationById segmentsByCalculation componentsByCalculation entry)
            | entry <- entries
            ]
  where
    calculationIds = List.nub (mapMaybe (fmap unpackId . (.activePayCalculationId)) entries)
    resultWithoutRows = Map.fromList [(unpackId entry.id, Right Nothing) | entry <- entries]

    reconstruct calculationById segmentsByCalculation componentsByCalculation entry =
        case fmap unpackId entry.activePayCalculationId of
            Nothing -> Right Nothing
            Just calculationId -> do
                calculation <- maybe (Left ApprovedPayLedgerActiveCalculationMissing) Right (Map.lookup calculationId calculationById)
                if calculation.timesheetEntryId /= unpackId entry.id
                    then Left ApprovedPayLedgerCalculationBelongsToDifferentEntry
                    else if isNothing calculation.sealedAt
                        then Left ApprovedPayLedgerCalculationNotSealed
                        else
                            Just
                                <$> wageCalculationFromRows
                                    entry
                                    calculation
                                    (List.sortOn (.ordinal) (Map.findWithDefault [] calculationId segmentsByCalculation))
                                    (List.sortOn (.ordinal) (Map.findWithDefault [] calculationId componentsByCalculation))

    groupRows rowCalculationId =
        Map.fromListWith (<>)
            . map (\row -> (rowCalculationId row, [row]))

wageCalculationFromRows :: TimesheetEntry -> TimesheetPayCalculation -> [TimesheetPayTimeSegment] -> [TimesheetPayEarningsComponent] -> Either ApprovedPayLedgerError WageCalculation
wageCalculationFromRows entry calculation segmentRows componentRows = do
    segments <- traverse paidSegmentFromRow segmentRows
    components <- traverse componentFromRow componentRows
    pure WageCalculation
        { calculatedEntryId = CalculationEntryId (tshow (unpackId entry.id))
        , calculationVersion = WageCalculationVersion calculation.calculationVersion
        , calculationRateBookVersion = RateBookVersion <$> calculation.rateBookVersion
        , publishedOperationalDate = Just calculation.operationalDate
        , paidTimeSegments = segments
        , earningsComponents = components
        }

paidSegmentFromRow :: TimesheetPayTimeSegment -> Either ApprovedPayLedgerError PaidTimeSegment
paidSegmentFromRow row = do
    kind <- case row.paidTimeKind of
        "worked" -> Right Worked
        "casual_minimum_engagement_top_up" -> Right CasualMinimumEngagementTopUp
        "public_holiday_minimum_top_up" -> Right PublicHolidayMinimumTopUp
        value -> Left (ApprovedPayLedgerUnknownPaidTimeKind value)
    condition <- parseSourceCondition row.sourceCondition
    pure PaidTimeSegment
        { paidTimeKind = kind
        , paidTimeStart = row.startsAt
        , paidTimeEnd = row.endsAt
        , paidTimeLocalDate = row.localDate
        , paidTimeSourceCondition = condition
        }

componentFromRow :: TimesheetPayEarningsComponent -> Either ApprovedPayLedgerError EarningsComponent
componentFromRow row = do
    unit <- case row.unitType of
        "hours"           -> Right Hours
        "commenced_hours" -> Right CommencedHours
        value             -> Left (ApprovedPayLedgerUnknownEarningsUnit value)
    condition <- parseSourceCondition row.sourceCondition
    source <- case row.calculationSource of
        "hospitality_award" -> Right HospitalityAward
        "external_imported_pay_item" -> Right ExternalImportedPayItem
        value -> Left (ApprovedPayLedgerUnknownCalculationSource value)
    pure EarningsComponent
        { quantity = toRational row.quantity
        , unitType = unit
        , ratePerUnit = row.ratePerUnit
        , amount = toRational row.exactAmount
        , publishedComponentDate = row.componentDate
        , publishedRateBoundaryDate = row.resolvedRateBoundaryDate
        , publishedXeroLocalBucketKey = row.xeroLocalBucketKey
        , publishedXeroEarningsRateId = row.xeroEarningsRateId
        , publishedXeroMappingLegacyFallback = row.xeroMappingLegacyFallback
        , sourceCondition = condition
        , calculationSource = source
        , sourceRateIdentity = RateSourceIdentity <$> row.sourceRateIdentity
        }

parseSourceCondition :: Text -> Either ApprovedPayLedgerError SourceCondition
parseSourceCondition = \case
    "ordinary" -> Right OrdinaryCondition
    "saturday" -> Right SaturdayCondition
    "sunday" -> Right SundayCondition
    "public_holiday" -> Right PublicHolidayCondition
    "evening_after_7pm_addition" -> Right EveningAdditionCondition
    "late_night_after_midnight_addition" -> Right EarlyMorningAdditionCondition
    "missed_meal_break_addition" -> Right MissedMealBreakAdditionCondition
    value -> case Text.stripPrefix "external_imported_pay_item:" value of
        Just itemId | not (Text.null itemId) -> Right (ImportedFlatRateCondition itemId)
        _ -> Left (ApprovedPayLedgerUnknownSourceCondition value)

persistApprovedTimesheetPayCalculation ::
    (?modelContext :: ModelContext) =>
    TimesheetEntry ->
    IO (Either Text TimesheetPayCalculation)
persistApprovedTimesheetPayCalculation =
    persistApprovedTimesheetPayCalculationWith True

-- | Development fixtures are synthetic approvals created before a retained
-- Xero tenant is restored. Keep their Xero facts explicitly eligible for the
-- legacy lookup path instead of sealing IDs from the throwaway seed tenant.
persistDevSeedApprovedTimesheetPayCalculation ::
    (?modelContext :: ModelContext) =>
    TimesheetEntry ->
    IO (Either Text TimesheetPayCalculation)
persistDevSeedApprovedTimesheetPayCalculation =
    persistApprovedTimesheetPayCalculationWith False

persistApprovedTimesheetPayCalculationWith ::
    (?modelContext :: ModelContext) =>
    Bool ->
    TimesheetEntry ->
    IO (Either Text TimesheetPayCalculation)
persistApprovedTimesheetPayCalculationWith sealXeroMapping entry = do
    case timesheetWageSubject entry of
        Left err -> pure (Left ("Cannot freeze approved pay calculation: " <> renderWageEvaluationError err))
        Right subject -> do
            results <- evaluateUnsealedWages ApprovalWageEvaluation [subject]
            case Map.lookup (TimesheetSubject (unpackId entry.id)) results of
                Nothing -> pure (Left "Cannot freeze approved pay calculation: result was not loaded.")
                Just (Left err) -> pure (Left ("Cannot freeze approved pay calculation: " <> renderWageEvaluationError err))
                Just (Right calculation) -> do
                    rateBoundaryFacts <- loadRateBoundaryFacts [calculation]
                    Right <$> persistWithRateBoundaryFacts sealXeroMapping rateBoundaryFacts entry calculation

data PayLedgerBackfillException = PayLedgerBackfillException [(UUID, Text)]
    deriving (Show)

instance Exception PayLedgerBackfillException

-- | Deployment backfill seam. Every eligible row is locked and processed in
-- one transaction. A single missing historical source fact rolls back the
-- complete batch and identifies the entry that prevented cutover. The adapter
-- deliberately has no source-age policy; effective rate and holiday facts are
-- still mandatory.
backfillApprovedTimesheetPayCalculations ::
    (?modelContext :: ModelContext) =>
    IO (Either [(UUID, Text)] Int)
backfillApprovedTimesheetPayCalculations = do
    result :: Either PayLedgerBackfillException Int <- Exception.try $ withTransaction do
        invalidActiveEntryIds :: [PG.Only UUID] <- sqlQuery
            "SELECT te.id FROM timesheet_entries te LEFT JOIN timesheet_pay_calculations calculation ON calculation.id = te.active_pay_calculation_id WHERE te.is_approved = TRUE AND te.deleted_at IS NULL AND te.active_pay_calculation_id IS NOT NULL AND (calculation.id IS NULL OR calculation.sealed_at IS NULL OR calculation.timesheet_entry_id <> te.id OR calculation.approved_at IS DISTINCT FROM te.approved_at OR calculation.approved_by_user_id IS DISTINCT FROM te.approved_by_user_id OR calculation.staff_pay_version_id IS DISTINCT FROM te.staff_pay_version_id OR calculation.shift_type_pay_version_id IS DISTINCT FROM te.shift_type_pay_version_id OR NOT EXISTS (SELECT 1 FROM timesheet_pay_time_segments segment WHERE segment.timesheet_pay_calculation_id = calculation.id) OR NOT EXISTS (SELECT 1 FROM timesheet_pay_earnings_components component WHERE component.timesheet_pay_calculation_id = calculation.id) OR (SELECT COUNT(*) <> COALESCE(MAX(segment.ordinal) + 1, 0) FROM timesheet_pay_time_segments segment WHERE segment.timesheet_pay_calculation_id = calculation.id) OR (SELECT COUNT(*) <> COALESCE(MAX(component.ordinal) + 1, 0) FROM timesheet_pay_earnings_components component WHERE component.timesheet_pay_calculation_id = calculation.id)) ORDER BY te.starts_at, te.id FOR UPDATE OF te"
            ()
        unless (null invalidActiveEntryIds) $
            Exception.throwIO
                ( PayLedgerBackfillException
                    [ (entryId, "Existing active approved-pay ledger is incomplete or does not preserve approval metadata.")
                    | PG.Only entryId <- invalidActiveEntryIds
                    ]
                )
        lockedEntryIds :: [PG.Only UUID] <- sqlQuery
            "SELECT id FROM timesheet_entries WHERE is_approved = TRUE AND active_pay_calculation_id IS NULL AND deleted_at IS NULL ORDER BY starts_at, id FOR UPDATE"
            ()
        fetchedEntries <- if null lockedEntryIds
            then pure []
            else query @TimesheetEntry
                |> filterWhereIn (#id, [ Id entryId | PG.Only entryId <- lockedEntryIds ])
                |> fetch
        let entriesById = Map.fromList [(unpackId entry.id, entry) | entry <- fetchedEntries]
            missingEntryIds = [entryId | PG.Only entryId <- lockedEntryIds, Map.notMember entryId entriesById]
            entries = mapMaybe (\(PG.Only entryId) -> Map.lookup entryId entriesById) lockedEntryIds
        unless (null missingEntryIds) $
            Exception.throwIO
                ( PayLedgerBackfillException
                    [(entryId, "Locked approved entry could not be reloaded.") | entryId <- missingEntryIds]
                )
        let subjectResults = [(unpackId entry.id, timesheetWageSubject entry) | entry <- entries]
            subjectFailures =
                [ (entryId, renderWageEvaluationError err)
                | (entryId, Left err) <- subjectResults
                ]
            subjects = [subject | (_, Right subject) <- subjectResults]
        unless (null subjectFailures) (Exception.throwIO (PayLedgerBackfillException subjectFailures))
        evaluated <- evaluateUnsealedWages HistoricalBackfillWageEvaluation subjects
        let calculations =
                [ case Map.lookup (TimesheetSubject (unpackId entry.id)) evaluated of
                    Nothing -> Left (unpackId entry.id, "Entry calculation was not loaded.")
                    Just result -> Bifunctor.first (\err -> (unpackId entry.id, renderWageEvaluationError err)) result
                | entry <- entries
                ]
            failures = lefts calculations
            successfulCalculations = rights calculations
        unless (null failures) (Exception.throwIO (PayLedgerBackfillException failures))
        historicalFactFailures <- validateHistoricalHolidayFacts entries (Map.fromList (zip (map (unpackId . (.id)) entries) successfulCalculations))
        unless (null historicalFactFailures) (Exception.throwIO (PayLedgerBackfillException historicalFactFailures))
        rateBoundaryFacts <- loadRateBoundaryFacts successfulCalculations
        forM_ (zip entries successfulCalculations) \(entry, calculation) -> do
            calculationRecord <- persistWithRateBoundaryFacts False rateBoundaryFacts entry calculation
            void $ entry
                |> set #activePayCalculationId (Just calculationRecord.id)
                |> set #legacyPayBackfillPending False
                |> updateRecord
        pure (length entries)
    pure $ case result of
        Left (PayLedgerBackfillException failures) -> Left failures
        Right count                                -> Right count
validateHistoricalHolidayFacts ::
    (?modelContext :: ModelContext) =>
    [TimesheetEntry] ->
    Map.Map UUID WageCalculation ->
    IO [(UUID, Text)]
validateHistoricalHolidayFacts entries contexts = do
    let awardEntries = filter requiresAwardFacts entries
        timingOutcomes = map (\entry -> (entry, timesheetEntryBoundaries entry)) awardEntries
        requiredYears = List.nub (concatMap (either (const []) entryYears) (map snd timingOutcomes))
    holidays <- if null requiredYears
        then pure []
        else query @PublicHoliday
            |> filterWhere (#jurisdiction, "VIC" :: Text)
            |> filterWhere (#isRegional, False)
            |> fetch
    let coveredYears = List.nub
            [ yearOf holiday.holidayDate
            | holiday <- holidays
            , isJust holiday.importedAt
            ]
    pure
        ( [ (unpackId entry.id, "Timesheet timing is invalid and must be repaired before payroll.")
          | (entry, Left _) <- timingOutcomes
          ]
            <> [ (unpackId entry.id, "Historical statewide holiday facts are missing for " <> tshow year <> ".")
               | (entry, Right boundaries) <- timingOutcomes
               , year <- entryYears boundaries
               , year `notElem` coveredYears
               ]
        )
  where
    requiresAwardFacts entry =
        case Map.lookup (unpackId entry.id) contexts of
            Nothing -> False
            Just calculation -> any ((== HospitalityAward) . (.calculationSource)) calculation.earningsComponents
    entryYears boundaries =
        List.nub
            [ yearOf (authoritativeStartLocalTime boundaries).localDay
            , yearOf (authoritativeEndLocalTime boundaries).localDay
            ]
    yearOf day = let (year, _, _) = toGregorian day in year

data RateBoundaryFacts = RateBoundaryFacts
    { baseRateOperativeFromById    :: !(Map.Map UUID (Maybe Day))
    , penaltyRateOperativeFromById :: !(Map.Map UUID (Maybe Day))
    , allowanceOperativeFromById   :: !(Map.Map UUID (Maybe Day))
    }

loadRateBoundaryFacts :: (?modelContext :: ModelContext) => [WageCalculation] -> IO RateBoundaryFacts
loadRateBoundaryFacts calculations = do
    let sources = mapMaybe (.sourceRateIdentity) (concatMap (.earningsComponents) calculations)
        baseIds = List.nub [projectionId | identity <- sources, Just (AwardLevelBaseRateSource projectionId _) <- [projectionRateSourceFromIdentity identity]]
        penaltyIds = List.nub [projectionId | identity <- sources, Just (AwardLevelPenaltyRateSource projectionId _) <- [projectionRateSourceFromIdentity identity]]
        allowanceIds = List.nub [projectionId | identity <- sources, Just (AwardTimePenaltyAllowanceSource projectionId _) <- [projectionRateSourceFromIdentity identity]]
    baseRates <- if null baseIds then pure [] else query @AwardLevelBaseRate |> filterWhereIn (#id, map Id baseIds) |> fetch
    penaltyRates <- if null penaltyIds then pure [] else query @AwardLevelPenaltyRate |> filterWhereIn (#id, map Id penaltyIds) |> fetch
    allowances <- if null allowanceIds then pure [] else query @AwardTimePenaltyAllowance |> filterWhereIn (#id, map Id allowanceIds) |> fetch
    pure RateBoundaryFacts
        { baseRateOperativeFromById = Map.fromList [(unpackId row.id, row.operativeFrom) | row <- baseRates]
        , penaltyRateOperativeFromById = Map.fromList [(unpackId row.id, row.operativeFrom) | row <- penaltyRates]
        , allowanceOperativeFromById = Map.fromList [(unpackId row.id, row.operativeFrom) | row <- allowances]
        }

persistWithRateBoundaryFacts :: (?modelContext :: ModelContext) => Bool -> RateBoundaryFacts -> TimesheetEntry -> WageCalculation -> IO TimesheetPayCalculation
persistWithRateBoundaryFacts sealXeroMapping rateBoundaryFacts entry calculation = do
    approvedAt <- maybe (fail "approved entry missing approved_at") pure entry.approvedAt
    approvedBy <- maybe (fail "approved entry missing approved_by_user_id") pure entry.approvedByUserId
    staffVersion <- maybe (fail "approved entry missing staff_pay_version_id") pure entry.staffPayVersionId
    shiftVersion <- maybe (fail "approved entry missing shift_type_pay_version_id") pure entry.shiftTypePayVersionId
    source <- calculationSourceFor calculation
    venueConfig <- query @VenueConfig
        |> filterWhere (#venueId, entry.venueId)
        |> fetchOne
    xeroMappingContext <- if sealXeroMapping then loadApprovalXeroMappingContext entry else pure Nothing
    calculationRecord <- newRecord @TimesheetPayCalculation
        |> set #timesheetEntryId (unpackId entry.id)
        |> set #calculationVersion (let WageCalculationVersion value = calculation.calculationVersion in value)
        |> set #calculationSource (calculationSourceValue source)
        |> set #rateBookVersion (fmap (\(RateBookVersion value) -> value) calculation.calculationRateBookVersion)
        |> set #operationalDate entry.operationalDate
        |> set #rosterWindowStart (startOfWeekFor venueConfig.rosterWeekStartsOn entry.operationalDate)
        |> set #rosterWeekStartsOn venueConfig.rosterWeekStartsOn
        |> set #venueTimezone "Australia/Melbourne"
        |> set #holidayJurisdiction "VIC"
        |> set #staffPayVersionId staffVersion
        |> set #shiftTypePayVersionId shiftVersion
        |> set #approvedAt approvedAt
        |> set #approvedByUserId approvedBy
        |> createRecord
    forM_ (zip [0 :: Int ..] calculation.paidTimeSegments) \(ordinal, paidSegment) ->
        void $ newRecord @TimesheetPayTimeSegment
            |> set #timesheetPayCalculationId (unpackId calculationRecord.id)
            |> set #ordinal ordinal
            |> set #paidTimeKind (paidTimeKindValue paidSegment.paidTimeKind)
            |> set #startsAt paidSegment.paidTimeStart
            |> set #endsAt paidSegment.paidTimeEnd
            |> set #localDate paidSegment.paidTimeLocalDate
            |> set #sourceCondition (sourceConditionValue paidSegment.paidTimeSourceCondition)
            |> createRecord
    forM_ (zip [0 :: Int ..] (datedEarningsComponents calculation)) \(ordinal, (componentDate, component)) -> do
        resolvedRateBoundaryDate <- resolveComponentRateBoundary rateBoundaryFacts venueConfig.rosterWeekStartsOn component
        (xeroLocalBucketKey, xeroEarningsRateId) <- resolveApprovalXeroMapping xeroMappingContext venueConfig.rosterWeekStartsOn entry componentDate (component { publishedRateBoundaryDate = resolvedRateBoundaryDate })
        void $ newRecord @TimesheetPayEarningsComponent
            |> set #timesheetPayCalculationId (unpackId calculationRecord.id)
            |> set #ordinal ordinal
            |> set #quantity (exactScientific component.quantity)
            |> set #unitType (unitValue component.unitType)
            |> set #ratePerUnit component.ratePerUnit
            |> set #exactAmount (exactScientific component.amount)
            |> set #componentDate (Just componentDate)
            |> set #resolvedRateBoundaryDate resolvedRateBoundaryDate
            |> set #xeroLocalBucketKey xeroLocalBucketKey
            |> set #xeroEarningsRateId xeroEarningsRateId
            |> set #xeroMappingLegacyFallback (not sealXeroMapping)
            |> set #sourceCondition (sourceConditionValue component.sourceCondition)
            |> set #calculationSource (calculationSourceValue component.calculationSource)
            |> set #sourceRateIdentity (fmap (\(RateSourceIdentity value) -> value) component.sourceRateIdentity)
            |> createRecord
    sealedAt <- getCurrentTime
    calculationRecord
        |> set #sealedAt (Just sealedAt)
        |> updateRecord

data ApprovalXeroMappingContext = ApprovalXeroMappingContext
    { approvalBucketContext       :: !XeroComponentBucketContext
    , approvalStaff               :: !Staff
    , approvalEarningsMappings    :: ![XeroEarningsRateMapping]
    , approvalPayItemRequirements :: ![XeroPayItemRequirementRecord]
    , approvalImportedPayItems    :: ![XeroImportedPayItem]
    }

loadApprovalXeroMappingContext :: (?modelContext :: ModelContext) => TimesheetEntry -> IO (Maybe ApprovalXeroMappingContext)
loadApprovalXeroMappingContext entry = do
    connection <- query @XeroConnection
        |> filterWhere (#venueId, entry.venueId)
        |> filterWhere (#connectionStatus, "active" :: Text)
        |> orderByDesc #connectedAt
        |> fetchOneOrNothing
    forM connection \activeConnection -> do
        staff <- fetch (Id entry.staffId)
        staffVersionId <- maybe (fail "Approved entry missing staff pay version for Xero mapping.") pure entry.staffPayVersionId
        shiftVersionId <- maybe (fail "Approved entry missing shift pay version for Xero mapping.") pure entry.shiftTypePayVersionId
        staffVersion <- fetch (Id staffVersionId)
        shiftVersion <- fetch (Id shiftVersionId)
        awardLevels <- query @AwardLevel |> fetch
        earningsMappings <- query @XeroEarningsRateMapping
            |> filterWhere (#xeroConnectionId, unpackId activeConnection.id)
            |> filterWhere (#mappingStatus, XeroEarningsRateMappingStatusEnumVerified)
            |> fetch
        requirements <- query @XeroPayItemRequirementRecord
            |> filterWhere (#xeroConnectionId, unpackId activeConnection.id)
            |> filterWhereIn (#requirementStatus, [Matched, XeroPayItemRequirementStatusEnumCreated])
            |> fetch
        importedPayItems <- query @XeroImportedPayItem
            |> filterWhere (#xeroConnectionId, unpackId activeConnection.id)
            |> fetch
        pure ApprovalXeroMappingContext
            { approvalBucketContext = XeroComponentBucketContext
                { bucketStaffPayVersions = Map.singleton staffVersionId staffVersion
                , bucketShiftTypePayVersions = Map.singleton shiftVersionId shiftVersion
                , bucketAwardLevels = awardLevels
                }
            , approvalStaff = staff
            , approvalEarningsMappings = earningsMappings
            , approvalPayItemRequirements = requirements
            , approvalImportedPayItems = importedPayItems
            }

resolveApprovalXeroMapping :: Maybe ApprovalXeroMappingContext -> Int -> TimesheetEntry -> Day -> EarningsComponent -> IO (Maybe Text, Maybe Text)
resolveApprovalXeroMapping Nothing _ _ _ _ = pure (Nothing, Nothing)
resolveApprovalXeroMapping (Just context) rosterWeekStartsOn entry componentDate component = do
    localBucketKey <- either (fail . cs) pure (componentBucketKey rosterWeekStartsOn context.approvalBucketContext entry context.approvalStaff component componentDate)
    let earningsRateId = case component.sourceCondition of
            ImportedFlatRateCondition itemId ->
                context.approvalImportedPayItems
                    |> find ((== itemId) . inputValue . (.id))
                    |> fmap (.xeroEarningsRateId)
            _ ->
                (context.approvalEarningsMappings |> find ((== localBucketKey) . (.localBucketKey)) >>= (.xeroEarningsRateId))
                    <|> (context.approvalPayItemRequirements |> find ((== localBucketKey) . (.requirementKey)) >>= (.xeroEarningsRateId))
    pure $ case earningsRateId of
        Nothing    -> (Nothing, Nothing)
        Just value -> (Just localBucketKey, Just value)

resolveComponentRateBoundary :: RateBoundaryFacts -> Int -> EarningsComponent -> IO (Maybe Day)
resolveComponentRateBoundary facts rosterWeekStartsOn component =
    case component.sourceRateIdentity of
        Nothing -> pure Nothing
        Just identity -> case projectionRateSourceFromIdentity identity of
            Just (AwardLevelBaseRateSource projectionId _) -> resolveFrom facts.baseRateOperativeFromById projectionId
            Just (AwardLevelPenaltyRateSource projectionId _) -> resolveFrom facts.penaltyRateOperativeFromById projectionId
            Just (AwardTimePenaltyAllowanceSource projectionId _) -> resolveFrom facts.allowanceOperativeFromById projectionId
            Nothing -> fail "Approved earnings component has an unsupported rate source identity."
  where
    resolveFrom operativeFromById projectionId =
        case Map.lookup projectionId operativeFromById of
            Nothing -> fail "Approved earnings component rate source does not exist."
            Just operativeFrom -> pure (venueEffectiveRateDate rosterWeekStartsOn <$> operativeFrom)

calculationSourceFor :: WageCalculation -> IO CalculationSource
calculationSourceFor calculation =
    case List.nub (map (.calculationSource) calculation.earningsComponents) of
        [source] -> pure source
        [] -> fail "approved wage calculation has no earnings components"
        _ -> fail "approved wage calculation has mixed calculation sources"

unitValue :: EarningsUnit -> Text
unitValue Hours          = "hours"
unitValue CommencedHours = "commenced_hours"

-- PostgreSQL NUMERIC cannot represent repeating rational hour quantities.
-- Preserve twelve decimal places at the ledger boundary; CSV display precision
-- is applied later and Xero uses the same twelve-place protocol boundary.
exactScientific :: Rational -> Scientific.Scientific
exactScientific value =
    Scientific.scientific (round (value * fromInteger wageLedgerScale)) (-12)

roundWageLedgerRational :: Rational -> Rational
roundWageLedgerRational value =
    fromInteger (round (value * fromInteger wageLedgerScale)) / fromInteger wageLedgerScale

wageLedgerScale :: Integer
wageLedgerScale = 10 ^ (12 :: Int)
