module Test.XeroTimesheetPreviewSpec where

import Application.Fixture.PayrollFixtures (TimesheetFixtureValues,
                                            createAndApproveEntry)
import Application.Helper.Pay
import Application.Helper.TimesheetPayLedger (loadApprovedTimesheetPayCalculation)
import Application.Helper.Xero
import Application.Helper.XeroAdminTypes
import Application.Helper.XeroPayItems
import Application.Helper.XeroTimesheetReadiness hiding
                                                 (validateXeroTimesheetReadiness)
import qualified Application.Helper.XeroTimesheetReadiness as Readiness
import Application.WageEngine (EarningsComponent (..), WageCalculation (..))
import Application.Xero.Timesheets.Preview
import Control.Exception (SomeException, try)
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.KeyMap as KeyMap
import Data.Either (isLeft)
import qualified Data.Map.Strict as Map
import Data.Scientific (Scientific)
import qualified Data.Text as Text
import Data.Time.Calendar (Day, addDays, diffDays, fromGregorian)
import Data.Time.Clock (addUTCTime)
import Data.Time.LocalTime (TimeOfDay (..))
import Generated.Types
import IHP.ControllerPrelude
import IHP.Test.Mocking
import Test.Hspec
import Test.Support
import Test.Support.XeroTimesheet

validateXeroTimesheetReadiness :: (?modelContext :: ModelContext) => XeroTimesheetReadinessRequest -> IO XeroTimesheetReadiness
validateXeroTimesheetReadiness request =
    Readiness.validateXeroTimesheetReadiness request >>= either (\err -> expectationFailure (cs (show err)) >> fail "expected readiness") pure

tests :: Spec
tests =
    aroundAll withDatabaseTestContext do
        describe "Xero timesheet preview payloads" do
            it "builds weekly daily units in period order and zero-fills missing days" $ withContext do
                withCleanDb do
                    fixture <- createPreviewFixture "weekly" [EntrySpec 0 fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 13 0 0)]
                    fixture.staffB `shouldSatisfy` isNothing
                    previewRun <- buildFixturePreview fixture

                    let line = onlyPreviewLine previewRun
                    line.previewLineNumberOfUnits `shouldBe` [4, 0, 0, 0, 0, 0, 0]

            it "allocates every final-day overnight component to its Operational-day position" $ withContext do
                withCleanDb do
                    fixture <-
                        createPreviewFixture
                            "weekly"
                            [ EntrySpecWithBreak
                                6
                                fixtureStaffA
                                (TimeOfDay 15 0 0)
                                (TimeOfDay 1 14 0)
                                (TimeOfDay 20 30 0)
                                (TimeOfDay 21 0 0)
                            ]
                    previewRun <- buildFixturePreview fixture

                    let lines = (onlyPreview previewRun).previewLines
                        lineFor keyPart =
                            case find (Text.isInfixOf keyPart . (.previewLineLocalBucketKey)) lines of
                                Just line -> line
                                Nothing   -> error ("expected Xero line containing " <> cs keyPart)
                    (lineFor "penalty:sunday_penalty").previewLineNumberOfUnits `shouldBe` replicate 6 0 <> [8.5]
                    (lineFor ":ordinary:").previewLineNumberOfUnits `shouldBe` replicate 6 0 <> [1.233333333333]
                    (lineFor "penalty:late_night_after_midnight").previewLineNumberOfUnits `shouldBe` replicate 6 0 <> [2]
                    map (.previewLineLocalBucketKey) lines `shouldSatisfy` all (not . Text.isInfixOf "penalty:missed_meal_break_addition")

            it "keeps a mid-period overnight shift in its Operational-day Xero position" $ withContext do
                withCleanDb do
                    fixture <- createPreviewFixture "weekly" [EntrySpec 2 fixtureStaffA (TimeOfDay 22 0 0) (TimeOfDay 2 0 0)]
                    previewRun <- buildFixturePreview fixture

                    let lines = (onlyPreview previewRun).previewLines
                    lines `shouldSatisfy` all (\line -> take 2 line.previewLineNumberOfUnits == [0, 0])
                    lines `shouldSatisfy` all (\line -> drop 3 line.previewLineNumberOfUnits == replicate 4 0)
                    lines `shouldSatisfy` all (\line -> line.previewLineNumberOfUnits !! 2 > 0)

            it "allocates a final-day cross-midnight shift in full to its Operational-day position" $ withContext do
                withCleanDb do
                    fixture <- createPreviewFixtureWithRosterStart 4 "weekly" [EntrySpec 6 fixtureStaffA (TimeOfDay 22 0 0) (TimeOfDay 2 0 0)]
                    previewRun <- buildFixturePreview fixture

                    let lines = (onlyPreview previewRun).previewLines
                        unitsAt index = sum [line.previewLineNumberOfUnits !! index | line <- lines]
                    payCalculation <- query @TimesheetPayCalculation |> filterWhere (#timesheetEntryId, unpackId (fromMaybe (error "expected entry") (head fixture.entries)).id) |> fetchOne
                    payCalculation.rosterWindowStart `shouldNotBe` fixture.periodStart
                    payCalculation.rosterWeekStartsOn `shouldBe` 4
                    map unitsAt [0 .. 5] `shouldBe` replicate 6 0
                    unitsAt 6 `shouldBe` 6

            it "preserves minute-level hourly Xero quantities" $ withContext do
                withCleanDb do
                    fixture <- createPreviewFixture "weekly" [EntrySpec 0 fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 13 0 30)]
                    previewRun <- buildFixturePreview fixture

                    let line = onlyPreviewLine previewRun
                    line.previewLineNumberOfUnits `shouldBe` [4.008333333333, 0, 0, 0, 0, 0, 0]

            it "aggregates exact components before serializing the Xero bucket" $ withContext do
                withCleanDb do
                    fixture <-
                        createPreviewFixture
                            "weekly"
                            [ EntrySpec 0 fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 9 0 30)
                            , EntrySpec 0 fixtureStaffA (TimeOfDay 9 1 0) (TimeOfDay 9 1 30)
                            ]
                    previewRun <- buildFixturePreview fixture

                    let line = onlyPreviewLine previewRun
                    line.previewLineNumberOfUnits `shouldBe` [0.016666666666, 0, 0, 0, 0, 0, 0]

            it "uses the approval-pinned source rather than a newer overlapping rate in preview bucket keys" $ withContext do
                withCleanDb do
                    fixture <- createPreviewFixture "weekly" [EntrySpec 0 fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 13 0 0)]
                    input <- fetchPreviewInput fixture.request fixture.connection
                    let firstEntry = fromMaybe (error "expected preview entry") (head fixture.entries)
                    payLevelUuid <- case do
                        staffVersionId <- firstEntry.staffPayVersionId
                        shiftVersionId <- firstEntry.shiftTypePayVersionId
                        staffVersion <- find (\version -> unpackId version.id == staffVersionId) input.previewStaffPayVersions
                        shiftVersion <- find (\version -> unpackId version.id == shiftVersionId) input.previewShiftTypePayVersions
                        shiftVersion.overrideAwardLevelId <|> staffVersion.defaultAwardLevelId of
                            Just value -> pure value
                            Nothing -> expectationFailure "expected one preview pay level" >> error "unreachable"
                    staff <-
                        case find (\candidate -> unpackId candidate.id == firstEntry.staffId) input.previewStaff of
                            Just value -> pure value
                            Nothing -> expectationFailure "expected preview staff" >> error "unreachable"
                    awardLevel <-
                        case find (\candidate -> unpackId candidate.id == payLevelUuid) input.previewAwardLevels of
                            Just value -> pure value
                            Nothing -> expectationFailure "expected preview award level" >> error "unreachable"
                    baseRate <- query @AwardLevelBaseRate
                        |> filterWhere (#awardLevelId, payLevelUuid)
                        |> filterWhere (#employmentBasis, staff.employmentBasis)
                        |> fetchOne
                    mapping <-
                        case find (Text.isInfixOf ":ordinary:source:" . (.localBucketKey)) input.previewEarningsMappings of
                            Just value -> pure value
                            Nothing -> expectationFailure "expected ordinary earnings mapping" >> error "unreachable"
                    sealedRateBoundary <- case do
                        calculation <- (Map.lookup (unpackId firstEntry.id) input.previewCalculationsByEntryId :: Maybe WageCalculation)
                        component <- (head calculation.earningsComponents :: Maybe EarningsComponent)
                        component.publishedRateBoundaryDate of
                            Just value -> pure value
                            Nothing -> expectationFailure "expected sealed rate boundary" >> error "unreachable"
                    let sourceIdentity =
                            "bepis-projection:award_level_base_rates:"
                                <> tshow (unpackId baseRate.id)
                                <> "/source:fwc_mapd_pay_rates:"
                                <> tshow baseRate.fwcMapdPayRateId
                        expectedKey =
                            "xero:pay-item:classification:"
                                <> tshow awardLevel.classificationFixedId
                                <> ":basis:"
                                <> inputValue staff.employmentBasis
                                <> ":effective:"
                                <> tshow sealedRateBoundary
                                <> ":ordinary:source:"
                                <> sourceIdentity
                                <> ":rate:"
                                <> tshow baseRate.hourlyRate
                        preparedInput =
                            input
                                { previewPayCalculationsByEntryId = fmap (withSealedRosterWeekStartsOn 1) input.previewPayCalculationsByEntryId
                                , previewEarningsMappings = [mapping |> set #localBucketKey expectedKey]
                                , previewPayItemRequirements = []
                                }
                    _ <- baseRate |> set #operativeFrom (Just (fromGregorian 2026 7 1)) |> set #hourlyRate 40 |> updateRecord

                    case buildXeroTimesheetPreviewRun preparedInput of
                        Left err -> expectationFailure (cs err)
                        Right previewRun -> (onlyPreviewLine previewRun).previewLineLocalBucketKey `shouldBe` expectedKey

            it "late-binds components approved before Xero routing without changing sealed wage facts" $ withContext do
                withCleanDb do
                    fixture <- createLateBindingPreviewFixture "weekly" [EntrySpec 0 fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 13 0 0)]
                    sealedBefore <- query @TimesheetPayEarningsComponent
                        |> filterWhereIn (#timesheetPayCalculationId, mapMaybe (fmap unpackId . (.activePayCalculationId)) fixture.entries)
                        |> orderBy #ordinal
                        |> fetch
                    sealedBefore `shouldSatisfy` all (isNothing . (.xeroLocalBucketKey))
                    sealedBefore `shouldSatisfy` all (isNothing . (.xeroEarningsRateId))

                    preparedInput <- fetchPreparedPreviewInput fixture.request fixture.connection >>= \case
                        Left message -> expectationFailure (cs message) >> error "unreachable"
                        Right value -> pure value
                    previewRun <- case buildXeroTimesheetPreviewRun preparedInput of
                        Left message -> expectationFailure (cs message) >> error "unreachable"
                        Right value -> pure value
                    previewRun.previewRunTimesheets `shouldSatisfy` (not . null)

                    bindings <- query @TimesheetPayComponentXeroBinding
                        |> filterWhere (#xeroConnectionId, unpackId fixture.connection.id)
                        |> orderBy #resolvedAt
                        |> fetch
                    length bindings `shouldBe` length (filter ((> 0) . (.quantity)) sealedBefore)
                    bindings `shouldSatisfy` all ((== "verified_mapping") . (.resolutionSource))
                    sealedAfter <- query @TimesheetPayEarningsComponent
                        |> filterWhereIn (#id, map (.id) sealedBefore)
                        |> orderBy #ordinal
                        |> fetch
                    map (\component -> (component.xeroLocalBucketKey, component.xeroEarningsRateId)) sealedAfter
                        `shouldBe` map (\component -> (component.xeroLocalBucketKey, component.xeroEarningsRateId)) sealedBefore

                    _ <- fetchPreparedPreviewInput fixture.request fixture.connection
                    persistedAgain <- query @TimesheetPayComponentXeroBinding
                        |> filterWhere (#xeroConnectionId, unpackId fixture.connection.id)
                        |> fetch
                    map (.id) persistedAgain `shouldMatchList` map (.id) bindings

                    mappingRows <- query @XeroEarningsRateMapping
                        |> filterWhere (#xeroConnectionId, unpackId fixture.connection.id)
                        |> fetch
                    forM_ mappingRows \mapping ->
                        mapping |> set #xeroEarningsRateId (Just "changed-after-late-binding") |> updateRecord >>= const (pure ())
                    routedAgain <- fetchPreparedPreviewInput fixture.request fixture.connection >>= \case
                        Left message -> expectationFailure (cs message) >> error "unreachable"
                        Right value -> pure value
                    rebuilt <- case buildXeroTimesheetPreviewRun routedAgain of
                        Left message -> expectationFailure (cs message) >> error "unreachable"
                        Right value -> pure value
                    map (.previewLineXeroEarningsRateId) (onlyPreview rebuilt).previewLines
                        `shouldSatisfy` all (`elem` map (.xeroEarningsRateId) bindings)

                    let firstBinding = fromMaybe (error "expected a late Xero binding") (head bindings)
                    updateAttempt :: Either SomeException TimesheetPayComponentXeroBinding <-
                        try (firstBinding |> set #xeroEarningsRateId "forbidden-reroute" |> updateRecord)
                    updateAttempt `shouldSatisfy` isLeft

            it "keeps approved Xero bucket mappings after the venue start day changes" $ withContext do
                withCleanDb do
                    fixture <- createPreviewFixture "weekly" [EntrySpec 0 fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 13 0 0)]
                    originalPreview <- buildFixturePreview fixture
                    sealedComponents <- query @TimesheetPayEarningsComponent
                        |> filterWhereIn (#timesheetPayCalculationId, mapMaybe (fmap unpackId . (.activePayCalculationId)) fixture.entries)
                        |> fetch
                    sealedComponents `shouldSatisfy` all (isJust . (.xeroLocalBucketKey))
                    sealedComponents `shouldSatisfy` all (isJust . (.xeroEarningsRateId))
                    venueConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId fixture.venue.id) |> fetchOne
                    _ <- venueConfig |> set #rosterWeekStartsOn 4 |> updateRecord
                    mappings <- query @XeroEarningsRateMapping |> filterWhere (#xeroConnectionId, unpackId fixture.connection.id) |> fetch
                    forM_ mappings \mapping ->
                        mapping |> set #xeroEarningsRateId (Just "changed-after-approval") |> updateRecord >>= const (pure ())

                    changedInput <- fetchPreviewInput fixture.request fixture.connection
                    changedPreview <- case buildXeroTimesheetPreviewRun changedInput of
                        Left err -> expectationFailure (cs err) >> error "unreachable"
                        Right value -> pure value

                    map (.previewLineLocalBucketKey) (onlyPreview originalPreview).previewLines
                        `shouldBe` map (.previewLineLocalBucketKey) (onlyPreview changedPreview).previewLines
                    map (.previewLineXeroEarningsRateId) (onlyPreview originalPreview).previewLines
                        `shouldBe` map (.previewLineXeroEarningsRateId) (onlyPreview changedPreview).previewLines
                    map (.previewLineXeroEarningsRateId) (onlyPreview changedPreview).previewLines
                        `shouldNotSatisfy` elem "changed-after-approval"

            it "builds fortnightly daily units in selected payroll-calendar order" $ withContext do
                withCleanDb do
                    fixture <- createPreviewFixture "fortnightly" [EntrySpec 13 fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 13 0 0)]
                    previewRun <- buildFixturePreview fixture

                    let line = onlyPreviewLine previewRun
                    length line.previewLineNumberOfUnits `shouldBe` 14
                    line.previewLineNumberOfUnits `shouldBe` replicate 13 0 <> [4]

            it "aggregates multiple entries for one employee and EarningsRateID into one line" $ withContext do
                withCleanDb do
                    fixture <-
                        createPreviewFixture
                            "weekly"
                            [ EntrySpec 0 fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 12 0 0)
                            , EntrySpec 0 fixtureStaffA (TimeOfDay 13 0 0) (TimeOfDay 17 0 0)
                            ]
                    previewRun <- buildFixturePreview fixture

                    previewRun.previewRunTimesheets `shouldSatisfy` ((== 1) . length)
                    let line = onlyPreviewLine previewRun
                    line.previewLineNumberOfUnits `shouldBe` [7, 0, 0, 0, 0, 0, 0]
                    length line.previewLineSourceEntryIds `shouldBe` 2

            it "builds one timesheet object per Xero employee" $ withContext do
                withCleanDb do
                    fixture <-
                        createPreviewFixture
                            "weekly"
                            [ EntrySpec 0 fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 13 0 0)
                            , EntrySpec 1 fixtureStaffB (TimeOfDay 9 0 0) (TimeOfDay 12 0 0)
                            ]
                    previewRun <- buildFixturePreview fixture

                    map (.previewXeroEmployeeId) previewRun.previewRunTimesheets `shouldBe` ["employee-a", "employee-b"]
                    previewRun.previewRunRequestArrayJson `shouldSatisfy` isArrayOfLength 2

            it "filters preview input by the selected synced Xero employee payroll calendar" $ withContext do
                withCleanDb do
                    fixture <-
                        createPreviewFixture
                            "weekly"
                            [ EntrySpec 0 fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 13 0 0)
                            , EntrySpec 1 fixtureStaffB (TimeOfDay 9 0 0) (TimeOfDay 12 0 0)
                            ]
                    overwritePreviewEmployeeRawCalendar fixture "employee-b" "calendar-other"

                    input <- fetchPreviewInput fixture.request fixture.connection
                    case buildXeroTimesheetPreviewRun input of
                        Left err -> expectationFailure (cs err)
                        Right previewRun -> do
                            let previews :: [XeroTimesheetPreview]
                                previews = previewRun.previewRunTimesheets
                                firstEntry :: TimesheetEntry
                                firstEntry = fromMaybe (error "expected first entry") (head fixture.entries)
                            map (.previewXeroEmployeeId) previews `shouldBe` ["employee-a"]
                            case previews of
                                [timesheetPreview] -> previewSourceEntryIds timesheetPreview `shouldBe` [unpackId firstEntry.id]
                                _ -> expectationFailure "expected one preview"

            it "excludes employees without a payroll calendar from selected-calendar preview input" $ withContext do
                withCleanDb do
                    fixture <-
                        createPreviewFixture
                            "weekly"
                            [ EntrySpec 0 fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 13 0 0)
                            , EntrySpec 1 fixtureStaffB (TimeOfDay 9 0 0) (TimeOfDay 12 0 0)
                            ]
                    employeeB <-
                        query @XeroEmployee
                            |> filterWhere (#xeroConnectionId, unpackId fixture.connection.id)
                            |> filterWhere (#xeroEmployeeId, "employee-b" :: Text)
                            |> fetchOne
                    _ <-
                        employeeB
                            |> set #rawPayload (Aeson.object ["EmployeeID" Aeson..= employeeB.xeroEmployeeId])
                            |> updateRecord

                    input <- fetchPreviewInput fixture.request fixture.connection

                    map (.staffId) input.previewTimesheetEntries `shouldBe` [unpackId fixture.staffA.id]

            it "keeps source entry ids and pay version ids in metadata but omits TrackingItemID from Xero request JSON" $ withContext do
                withCleanDb do
                    fixture <- createPreviewFixture "weekly" [EntrySpec 0 fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 13 0 0)]
                    previewRun <- buildFixturePreview fixture

                    let preview = onlyPreview previewRun
                    preview.previewSourceEntryIds `shouldBe` map (unpackId . (.id)) fixture.entries
                    preview.previewStaffPayVersionIds `shouldBe` sort (nub (mapMaybe (.staffPayVersionId) fixture.entries))
                    preview.previewShiftPayVersionIds `shouldBe` sort (nub (mapMaybe (.shiftTypePayVersionId) fixture.entries))
                    preview.previewRequestObjectJson `shouldSatisfy` not . jsonContainsKey "TrackingItemID"

            it "marks matching Xero draft timesheets as update previews" $ withContext do
                withCleanDb do
                    fixture <- createPreviewFixture "weekly" [EntrySpec 0 fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 13 0 0)]
                    let remote = remoteTimesheetRef "remote-timesheet-a" "employee-a" fixture.periodStart fixture.periodEnd (Just "DRAFT")
                    previewRun <- buildFixturePreviewWithRemotes fixture [remote]

                    let preview = onlyPreview previewRun
                    preview.previewExistingXeroTimesheetId `shouldBe` Just "remote-timesheet-a"
                    preview.previewRequestObjectJson `shouldSatisfy` jsonContainsKey "TimesheetID"
                    xeroTimesheetPreviewRunJson previewRun `shouldSatisfy` jsonContainsKey "operation"

            it "uses matched managed pay item requirements when explicit earnings mappings are absent" $ withContext do
                withCleanDb do
                    fixture <- createPreviewFixture "weekly" [EntrySpec 0 fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 13 0 0)]
                    mappings <- query @XeroEarningsRateMapping |> filterWhere (#xeroConnectionId, unpackId fixture.connection.id) |> fetch
                    forM_ mappings \mapping ->
                        mapping |> set #mappingStatus XeroEarningsRateMappingStatusEnumStale |> updateRecord >>= const (pure ())

                    previewRun <- buildFixturePreview fixture

                    (onlyPreviewLine previewRun).previewLineXeroEarningsRateId `shouldSatisfy` Text.isPrefixOf "earnings-"

            it "maps the separate missed meal break 50% component to its managed pay item bucket" $ withContext do
                withCleanDb do
                    fixture <- createPreviewFixture "weekly" [EntrySpec 0 fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 17 0 0)]

                    previewRun <- buildFixturePreview fixture

                    let lines = (onlyPreview previewRun).previewLines
                    map (.previewLineLocalBucketKey) lines `shouldSatisfy` any (Text.isInfixOf "penalty:missed_meal_break_addition")
                    delayedLine <-
                        case find (Text.isInfixOf "penalty:missed_meal_break_addition" . (.previewLineLocalBucketKey)) lines of
                            Just line -> pure line
                            Nothing   -> expectationFailure "expected a missed meal break preview line" >> error "unreachable"
                    delayedLine.previewLineNumberOfUnits `shouldBe` [2, 0, 0, 0, 0, 0, 0]

            it "persists preview payload, readiness snapshot, and duplicate-check snapshot without posting to Xero" $ withContext do
                withCleanDb do
                    fixture <- createPreviewFixture "weekly" [EntrySpec 0 fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 13 0 0)]
                    readiness <- validateXeroTimesheetReadiness fixture.request
                    let duplicateCheck = Aeson.object ["remoteTimesheets" Aeson..= ([] :: [Aeson.Value])]

                    result <- createPersistedXeroTimesheetPreview fixture.owner.id fixture.request readiness duplicateCheck

                    case result of
                        Left err -> expectationFailure (cs err)
                        Right run -> do
                            run.status `shouldBe` XeroSubmissionRunStatusEnumPreviewed
                            run.readinessSnapshotJson `shouldSatisfy` jsonContainsKey "ready"
                            run.xeroDuplicateCheckJson `shouldBe` duplicateCheck
                            run.previewPayloadJson `shouldSatisfy` jsonContainsKey "requestPayload"
                            run.selectedPayrollCalendarId `shouldBe` Just "calendar-preview"
                            run.selectedPeriodKey `shouldBe` fixture.request.readinessSelectedPeriodKey

            it "previews a historical selected Xero period without a global calendar selection" $ withContext do
                withCleanDb do
                    let historicalStart = fromGregorian 2026 1 5
                    fixture <- createPreviewFixtureAtPeriod "weekly" historicalStart [EntrySpec 0 fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 13 0 0)]
                    readiness <- validateXeroTimesheetReadiness fixture.request
                    result <- createPersistedXeroTimesheetPreview fixture.owner.id fixture.request readiness (Aeson.object [])

                    case result of
                        Left err -> expectationFailure (cs err)
                        Right run -> do
                            run.payPeriodStart `shouldBe` historicalStart
                            run.payPeriodEnd `shouldBe` addDays 6 historicalStart
                            run.selectedPayrollCalendarId `shouldBe` Just "calendar-preview"
                            run.previewPayloadJson `shouldSatisfy` jsonContainsKey "requestPayload"
