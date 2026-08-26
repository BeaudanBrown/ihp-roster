module Application.WageEngine.Adapter
    ( WageEngineEntryRequest (..)
    , WageEngineSubjectRequest (..)
    , EntryContextRow (..)
    , ImportedPayItemRow (..)
    , ProjectedAwardLevelRow (..)
    , ProjectedBaseRateRow (..)
    , ProjectedPenaltyRateRow (..)
    , ProjectedTimeAdditionRow (..)
    , StatewideHolidayRow (..)
    , RateProjectionScope (..)
    , WageEngineBulkSource (..)
    , WageEngineDatabaseRead (..)
    , WageEngineAdapterError (..)
    , LoadedCalculationContext (..)
    , loadWageEngineContextResultsWith
    , loadWageEngineContextsWith
    , databaseWageEngineBulkSource
    , databaseWageEngineBulkSourceWith
    , loadWageEngineContextsForEntries
    , loadWageEngineContextResultsForSubjects
    , calculationInputFromLoadedContext
    )
where

import Application.Error.Runtime (ExternalRuntimeCategory (..), externalRuntimeInvariantFailure)
import Application.Helper.WeekBoundaries (venueEffectiveRateDate,
                                          venueEffectiveRateEndDate)
import Application.VenueTime (AwardSegment, ResolvedInterval)
import Application.VenueTime.Model (AuthoritativeBoundaries,
                                    authoritativeEndLocalTime,
                                    authoritativeStartLocalTime,
                                    decodeTimesheetTiming,
                                    timesheetTimingBoundaries)
import Application.WageEngine
import qualified Data.Bifunctor as Bifunctor
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import Data.Scientific (Scientific)
import qualified Data.Set as Set
import qualified Data.Text as Text
import Data.Time.Calendar (Day, addDays)
import Data.Traversable (traverse)
import qualified Generated.Types as G
import IHP.ControllerPrelude
import IHP.ModelSupport (ModelContext, unpackId)
import IHP.Prelude

newtype WageEngineEntryRequest = WageEngineEntryRequest
    { requestedEntryId :: UUID
    }
    deriving (Eq, Ord, Show)

-- | Persistence-independent facts needed to load one calculation context.
-- Current draft subjects leave the version ids empty; approval and historical
-- subjects provide immutable pay-version ids.
data WageEngineSubjectRequest = WageEngineSubjectRequest
    { subjectRequestId                    :: !UUID
    , subjectRequestOperationalDate       :: !Day
    , subjectRequestComponentStartDate    :: !Day
    , subjectRequestComponentEndDate      :: !Day
    , subjectRequestVenueId               :: !UUID
    , subjectRequestStaffId               :: !UUID
    , subjectRequestShiftTypeId           :: !UUID
    , subjectRequestStaffPayVersionId     :: !(Maybe UUID)
    , subjectRequestShiftTypePayVersionId :: !(Maybe UUID)
    }
    deriving (Eq, Show)

data EntryContextRow = EntryContextRow
    { contextEntryId                :: !UUID
    , contextVenueId                :: !UUID
    , contextOperationalDate        :: !Day
    , contextComponentStartDate     :: !Day
    , contextComponentEndDate       :: !Day
    , contextTimingIsValid          :: !Bool
    , contextVenueTimeZone          :: !Text
    , contextRosterWeekStartsOn     :: !Int
    , contextHolidayJurisdiction    :: !Text
    , contextEmploymentBasis        :: !EmploymentBasis
    , contextShiftAwardLevelId      :: !(Maybe UUID)
    , contextStaffAwardLevelId      :: !(Maybe UUID)
    , contextShiftImportedPayItemId :: !(Maybe UUID)
    , contextStaffImportedPayItemId :: !(Maybe UUID)
    }
    deriving (Eq, Show)

data ImportedPayItemRow = ImportedPayItemRow
    { importedRowId         :: !UUID
    , importedRowVenueId    :: !UUID
    , importedRowName       :: !Text
    , importedRowHourlyRate :: !Scientific
    }
    deriving (Eq, Show)

data ProjectedAwardLevelRow = ProjectedAwardLevelRow
    { projectedAwardLevelId          :: !UUID
    , projectedAwardFixedId          :: !Int
    , projectedClassificationFixedId :: !Int
    , projectedClassificationName    :: !Text
    , projectedAwardLevelIsActive    :: !Bool
    }
    deriving (Eq, Show)

data ProjectedBaseRateRow = ProjectedBaseRateRow
    { projectedBaseAwardLevelId :: !UUID
    , projectedBaseBasis        :: !EmploymentBasis
    , projectedBaseSourceId     :: !RateSourceIdentity
    , projectedBaseHourlyRate   :: !Scientific
    , projectedBaseFrom         :: !(Maybe Day)
    , projectedBaseTo           :: !(Maybe Day)
    }
    deriving (Eq, Show)

data ProjectedPenaltyRateRow = ProjectedPenaltyRateRow
    { projectedPenaltyAwardLevelId :: !UUID
    , projectedPenaltyBasis        :: !EmploymentBasis
    , projectedPenaltyKind         :: !BaseRateKind
    , projectedPenaltySourceId     :: !RateSourceIdentity
    , projectedPenaltyHourlyRate   :: !Scientific
    , projectedPenaltyFrom         :: !(Maybe Day)
    , projectedPenaltyTo           :: !(Maybe Day)
    }
    deriving (Eq, Show)

data ProjectedTimeAdditionRow = ProjectedTimeAdditionRow
    { projectedAdditionAwardFixedId :: !Int
    , projectedAdditionKind         :: !TimeAdditionKind
    , projectedAdditionSourceId     :: !RateSourceIdentity
    , projectedAdditionAmount       :: !Scientific
    , projectedAdditionFrom         :: !(Maybe Day)
    , projectedAdditionTo           :: !(Maybe Day)
    }
    deriving (Eq, Show)

data StatewideHolidayRow = StatewideHolidayRow
    { holidayRowJurisdiction :: !Text
    , holidayRowDate         :: !Day
    }
    deriving (Eq, Show)

data RateProjectionScope = RateProjectionScope
    { scopedAwardLevelIds :: ![UUID]
    , scopedWorkedFrom    :: !(Maybe Day)
    , scopedWorkedTo      :: !(Maybe Day)
    }
    deriving (Eq, Show)

data WageEngineBulkSource m = WageEngineBulkSource
    { fetchEntryContextRows          :: [UUID] -> m [EntryContextRow]
    , fetchImportedPayItemRows       :: [UUID] -> m [ImportedPayItemRow]
    , fetchProjectedAwardLevelRows   :: m [ProjectedAwardLevelRow]
    , fetchProjectedBaseRateRows     :: RateProjectionScope -> m [ProjectedBaseRateRow]
    , fetchProjectedPenaltyRateRows  :: RateProjectionScope -> m [ProjectedPenaltyRateRow]
    , fetchProjectedTimeAdditionRows :: RateProjectionScope -> m [ProjectedTimeAdditionRow]
    , fetchStatewideHolidayRows      :: [EntryContextRow] -> m [StatewideHolidayRow]
    }

data WageEngineDatabaseRead
    = TimesheetEntriesRead !Int
    | VenueConfigsRead !Int
    | StaffRowsRead !Int
    | ShiftTypeRowsRead !Int
    | StaffPayVersionsRead !Int
    | ShiftTypePayVersionsRead !Int
    | ImportedPayItemsRead !Int
    | AwardLevelsRead
    | BaseRatesRead !RateProjectionScope
    | PenaltyRatesRead !RateProjectionScope
    | TimeAdditionsRead !RateProjectionScope
    | StatewideHolidaysRead !Day !Day
    deriving (Eq, Show)

data WageEngineAdapterError
    = MissingCalculationContext !UUID
    | InvalidPersistedTiming !UUID
    | UnsupportedCalculationContext !UUID !UnsupportedInput
    | InvalidProjectedRateBook !UUID !RateBookError
    deriving (Eq, Show)

data LoadedCalculationContext = LoadedCalculationContext
    { loadedEntryId               :: !UUID
    , loadedVenueContext          :: !VenueAwardContext
    , loadedArrangement           :: !EmploymentArrangement
    , loadedAwardRateContext      :: !(Maybe AwardRateContext)
    , loadedStatewideHolidayDates :: !(Set.Set Day)
    , loadedImportedOverrides     :: !ImportedOverrideContext
    }
    deriving (Eq, Show)

loadWageEngineContextsWith :: Monad m => WageEngineBulkSource m -> [WageEngineEntryRequest] -> m (Either [WageEngineAdapterError] (Map.Map UUID LoadedCalculationContext))
loadWageEngineContextsWith source requests = do
    results <- loadWageEngineContextResultsWith source requests
    let orderedResults = mapMaybe (\request -> Map.lookup request.requestedEntryId results) requests
        errors = [validationError | Left validationError <- orderedResults]
        contexts = [context | Right context <- orderedResults]
    pure $
        if null errors
            then Right (Map.fromList (map (\context -> (context.loadedEntryId, context)) contexts))
            else Left errors

-- | Bulk-load every source relation once while retaining successful contexts
-- beside entry-local failures. Workflow previews use this form so one invalid
-- draft cannot discard another draft's valid calculation.
loadWageEngineContextResultsWith :: Monad m => WageEngineBulkSource m -> [WageEngineEntryRequest] -> m (Map.Map UUID (Either WageEngineAdapterError LoadedCalculationContext))
loadWageEngineContextResultsWith source requests = do
    entryContextRows <- source.fetchEntryContextRows (map (.requestedEntryId) requests)
    let importedPayItemIds =
            entryContextRows
                |> concatMap (\row -> catMaybes [row.contextShiftImportedPayItemId, row.contextStaffImportedPayItemId])
                |> List.nub
    importedPayItemRows <- source.fetchImportedPayItemRows importedPayItemIds
    awardLevelRows <- source.fetchProjectedAwardLevelRows
    let workedDates = map (.contextOperationalDate) entryContextRows
        projectionScope =
            RateProjectionScope
                { scopedAwardLevelIds =
                    awardLevelRows
                        |> filter (\row -> row.projectedAwardFixedId == 9 && row.projectedAwardLevelIsActive)
                        |> map (.projectedAwardLevelId)
                , scopedWorkedFrom = listToMaybe (List.sort workedDates)
                , scopedWorkedTo = listToMaybe (reverse (List.sort workedDates))
                }
    baseRateRows <- source.fetchProjectedBaseRateRows projectionScope
    penaltyRateRows <- source.fetchProjectedPenaltyRateRows projectionScope
    timeAdditionRows <- source.fetchProjectedTimeAdditionRows projectionScope
    holidayRows <- source.fetchStatewideHolidayRows entryContextRows

    let entryContextById = Map.fromList (map (\row -> (row.contextEntryId, row)) entryContextRows)
        importedPayItemById = Map.fromList (map (\row -> (row.importedRowId, row)) importedPayItemRows)
        awardLevelById =
            awardLevelRows
                |> filter (\row -> row.projectedAwardFixedId == 9 && row.projectedAwardLevelIsActive)
                |> map (\row -> (row.projectedAwardLevelId, row))
                |> Map.fromList
        holidayDatesByJurisdiction =
            Map.fromListWith Set.union
                [ (row.holidayRowJurisdiction, Set.singleton row.holidayRowDate)
                | row <- holidayRows
                ]
        rateBookRequests =
            requests
                |> mapMaybe
                    ( \request -> do
                        contextRow <- Map.lookup request.requestedEntryId entryContextById
                        pure ((contextRow.contextRosterWeekStartsOn, contextRow.contextOperationalDate), request.requestedEntryId)
                    )
                |> Map.fromListWith (<> )
                . map (\(key, entryId) -> (key, [entryId]))
        rateProjectionIndex = indexProjectedRates baseRateRows penaltyRateRows timeAdditionRows
        rateBooksByRequest =
            Map.mapWithKey
                (\(weekStartsOn, workedOn) _ -> buildProjectedRateBook weekStartsOn workedOn awardLevelRows rateProjectionIndex)
                rateBookRequests
        built =
            map
                ( buildLoadedContext
                    entryContextById
                    importedPayItemById
                    awardLevelById
                    holidayDatesByJurisdiction
                    rateBooksByRequest
                )
                requests
    pure $ Map.fromList (zip (map (.requestedEntryId) requests) built)

buildLoadedContext ::
    Map.Map UUID EntryContextRow ->
    Map.Map UUID ImportedPayItemRow ->
    Map.Map UUID ProjectedAwardLevelRow ->
    Map.Map Text (Set.Set Day) ->
    Map.Map (Int, Day) (Either RateBookError ValidatedRateBook) ->
    WageEngineEntryRequest ->
    Either WageEngineAdapterError LoadedCalculationContext
buildLoadedContext entryContextById importedPayItemById awardLevelById holidayDatesByJurisdiction rateBooksByRequest request = do
    contextRow <- maybe (Left (MissingCalculationContext request.requestedEntryId)) Right (Map.lookup request.requestedEntryId entryContextById)
    unless contextRow.contextTimingIsValid (Left (InvalidPersistedTiming request.requestedEntryId))
    venueContext <-
        Bifunctor.first
            (UnsupportedCalculationContext request.requestedEntryId)
            (resolveVenueAwardContext contextRow.contextVenueTimeZone contextRow.contextHolidayJurisdiction)
    importedOverrides <-
        ImportedOverrideContext
            <$> mapM (resolveImportedPayItemRow request.requestedEntryId contextRow.contextVenueId importedPayItemById) contextRow.contextShiftImportedPayItemId
            <*> mapM (resolveImportedPayItemRow request.requestedEntryId contextRow.contextVenueId importedPayItemById) contextRow.contextStaffImportedPayItemId
    loadedAwardRateContext <-
        case selectedImportedPayItem importedOverrides of
            Just _ -> Right Nothing
            Nothing -> do
                rateBookResult <- maybe (Left (MissingCalculationContext request.requestedEntryId)) Right (Map.lookup (contextRow.contextRosterWeekStartsOn, contextRow.contextOperationalDate) rateBooksByRequest)
                rateBook <- Bifunctor.first (InvalidProjectedRateBook request.requestedEntryId) rateBookResult
                selectedAwardLevelId <- maybe (Left (MissingCalculationContext request.requestedEntryId)) Right (contextRow.contextShiftAwardLevelId <|> contextRow.contextStaffAwardLevelId)
                awardLevel <- maybe (Left (MissingCalculationContext request.requestedEntryId)) Right (Map.lookup selectedAwardLevelId awardLevelById)
                classification <- maybe (Left (MissingCalculationContext request.requestedEntryId)) Right (awardClassificationFromFixedId awardLevel.projectedClassificationFixedId)
                pure
                    ( Just
                        ( AwardRateContext
                            ( ResolvedAwardLevel
                                classification
                                (tshow awardLevel.projectedAwardLevelId)
                                awardLevel.projectedClassificationName
                            )
                            rateBook
                        )
                    )
    pure
        LoadedCalculationContext
            { loadedEntryId = request.requestedEntryId
            , loadedVenueContext = venueContext
            , loadedArrangement = AwardHourlyEmployment contextRow.contextEmploymentBasis
            , loadedAwardRateContext
            , loadedStatewideHolidayDates = Map.findWithDefault Set.empty contextRow.contextHolidayJurisdiction holidayDatesByJurisdiction
            , loadedImportedOverrides = importedOverrides
            }

resolveImportedPayItemRow :: UUID -> UUID -> Map.Map UUID ImportedPayItemRow -> UUID -> Either WageEngineAdapterError ImportedPayItem
resolveImportedPayItemRow entryId venueId importedPayItemById importedPayItemId = do
    importedRow <- maybe (Left (MissingCalculationContext entryId)) Right (Map.lookup importedPayItemId importedPayItemById)
    if importedRow.importedRowVenueId /= venueId
        then Left (MissingCalculationContext entryId)
        else pure (ImportedPayItem (tshow importedRow.importedRowId) importedRow.importedRowName importedRow.importedRowHourlyRate)

data ProjectedRateIndex = ProjectedRateIndex
    { baseRatesByAwardLevel    :: !(Map.Map UUID [ProjectedBaseRateRow])
    , penaltyRatesByAwardLevel :: !(Map.Map UUID [ProjectedPenaltyRateRow])
    , additionsByAward         :: !(Map.Map Int [ProjectedTimeAdditionRow])
    }

indexProjectedRates :: [ProjectedBaseRateRow] -> [ProjectedPenaltyRateRow] -> [ProjectedTimeAdditionRow] -> ProjectedRateIndex
indexProjectedRates baseRates penaltyRates additions =
    ProjectedRateIndex
        { baseRatesByAwardLevel = Map.fromListWith (<>) [(rate.projectedBaseAwardLevelId, [rate]) | rate <- baseRates]
        , penaltyRatesByAwardLevel = Map.fromListWith (<>) [(rate.projectedPenaltyAwardLevelId, [rate]) | rate <- penaltyRates]
        , additionsByAward = Map.fromListWith (<>) [(addition.projectedAdditionAwardFixedId, [addition]) | addition <- additions]
        }

buildProjectedRateBook ::
    Int ->
    Day ->
    [ProjectedAwardLevelRow] ->
    ProjectedRateIndex ->
    Either RateBookError ValidatedRateBook
buildProjectedRateBook weekStartsOn workedOn awardLevels rateIndex = do
    let activeAwardLevels = filter (\row -> row.projectedAwardFixedId == 9 && row.projectedAwardLevelIsActive) awardLevels
        unsupportedFixedIds =
            activeAwardLevels
                |> map (.projectedClassificationFixedId)
                |> filter (isNothing . awardClassificationFromFixedId)
                |> List.sort
    case unsupportedFixedIds of
        fixedId : _ -> Left (UnsupportedClassificationFixedId fixedId)
        [] -> do
            let awardLevelById = Map.fromList (map (\row -> (row.projectedAwardLevelId, row)) activeAwardLevels)
                activeAwardLevelIds = Map.keys awardLevelById
                effectiveBaseRates =
                    activeAwardLevelIds
                        |> concatMap (\awardLevelId -> Map.findWithDefault [] awardLevelId rateIndex.baseRatesByAwardLevel)
                        |> filter (baseRateEffectiveOn weekStartsOn workedOn)
                effectivePenaltyRates =
                    activeAwardLevelIds
                        |> concatMap (\awardLevelId -> Map.findWithDefault [] awardLevelId rateIndex.penaltyRatesByAwardLevel)
                        |> filter (penaltyRateEffectiveOn weekStartsOn workedOn)
                effectiveAdditions =
                    Map.findWithDefault [] 9 rateIndex.additionsByAward
                        |> filter (additionEffectiveOn weekStartsOn workedOn)
            candidateRates <-
                mapM (baseCandidateRate awardLevelById) effectiveBaseRates
                    >>= \baseCandidates ->
                        mapM (penaltyCandidateRate awardLevelById) effectivePenaltyRates
                            >>= \penaltyCandidates ->
                                mapM additionCandidateRate effectiveAdditions
                                    >>= \additionCandidates -> pure (baseCandidates <> penaltyCandidates <> additionCandidates)
            let latestSnapshotCandidates = selectLatestEffectiveSnapshot candidateRates
                sortedCandidates = List.sortOn (.candidateRateKey) latestSnapshotCandidates
                effectivePeriod = fromMaybe fallbackPeriod (minimumMay (map (.candidateRateEffectivePeriod) sortedCandidates))
                version = renderRateBookVersion effectivePeriod sortedCandidates
            mkValidatedRateBook
                RateBookCandidate
                    { candidateAwardFixedId = 9
                    , candidateVersion = version
                    , candidateEffectivePeriod = effectivePeriod
                    , candidateRates = sortedCandidates
                    }
  where
    fallbackPeriod = EffectivePeriod (Just workedOn) (Just workedOn)

-- MAPD annual snapshots can remain open-ended after the next annual snapshot is
-- published. Select the latest effective start for the worked date before
-- validating completeness; rows within that snapshot still conflict normally.
selectLatestEffectiveSnapshot :: [CandidateRate] -> [CandidateRate]
selectLatestEffectiveSnapshot [] = []
selectLatestEffectiveSnapshot rates@(first : rest) =
    filter ((== latestEffectiveFrom) . (.effectiveFrom) . (.candidateRateEffectivePeriod)) rates
  where
    effectiveFrom = (.effectiveFrom) . (.candidateRateEffectivePeriod)
    latestEffectiveFrom = foldl' max (effectiveFrom first) (map effectiveFrom rest)

minimumMay :: Ord value => [value] -> Maybe value
minimumMay []             = Nothing
minimumMay (first : rest) = Just (foldl' min first rest)

baseCandidateRate :: Map.Map UUID ProjectedAwardLevelRow -> ProjectedBaseRateRow -> Either RateBookError CandidateRate
baseCandidateRate awardLevelById row = do
    awardLevel <- maybe (Left (UnsupportedClassificationFixedId (-1))) Right (Map.lookup row.projectedBaseAwardLevelId awardLevelById)
    period <- projectedEffectivePeriod row.projectedBaseFrom row.projectedBaseTo
    let rateKey = CandidateClassificationRate awardLevel.projectedClassificationFixedId row.projectedBaseBasis OrdinaryRate
    pure
        CandidateRate
            { candidateRateKey = rateKey
            , candidateRatePerUnit = row.projectedBaseHourlyRate
            , candidateRateSourceIdentity = row.projectedBaseSourceId
            , candidateRateSourceOwner = ClassificationOwner awardLevel.projectedClassificationFixedId
            , candidateRateEffectivePeriod = period
            }

penaltyCandidateRate :: Map.Map UUID ProjectedAwardLevelRow -> ProjectedPenaltyRateRow -> Either RateBookError CandidateRate
penaltyCandidateRate awardLevelById row = do
    awardLevel <- maybe (Left (UnsupportedClassificationFixedId (-1))) Right (Map.lookup row.projectedPenaltyAwardLevelId awardLevelById)
    period <- projectedEffectivePeriod row.projectedPenaltyFrom row.projectedPenaltyTo
    let rateKey = CandidateClassificationRate awardLevel.projectedClassificationFixedId row.projectedPenaltyBasis row.projectedPenaltyKind
    pure
        CandidateRate
            { candidateRateKey = rateKey
            , candidateRatePerUnit = row.projectedPenaltyHourlyRate
            , candidateRateSourceIdentity = row.projectedPenaltySourceId
            , candidateRateSourceOwner = ClassificationOwner awardLevel.projectedClassificationFixedId
            , candidateRateEffectivePeriod = period
            }

additionCandidateRate :: ProjectedTimeAdditionRow -> Either RateBookError CandidateRate
additionCandidateRate row = do
    period <- projectedEffectivePeriod row.projectedAdditionFrom row.projectedAdditionTo
    let rateKey = CandidateAwardAddition row.projectedAdditionKind
    pure
        CandidateRate
            { candidateRateKey = rateKey
            , candidateRatePerUnit = row.projectedAdditionAmount
            , candidateRateSourceIdentity = row.projectedAdditionSourceId
            , candidateRateSourceOwner = AwardOwner row.projectedAdditionAwardFixedId
            , candidateRateEffectivePeriod = period
            }

projectedEffectivePeriod :: Maybe Day -> Maybe Day -> Either RateBookError EffectivePeriod
projectedEffectivePeriod maybeFrom maybeTo =
    Right (EffectivePeriod maybeFrom maybeTo)

renderRateBookVersion :: EffectivePeriod -> [CandidateRate] -> Text
renderRateBookVersion period rates =
    "MA000009:"
        <> maybe "missing" tshow period.effectiveFrom
        <> ":"
        <> maybe "open" tshow period.effectiveTo
        <> ":"
        <> Text.intercalate "," (List.sort (List.nub (map rateFingerprint rates)))
  where
    rateFingerprint rate =
        let RateSourceIdentity sourceId = rate.candidateRateSourceIdentity
         in candidateRateKeyValue rate.candidateRateKey <> "=" <> tshow rate.candidateRatePerUnit <> "@" <> sourceId

candidateRateKeyValue :: CandidateRateKey -> Text
candidateRateKeyValue = \case
    CandidateClassificationRate fixedId basis rateKind ->
        tshow fixedId <> ":" <> basisValue basis <> ":" <> baseRateKindValue rateKind
    CandidateAwardAddition additionKind -> "award:" <> timeAdditionKindValue additionKind
  where
    basisValue PermanentPartTime = "permanent_part_time"
    basisValue CasualEmployment  = "casual"
    baseRateKindValue OrdinaryRate      = "ordinary"
    baseRateKindValue SaturdayRate      = "saturday"
    baseRateKindValue SundayRate        = "sunday"
    baseRateKindValue PublicHolidayRate = "public_holiday"
    timeAdditionKindValue EveningAddition      = "evening_after_7pm"
    timeAdditionKindValue EarlyMorningAddition = "late_night_after_midnight"

baseRateEffectiveOn :: Int -> Day -> ProjectedBaseRateRow -> Bool
baseRateEffectiveOn weekStartsOn workedOn row = projectedRateEffectiveOn weekStartsOn workedOn row.projectedBaseFrom row.projectedBaseTo

penaltyRateEffectiveOn :: Int -> Day -> ProjectedPenaltyRateRow -> Bool
penaltyRateEffectiveOn weekStartsOn workedOn row = projectedRateEffectiveOn weekStartsOn workedOn row.projectedPenaltyFrom row.projectedPenaltyTo

additionEffectiveOn :: Int -> Day -> ProjectedTimeAdditionRow -> Bool
additionEffectiveOn weekStartsOn workedOn row = projectedRateEffectiveOn weekStartsOn workedOn row.projectedAdditionFrom row.projectedAdditionTo

projectedRateEffectiveOn :: Int -> Day -> Maybe Day -> Maybe Day -> Bool
projectedRateEffectiveOn weekStartsOn workedOn operativeFrom operativeTo =
    maybe True ((<= workedOn) . venueEffectiveRateDate weekStartsOn) operativeFrom
        && maybe True (>= workedOn) (venueEffectiveRateEndDate weekStartsOn operativeTo)

calculationInputFromLoadedContext :: LoadedCalculationContext -> [AwardSegment] -> Maybe ResolvedInterval -> WageCalculationInput
calculationInputFromLoadedContext loadedContext shiftSegments unpaidMealBreak =
    WageCalculationInput
        { calculationEntryId = CalculationEntryId (tshow loadedContext.loadedEntryId)
        , calculationVenueContext = loadedContext.loadedVenueContext
        , calculationArrangement = loadedContext.loadedArrangement
        , calculationAwardRateContext = loadedContext.loadedAwardRateContext
        , calculationStatewidePublicHolidayDates = loadedContext.loadedStatewideHolidayDates
        , calculationImportedOverrides = loadedContext.loadedImportedOverrides
        , calculationUnsupportedFeatures = Set.empty
        , calculationShiftSegments = shiftSegments
        , calculationUnpaidMealBreak = unpaidMealBreak
        }

loadWageEngineContextsForEntries :: (?modelContext :: ModelContext) => [G.TimesheetEntry] -> IO (Either [WageEngineAdapterError] (Map.Map UUID LoadedCalculationContext))
loadWageEngineContextsForEntries entries =
    loadWageEngineContextsWith databaseWageEngineBulkSource (entryRequests entries)


-- | Load current or immutable context for arbitrary unsealed subjects without
-- requiring a persisted Timesheet row. All subject relations and every rate
-- relation are loaded once per batch.
loadWageEngineContextResultsForSubjects :: (?modelContext :: ModelContext) => [WageEngineSubjectRequest] -> IO (Map.Map UUID (Either WageEngineAdapterError LoadedCalculationContext))
loadWageEngineContextResultsForSubjects subjects =
    loadWageEngineContextResultsWith source requests
  where
    requests = [WageEngineEntryRequest subject.subjectRequestId | subject <- subjects]
    source = databaseWageEngineBulkSource
        { fetchEntryContextRows = const (fetchDatabaseSubjectContextRows subjects)
        }

entryRequests :: [G.TimesheetEntry] -> [WageEngineEntryRequest]
entryRequests entries =
    [ WageEngineEntryRequest (unpackId entry.id)
    | entry <- entries
    ]

databaseWageEngineBulkSource :: (?modelContext :: ModelContext) => WageEngineBulkSource IO
databaseWageEngineBulkSource = databaseWageEngineBulkSourceWith (const (pure ()))

databaseWageEngineBulkSourceWith :: (?modelContext :: ModelContext) => (WageEngineDatabaseRead -> IO ()) -> WageEngineBulkSource IO
databaseWageEngineBulkSourceWith observeRead =
    WageEngineBulkSource
        { fetchEntryContextRows = fetchDatabaseEntryContextRows observeRead
        , fetchImportedPayItemRows = fetchDatabaseImportedPayItemRows observeRead
        , fetchProjectedAwardLevelRows = fetchDatabaseAwardLevels observeRead
        , fetchProjectedBaseRateRows = fetchDatabaseProjectedBaseRates observeRead
        , fetchProjectedPenaltyRateRows = fetchDatabaseProjectedPenaltyRates observeRead
        , fetchProjectedTimeAdditionRows = fetchDatabaseProjectedTimeAdditions observeRead
        , fetchStatewideHolidayRows = fetchDatabaseStatewideHolidayRows observeRead
        }

fetchDatabaseAwardLevels :: (?modelContext :: ModelContext) => (WageEngineDatabaseRead -> IO ()) -> IO [ProjectedAwardLevelRow]
fetchDatabaseAwardLevels observeRead = do
    observeRead AwardLevelsRead
    query @G.AwardLevel
        |> filterWhere (#awardFixedId, 9)
        |> filterWhere (#isActive, True)
        |> fetch
        |> fmap (map projectAwardLevel)

fetchDatabaseSubjectContextRows :: (?modelContext :: ModelContext) => [WageEngineSubjectRequest] -> IO [EntryContextRow]
fetchDatabaseSubjectContextRows [] = pure []
fetchDatabaseSubjectContextRows subjects = do
    let venueIds = List.nub (map (.subjectRequestVenueId) subjects)
        staffIds = List.nub (map (.subjectRequestStaffId) subjects)
        shiftTypeIds = List.nub (map (.subjectRequestShiftTypeId) subjects)
        staffPayVersionIds = List.nub (mapMaybe (.subjectRequestStaffPayVersionId) subjects)
        shiftTypePayVersionIds = List.nub (mapMaybe (.subjectRequestShiftTypePayVersionId) subjects)
    venueConfigs <- query @G.VenueConfig |> filterWhereIn (#venueId, venueIds) |> fetch
    staffRows <- query @G.Staff |> filterWhereIn (#id, map (\rowId -> Id rowId :: Id G.Staff) staffIds) |> fetch
    shiftTypes <- query @G.ShiftType |> filterWhereIn (#id, map (\rowId -> Id rowId :: Id G.ShiftType) shiftTypeIds) |> fetch
    staffPayVersions <- if null staffPayVersionIds
        then pure []
        else query @G.StaffPayVersion |> filterWhereIn (#id, map (\rowId -> Id rowId :: Id G.StaffPayVersion) staffPayVersionIds) |> fetch
    shiftTypePayVersions <- if null shiftTypePayVersionIds
        then pure []
        else query @G.ShiftTypePayVersion |> filterWhereIn (#id, map (\rowId -> Id rowId :: Id G.ShiftTypePayVersion) shiftTypePayVersionIds) |> fetch
    let venueConfigByVenueId = Map.fromList [(row.venueId, row) | row <- venueConfigs]
        staffById = Map.fromList [(unpackId row.id, row) | row <- staffRows]
        shiftTypeById = Map.fromList [(unpackId row.id, row) | row <- shiftTypes]
        staffPayVersionById = Map.fromList [(unpackId row.id, row) | row <- staffPayVersions]
        shiftTypePayVersionById = Map.fromList [(unpackId row.id, row) | row <- shiftTypePayVersions]
    pure (mapMaybe (projectSubjectContext venueConfigByVenueId staffById shiftTypeById staffPayVersionById shiftTypePayVersionById) subjects)

projectSubjectContext ::
    Map.Map UUID G.VenueConfig ->
    Map.Map UUID G.Staff ->
    Map.Map UUID G.ShiftType ->
    Map.Map UUID G.StaffPayVersion ->
    Map.Map UUID G.ShiftTypePayVersion ->
    WageEngineSubjectRequest ->
    Maybe EntryContextRow
projectSubjectContext venueConfigs staffRows shiftTypes staffVersions shiftVersions subject = do
    venueConfig <- Map.lookup subject.subjectRequestVenueId venueConfigs
    staff <- Map.lookup subject.subjectRequestStaffId staffRows
    shiftType <- Map.lookup subject.subjectRequestShiftTypeId shiftTypes
    staffVersion <- traverse (`Map.lookup` staffVersions) subject.subjectRequestStaffPayVersionId
    shiftVersion <- traverse (`Map.lookup` shiftVersions) subject.subjectRequestShiftTypePayVersionId
    pure EntryContextRow
        { contextEntryId = subject.subjectRequestId
        , contextVenueId = subject.subjectRequestVenueId
        , contextOperationalDate = subject.subjectRequestOperationalDate
        , contextComponentStartDate = subject.subjectRequestComponentStartDate
        , contextComponentEndDate = subject.subjectRequestComponentEndDate
        , contextTimingIsValid = True
        , contextVenueTimeZone = venueConfig.timezone
        , contextRosterWeekStartsOn = venueConfig.rosterWeekStartsOn
        , contextHolidayJurisdiction = venueConfig.publicHolidayJurisdiction
        , contextEmploymentBasis = projectEmploymentBasis (maybe staff.employmentBasis (.employmentBasis) staffVersion)
        , contextShiftAwardLevelId = maybe (fmap unpackId shiftType.overrideAwardLevelId) (.overrideAwardLevelId) shiftVersion
        , contextStaffAwardLevelId = maybe (fmap unpackId staff.defaultAwardLevelId) (.defaultAwardLevelId) staffVersion
        , contextShiftImportedPayItemId = fmap unpackId (maybe shiftType.importedXeroPayItemId (.importedXeroPayItemId) shiftVersion)
        , contextStaffImportedPayItemId = fmap unpackId (maybe staff.importedXeroPayItemId (.importedXeroPayItemId) staffVersion)
        }

fetchDatabaseEntryContextRows :: (?modelContext :: ModelContext) => (WageEngineDatabaseRead -> IO ()) -> [UUID] -> IO [EntryContextRow]
fetchDatabaseEntryContextRows _ [] = pure []
fetchDatabaseEntryContextRows observeRead entryIds = do
    observeRead (TimesheetEntriesRead (length entryIds))
    entries <- query @G.TimesheetEntry
        |> filterWhereIn (#id, map (\entryId -> Id entryId :: Id G.TimesheetEntry) entryIds)
        |> fetch
    let venueIds = List.nub (map (.venueId) entries)
        staffIds = List.nub (map (.staffId) entries)
        shiftTypeIds = List.nub (map (.shiftTypeId) entries)
        staffPayVersionIds = List.nub (mapMaybe (.staffPayVersionId) entries)
        shiftTypePayVersionIds = List.nub (mapMaybe (.shiftTypePayVersionId) entries)
    observeRead (VenueConfigsRead (length venueIds))
    venueConfigs <- query @G.VenueConfig
        |> filterWhereIn (#venueId, venueIds)
        |> fetch
    observeRead (StaffRowsRead (length staffIds))
    staffRows <- query @G.Staff
        |> filterWhereIn (#id, map (\staffId -> Id staffId :: Id G.Staff) staffIds)
        |> fetch
    observeRead (ShiftTypeRowsRead (length shiftTypeIds))
    shiftTypes <- query @G.ShiftType
        |> filterWhereIn (#id, map (\shiftTypeId -> Id shiftTypeId :: Id G.ShiftType) shiftTypeIds)
        |> fetch
    staffPayVersions <-
        if null staffPayVersionIds
            then pure []
            else do
                observeRead (StaffPayVersionsRead (length staffPayVersionIds))
                query @G.StaffPayVersion
                    |> filterWhereIn (#id, map (\versionId -> Id versionId :: Id G.StaffPayVersion) staffPayVersionIds)
                    |> fetch
    shiftTypePayVersions <-
        if null shiftTypePayVersionIds
            then pure []
            else do
                observeRead (ShiftTypePayVersionsRead (length shiftTypePayVersionIds))
                query @G.ShiftTypePayVersion
                    |> filterWhereIn (#id, map (\versionId -> Id versionId :: Id G.ShiftTypePayVersion) shiftTypePayVersionIds)
                    |> fetch
    let venueConfigByVenueId = Map.fromList [(row.venueId, row) | row <- venueConfigs]
        staffById = Map.fromList [(unpackId row.id, row) | row <- staffRows]
        shiftTypeById = Map.fromList [(unpackId row.id, row) | row <- shiftTypes]
        staffPayVersionById = Map.fromList [(unpackId row.id, row) | row <- staffPayVersions]
        shiftTypePayVersionById = Map.fromList [(unpackId row.id, row) | row <- shiftTypePayVersions]
    pure
        ( mapMaybe
            (projectEntryContext venueConfigByVenueId staffById shiftTypeById staffPayVersionById shiftTypePayVersionById)
            entries
        )

projectEntryContext ::
    Map.Map UUID G.VenueConfig ->
    Map.Map UUID G.Staff ->
    Map.Map UUID G.ShiftType ->
    Map.Map UUID G.StaffPayVersion ->
    Map.Map UUID G.ShiftTypePayVersion ->
    G.TimesheetEntry ->
    Maybe EntryContextRow
projectEntryContext venueConfigByVenueId staffById shiftTypeById staffPayVersionById shiftTypePayVersionById entry = do
    venueConfig <- Map.lookup entry.venueId venueConfigByVenueId
    staff <- Map.lookup entry.staffId staffById
    shiftType <- Map.lookup entry.shiftTypeId shiftTypeById
    staffPayVersion <- case entry.staffPayVersionId of
        Nothing        -> pure Nothing
        Just versionId -> Just <$> Map.lookup versionId staffPayVersionById
    shiftTypePayVersion <- case entry.shiftTypePayVersionId of
        Nothing        -> pure Nothing
        Just versionId -> Just <$> Map.lookup versionId shiftTypePayVersionById
    let (componentStartDate, componentEndDate, timingIsValid) = case decodeTimesheetTiming entry of
            Left _ -> (entry.operationalDate, entry.operationalDate, False)
            Right timing ->
                let boundaries = timesheetTimingBoundaries timing
                 in ((authoritativeStartLocalTime boundaries).localDay, (authoritativeEndLocalTime boundaries).localDay, True)
    pure
        EntryContextRow
            { contextEntryId = unpackId entry.id
            , contextVenueId = entry.venueId
            , contextOperationalDate = entry.operationalDate
            , contextComponentStartDate = componentStartDate
            , contextComponentEndDate = componentEndDate
            , contextTimingIsValid = timingIsValid
            , contextVenueTimeZone = venueConfig.timezone
            , contextRosterWeekStartsOn = venueConfig.rosterWeekStartsOn
            , contextHolidayJurisdiction = venueConfig.publicHolidayJurisdiction
            , contextEmploymentBasis = projectEmploymentBasis (maybe staff.employmentBasis (.employmentBasis) staffPayVersion)
            , contextShiftAwardLevelId = maybe (fmap unpackId shiftType.overrideAwardLevelId) (.overrideAwardLevelId) shiftTypePayVersion
            , contextStaffAwardLevelId = maybe (fmap unpackId staff.defaultAwardLevelId) (.defaultAwardLevelId) staffPayVersion
            , contextShiftImportedPayItemId = fmap unpackId (maybe shiftType.importedXeroPayItemId (.importedXeroPayItemId) shiftTypePayVersion)
            , contextStaffImportedPayItemId = fmap unpackId (maybe staff.importedXeroPayItemId (.importedXeroPayItemId) staffPayVersion)
            }

fetchDatabaseImportedPayItemRows :: (?modelContext :: ModelContext) => (WageEngineDatabaseRead -> IO ()) -> [UUID] -> IO [ImportedPayItemRow]
fetchDatabaseImportedPayItemRows _ [] = pure []
fetchDatabaseImportedPayItemRows observeRead importedPayItemIds = do
    observeRead (ImportedPayItemsRead (length importedPayItemIds))
    records <- query @G.XeroImportedPayItem
        |> filterWhereIn (#id, map (\recordId -> Id recordId :: Id G.XeroImportedPayItem) importedPayItemIds)
        |> filterWhere (#archivedAt, Nothing)
        |> fetch
    pure
        [ ImportedPayItemRow (unpackId record.id) record.venueId record.name record.ratePerUnit
        | record <- records
        ]

fetchDatabaseStatewideHolidayRows :: (?modelContext :: ModelContext) => (WageEngineDatabaseRead -> IO ()) -> [EntryContextRow] -> IO [StatewideHolidayRow]
fetchDatabaseStatewideHolidayRows _ [] = pure []
fetchDatabaseStatewideHolidayRows observeRead contextRows = do
    let componentStartDates = List.sort (map (.contextComponentStartDate) contextRows)
        componentEndDates = List.sort (map (.contextComponentEndDate) contextRows)
        fromDate = fromMaybe (externalRuntimeInvariantFailure PersistedRuntimeInvariant "WageEngine holiday scope unexpectedly empty") (listToMaybe componentStartDates)
        toDate = fromMaybe (externalRuntimeInvariantFailure PersistedRuntimeInvariant "WageEngine holiday scope unexpectedly empty") (listToMaybe (reverse componentEndDates))
    observeRead (StatewideHolidaysRead fromDate toDate)
    holidays <- query @G.PublicHoliday
        |> filterWhere (#jurisdiction, "VIC" :: Text)
        |> filterWhere (#isRegional, False)
        |> filterWhereGreaterThanOrEqualTo (#holidayDate, fromDate)
        |> filterWhereLessThanOrEqualTo (#holidayDate, toDate)
        |> fetch
    pure [StatewideHolidayRow holiday.jurisdiction holiday.holidayDate | holiday <- holidays]

projectAwardLevel :: G.AwardLevel -> ProjectedAwardLevelRow
projectAwardLevel awardLevel =
    ProjectedAwardLevelRow
        { projectedAwardLevelId = unpackId awardLevel.id
        , projectedAwardFixedId = awardLevel.awardFixedId
        , projectedClassificationFixedId = awardLevel.classificationFixedId
        , projectedClassificationName = awardLevel.classification
        , projectedAwardLevelIsActive = awardLevel.isActive
        }

fetchDatabaseProjectedBaseRates :: (?modelContext :: ModelContext) => (WageEngineDatabaseRead -> IO ()) -> RateProjectionScope -> IO [ProjectedBaseRateRow]
fetchDatabaseProjectedBaseRates observeRead scope =
    case projectionScopeBounds scope of
        Nothing -> pure []
        Just (awardLevelIds, fromDate, toDate) -> do
            observeRead (BaseRatesRead scope)
            rates <- query @G.AwardLevelBaseRate
                |> filterWhereIn (#awardLevelId, awardLevelIds)
                |> filterWhereLessThanOrEqualTo (#operativeFrom, Just toDate)
                |> queryOr
                    (filterWhere (#operativeTo, Nothing :: Maybe Day))
                    (filterWhereGreaterThanOrEqualTo (#operativeTo, Just (addDays (-7) fromDate)))
                |> fetch
            pure
                [ ProjectedBaseRateRow
                    rate.awardLevelId
                    (projectEmploymentBasis rate.employmentBasis)
                    (projectionRateSourceIdentity (AwardLevelBaseRateSource (unpackId rate.id) rate.fwcMapdPayRateId))
                    rate.hourlyRate
                    rate.operativeFrom
                    rate.operativeTo
                | rate <- rates
                ]

fetchDatabaseProjectedPenaltyRates :: (?modelContext :: ModelContext) => (WageEngineDatabaseRead -> IO ()) -> RateProjectionScope -> IO [ProjectedPenaltyRateRow]
fetchDatabaseProjectedPenaltyRates observeRead scope =
    case projectionScopeBounds scope of
        Nothing -> pure []
        Just (awardLevelIds, fromDate, toDate) -> do
            observeRead (PenaltyRatesRead scope)
            rates <- query @G.AwardLevelPenaltyRate
                |> filterWhereIn (#awardLevelId, awardLevelIds)
                |> filterWhereIn (#penaltyKind, [G.SaturdayPenalty, G.SundayPenalty, G.PublicHolidayPenalty])
                |> filterWhereLessThanOrEqualTo (#operativeFrom, Just toDate)
                |> queryOr
                    (filterWhere (#operativeTo, Nothing :: Maybe Day))
                    (filterWhereGreaterThanOrEqualTo (#operativeTo, Just (addDays (-7) fromDate)))
                |> fetch
            pure (mapMaybe projectPenaltyRow rates)
  where
    projectPenaltyRow rate = do
        rateKind <- case rate.penaltyKind of
            G.SaturdayPenalty      -> Just SaturdayRate
            G.SundayPenalty        -> Just SundayRate
            G.PublicHolidayPenalty -> Just PublicHolidayRate
            _                      -> Nothing
        pure
            ( ProjectedPenaltyRateRow
                rate.awardLevelId
                (projectEmploymentBasis rate.employmentBasis)
                rateKind
                (projectionRateSourceIdentity (AwardLevelPenaltyRateSource (unpackId rate.id) rate.fwcMapdPenaltyRateId))
                rate.hourlyRate
                rate.operativeFrom
                rate.operativeTo
            )

fetchDatabaseProjectedTimeAdditions :: (?modelContext :: ModelContext) => (WageEngineDatabaseRead -> IO ()) -> RateProjectionScope -> IO [ProjectedTimeAdditionRow]
fetchDatabaseProjectedTimeAdditions observeRead scope =
    case projectionScopeBounds scope of
        Nothing -> pure []
        Just (_, fromDate, toDate) -> do
            observeRead (TimeAdditionsRead scope)
            allowances <- query @G.AwardTimePenaltyAllowance
                |> filterWhere (#awardFixedId, 9)
                |> filterWhereIn (#penaltyKind, [G.EveningAfter7Pm, G.LateNightAfterMidnight])
                |> filterWhereLessThanOrEqualTo (#operativeFrom, Just toDate)
                |> queryOr
                    (filterWhere (#operativeTo, Nothing :: Maybe Day))
                    (filterWhereGreaterThanOrEqualTo (#operativeTo, Just (addDays (-7) fromDate)))
                |> fetch
            pure (mapMaybe projectAdditionRow allowances)
  where
    projectAdditionRow allowance = do
        additionKind <- case allowance.penaltyKind of
            G.EveningAfter7Pm        -> Just EveningAddition
            G.LateNightAfterMidnight -> Just EarlyMorningAddition
            _                        -> Nothing
        pure
            ( ProjectedTimeAdditionRow
                allowance.awardFixedId
                additionKind
                (projectionRateSourceIdentity (AwardTimePenaltyAllowanceSource (unpackId allowance.id) allowance.fwcMapdWageAllowanceId))
                allowance.hourlyAmount
                allowance.operativeFrom
                allowance.operativeTo
            )

projectionScopeBounds :: RateProjectionScope -> Maybe ([UUID], Day, Day)
projectionScopeBounds scope
    | null scope.scopedAwardLevelIds = Nothing
    | otherwise = do
        fromDate <- scope.scopedWorkedFrom
        toDate <- scope.scopedWorkedTo
        pure (scope.scopedAwardLevelIds, fromDate, toDate)

projectEmploymentBasis :: G.StaffEmploymentBasisEnum -> EmploymentBasis
projectEmploymentBasis = \case
    G.Permanent -> PermanentPartTime
    G.Casual    -> CasualEmployment
