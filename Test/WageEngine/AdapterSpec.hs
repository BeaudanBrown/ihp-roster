module Test.WageEngine.AdapterSpec where

import Application.FwcMapd.Sync (storeCuratedMapdAwardData)
import Application.Helper.Pay (PayTotals (..), TimesheetPayResult (..),
                               ensurePayVersionsForTimesheetApproval,
                               fetchTimesheetPay, lockPayVersionsForApproval)
import Application.Helper.TimesheetPayLedger (backfillApprovedTimesheetPayCalculations,
                                              loadApprovedTimesheetPayCalculation,
                                              persistApprovedTimesheetPayCalculation)
import Application.VenueTime (AwardSegment)
import Application.WageEngine
import Application.WageEngine.Adapter
import Control.Monad (void)
import Data.IORef
import qualified Data.Map.Strict as Map
import Data.Scientific (Scientific)
import qualified Data.Text as Text
import qualified Data.Text.Encoding as TextEncoding
import Data.Time.Calendar (Day, fromGregorian)
import Data.Time.Clock (getCurrentTime)
import Data.Time.LocalTime (TimeOfDay (..))
import qualified Data.UUID as UUID
import Generated.Types
import IHP.ControllerPrelude
import qualified IHP.Log as Log
import IHP.ModelSupport.Types (ModelContext)
import qualified IHP.ModelSupport.Types as ModelSupport
import IHP.Prelude
import IHP.Test.Mocking
import qualified Prelude
import Test.Hspec
import Test.Support
import Test.Support.FwcMapdFixture (loadFwcMapdFixture)
import Test.WageEngine.Fixture (awardSegmentBetween, completeRateBookCandidate)

pureTests :: Spec
pureTests =
    describe "bulk wage-engine adapter structure" do
        it "executes each bounded bulk loader once, independent of entry count" do
            calls <- newIORef ([] :: [Text])
            let record :: Text -> value -> IO value
                record name value = modifyIORef' calls (<> [name]) >> pure value
                source =
                    WageEngineBulkSource
                        { fetchEntryContextRows = \_ -> record "entry-contexts" []
                        , fetchImportedPayItemRows = \_ -> record "imported-items" []
                        , fetchProjectedAwardLevelRows = record "award-levels" []
                        , fetchProjectedBaseRateRows = \_ -> record "base-rates" []
                        , fetchProjectedPenaltyRateRows = \_ -> record "penalty-rates" []
                        , fetchProjectedTimeAdditionRows = \_ -> record "time-additions" []
                        , fetchStatewideHolidayRows = \_ -> record "holidays" []
                        }
                entryId = uuid "10000000-0000-0000-0000-000000000001"
                requests = replicate 100 (WageEngineEntryRequest entryId)

            result <- loadWageEngineContextsWith source requests

            result `shouldSatisfy` \case
                Left (MissingCalculationContext missingEntryId : _) -> missingEntryId == entryId
                _ -> False
            readIORef calls
                `shouldReturn`
                    [ "entry-contexts"
                    , "imported-items"
                    , "award-levels"
                    , "base-rates"
                    , "penalty-rates"
                    , "time-additions"
                    , "holidays"
                    ]

        it "selects versioned rates at the venue week rollover from one in-memory index" do
            let beforeEntryId = uuid "10000000-0000-0000-0000-000000000010"
                afterEntryId = uuid "10000000-0000-0000-0000-000000000011"
                beforeDate = fromGregorian 2026 7 3
                afterDate = fromGregorian 2026 7 6
                oldCandidate = completeRateBookCandidate 100
                newPeriod = EffectivePeriod (Just (fromGregorian 2026 7 1)) Nothing
                newCandidate =
                    (completeRateBookCandidate 110)
                        { candidateVersion = "fixture-2026"
                        , candidateEffectivePeriod = newPeriod
                        , candidateRates = map (\rate -> rate { candidateRateEffectivePeriod = newPeriod }) (candidateRates (completeRateBookCandidate 110))
                        }
                (baseRows, penaltyRows, additionRows) = projectionRowsForCandidates [oldCandidate, newCandidate]
                contextRows =
                    [ testEntryContext beforeEntryId beforeDate
                    , testEntryContext afterEntryId afterDate
                    ]
                source =
                    WageEngineBulkSource
                        { fetchEntryContextRows = \_ -> pure contextRows
                        , fetchImportedPayItemRows = \_ -> pure []
                        , fetchProjectedAwardLevelRows = pure testAwardLevelRows
                        , fetchProjectedBaseRateRows = \_ -> pure baseRows
                        , fetchProjectedPenaltyRateRows = \_ -> pure penaltyRows
                        , fetchProjectedTimeAdditionRows = \_ -> pure additionRows
                        , fetchStatewideHolidayRows = \_ -> pure []
                        }
                requests =
                    [ WageEngineEntryRequest beforeEntryId
                    , WageEngineEntryRequest afterEntryId
                    ]

            contexts <- loadWageEngineContextsWith source requests >>= expectRight
            let beforeBook = loadedRateBookOrFail (contexts Map.! beforeEntryId)
                afterBook = loadedRateBookOrFail (contexts Map.! afterEntryId)
                ordinaryLevel1 = ClassificationRate HospitalityLevel1 PermanentPartTime OrdinaryRate

            lookupValidatedRate ordinaryLevel1 beforeBook `shouldBe` Just 100
            lookupValidatedRate ordinaryLevel1 afterBook `shouldBe` Just 110
            validatedRateBookEffectivePeriod beforeBook `shouldBe` oldCandidate.candidateEffectivePeriod
            validatedRateBookEffectivePeriod afterBook `shouldBe` newPeriod

            let inactiveEntryId = uuid "10000000-0000-0000-0000-000000000012"
                inactiveAwardLevelId = uuid "20000000-0000-0000-0000-000000000012"
                inactiveContext =
                    (testEntryContext inactiveEntryId beforeDate)
                        { contextStaffAwardLevelId = Just inactiveAwardLevelId
                        }
                inactiveSource =
                    source
                        { fetchEntryContextRows = \_ -> pure [inactiveContext]
                        , fetchProjectedAwardLevelRows =
                            pure (ProjectedAwardLevelRow inactiveAwardLevelId 9 243 "Inactive Level 1" False : testAwardLevelRows)
                        }

            loadWageEngineContextsWith inactiveSource [WageEngineEntryRequest inactiveEntryId]
                `shouldReturn` Left [MissingCalculationContext inactiveEntryId]

            let unsupportedEntryId = uuid "10000000-0000-0000-0000-000000000013"
                unsupportedContext =
                    (testEntryContext unsupportedEntryId beforeDate)
                        { contextVenueTimeZone = "Etc/UTC"
                        }
                unsupportedSource = source { fetchEntryContextRows = \_ -> pure [unsupportedContext] }
            loadWageEngineContextsWith unsupportedSource [WageEngineEntryRequest unsupportedEntryId]
                `shouldReturn` Left [UnsupportedCalculationContext unsupportedEntryId (UnsupportedVenueTimeZone "Etc/UTC")]

databaseTests :: Spec
databaseTests = aroundAll withDatabaseTestContext do
    describe "database wage-engine adapter" do
        it "blocks Award calculation but permits imported override when the projected rate book is partial" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Partial rate book"
                partialLevel <- newRecord @AwardLevel
                    |> set #awardFixedId 9
                    |> set #classificationFixedId 243
                    |> set #classification "Level 1"
                    |> set #isActive True
                    |> createRecord
                staff <- createStaffRecord venue Nothing "Partial" "Rate"
                    >>= updateRecord . set #defaultAwardLevelId (Just partialLevel.id)
                shiftType <- createShiftTypeRecord venue partialLevel "Ordinary"
                entry <- createAdapterEntry venue staff shiftType (fromGregorian 2026 1 6)

                result <- loadWageEngineContextsForEntries [entry]

                result `shouldSatisfy` \case
                    Left errors -> any isMissingRateBookError errors
                    Right _ -> False

                importedBy <- createUserRecord "partial-import@example.com" "admin" True
                importedPayItem <- createImportedXeroPayItemRecord venue importedBy "Partial-book import" "partial-book-import" 55
                importedStaff <- createStaffRecord venue Nothing "Imported" "Without Award"
                    >>= updateRecord . set #importedXeroPayItemId (Just importedPayItem.id)
                importedShiftType <- newRecord @ShiftType
                    |> set #venueId (unpackId venue.id)
                    |> set #name "Imported without Award"
                    |> set #sortOrder 0
                    |> set #overrideAwardLevelId Nothing
                    |> set #isActive True
                    |> createRecord
                importedEntry <- createAdapterEntry venue importedStaff importedShiftType (fromGregorian 2026 1 6)

                importedContexts <- loadWageEngineContextsForEntries [importedEntry] >>= expectRight
                importedContext <- maybe (expectationFailure "missing imported context" >> fail "unreachable") pure (Map.lookup (unpackId importedEntry.id) importedContexts)
                calculateTimesheetPay (calculationInputFromLoadedContext importedContext [fourHourInterval (testWorkedOn importedEntry)] Nothing)
                    `shouldSatisfy` \case
                        Right calculation -> rateForCalculation calculation == Just 55
                        Left _            -> False

        it "rejects newly approved rows without a sealed active calculation" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Strict approval ledger"
                approver <- createUserRecord "strict-ledger-approver@example.com" "admin" True
                staff <- createStaffRecord venue Nothing "Strict" "Ledger"
                entry <- createTimesheetEntryRecord venue staff (fromGregorian 2026 7 6)
                approvedAt <- getCurrentTime
                (staffVersion, shiftVersion) <- ensurePayVersionsForTimesheetApproval approver.id entry
                ( entry
                    |> set #isApproved True
                    |> set #staffPayVersionId (Just (unpackId staffVersion.id))
                    |> set #shiftTypePayVersionId (Just (unpackId shiftVersion.id))
                    |> set #approvedAt (Just approvedAt)
                    |> set #approvedByUserId (Just (unpackId approver.id))
                    |> updateRecord
                    |> void
                    ) `shouldThrow` anyException
                unchanged <- fetch entry.id
                unchanged.isApproved `shouldBe` False
                ( unchanged
                    |> set #legacyPayBackfillPending True
                    |> updateRecord
                    |> void
                    ) `shouldThrow` anyException

        it "persists exact Award ledger facts with immutable source provenance" $ withContext do
            withCleanDb do
                fixture <- loadFwcMapdFixture
                _ <- storeCuratedMapdAwardData [fixture]
                venue <- createVenueWithConfig "Immutable Award ledger"
                level <- query @AwardLevel
                    |> filterWhere (#classificationFixedId, 243)
                    |> fetchOne
                approver <- createUserRecord "ledger-approver@example.com" "admin" True
                staff <- createStaffRecord venue Nothing "Ledger" "Worker"
                    >>= updateRecord
                        . set #employmentBasis Permanent
                        . set #defaultAwardLevelId (Just level.id)
                shiftType <- createShiftTypeRecord venue level "Ledger ordinary"
                entry <- createAdapterEntry venue staff shiftType (fromGregorian 2026 7 6)
                approvedAt <- getCurrentTime
                (staffVersion, shiftVersion) <- ensurePayVersionsForTimesheetApproval approver.id entry
                lockPayVersionsForApproval approver.id approvedAt staffVersion shiftVersion
                approvedEntry <- withLegacyPayBackfillFixture do
                    entry
                        |> set #isApproved True
                        |> set #legacyPayBackfillPending True
                        |> set #staffPayVersionId (Just (unpackId staffVersion.id))
                        |> set #shiftTypePayVersionId (Just (unpackId shiftVersion.id))
                        |> set #approvedAt (Just approvedAt)
                        |> set #approvedByUserId (Just (unpackId approver.id))
                        |> updateRecord

                persisted <- persistApprovedTimesheetPayCalculation approvedEntry >>= expectRight
                segments <- query @TimesheetPayTimeSegment
                    |> filterWhere (#timesheetPayCalculationId, unpackId persisted.id)
                    |> orderBy #ordinal
                    |> fetch
                components <- query @TimesheetPayEarningsComponent
                    |> filterWhere (#timesheetPayCalculationId, unpackId persisted.id)
                    |> orderBy #ordinal
                    |> fetch

                persisted.calculationVersion `shouldBe` "hospitality-award-v1"
                persisted.calculationSource `shouldBe` "hospitality_award"
                persisted.rateBookVersion `shouldSatisfy` maybe False (not . Text.null)
                fmap (.paidTimeKind) segments `shouldBe` ["worked"]
                fmap (.quantity) components `shouldBe` [4]
                components `shouldSatisfy` all (isJust . (.sourceRateIdentity))
                activeEntry <- approvedEntry
                    |> set #activePayCalculationId (Just persisted.id)
                    |> set #legacyPayBackfillPending False
                    |> updateRecord
                frozenBefore <- loadApprovedTimesheetPayCalculation activeEntry >>= expectRight

                sourceRate <- query @AwardLevelBaseRate
                    |> filterWhere (#awardLevelId, unpackId level.id)
                    |> filterWhere (#employmentBasis, Permanent)
                    |> fetchOne
                _ <- sourceRate |> set #hourlyRate (sourceRate.hourlyRate + 100) |> updateRecord
                frozenComponents <- query @TimesheetPayEarningsComponent
                    |> filterWhere (#timesheetPayCalculationId, unpackId persisted.id)
                    |> orderBy #ordinal
                    |> fetch
                fmap (.exactAmount) frozenComponents `shouldBe` fmap (.exactAmount) components
                fmap (.ratePerUnit) frozenComponents `shouldBe` fmap (.ratePerUnit) components
                frozenAfter <- loadApprovedTimesheetPayCalculation activeEntry >>= expectRight
                frozenAfter `shouldBe` frozenBefore
                let component = fromMaybe (error "expected frozen component") (listToMaybe components)
                ( newRecord @TimesheetPayEarningsComponent
                    |> set #timesheetPayCalculationId (unpackId persisted.id)
                    |> set #ordinal 99
                    |> set #quantity component.quantity
                    |> set #unitType component.unitType
                    |> set #ratePerUnit component.ratePerUnit
                    |> set #exactAmount component.exactAmount
                    |> set #sourceCondition component.sourceCondition
                    |> set #calculationSource component.calculationSource
                    |> set #sourceRateIdentity component.sourceRateIdentity
                    |> createRecord
                    |> void
                    ) `shouldThrow` anyException

        it "persists imported pay as external_imported_pay_item without an Award book" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Immutable imported ledger"
                approver <- createUserRecord "imported-ledger-approver@example.com" "admin" True
                importedItem <- createImportedXeroPayItemRecord venue approver "Imported ledger item" "imported-ledger-item" 55
                staff <- createStaffRecord venue Nothing "Imported" "Worker"
                    >>= updateRecord . set #importedXeroPayItemId (Just importedItem.id)
                shiftType <- newRecord @ShiftType
                    |> set #venueId (unpackId venue.id)
                    |> set #name "Imported ledger shift"
                    |> set #sortOrder 0
                    |> set #overrideAwardLevelId Nothing
                    |> set #isActive True
                    |> createRecord
                entry <- createAdapterEntry venue staff shiftType (fromGregorian 2026 7 6)
                approvedAt <- getCurrentTime
                (staffVersion, shiftVersion) <- ensurePayVersionsForTimesheetApproval approver.id entry
                lockPayVersionsForApproval approver.id approvedAt staffVersion shiftVersion
                approvedEntry <- withLegacyPayBackfillFixture do
                    entry
                        |> set #isApproved True
                        |> set #legacyPayBackfillPending True
                        |> set #staffPayVersionId (Just (unpackId staffVersion.id))
                        |> set #shiftTypePayVersionId (Just (unpackId shiftVersion.id))
                        |> set #approvedAt (Just approvedAt)
                        |> set #approvedByUserId (Just (unpackId approver.id))
                        |> updateRecord

                persisted <- persistApprovedTimesheetPayCalculation approvedEntry >>= expectRight
                components <- query @TimesheetPayEarningsComponent
                    |> filterWhere (#timesheetPayCalculationId, unpackId persisted.id)
                    |> fetch

                persisted.calculationSource `shouldBe` "external_imported_pay_item"
                persisted.rateBookVersion `shouldBe` Nothing
                fmap (.calculationSource) components `shouldBe` ["external_imported_pay_item"]
                fmap (.sourceCondition) components `shouldBe` ["external_imported_pay_item:" <> tshow (unpackId importedItem.id)]

        it "backfills all-or-nothing and is idempotent" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Ledger backfill"
                approver <- createUserRecord "ledger-backfill@example.com" "admin" True
                importedItem <- createImportedXeroPayItemRecord venue approver "Backfill import" "backfill-import" 42
                invalidImportedItem <- newRecord @XeroImportedPayItem
                    |> set #venueId (unpackId venue.id)
                    |> set #xeroConnectionId importedItem.xeroConnectionId
                    |> set #xeroEarningsRateId "backfill-import-invalid"
                    |> set #name "Backfill invalid import"
                    |> set #earningsType "ordinarytimeearnings"
                    |> set #rateType "rateperunit"
                    |> set #typeOfUnits "hours"
                    |> set #ratePerUnit 42
                    |> set #importedByUserId (unpackId approver.id)
                    |> createRecord
                shiftType <- newRecord @ShiftType
                    |> set #venueId (unpackId venue.id)
                    |> set #name "Backfill shift"
                    |> set #sortOrder 0
                    |> set #overrideAwardLevelId Nothing
                    |> set #isActive True
                    |> createRecord
                validStaff <- createStaffRecord venue Nothing "Valid" "Backfill"
                    >>= updateRecord . set #importedXeroPayItemId (Just importedItem.id)
                invalidStaff <- createStaffRecord venue Nothing "Invalid" "Backfill"
                    >>= updateRecord . set #importedXeroPayItemId (Just invalidImportedItem.id)
                validEntry <- createAdapterEntry venue validStaff shiftType (fromGregorian 2026 7 6)
                invalidEntry <- createAdapterEntry venue invalidStaff shiftType (fromGregorian 2026 7 7)
                approvedAt <- getCurrentTime
                forM_ [validEntry, invalidEntry] \entry -> do
                    (staffVersion, shiftVersion) <- ensurePayVersionsForTimesheetApproval approver.id entry
                    lockPayVersionsForApproval approver.id approvedAt staffVersion shiftVersion
                    void $ withLegacyPayBackfillFixture do
                        entry
                            |> set #isApproved True
                            |> set #legacyPayBackfillPending True
                            |> set #staffPayVersionId (Just (unpackId staffVersion.id))
                            |> set #shiftTypePayVersionId (Just (unpackId shiftVersion.id))
                            |> set #approvedAt (Just approvedAt)
                            |> set #approvedByUserId (Just (unpackId approver.id))
                            |> updateRecord

                _ <- invalidImportedItem
                    |> set #archivedAt (Just approvedAt)
                    |> set #archivedByUserId (Just (unpackId approver.id))
                    |> set #archiveReason (Just "exercise atomic backfill")
                    |> updateRecord

                failed <- backfillApprovedTimesheetPayCalculations
                failed `shouldSatisfy` \case
                    Left [(entryId, _)] -> entryId == unpackId invalidEntry.id
                    _ -> False
                query @TimesheetPayCalculation |> fetchCount `shouldReturn` 0

                _ <- invalidImportedItem
                    |> set #archivedAt Nothing
                    |> set #archivedByUserId Nothing
                    |> set #archiveReason Nothing
                    |> updateRecord

                backfillApprovedTimesheetPayCalculations `shouldReturn` Right 2
                backfillApprovedTimesheetPayCalculations `shouldReturn` Right 0
                query @TimesheetPayCalculation |> fetchCount `shouldReturn` 2

        it "bulk-loads exact #264 provenance once and matches SQL only for approved parity scenarios" $ withContext do
            withCleanDb do
                fixture <- loadFwcMapdFixture
                _ <- storeCuratedMapdAwardData [fixture]
                venue <- createVenueWithConfig "Wage adapter parity"
                level1 <- query @AwardLevel
                    |> filterWhere (#classificationFixedId, 243)
                    |> fetchOne
                level2 <- query @AwardLevel
                    |> filterWhere (#classificationFixedId, 246)
                    |> fetchOne
                permanentStaff <- createStaffRecord venue Nothing "Permanent" "Parity"
                    >>= updateRecord
                        . set #employmentBasis Permanent
                        . set #defaultAwardLevelId (Just level1.id)
                casualStaff <- createStaffRecord venue Nothing "Casual" "Parity"
                    >>= updateRecord
                        . set #employmentBasis Casual
                        . set #defaultAwardLevelId (Just level1.id)
                importedBy <- createUserRecord "wage-adapter-import@example.com" "admin" True
                importedPayItem <- createImportedXeroPayItemRecord venue importedBy "Imported parity" "wage-adapter-import" 55
                importedStaff <- createStaffRecord venue Nothing "Imported" "Parity"
                    >>= updateRecord . set #importedXeroPayItemId (Just importedPayItem.id)
                shiftType <- createShiftTypeRecord venue level1 "Ordinary"
                overrideShiftType <- createShiftTypeRecord venue level2 "Level 2 override"
                importedShiftType <- newRecord @ShiftType
                    |> set #venueId (unpackId venue.id)
                    |> set #name "Imported flat rate"
                    |> set #sortOrder 0
                    |> set #overrideAwardLevelId Nothing
                    |> set #isActive True
                    |> createRecord
                ordinaryEntry <- createAdapterEntry venue permanentStaff shiftType (fromGregorian 2026 7 6)
                overrideEntry <- createAdapterEntry venue permanentStaff overrideShiftType (fromGregorian 2026 7 6)
                saturdayEntry <- createAdapterEntry venue casualStaff shiftType (fromGregorian 2026 7 11)
                holidayEntry <- createAdapterEntry venue permanentStaff shiftType (fromGregorian 2026 7 7)
                importedEntry <- createAdapterEntry venue importedStaff importedShiftType (fromGregorian 2026 7 11)
                _ <- newRecord @PublicHoliday
                    |> set #jurisdiction "VIC"
                    |> set #holidayDate (testWorkedOn holidayEntry)
                    |> set #name "Parity Holiday"
                    |> set #isRegional False
                    |> createRecord
                let entries = [ordinaryEntry, overrideEntry, saturdayEntry, holidayEntry, importedEntry]
                    requests = [WageEngineEntryRequest (unpackId entry.id) | entry <- entries]
                calls <- newIORef ([] :: [Text])
                databaseReads <- newIORef ([] :: [WageEngineDatabaseRead])
                capturedQueries <- newIORef ([] :: [Text])
                queryLogger <-
                    Log.newLogger
                        def
                            { Log.destination =
                                Log.Callback
                                    (\line -> modifyIORef' capturedQueries (<> [TextEncoding.decodeUtf8 (Log.fromLogStr line)]))
                                    (pure ())
                            }
                let originalModelContext = ?modelContext
                    observedLoad :: IO (Either [WageEngineAdapterError] (Map.Map UUID LoadedCalculationContext))
                    observedLoad =
                        let ?modelContext = originalModelContext { ModelSupport.logger = queryLogger }
                         in let databaseSource = databaseWageEngineBulkSourceWith (\databaseRead -> modifyIORef' databaseReads (<> [databaseRead]))
                                countedSource = countBulkSourceCalls calls databaseSource
                             in loadWageEngineContextsWith countedSource requests

                loaded <- observedLoad
                Log.cleanup queryLogger
                contexts <- expectRight loaded
                readIORef calls
                    `shouldReturn`
                        [ "entry-contexts"
                        , "imported-items"
                        , "award-levels"
                        , "base-rates"
                        , "penalty-rates"
                        , "time-additions"
                        , "holidays"
                        ]
                readIORef databaseReads >>= (`shouldSatisfy` satisfyBoundedDatabaseReads)
                queryLines <- filter (Text.isInfixOf "SELECT ") . Text.lines . Text.concat <$> readIORef capturedQueries
                queryLines `shouldSatisfy` boundedQueryLog

                fmap (.resolvedAwardClassification) (Map.lookup (unpackId overrideEntry.id) contexts >>= loadedAwardLevel)
                    `shouldBe` Just HospitalityLevel2
                (Map.lookup (unpackId importedEntry.id) contexts >>= (.loadedAwardRateContext)) `shouldBe` Nothing

                forM_ entries \entry -> do
                    sqlResult <- fetchTimesheetPay entry.id >>= expectRight
                    context <- maybe (expectationFailure "missing loaded context" >> fail "unreachable") pure (Map.lookup (unpackId entry.id) contexts)
                    let calculationInput = calculationInputFromLoadedContext context [fourHourInterval (testWorkedOn entry)] Nothing
                    haskellResult <- expectRight (calculateTimesheetPay calculationInput)

                    sum (map (.amount) haskellResult.earningsComponents)
                        `shouldBe` toRational sqlResult.totals.totalAmount
                    sum (map paidTimeDurationSeconds haskellResult.paidTimeSegments)
                        `shouldBe` toRational (sqlResult.totals.paidMinutes * 60)
                    haskellResult.earningsComponents `shouldSatisfy` all hasStableComponentSource

                let initialVersions = Map.mapMaybe (fmap validatedRateBookVersion . loadedRateBook) contexts
                _ <- storeCuratedMapdAwardData [fixture]
                refreshedContexts <- loadWageEngineContextsForEntries entries >>= expectRight
                let refreshedVersions = Map.mapMaybe (fmap validatedRateBookVersion . loadedRateBook) refreshedContexts
                refreshedVersions `shouldNotBe` initialVersions

                level1PermanentRate <- query @AwardLevelBaseRate
                    |> filterWhere (#awardLevelId, unpackId level1.id)
                    |> filterWhere (#employmentBasis, Permanent)
                    |> fetchOne
                _ <- level1PermanentRate
                    |> set #hourlyRate (level1PermanentRate.hourlyRate + 0.01)
                    |> updateRecord
                changedContexts <- loadWageEngineContextsForEntries entries >>= expectRight
                Map.mapMaybe (fmap validatedRateBookVersion . loadedRateBook) changedContexts
                    `shouldNotBe` refreshedVersions

boundedQueryLog :: [Text] -> Bool
boundedQueryLog queryLines =
    length queryLines == length expectedTables
        && all (\tableName -> length (filter (Text.isInfixOf (" FROM " <> tableName <> " ")) queryLines) == 1) expectedTables
        && scoped "award_levels" ["award_fixed_id =", "is_active ="]
        && scoped "award_level_base_rates" ["award_level_id = ANY", "operative_from <=", "operative_to >="]
        && scoped "award_level_penalty_rates" ["award_level_id = ANY", "penalty_kind = ANY", "operative_from <=", "operative_to >="]
        && scoped "award_time_penalty_allowances" ["award_fixed_id =", "penalty_kind = ANY", "operative_from <=", "operative_to >="]
        && scoped "public_holidays" ["jurisdiction =", "is_regional =", "holiday_date >=", "holiday_date <="]
  where
    expectedTables =
        [ "timesheet_entries"
        , "venue_config"
        , "staff"
        , "shift_types"
        , "xero_imported_pay_items"
        , "award_levels"
        , "award_level_base_rates"
        , "award_level_penalty_rates"
        , "award_time_penalty_allowances"
        , "public_holidays"
        ]
    scoped tableName requiredFragments =
        case filter (Text.isInfixOf (" FROM " <> tableName <> " ")) queryLines of
            [queryLine] -> all (`Text.isInfixOf` queryLine) requiredFragments
            _           -> False

satisfyBoundedDatabaseReads :: [WageEngineDatabaseRead] -> Bool
satisfyBoundedDatabaseReads = \case
    [ TimesheetEntriesRead 5
        , VenueConfigsRead 1
        , StaffRowsRead 3
        , ShiftTypeRowsRead 3
        , ImportedPayItemsRead 1
        , AwardLevelsRead
        , BaseRatesRead baseScope
        , PenaltyRatesRead penaltyScope
        , TimeAdditionsRead additionScope
        , StatewideHolidaysRead holidayFrom holidayTo
        ] ->
            baseScope == penaltyScope
                && penaltyScope == additionScope
                && length baseScope.scopedAwardLevelIds == 7
                && baseScope.scopedWorkedFrom == Just (fromGregorian 2026 7 6)
                && baseScope.scopedWorkedTo == Just (fromGregorian 2026 7 11)
                && holidayFrom == fromGregorian 2026 7 6
                && holidayTo == fromGregorian 2026 7 12
    _ -> False

rateForCalculation :: WageCalculation -> Maybe Scientific
rateForCalculation calculation =
    case calculation.earningsComponents of
        [component] -> Just component.ratePerUnit
        _           -> Nothing

loadedAwardLevel :: LoadedCalculationContext -> Maybe ResolvedAwardLevel
loadedAwardLevel context = (.awardRateLevel) <$> context.loadedAwardRateContext

loadedRateBook :: LoadedCalculationContext -> Maybe ValidatedRateBook
loadedRateBook context = (.awardRateBook) <$> context.loadedAwardRateContext

loadedRateBookOrFail :: LoadedCalculationContext -> ValidatedRateBook
loadedRateBookOrFail context =
    fromMaybe (error "expected loaded Award rate context") (loadedRateBook context)

hasStableComponentSource :: EarningsComponent -> Bool
hasStableComponentSource component =
    case (component.calculationSource, component.sourceRateIdentity) of
        (HospitalityAward, Just (RateSourceIdentity sourceId)) -> Text.isPrefixOf "bepis-projection:" sourceId && "/source:fwc_mapd_" `Text.isInfixOf` sourceId
        (ExternalImportedPayItem, Nothing) -> True
        _ -> False

testAwardLevelRows :: [ProjectedAwardLevelRow]
testAwardLevelRows =
    [ ProjectedAwardLevelRow
        (awardLevelUuid classification)
        9
        (awardClassificationFixedId classification)
        (tshow classification)
        True
    | classification <- supportedAwardClassifications
    ]

testEntryContext :: UUID -> Day -> EntryContextRow
testEntryContext entryId workedOn =
    EntryContextRow
        entryId
        workedOn
        "Australia/Melbourne"
        1
        "VIC"
        PermanentPartTime
        Nothing
        (Just (awardLevelUuid HospitalityLevel1))
        Nothing
        Nothing

projectionRowsForCandidates :: [RateBookCandidate] -> ([ProjectedBaseRateRow], [ProjectedPenaltyRateRow], [ProjectedTimeAdditionRow])
projectionRowsForCandidates = foldl' appendCandidate ([], [], [])
  where
    appendCandidate accumulated candidate = foldl' appendRate accumulated candidate.candidateRates
    appendRate (baseRows, penaltyRows, additionRows) rate =
        let RateSourceIdentity sourceIdentity = rate.candidateRateSourceIdentity
            period = rate.candidateRateEffectivePeriod
         in case rate.candidateRateKey of
                CandidateClassificationRate fixedId basis OrdinaryRate ->
                    ( ProjectedBaseRateRow (awardLevelUuidForFixedId fixedId) basis sourceIdentity rate.candidateRatePerUnit period.effectiveFrom period.effectiveTo : baseRows
                    , penaltyRows
                    , additionRows
                    )
                CandidateClassificationRate fixedId basis rateKind ->
                    ( baseRows
                    , ProjectedPenaltyRateRow (awardLevelUuidForFixedId fixedId) basis rateKind sourceIdentity rate.candidateRatePerUnit period.effectiveFrom period.effectiveTo : penaltyRows
                    , additionRows
                    )
                CandidateAwardAddition additionKind ->
                    ( baseRows
                    , penaltyRows
                    , ProjectedTimeAdditionRow 9 additionKind sourceIdentity rate.candidateRatePerUnit period.effectiveFrom period.effectiveTo : additionRows
                    )

awardLevelUuid :: AwardClassification -> UUID
awardLevelUuid = awardLevelUuidForFixedId . awardClassificationFixedId

awardLevelUuidForFixedId :: Int -> UUID
awardLevelUuidForFixedId fixedId = UUID.fromWords 0 0 0 (fromIntegral fixedId)

isMissingRateBookError :: WageEngineAdapterError -> Bool
isMissingRateBookError = \case
    InvalidProjectedRateBook _ (MissingRequiredRate _) -> True
    _ -> False

createAdapterEntry :: (?modelContext :: ModelContext) => Venue -> Staff -> ShiftType -> Day -> IO TimesheetEntry
createAdapterEntry venue staff shiftType workedOn =
    createTimesheetEntryRecord venue staff workedOn
        >>= updateRecord
            . set #shiftTypeId (unpackId shiftType.id)
            . setTestStartTime (TimeOfDay 9 0 0)
            . setTestEndTime (TimeOfDay 13 0 0)

fourHourInterval :: Day -> AwardSegment
fourHourInterval localDate =
    awardSegmentBetween localDate (TimeOfDay 9 0 0) localDate (TimeOfDay 13 0 0)

countBulkSourceCalls :: IORef [Text] -> WageEngineBulkSource IO -> WageEngineBulkSource IO
countBulkSourceCalls calls source =
    WageEngineBulkSource
        { fetchEntryContextRows = \entryIds -> count "entry-contexts" (source.fetchEntryContextRows entryIds)
        , fetchImportedPayItemRows = \itemIds -> count "imported-items" (source.fetchImportedPayItemRows itemIds)
        , fetchProjectedAwardLevelRows = count "award-levels" source.fetchProjectedAwardLevelRows
        , fetchProjectedBaseRateRows = \scope -> count "base-rates" (source.fetchProjectedBaseRateRows scope)
        , fetchProjectedPenaltyRateRows = \scope -> count "penalty-rates" (source.fetchProjectedPenaltyRateRows scope)
        , fetchProjectedTimeAdditionRows = \scope -> count "time-additions" (source.fetchProjectedTimeAdditionRows scope)
        , fetchStatewideHolidayRows = \requests -> count "holidays" (source.fetchStatewideHolidayRows requests)
        }
  where
    count :: Text -> IO value -> IO value
    count name action = modifyIORef' calls (<> [name]) >> action

expectRight :: Show error => Either error value -> IO value
expectRight = \case
    Left failure -> expectationFailure (Text.unpack (tshow failure)) >> fail "unreachable"
    Right value  -> pure value

uuid :: String -> UUID
uuid raw = fromMaybe (Prelude.error ("invalid UUID fixture " <> raw)) (UUID.fromString raw)
