module Test.FwcMapdSyncSpec where

import Application.FwcMapd.Client (MapdPageMeta (..), MapdResultsPage (..),
                                   assembleCanonicalClassificationValues,
                                   assemblePagedResults)
import Application.FwcMapd.Error (MapdSyncError (MapdSnapshotInvalid))
import Application.FwcMapd.Job (fwcMapdRefreshJobKind,
                                performFwcMapdRefreshJobWith)
import qualified Application.FwcMapd.Payload as MapdPayload
import Application.FwcMapd.Sync
import qualified Application.FwcMapd.Sync as FwcMapd
import Application.Helper.FwcMapd
import Application.WageSourceAlert.Job (wageSourceHealthCheckJobKind)
import Application.WageSourcePolicy (fwcMaximumAge)
import qualified Control.Exception as Exception
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Types as AesonTypes
import qualified Data.ByteString.Lazy.Char8 as LByteString
import Data.Either (isLeft)
import Data.Scientific (Scientific)
import qualified Data.Text as Text
import Data.Time.Calendar (fromGregorian)
import Data.Time.Clock (addUTCTime)
import Generated.Enums (AwardPenaltyKindEnum (..))
import Generated.Types
import IHP.ControllerPrelude
import IHP.Prelude
import IHP.Test.Mocking
import Test.Hspec
import Test.Support
import Test.Support.FwcMapdFixture (loadFwcMapdFixture)

pureTests :: Spec
pureTests = do
    describe "FWC MAPD sync curation" do
        it "keeps only latest active adult hourly bar/pub rates and referenced classifications" do
            let asOfDate = fromGregorian 2026 4 24
                award2024 = awardPayload 2024
                award2025 = awardPayload 2025
                level1Classification = classificationPayload 101 2025 "Level 1" (Just "Food and beverage attendant grade 1")
                casinoClassification = classificationPayload 102 2025 "Level 1" (Just "Casino electronic gaming employee grade 1")
                casinoIntroClassification = classificationPayloadWithClause 106 2025 "Introductory level" Nothing (Just "Casino Gaming Employees")
                oldClassification = classificationPayload 103 2024 "Level 2" (Just "Food and beverage attendant grade 2")
                level1Rate =
                    payRatePayloadWithBasePayRateId "BR1"
                        (payRatePayload
                            101
                            2025
                            "AD"
                            "Level 1"
                            (Just "Food and beverage attendant grade 1")
                            Nothing
                            (Just "Weekly")
                            (Just 24.95)
                            (Just "Hourly"))
                juniorRate =
                    payRatePayload
                        104
                        2025
                        "JN"
                        "19 years of age"
                        (Just "Introductory level")
                        (Just 21.21)
                        (Just "Hourly")
                        Nothing
                        Nothing
                casinoRate =
                    payRatePayloadWithBasePayRateId "BR2"
                        (payRatePayload
                            102
                            2025
                            "AD"
                            "Level 1"
                            (Just "Casino electronic gaming employee grade 1")
                            Nothing
                            (Just "Weekly")
                            (Just 26.38)
                            (Just "Hourly"))
                weeklyOnlyRate =
                    payRatePayload
                        105
                        2025
                        "AD"
                        "Managerial staff"
                        (Just "Food and beverage supervisor")
                        (Just 60732)
                        (Just "Annual")
                        Nothing
                        Nothing
                casinoIntroRate =
                    payRatePayload
                        106
                        2025
                        "AD"
                        "Introductory level"
                        Nothing
                        Nothing
                        (Just "Weekly")
                        (Just 26.38)
                        (Just "Hourly")
                oldRate =
                    payRatePayload
                        103
                        2024
                        "AD"
                        "Level 2"
                        (Just "Food and beverage attendant grade 2")
                        Nothing
                        (Just "Weekly")
                        (Just 23.55)
                        (Just "Hourly")
                level1Penalty = (penaltyRatePayload 101 2025 "Level 1" (Just "Food and beverage attendant grade 1") "Saturday penalty" (Just 37.50)) { penaltyBasePayRateId = Just "BR1" }
                casinoPenalty = (penaltyRatePayload 102 2025 "Level 1" (Just "Casino electronic gaming employee grade 1") "Saturday penalty" (Just 39.57)) { penaltyBasePayRateId = Just "BR2" }

                (_, awards, classifications, payRates, penalties) =
                    curateAwardData
                        barVenueCurationProfile
                        asOfDate
                        ( 9
                        , [(award2024, Aeson.Null), (award2025, Aeson.Null)]
                        , [(level1Classification, Aeson.Null), (casinoClassification, Aeson.Null), (casinoIntroClassification, Aeson.Null), (oldClassification, Aeson.Null)]
                        , [(level1Rate, Aeson.Null), (juniorRate, Aeson.Null), (casinoRate, Aeson.Null), (weeklyOnlyRate, Aeson.Null), (casinoIntroRate, Aeson.Null), (oldRate, Aeson.Null)]
                        , [(level1Penalty, Aeson.Null), (casinoPenalty, Aeson.Null)]
                        )

            map (awardPayloadPublishedYear . fst) awards `shouldBe` [Just 2025]
            map (specClassificationPayloadFixedId . fst) classifications `shouldBe` [101]
            map (specPayRatePayloadClassificationFixedId . fst) payRates `shouldBe` [Just 101]
            map (specPenaltyRatePayloadClassificationFixedId . fst) penalties `shouldBe` [Just 101]

        it "assembles canonical classification responses deterministically when paging omits Level 3" do
            fixture <- loadFwcMapdFixture
            let allClassifications = map snd fixture.curatedClassifications
                withoutLevel3 = filter ((/= Just 257) . classificationFixedIdFromValue) allClassifications
                directLevel3 = filter ((== Just 257) . classificationFixedIdFromValue) allClassifications

            assembleCanonicalClassificationValues expectedCoreClassificationFixedIds (reverse withoutLevel3) directLevel3
                `shouldBe` Right allClassifications

        it "rejects inconsistent paging metadata instead of accepting repeated pages" do
            let firstPage = MapdResultsPage [Aeson.String "first"] (MapdPageMeta 2 1)
                repeatedFirstPage = MapdResultsPage [Aeson.String "first again"] (MapdPageMeta 2 1)

            assemblePagedResults [firstPage, repeatedFirstPage]
                `shouldBe` Left "FWC MAPD paging inconsistent: requested page 2 reported current_page 1"

        it "normalizes identical source duplicates and rejects conflicting duplicates independent of response order" do
            fixture <- loadFwcMapdFixture
            let Just duplicate = head fixture.curatedPenaltyRates
                conflictingPayload = (fst duplicate) { MapdPayload.penaltyCalculatedValue = Just 999.99 }
                conflicting = (conflictingPayload, snd duplicate)
                withIdenticalDuplicate = fixture { curatedPenaltyRates = duplicate : fixture.curatedPenaltyRates }
                withConflict = fixture { curatedPenaltyRates = conflicting : fixture.curatedPenaltyRates }

            fmap (length . (.validatedPenaltyRates)) (validateMapdSnapshot withIdenticalDuplicate) `shouldBe` Right 49
            validateMapdSnapshot withConflict `shouldSatisfy` isLeft
            validateMapdSnapshot (withConflict { curatedPenaltyRates = reverse withConflict.curatedPenaltyRates })
                `shouldBe` validateMapdSnapshot withConflict

        it "requires award provenance and a permanent ordinary source rate" do
            fixture <- loadFwcMapdFixture
            let Just firstPayRate = head fixture.curatedPayRates
                casualOnlyPayRate = ((fst firstPayRate) { MapdPayload.calculatedRateType = Just "Casual Hourly" }, snd firstPayRate)
                casualOnlyCandidate = fixture { curatedPayRates = casualOnlyPayRate : drop 1 fixture.curatedPayRates }

            validateMapdSnapshot (fixture { curatedAwards = [] })
                `shouldBe` Left "FWC MAPD snapshot incomplete: missing award provenance for award_fixed_id 9"
            validateMapdSnapshot casualOnlyCandidate
                `shouldBe` Left "FWC MAPD snapshot incomplete: missing permanent ordinary/base rate for classification 242"

        it "requires clause 29.2 commenced-hour allowance provenance" do
            fixture <- loadFwcMapdFixture
            let Just firstAllowance = head fixture.curatedWageAllowances
                wrongClauseAllowance = ((fst firstAllowance) { MapdPayload.wageAllowanceClauses = Just "28" }, snd firstAllowance)
                wrongClauseCandidate = fixture { curatedWageAllowances = wrongClauseAllowance : drop 1 fixture.curatedWageAllowances }

            validateMapdSnapshot wrongClauseCandidate
                `shouldBe` Left "FWC MAPD snapshot inconsistent: EveningAfter7Pm addition is not owned by clause 29.2"

        it "rejects an incomplete candidate with a deterministic actionable diagnostic" do
            fixture <- loadFwcMapdFixture
            let withoutLevel3 =
                    fixture
                        { curatedClassifications = filter ((/= 257) . specClassificationPayloadFixedId . fst) fixture.curatedClassifications
                        }

            validateMapdSnapshot withoutLevel3
                `shouldBe` Left "FWC MAPD snapshot incomplete: missing classification_fixed_id 257"

        it "keeps hospitality weekday time penalties from wage allowances" do
            let asOfDate = fromGregorian 2026 4 24
                eveningAllowance = wageAllowancePayload 2025 "Penalty-Monday to Friday-7.00 pm to midnight" 10 2.81
                lateNightAllowance = wageAllowancePayload 2025 "Penalty-Monday to Friday-midnight to 7.00 am" 15 4.22
                oldAllowance = wageAllowancePayload 2024 "Penalty-Monday to Friday-7.00 pm to midnight" 10 2.65
                unrelatedAllowance = wageAllowancePayload 2025 "First aid allowance" 0 3.14

                wageAllowances =
                    curateWageAllowances
                        barVenueCurationProfile
                        asOfDate
                        [ (eveningAllowance, Aeson.Null)
                        , (lateNightAllowance, Aeson.Null)
                        , (oldAllowance, Aeson.Null)
                        , (unrelatedAllowance, Aeson.Null)
                        ]

            map (normaliseTimePenaltyKind . fst) wageAllowances `shouldBe` [Just EveningAfter7Pm, Just LateNightAfterMidnight]
            map (wageAllowancePayloadAmount . fst) wageAllowances `shouldBe` [Just 2.81, Just 4.22]

        it "keeps casual ordinary penalties for casual base-rate projection but excludes casual overtime" do
            let asOfDate = fromGregorian 2026 4 24
                award2025 = awardPayload 2025
                level1Classification = classificationPayload 101 2025 "Level 1" (Just "Food and beverage attendant grade 1")
                level1Rate =
                    payRatePayloadWithBasePayRateId "BR1"
                        (payRatePayload
                            101
                            2025
                            "AD"
                            "Level 1"
                            (Just "Food and beverage attendant grade 1")
                            Nothing
                            (Just "Weekly")
                            (Just 24.95)
                            (Just "Hourly"))
                casualOrdinaryPenalty =
                    (penaltyRatePayload 101 2025 "Level 1" (Just "Food and beverage attendant grade 1") "Casual employees - ordinary hours" (Just 31.19))
                        { penaltyBasePayRateId = Just "BR1" }
                casualOvertimePenalty =
                    (penaltyRatePayload 101 2025 "Level 1" (Just "Food and beverage attendant grade 1") "Casual employees - overtime ordinary hours" (Just 44.10))
                        { penaltyBasePayRateId = Just "BR1" }

                (_, _, _, _, penalties) =
                    curateAwardData
                        barVenueCurationProfile
                        asOfDate
                        ( 9
                        , [(award2025, Aeson.Null)]
                        , [(level1Classification, Aeson.Null)]
                        , [(level1Rate, Aeson.Null)]
                        , [(casualOrdinaryPenalty, Aeson.Null), (casualOvertimePenalty, Aeson.Null)]
                        )

            map (payloadPenaltyDescription . fst) penalties `shouldBe` [Just "Casual employees - ordinary hours"]
            map (normalisePenaltyKind . fst) penalties `shouldBe` [Nothing]

        it "excludes public-holiday overtime rows at the curation boundary" do
            let asOfDate = fromGregorian 2026 4 24
                classification = classificationPayload 101 2025 "Level 1" (Just "Food and beverage attendant grade 1")
                payRate = payRatePayloadWithBasePayRateId "BR1" (payRatePayload 101 2025 "AD" "Level 1" (Just "Food and beverage attendant grade 1") Nothing (Just "Weekly") (Just 24.95) (Just "Hourly"))
                publicHolidayOvertime =
                    (penaltyRatePayload 101 2025 "Level 1" (Just "Food and beverage attendant grade 1") "Public holiday overtime" (Just 56.14))
                        { penaltyBasePayRateId = Just "BR1" }
                (_, _, _, _, penalties) =
                    curateAwardData barVenueCurationProfile asOfDate
                        (9, [(awardPayload 2025, Aeson.Null)], [(classification, Aeson.Null)], [(payRate, Aeson.Null)], [(publicHolidayOvertime, Aeson.Null)])

            penalties `shouldBe` []

        it "decodes text-ish MAPD fields from numbers and booleans" do
            let decoded =
                    Aeson.eitherDecode
                        (LByteString.pack "{\"classification_fixed_id\":101,\"classification\":\"Level 1\",\"classification_level\":1,\"clauses\":[],\"operative_from\":\"2025-07-01\",\"published_year\":2025}") ::
                        Either String ClassificationPayload

            fmap payloadClassificationLevel decoded `shouldBe` Right (Just "1.0")

        it "curates every supported adult hourly classification and rate category from the dated MAPD fixtures" do
            fixture <- loadFwcMapdFixture

            fixture.curatedAwardFixedId `shouldBe` 9
            map (awardPayloadCode . fst) fixture.curatedAwards `shouldBe` ["MA000009"]
            map (specClassificationPayloadFixedId . fst) fixture.curatedClassifications `shouldBe` expectedCoreClassificationFixedIds
            mapMaybe (specPayRatePayloadBasePayRateId . fst) fixture.curatedPayRates `shouldBe` expectedCoreBasePayRateIds
            length fixture.curatedPenaltyRates `shouldBe` 49
            forM_ expectedCoreBasePayRateIds \basePayRateId ->
                mapMaybe (fixturePenaltyCategory . fst) (filter ((== Just basePayRateId) . penaltyPayloadBasePayRateId . fst) fixture.curatedPenaltyRates)
                    `shouldMatchList` expectedFixturePenaltyCategories
            map (normaliseTimePenaltyKind . fst) fixture.curatedWageAllowances
                `shouldMatchList` [Just EveningAfter7Pm, Just LateNightAfterMidnight]

databaseTests :: Spec
databaseTests = do
    aroundAll withDatabaseTestContext do
        describe "FWC MAPD admin data" do
            it "durably publishes the support award-rate resource without a local browser hub" $ withContext do
                withCleanDb do
                    appJob <- newRecord @AppJob |> set #jobKind fwcMapdRefreshJobKind |> set #relatedTable (Just "fwc_mapd_sync_runs") |> createRecord
                    let summary = MapdPayload.MapdSyncSummary [] 0 0 0 0 0
                    performFwcMapdRefreshJobWith (pure (Right summary)) appJob
                    [durableEvent] <- query @LiveInvalidationEvent |> filterWhere (#source, "support.award_rates.refresh" :: Text) |> fetch
                    query @LiveInvalidationEventResource |> filterWhere (#eventId, unpackId durableEvent.id) |> fetchCount `shouldReturn` 1
                    [freshnessCheck] <- query @AppJob |> filterWhere (#jobKind, wageSourceHealthCheckJobKind) |> fetch
                    freshnessCheck.relatedId `shouldBe` Just (unpackId appJob.id)
                    freshnessCheck.runAt `shouldSatisfy` (> addUTCTime fwcMaximumAge appJob.createdAt)

            it "projects invalid provider snapshots to the safe job boundary" $ withContext do
                withCleanDb do
                    appJob <- newRecord @AppJob |> set #jobKind fwcMapdRefreshJobKind |> set #relatedTable (Just "fwc_mapd_sync_runs") |> createRecord
                    result <- Exception.try (performFwcMapdRefreshJobWith (Exception.throwIO MapdSnapshotInvalid) appJob) :: IO (Either Exception.SomeException ())
                    case result of
                        Right () -> expectationFailure "Expected invalid FWC MAPD snapshot failure"
                        Left exception -> tshow exception `shouldBe` "application.async.error.app-job/job-validation-rejected: The job's validated data was rejected."

            it "rejects a malformed persisted FWC refresh payload before synchronization" $ withContext do
                withCleanDb do
                    appJob <- newRecord @AppJob |> set #jobKind fwcMapdRefreshJobKind |> set #relatedTable (Just "fwc_mapd_sync_runs") |> set #payload (Aeson.String "not-an-object") |> createRecord
                    result <- Exception.try (performFwcMapdRefreshJobWith (expectationFailure "malformed payload must fail before FWC sync" >> pure (Left "unused")) appJob) :: IO (Either Exception.SomeException ())
                    case result of
                        Right () -> expectationFailure "Expected malformed FWC refresh payload failure"
                        Left exception -> tshow exception `shouldBe` "application.async.error.app-job/job-malformed-persisted-payload: The stored job payload is invalid."

            it "projects every fixture classification and expected rate category without asserting current dollar amounts" $ withContext do
                withCleanDb do
                    fixture <- loadFwcMapdFixture

                    summary <- storeCuratedMapdAwardData [fixture]

                    summary.fetchedAwardCount `shouldBe` 1
                    summary.fetchedClassificationCount `shouldBe` 7
                    summary.fetchedPayRateCount `shouldBe` 7
                    summary.fetchedPenaltyRateCount `shouldBe` 49
                    summary.fetchedWageAllowanceCount `shouldBe` 2

                    awardLevels <- query @AwardLevel |> orderByAsc #classificationFixedId |> fetch
                    map (.classificationFixedId) awardLevels `shouldBe` expectedCoreClassificationFixedIds
                    forM_ awardLevels \awardLevel -> do
                        baseRates <-
                            query @AwardLevelBaseRate
                                |> filterWhere (#awardLevelId, unpackId awardLevel.id)
                                |> fetch
                        penaltyRates <-
                            query @AwardLevelPenaltyRate
                                |> filterWhere (#awardLevelId, unpackId awardLevel.id)
                                |> fetch

                        map (.employmentBasis) baseRates `shouldMatchList` [Permanent, Casual]
                        map (\penaltyRate -> (penaltyRate.employmentBasis, penaltyRate.penaltyKind)) penaltyRates
                            `shouldMatchList`
                                [ (Permanent, SaturdayPenalty)
                                , (Permanent, SundayPenalty)
                                , (Permanent, PublicHolidayPenalty)
                                , (Casual, SaturdayPenalty)
                                , (Casual, SundayPenalty)
                                , (Casual, PublicHolidayPenalty)
                                ]

                    timeAllowances <- query @AwardTimePenaltyAllowance |> fetch
                    map (.penaltyKind) timeAllowances
                        `shouldMatchList` [EveningAfter7Pm, LateNightAfterMidnight]

            it "records an actionable failed sync and leaves the complete active projection unchanged" $ withContext do
                withCleanDb do
                    fixture <- loadFwcMapdFixture
                    _ <- storeCuratedMapdAwardData [fixture]
                    originalLevels <- query @AwardLevel |> orderByAsc #classificationFixedId |> fetch
                    originalBaseRates <- query @AwardLevelBaseRate |> orderByAsc #awardLevelId |> fetch
                    let incompleteCandidate =
                            fixture
                                { curatedClassifications = filter ((/= 257) . specClassificationPayloadFixedId . fst) fixture.curatedClassifications
                                }

                    syncResult <- Exception.try (runMapdSyncWith [9] (storeCuratedMapdAwardData [incompleteCandidate])) :: IO (Either Exception.SomeException MapdSyncSummary)

                    syncResult `shouldSatisfy` isLeft
                    refreshedLevels <- query @AwardLevel |> orderByAsc #classificationFixedId |> fetch
                    refreshedBaseRates <- query @AwardLevelBaseRate |> orderByAsc #awardLevelId |> fetch
                    failedRun <- query @FwcMapdSyncRun |> orderByDesc #startedAt |> fetchOne
                    map (\level -> (level.id, level.classificationFixedId, level.isActive, level.syncedAt)) refreshedLevels
                        `shouldBe` map (\level -> (level.id, level.classificationFixedId, level.isActive, level.syncedAt)) originalLevels
                    map (\rate -> (rate.id, rate.hourlyRate, rate.fwcMapdPayRateId)) refreshedBaseRates
                        `shouldBe` map (\rate -> (rate.id, rate.hourlyRate, rate.fwcMapdPayRateId)) originalBaseRates
                    failedRun.status `shouldBe` "failed"
                    failedRun.errorMessage `shouldBe` Just "FWC MAPD candidate failed validation."

            it "keeps award level ids stable while adding new effective-dated rates" $ withContext do
                withCleanDb do
                    venue <- createVenueWithConfig "Award Rates"
                    firstSyncedAt <- getCurrentTime
                    _ <-
                        newRecord @FwcMapdClassification
                            |> set #awardFixedId 9
                            |> set #classificationFixedId 101
                            |> set #classification "Level 1"
                            |> set #parentClassificationName (Just "Food and beverage attendant grade 1")
                            |> set #operativeFrom (Just (fromGregorian 2025 7 1))
                            |> set #operativeTo (Just (fromGregorian 2026 6 30))
                            |> set #publishedYear (Just 2025)
                            |> set #syncedAt firstSyncedAt
                            |> createRecord
                    _ <-
                        newRecord @FwcMapdPayRate
                            |> set #awardFixedId 9
                            |> set #classificationFixedId (Just 101)
                            |> set #classification "Level 1"
                            |> set #parentClassificationName (Just "Food and beverage attendant grade 1")
                            |> set #employeeRateTypeCode (Just "AD")
                            |> set #basePayRateId (Just "BR2025")
                            |> set #calculatedRate (Just 24.95)
                            |> set #calculatedRateType (Just "Hourly")
                            |> set #operativeFrom (Just (fromGregorian 2025 7 1))
                            |> set #operativeTo (Just (fromGregorian 2026 6 30))
                            |> set #publishedYear (Just 2025)
                            |> set #syncedAt firstSyncedAt
                            |> createRecord

                    populateAwardLevelProjection 9 firstSyncedAt
                    firstAwardLevel <- query @AwardLevel |> fetchOne
                    staff <- createStaffRecord venue Nothing "Stable" "Reference"
                    shiftType <-
                        newRecord @ShiftType
                            |> set #venueId (unpackId venue.id)
                            |> set #name "Award override"
                            |> set #payAssignmentMode AwardRate
                            |> set #overrideAwardLevelId (Just firstAwardLevel.id)
                            |> createRecord
                    _ <- staff |> set #payAssignmentMode AwardRate |> set #defaultAwardLevelId (Just firstAwardLevel.id) |> updateRecord

                    secondSyncedAt <- getCurrentTime
                    _ <-
                        newRecord @FwcMapdClassification
                            |> set #awardFixedId 9
                            |> set #classificationFixedId 101
                            |> set #classification "Level 1"
                            |> set #parentClassificationName (Just "Food and beverage attendant grade 1")
                            |> set #operativeFrom (Just (fromGregorian 2026 7 1))
                            |> set #operativeTo (Nothing :: Maybe Day)
                            |> set #publishedYear (Just 2026)
                            |> set #syncedAt secondSyncedAt
                            |> createRecord
                    _ <-
                        newRecord @FwcMapdPayRate
                            |> set #awardFixedId 9
                            |> set #classificationFixedId (Just 101)
                            |> set #classification "Level 1"
                            |> set #parentClassificationName (Just "Food and beverage attendant grade 1")
                            |> set #employeeRateTypeCode (Just "AD")
                            |> set #basePayRateId (Just "BR2026")
                            |> set #calculatedRate (Just 25.80)
                            |> set #calculatedRateType (Just "Hourly")
                            |> set #operativeFrom (Just (fromGregorian 2026 7 1))
                            |> set #operativeTo (Nothing :: Maybe Day)
                            |> set #publishedYear (Just 2026)
                            |> set #syncedAt secondSyncedAt
                            |> createRecord

                    populateAwardLevelProjection 9 secondSyncedAt

                    awardLevels <- query @AwardLevel |> fetch
                    baseRates <- query @AwardLevelBaseRate |> orderByAsc #operativeFrom |> fetch
                    refreshedStaff <- fetch staff.id
                    refreshedShiftType <- fetch shiftType.id

                    map (.id) awardLevels `shouldBe` [firstAwardLevel.id]
                    refreshedStaff.defaultAwardLevelId `shouldBe` Just firstAwardLevel.id
                    refreshedShiftType.overrideAwardLevelId `shouldBe` Just firstAwardLevel.id
                    map (.hourlyRate) baseRates `shouldBe` [24.95, 25.80]
                    map (.operativeFrom) baseRates `shouldBe` [Just (fromGregorian 2025 7 1), Just (fromGregorian 2026 7 1)]

            it "builds the support/admin award-rate view model from the latest current core hospitality snapshot" $ withContext do
                withCleanDb do
                    let oldSyncedAt = UTCTime (fromGregorian 2026 1 1) 0
                    let latestSyncedAt = UTCTime (fromGregorian 2026 2 1) 0
                    _ <-
                        newRecord @FwcMapdAward
                            |> set #awardFixedId 9
                            |> set #awardId 8009
                            |> set #code "MA000009"
                            |> set #name "Hospitality Industry (General) Award 2020"
                            |> set #awardOperativeTo (Nothing :: Maybe Day)
                            |> set #syncedAt oldSyncedAt
                            |> createRecord
                    _ <-
                        newRecord @FwcMapdClassification
                            |> set #awardFixedId 9
                            |> set #classificationFixedId 101
                            |> set #classification "Level 1"
                            |> set #parentClassificationName (Just "Food and beverage attendant grade 1")
                            |> set #clauseDescription (Just "Hospitality employees")
                            |> set #operativeTo (Nothing :: Maybe Day)
                            |> set #syncedAt oldSyncedAt
                            |> createRecord
                    _ <-
                        newRecord @FwcMapdPayRate
                            |> set #awardFixedId 9
                            |> set #classificationFixedId (Just 101)
                            |> set #classification "Level 1"
                            |> set #parentClassificationName (Just "Food and beverage attendant grade 1")
                            |> set #employeeRateTypeCode (Just "AD")
                            |> set #calculatedRate (Just 23.95)
                            |> set #calculatedRateType (Just "Hourly")
                            |> set #operativeTo (Nothing :: Maybe Day)
                            |> set #syncedAt oldSyncedAt
                            |> createRecord

                    award <-
                        newRecord @FwcMapdAward
                            |> set #awardFixedId 9
                            |> set #awardId 9009
                            |> set #code "MA000009"
                            |> set #name "Hospitality Industry (General) Award 2020"
                            |> set #awardOperativeTo (Nothing :: Maybe Day)
                            |> set #syncedAt latestSyncedAt
                            |> createRecord
                    _ <-
                        newRecord @FwcMapdAward
                            |> set #awardFixedId 99
                            |> set #awardId 9099
                            |> set #code "OLD"
                            |> set #name "Closed Award"
                            |> set #awardOperativeTo (Just (fromGregorian 2024 6 30))
                            |> set #syncedAt latestSyncedAt
                            |> createRecord
                    coreClassification <-
                        newRecord @FwcMapdClassification
                            |> set #awardFixedId award.awardFixedId
                            |> set #classificationFixedId 101
                            |> set #classification "Level 1"
                            |> set #parentClassificationName (Just "Food and beverage attendant grade 1")
                            |> set #clauseDescription (Just "Hospitality employees")
                            |> set #operativeTo (Nothing :: Maybe Day)
                            |> set #syncedAt latestSyncedAt
                            |> createRecord
                    _ <-
                        newRecord @FwcMapdClassification
                            |> set #awardFixedId award.awardFixedId
                            |> set #classificationFixedId 102
                            |> set #classification "Level 1"
                            |> set #parentClassificationName (Just "Casino electronic gaming employee grade 1")
                            |> set #operativeTo (Nothing :: Maybe Day)
                            |> set #syncedAt latestSyncedAt
                            |> createRecord
                    _ <-
                        newRecord @FwcMapdClassification
                            |> set #awardFixedId award.awardFixedId
                            |> set #classificationFixedId 103
                            |> set #classification "Loaded Rate"
                            |> set #clauseDescription (Just "LoadedRates schedule")
                            |> set #operativeTo (Nothing :: Maybe Day)
                            |> set #syncedAt latestSyncedAt
                            |> createRecord
                    _ <-
                        newRecord @FwcMapdPayRate
                            |> set #awardFixedId award.awardFixedId
                            |> set #classificationFixedId (Just coreClassification.classificationFixedId)
                            |> set #classification coreClassification.classification
                            |> set #parentClassificationName coreClassification.parentClassificationName
                            |> set #employeeRateTypeCode (Just "AD")
                            |> set #calculatedRate (Just 24.95)
                            |> set #calculatedRateType (Just "Hourly")
                            |> set #operativeTo (Nothing :: Maybe Day)
                            |> set #syncedAt latestSyncedAt
                            |> createRecord
                    _ <-
                        newRecord @FwcMapdPayRate
                            |> set #awardFixedId award.awardFixedId
                            |> set #classificationFixedId (Just coreClassification.classificationFixedId)
                            |> set #classification "Junior Level 1"
                            |> set #employeeRateTypeCode (Just "JN")
                            |> set #calculatedRate (Just 19.95)
                            |> set #calculatedRateType (Just "Hourly")
                            |> set #operativeTo (Nothing :: Maybe Day)
                            |> set #syncedAt latestSyncedAt
                            |> createRecord

                    adminData <- fetchFwcMapdAdminData

                    map (.code) adminData.currentAwards `shouldBe` ["MA000009"]
                    map (.classificationFixedId) adminData.currentCoreClassifications `shouldBe` [101]
                    map (.classification) adminData.currentCoreAdultPayRates `shouldBe` ["Level 1"]
                    map (.calculatedRate) adminData.currentCoreAdultPayRates `shouldBe` [Just 24.95]

expectedCoreBasePayRateIds :: [Text]
expectedCoreBasePayRateIds = ["BR89890", "BR89891", "BR89892", "BR89894", "BR89895", "BR89896", "BR89897"]

expectedFixturePenaltyCategories :: [Text]
expectedFixturePenaltyCategories =
    [ "casual:ordinary"
    , "casual:public_holiday_penalty"
    , "casual:saturday_penalty"
    , "casual:sunday_penalty"
    , "permanent:public_holiday_penalty"
    , "permanent:saturday_penalty"
    , "permanent:sunday_penalty"
    ]

classificationFixedIdFromValue :: Aeson.Value -> Maybe Int
classificationFixedIdFromValue = AesonTypes.parseMaybe (Aeson.withObject "classification" (Aeson..: "classification_fixed_id"))

fixturePenaltyCategory :: PenaltyRatePayload -> Maybe Text
fixturePenaltyCategory payload
    | isCasualPenalty && payload.penaltyDescription == Just "Ordinary hours" = Just "casual:ordinary"
    | otherwise = do
        penaltyKind <- normalisePenaltyKind payload
        pure (employmentBasisLabel <> ":" <> inputValue penaltyKind)
    where
        clauseDescription = Text.toLower (fromMaybe "" payload.penaltyClauseDescription)
        isCasualPenalty = "casual" `Text.isInfixOf` clauseDescription
        employmentBasisLabel = if isCasualPenalty then "casual" else "permanent"

awardPayloadCode :: AwardPayload -> Text
awardPayloadCode payload = payload.code

penaltyPayloadBasePayRateId :: PenaltyRatePayload -> Maybe Text
penaltyPayloadBasePayRateId payload = payload.penaltyBasePayRateId

specPayRatePayloadBasePayRateId :: PayRatePayload -> Maybe Text
specPayRatePayloadBasePayRateId payload = payload.basePayRateId

awardPayloadPublishedYear :: AwardPayload -> Maybe Int
awardPayloadPublishedYear payload = payload.publishedYear

specClassificationPayloadFixedId :: ClassificationPayload -> Int
specClassificationPayloadFixedId payload = payload.classificationFixedId

specPayRatePayloadClassificationFixedId :: PayRatePayload -> Maybe Int
specPayRatePayloadClassificationFixedId payload = payload.classificationFixedId

specPenaltyRatePayloadClassificationFixedId :: PenaltyRatePayload -> Maybe Int
specPenaltyRatePayloadClassificationFixedId payload = payload.penaltyClassificationFixedId

payloadPenaltyDescription :: PenaltyRatePayload -> Maybe Text
payloadPenaltyDescription payload = payload.penaltyDescription

payloadClassificationLevel :: ClassificationPayload -> Maybe Text
payloadClassificationLevel payload = payload.classificationLevel

wageAllowancePayloadAmount :: WageAllowancePayload -> Maybe Scientific
wageAllowancePayloadAmount payload = payload.wageAllowanceAmount

awardPayload :: Int -> AwardPayload
awardPayload publishedYear =
    AwardPayload
        { awardFixedId = 9
        , awardId = 9000 + publishedYear
        , code = "MA000009"
        , name = "Hospitality Industry (General) Award 2020"
        , awardOperativeFrom = Just (fromGregorian 2010 1 1)
        , awardOperativeTo = Nothing
        , publishedYear = Just publishedYear
        , versionNumber = Just 1
        , lastModifiedDatetime = Nothing
        }

penaltyRatePayload :: Int -> Int -> Text -> Maybe Text -> Text -> Maybe Scientific -> PenaltyRatePayload
penaltyRatePayload classificationFixedId publishedYear classification parentClassificationName description calculatedValue =
    PenaltyRatePayload
        { penaltyClassificationFixedId = Just classificationFixedId
        , penaltyClassification = classification
        , penaltyClassificationLevel = Nothing
        , penaltyParentClassificationName = parentClassificationName
        , penaltyClauseDescription = Just "Adult full-time and part-time employees-ordinary and penalty rates"
        , penaltyEmployeeRateTypeCode = Just "AD"
        , penaltyBasePayRateId = Nothing
        , penaltyFixedId = Just classificationFixedId
        , penaltyDescription = Just description
        , penaltyText = Nothing
        , penaltyRate = Nothing
        , penaltyRateUnit = Just "Hourly"
        , penaltyCalculatedValue = calculatedValue
        , penaltyOperativeFrom = Just (fromGregorian 2025 7 1)
        , penaltyOperativeTo = Nothing
        , penaltyPublishedYear = Just publishedYear
        , penaltyVersionNumber = Just 1
        , penaltyLastModifiedDatetime = Nothing
        }

classificationPayload :: Int -> Int -> Text -> Maybe Text -> ClassificationPayload
classificationPayload classificationFixedId publishedYear classification parentClassificationName =
    classificationPayloadWithClause classificationFixedId publishedYear classification parentClassificationName Nothing

classificationPayloadWithClause :: Int -> Int -> Text -> Maybe Text -> Maybe Text -> ClassificationPayload
classificationPayloadWithClause classificationFixedId publishedYear classification parentClassificationName clauseDescription =
    ClassificationPayload
        { classificationFixedId
        , classification
        , classificationLevel = Nothing
        , parentClassificationName
        , clauseFixedId = Nothing
        , clauseDescription
        , clauses = Aeson.Array mempty
        , nextDownClassificationFixedId = Nothing
        , nextUpClassificationFixedId = Nothing
        , operativeFrom = Just (fromGregorian 2025 7 1)
        , operativeTo = Nothing
        , publishedYear = Just publishedYear
        , versionNumber = Just 1
        , lastModifiedDatetime = Nothing
        }

payRatePayload ::
    Int ->
    Int ->
    Text ->
    Text ->
    Maybe Text ->
    Maybe Scientific ->
    Maybe Text ->
    Maybe Scientific ->
    Maybe Text ->
    PayRatePayload
payRatePayload classificationFixedId publishedYear employeeRateTypeCode classification parentClassificationName baseRate baseRateType calculatedRate calculatedRateType =
    PayRatePayload
        { classificationFixedId = Just classificationFixedId
        , classification
        , classificationLevel = Nothing
        , parentClassificationName
        , employeeRateTypeCode = Just employeeRateTypeCode
        , basePayRateId = Nothing
        , baseRate
        , baseRateType
        , calculatedPayRateId = Nothing
        , calculatedRate
        , calculatedRateType
        , operativeFrom = Just (fromGregorian 2025 7 1)
        , operativeTo = Nothing
        , publishedYear = Just publishedYear
        , versionNumber = Just 1
        , lastModifiedDatetime = Nothing
        }

payRatePayloadWithBasePayRateId :: Text -> PayRatePayload -> PayRatePayload
payRatePayloadWithBasePayRateId value payload =
    payload { FwcMapd.basePayRateId = Just value }

wageAllowancePayload :: Int -> Text -> Scientific -> Scientific -> WageAllowancePayload
wageAllowancePayload publishedYear allowance rate allowanceAmount =
    WageAllowancePayload
        { wageAllowanceFixedId = Just (2000 + publishedYear)
        , wageAllowanceClauseFixedId = Just 738
        , wageAllowanceClauses = Just "29.2"
        , wageAllowance = Just allowance
        , wageAllowanceType = Just "Detail"
        , wageAllowanceIsAllPurpose = Just False
        , wageAllowanceRate = Just rate
        , wageAllowanceBaseRate = Just 1068.4
        , wageAllowanceBasePayRateId = Just "BR89895"
        , wageAllowanceRateUnit = Just "Percent"
        , wageAllowanceAmount = Just allowanceAmount
        , wageAllowancePaymentFrequency = Just "per hour or part thereof"
        , wageAllowanceOperativeFrom = Just (fromGregorian 2025 7 1)
        , wageAllowanceOperativeTo = Nothing
        , wageAllowancePublishedYear = Just publishedYear
        , wageAllowanceVersionNumber = Just 1
        , wageAllowanceLastModifiedDatetime = Nothing
        }
