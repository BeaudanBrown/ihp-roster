module Application.Helper.TimesheetPayLedger
    ( backfillApprovedTimesheetPayCalculations
    , loadApprovedTimesheetPayCalculation
    , persistApprovedTimesheetPayCalculation
    ) where

import Application.VenueTime.Model
import Application.WageEngine
import Application.WageEngine.Adapter (LoadedCalculationContext (..),
                                       WageEngineAdapterError (..),
                                       calculationInputFromLoadedContext,
                                       loadWageEngineContextsForEntries)
import Control.Exception (Exception)
import qualified Control.Exception as Exception
import Control.Monad (void)
import qualified Data.Bifunctor as Bifunctor
import Data.Either (lefts, rights)
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import qualified Data.Scientific as Scientific
import qualified Data.Text as Text
import Data.Time.Clock (getCurrentTime)
import Data.Traversable (traverse)
import Generated.Types
import IHP.ControllerPrelude
import IHP.ModelSupport (ModelContext, sqlQuery, unpackId)
import IHP.Prelude

-- | Reconstructs the exact sealed facts without consulting mutable pay sources.
loadApprovedTimesheetPayCalculation ::
    (?modelContext :: ModelContext) =>
    TimesheetEntry ->
    IO (Either Text (Maybe WageCalculation))
loadApprovedTimesheetPayCalculation entry =
    case entry.activePayCalculationId of
        Nothing -> pure (Right Nothing)
        Just calculationId -> do
            calculation <- fetch calculationId
            segments <- query @TimesheetPayTimeSegment
                |> filterWhere (#timesheetPayCalculationId, unpackId calculation.id)
                |> orderBy #ordinal
                |> fetch
            components <- query @TimesheetPayEarningsComponent
                |> filterWhere (#timesheetPayCalculationId, unpackId calculation.id)
                |> orderBy #ordinal
                |> fetch
            if calculation.timesheetEntryId /= unpackId entry.id
                then pure (Left "Active pay calculation belongs to a different timesheet entry.")
                else if isNothing calculation.sealedAt
                    then pure (Left "Active pay calculation is not sealed.")
                    else pure (Just <$> wageCalculationFromRows entry calculation segments components)

wageCalculationFromRows :: TimesheetEntry -> TimesheetPayCalculation -> [TimesheetPayTimeSegment] -> [TimesheetPayEarningsComponent] -> Either Text WageCalculation
wageCalculationFromRows entry calculation segmentRows componentRows = do
    segments <- traverse paidSegmentFromRow segmentRows
    components <- traverse componentFromRow componentRows
    pure WageCalculation
        { calculatedEntryId = CalculationEntryId (tshow (unpackId entry.id))
        , calculationVersion = WageCalculationVersion calculation.calculationVersion
        , calculationRateBookVersion = RateBookVersion <$> calculation.rateBookVersion
        , paidTimeSegments = segments
        , earningsComponents = components
        }

paidSegmentFromRow :: TimesheetPayTimeSegment -> Either Text PaidTimeSegment
paidSegmentFromRow row = do
    kind <- case row.paidTimeKind of
        "worked" -> Right Worked
        "casual_minimum_engagement_top_up" -> Right CasualMinimumEngagementTopUp
        "public_holiday_minimum_top_up" -> Right PublicHolidayMinimumTopUp
        value -> Left ("Unknown persisted paid-time kind: " <> value)
    condition <- parseSourceCondition row.sourceCondition
    pure PaidTimeSegment
        { paidTimeKind = kind
        , paidTimeStart = row.startsAt
        , paidTimeEnd = row.endsAt
        , paidTimeLocalDate = row.localDate
        , paidTimeSourceCondition = condition
        }

componentFromRow :: TimesheetPayEarningsComponent -> Either Text EarningsComponent
componentFromRow row = do
    unit <- case row.unitType of
        "hours"           -> Right Hours
        "commenced_hours" -> Right CommencedHours
        value             -> Left ("Unknown persisted earnings unit: " <> value)
    condition <- parseSourceCondition row.sourceCondition
    source <- case row.calculationSource of
        "hospitality_award" -> Right HospitalityAward
        "external_imported_pay_item" -> Right ExternalImportedPayItem
        value -> Left ("Unknown persisted calculation source: " <> value)
    pure EarningsComponent
        { quantity = toRational row.quantity
        , unitType = unit
        , ratePerUnit = row.ratePerUnit
        , amount = toRational row.exactAmount
        , sourceCondition = condition
        , calculationSource = source
        , sourceRateIdentity = RateSourceIdentity <$> row.sourceRateIdentity
        }

parseSourceCondition :: Text -> Either Text SourceCondition
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
        _ -> Left ("Unknown persisted source condition: " <> value)

persistApprovedTimesheetPayCalculation ::
    (?modelContext :: ModelContext) =>
    TimesheetEntry ->
    IO (Either Text TimesheetPayCalculation)
persistApprovedTimesheetPayCalculation entry = do
    contexts <- loadWageEngineContextsForEntries [entry]
    case contexts of
        Left errors -> pure (Left ("Cannot freeze approved pay calculation: " <> tshow errors))
        Right contexts ->
            case Map.lookup (unpackId entry.id) contexts of
                Nothing -> pure (Left "Cannot freeze approved pay calculation: entry context was not loaded.")
                Just loadedContext ->
                    case calculateEntry loadedContext entry of
                        Left reason       -> pure (Left reason)
                        Right calculation -> Right <$> persist entry loadedContext.loadedVenueContext calculation

calculateEntry :: LoadedCalculationContext -> TimesheetEntry -> Either Text WageCalculation
calculateEntry loadedContext entry = do
    boundaries <- Bifunctor.first (\err -> "Invalid approved timesheet boundaries: " <> tshow err) (timesheetEntryBoundaries entry)
    shiftSegments <- Bifunctor.first (\err -> "Cannot segment approved timesheet: " <> tshow err) (authoritativeAwardSegments boundaries)
    Bifunctor.first
        (\err -> "Cannot freeze approved pay calculation: " <> tshow err)
        (calculateTimesheetPay (calculationInputFromLoadedContext loadedContext shiftSegments (authoritativeUnpaidMealBreak boundaries)))

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
        entries :: [TimesheetEntry] <- sqlQuery
            "SELECT timesheet_entries.* FROM timesheet_entries WHERE is_approved = TRUE AND active_pay_calculation_id IS NULL AND deleted_at IS NULL ORDER BY starts_at, id FOR UPDATE"
            ()
        contextsResult <- loadWageEngineContextsForEntries entries
        contexts <- case contextsResult of
            Left errors -> Exception.throwIO (PayLedgerBackfillException (map adapterFailure errors))
            Right value -> pure value
        let calculations =
                [ case Map.lookup (unpackId entry.id) contexts of
                    Nothing -> Left (unpackId entry.id, "Entry context was not loaded.")
                    Just context -> Bifunctor.first (\reason -> (unpackId entry.id, reason)) (calculateEntry context entry)
                | entry <- entries
                ]
            failures = lefts calculations
        unless (null failures) (Exception.throwIO (PayLedgerBackfillException failures))
        forM_ (zip entries (rights calculations)) \(entry, calculation) -> do
            context <- maybe (Exception.throwIO (PayLedgerBackfillException [(unpackId entry.id, "Entry context disappeared.")])) pure (Map.lookup (unpackId entry.id) contexts)
            calculationRecord <- persist entry context.loadedVenueContext calculation
            void $ entry
                |> set #activePayCalculationId (Just calculationRecord.id)
                |> set #legacyPayBackfillPending False
                |> updateRecord
        pure (length entries)
    pure $ case result of
        Left (PayLedgerBackfillException failures) -> Left failures
        Right count                                -> Right count
  where
    adapterFailure error = (adapterErrorEntryId error, tshow error)
    adapterErrorEntryId = \case
        MissingCalculationContext entryId -> entryId
        UnsupportedCalculationContext entryId _ -> entryId
        InvalidProjectedRateBook entryId _ -> entryId

persist :: (?modelContext :: ModelContext) => TimesheetEntry -> VenueAwardContext -> WageCalculation -> IO TimesheetPayCalculation
persist entry venueContext calculation = do
    approvedAt <- maybe (fail "approved entry missing approved_at") pure entry.approvedAt
    approvedBy <- maybe (fail "approved entry missing approved_by_user_id") pure entry.approvedByUserId
    staffVersion <- maybe (fail "approved entry missing staff_pay_version_id") pure entry.staffPayVersionId
    shiftVersion <- maybe (fail "approved entry missing shift_type_pay_version_id") pure entry.shiftTypePayVersionId
    source <- calculationSourceFor calculation
    calculationRecord <- newRecord @TimesheetPayCalculation
        |> set #timesheetEntryId (unpackId entry.id)
        |> set #calculationVersion (let WageCalculationVersion value = calculation.calculationVersion in value)
        |> set #calculationSource (calculationSourceValue source)
        |> set #rateBookVersion (fmap (\(RateBookVersion value) -> value) calculation.calculationRateBookVersion)
        |> set #venueTimezone (case venueContext.venueTimeZone of AustraliaMelbourne -> "Australia/Melbourne")
        |> set #holidayJurisdiction (case venueContext.publicHolidayJurisdiction of VictoriaStatewide -> "VIC")
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
    forM_ (zip [0 :: Int ..] calculation.earningsComponents) \(ordinal, component) ->
        void $ newRecord @TimesheetPayEarningsComponent
            |> set #timesheetPayCalculationId (unpackId calculationRecord.id)
            |> set #ordinal ordinal
            |> set #quantity (exactScientific component.quantity)
            |> set #unitType (unitValue component.unitType)
            |> set #ratePerUnit component.ratePerUnit
            |> set #exactAmount (exactScientific component.amount)
            |> set #sourceCondition (sourceConditionValue component.sourceCondition)
            |> set #calculationSource (calculationSourceValue component.calculationSource)
            |> set #sourceRateIdentity (fmap (\(RateSourceIdentity value) -> value) component.sourceRateIdentity)
            |> createRecord
    sealedAt <- getCurrentTime
    calculationRecord
        |> set #sealedAt (Just sealedAt)
        |> updateRecord

calculationSourceFor :: WageCalculation -> IO CalculationSource
calculationSourceFor calculation =
    case List.nub (map (.calculationSource) calculation.earningsComponents) of
        [source] -> pure source
        [] -> fail "approved wage calculation has no earnings components"
        _ -> fail "approved wage calculation has mixed calculation sources"

unitValue :: EarningsUnit -> Text
unitValue Hours          = "hours"
unitValue CommencedHours = "commenced_hours"

-- Scientific values from the engine are finite decimals. Converting its exact
-- rational quantities through Scientific preserves those decimal facts in the
-- NUMERIC ledger rather than rounding them to display precision.
exactScientific :: Rational -> Scientific.Scientific
exactScientific = fst . Scientific.fromRationalRepetendUnlimited
