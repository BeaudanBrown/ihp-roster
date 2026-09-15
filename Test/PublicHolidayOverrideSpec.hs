module Test.PublicHolidayOverrideSpec where

import Application.PublicHolidays.Override
import Application.PublicHolidays.OverrideIncident
import Application.PublicHolidays.Sync
import Application.WageSourceFacts
import Application.WageSourcePolicy
import qualified Control.Exception as Exception
import Data.Either (isLeft)
import qualified Data.Set as Set
import qualified Data.Text.IO as TextIO
import Generated.Types hiding (verifiedAt, reviewDueAt)
import qualified Hasql.Session as HasqlSession
import IHP.ControllerPrelude
import IHP.ModelSupport (unsafeSqlExecDiscardResult)
import IHP.ModelSupport.Types (ModelContext (transactionRunner), TransactionRunner (runInTransaction))
import IHP.Test.Mocking
import Test.Hspec
import Test.Support
import Test.Support.DataVicFixture

pureTests :: Spec
pureTests = describe "verified VIC calendar" do
    it "contains all 14 verified 2026 dates, including Grand Final eve" do
        length verifiedVic2026Holidays `shouldBe` 14
        lookup (fromGregorian 2026 9 25) verifiedVic2026Holidays `shouldBe` Just "Friday before the AFL grand final"
        overrideStatus verifiedAt calendar overrideFixture `shouldBe` OverrideReady
    it "expires at the exact review deadline and rejects future verification" do
        overrideStatus (addUTCTime (-1) verifiedAt) calendar overrideFixture `shouldBe` OverrideInvalid
        overrideStatus (addUTCTime (-1) reviewDueAt) calendar overrideFixture `shouldBe` OverrideReady
        overrideStatus reviewDueAt calendar overrideFixture `shouldBe` OverrideExpired
        overriddenYears [overrideFixture] `shouldBe` Set.singleton 2026
    it "rejects missing, extra, duplicated, misdated and unknown snapshots" do
        overrideStatus verifiedAt (drop 1 calendar) overrideFixture `shouldBe` OverrideInvalid
        overrideStatus verifiedAt (calendar <> take 1 calendar) overrideFixture `shouldBe` OverrideInvalid
        let changed = map (set #holidayDate (fromGregorian 2026 9 3)) (take 1 calendar) <> drop 1 calendar
        overrideStatus verifiedAt changed overrideFixture `shouldBe` OverrideInvalid
        overrideStatus verifiedAt calendar (overrideFixture |> set #snapshotKey "unknown") `shouldBe` OverrideInvalid
        overrideStatus verifiedAt calendar (overrideFixture |> set #retiredAt (Just verifiedAt)) `shouldBe` OverrideInvalid
        usableOverrideYears reviewDueAt calendar [overrideFixture] `shouldBe` Set.empty
    it "does not let regional or other-jurisdiction rows satisfy statewide coverage" do
        let regional = map (set #isRegional True) calendar
            interstate = map (set #jurisdiction "NSW") calendar
        overrideStatus verifiedAt regional overrideFixture `shouldBe` OverrideInvalid
        overrideStatus verifiedAt interstate overrideFixture `shouldBe` OverrideInvalid
        overrideStatus verifiedAt (map (set #region (Just "Unexpected region")) calendar) overrideFixture `shouldBe` OverrideInvalid
        overrideStatus verifiedAt (calendar <> regional <> interstate) overrideFixture `shouldBe` OverrideReady

-- Pure construction deliberately exercises the same complete-calendar check
-- used by live payroll facts, not a parallel test-only date validator.
calendar :: [PublicHoliday]
calendar = [newRecord @PublicHoliday |> set #jurisdiction "VIC" |> set #holidayDate day |> set #name name | (day, name) <- verifiedVic2026Holidays]

verifiedAt :: UTCTime
verifiedAt = UTCTime (fromGregorian 2026 9 15) (secondsToDiffTime 9000)

reviewDueAt :: UTCTime
reviewDueAt = UTCTime (fromGregorian 2026 10 15) 0

overrideFixture :: PublicHolidayOverride
overrideFixture = newRecord @PublicHolidayOverride
    |> set #jurisdiction "VIC"
    |> set #targetYear 2026
    |> set #snapshotKey verifiedVic2026Key
    |> set #sourceUrl verifiedVic2026SourceUrl
    |> set #verifiedAt verifiedAt
    |> set #reviewDueAt reviewDueAt

databaseTests :: Spec
databaseTests = aroundAll withDatabaseTestContext do
    describe "public holiday override persistence" do
        it "emits exact review-window and expiry transitions without reminders" $ withContext do
            withCleanDb do
                _ <- createUserRecordWithPlatformRole "override-alert@example.com" "staff" (Just SuperAdmin) True
                mapM_ createRecord calendar
                _ <- createRecord overrideFixture
                let windowOpens = addUTCTime (negate (7 * 24 * 60 * 60)) reviewDueAt
                _ <- reconcilePublicHolidayOverridesAt (addUTCTime (-1) windowOpens)
                query @OperationalIncidentEvent |> fetchCount >>= (`shouldBe` 0)
                _ <- reconcilePublicHolidayOverridesAt windowOpens
                _ <- reconcilePublicHolidayOverridesAt (addUTCTime 1 windowOpens)
                _ <- reconcilePublicHolidayOverridesAt reviewDueAt
                events <- query @OperationalIncidentEvent |> orderByAsc #eventSequence |> fetch
                map (.transition) events `shouldBe` ["opened", "impact_escalated"]
                map (.impactKey) events `shouldBe` ["review_window", "expired"]
                incident <- query @OperationalIncident |> fetchOne
                incident.stableIdentity `shouldBe` "VIC:2026:1"
                incident.state `shouldBe` "open"

        it "initially observes overdue only and starts a new audited cycle on extension" $ withContext do
            withCleanDb do
                actor <- createUserRecordWithPlatformRole "override-reviewer@example.com" "staff" (Just SuperAdmin) True
                mapM_ createRecord calendar
                override <- createRecord overrideFixture
                _ <- reconcilePublicHolidayOverridesAt reviewDueAt
                firstEvents <- query @OperationalIncidentEvent |> fetch
                map (.impactKey) firstEvents `shouldBe` ["expired"]

                let reviewedAt = addUTCTime 60 reviewDueAt
                let nextDue = addUTCTime (30 * 24 * 60 * 60) reviewedAt
                extended <- extendPublicHolidayOverrideReview actor override.id nextDue "verified calendar retained" reviewedAt
                extended `shouldSatisfy` isJust
                refreshed <- fetch override.id
                refreshed.reviewCycle `shouldBe` 2
                refreshed.reviewedByUserId `shouldBe` Just (unpackId actor.id)
                incidents <- query @OperationalIncident |> orderByAsc #createdAt |> fetch
                map (.stableIdentity) incidents `shouldBe` ["VIC:2026:1"]
                map (.state) incidents `shouldBe` ["resolved"]

                retired <- retirePublicHolidayOverride actor override.id "validated return to provider authority" (addUTCTime 1 reviewedAt)
                retired `shouldSatisfy` isJust
                fetchActivePublicHolidayOverrides `shouldReturn` []

        it "corrects only the known rows, retains import timestamps and records an idempotent audit" $ withContext do
            withCleanDb do
                records <- loadDataVicHolidayFixture
                _ <- importDataVicPublicHolidayRecordsForYears [2026] records
                before <- query @PublicHoliday |> orderByAsc #holidayDate |> fetch
                easterMonday <- newRecord @PublicHoliday |> set #jurisdiction "VIC" |> set #holidayDate (fromGregorian 2027 3 28) |> set #name "Easter Monday" |> createRecord
                easterSunday <- newRecord @PublicHoliday |> set #jurisdiction "VIC" |> set #holidayDate (fromGregorian 2027 3 28) |> set #name "Easter Sunday" |> createRecord
                runCorrection
                after <- query @PublicHoliday |> filterWhere (#jurisdiction, "VIC" :: Text) |> fetch
                [override] <- fetchActivePublicHolidayOverrides
                overrideStatus verifiedAt after override `shouldBe` OverrideReady
                forM_ before \old -> do
                    retained <- fetch old.id
                    retained.holidayDate `shouldBe` old.holidayDate
                    retained.importedAt `shouldBe` old.importedAt
                corrected <- fetch easterMonday.id
                corrected.holidayDate `shouldBe` fromGregorian 2027 3 29
                corrected.importedAt `shouldBe` easterMonday.importedAt
                (fetch easterSunday.id >>= \entry -> pure entry.holidayDate) `shouldReturn` fromGregorian 2027 3 28
                grandFinal <- query @PublicHoliday |> filterWhere (#holidayDate, fromGregorian 2026 9 25) |> fetchOne
                grandFinal.importedAt `shouldBe` Nothing
                runCorrection
                [repeated] <- fetchActivePublicHolidayOverrides
                repeated.correctionBefore `shouldBe` override.correctionBefore
                repeated.correctionAfter `shouldBe` override.correctionAfter
                repeated.id `shouldBe` override.id

        it "accepts already corrected rows without duplication or renewing timestamps" $ withContext do
            withCleanDb do
                mapM_ createRecord calendar
                easter <- newRecord @PublicHoliday |> set #jurisdiction "VIC" |> set #holidayDate (fromGregorian 2027 3 29) |> set #name "Easter Monday" |> createRecord
                runCorrection
                query @PublicHoliday |> fetchCount >>= (`shouldBe` 15)
                retained <- fetch easter.id
                retained.holidayDate `shouldBe` easter.holidayDate
                retained.description `shouldBe` easter.description
                retained.importedAt `shouldBe` easter.importedAt

        it "aborts ambiguous Easter Monday corrections without touching either row" $ withContext do
            withCleanDb do
                mapM_ createRecord calendar
                forM_ [28, 29] \day -> do
                    _ <- newRecord @PublicHoliday |> set #jurisdiction "VIC" |> set #holidayDate (fromGregorian 2027 3 day) |> set #name "Easter Monday" |> createRecord
                    pure ()
                result <- Exception.try runCorrection :: IO (Either Exception.SomeException ())
                result `shouldSatisfy` isLeft
                query @PublicHolidayOverride |> fetchCount >>= (`shouldBe` 0)
                query @PublicHoliday |> filterWhere (#name, "Easter Monday" :: Text) |> fetchCount >>= (`shouldBe` 3)

        it "rejects a mismatched migration atomically, without retaining the added Grand Final row" $ withContext do
            withCleanDb do
                records <- loadDataVicHolidayFixture
                _ <- importDataVicPublicHolidayRecordsForYears [2026] (drop 1 records)
                result <- Exception.try runCorrection :: IO (Either Exception.SomeException ())
                result `shouldSatisfy` isLeft
                query @PublicHolidayOverride |> fetchCount >>= (`shouldBe` 0)
                query @PublicHoliday |> filterWhere (#holidayDate, fromGregorian 2026 9 25) |> fetchCount >>= (`shouldBe` 0)

        it "blocks even valid provider replacements, including multi-year requests, without renewing dates" $ withContext do
            withCleanDb do
                records <- loadDataVicHolidayFixture
                _ <- importDataVicPublicHolidayRecordsForYears [2026] records
                runCorrection
                before <- query @PublicHoliday |> orderByAsc #id |> fetch
                result <- Exception.try (importDataVicPublicHolidayRecordsForYears [2025, 2026, 2027] records) :: IO (Either Exception.SomeException PublicHolidaySyncSummary)
                result `shouldSatisfy` isLeft
                after <- query @PublicHoliday |> orderByAsc #id |> fetch
                map (\h -> (h.id, h.holidayDate, h.importedAt)) after `shouldBe` map (\h -> (h.id, h.holidayDate, h.importedAt)) before

        it "protects the pinned rows at the database boundary even after review expiry" $ withContext do
            withCleanDb do
                mapM_ createRecord calendar
                _ <- createRecord (overrideFixture |> set #verifiedAt (addUTCTime (-100) verifiedAt) |> set #reviewDueAt (addUTCTime (-1) verifiedAt))
                withTransaction do
                    forM_ [ "DELETE FROM public_holidays WHERE jurisdiction = 'VIC' AND holiday_date = DATE '2026-03-09'"
                          , "UPDATE public_holidays SET holiday_date = DATE '2026-09-03' WHERE jurisdiction = 'VIC' AND holiday_date = DATE '2026-03-09'"
                          , "INSERT INTO public_holidays (jurisdiction, holiday_date, name) VALUES ('VIC', DATE '2026-02-01', 'Unexpected')"
                          ] \statement -> do
                        unsafeSqlExecDiscardResult "SAVEPOINT protected_write" ()
                        result <- Exception.try (unsafeSqlExecDiscardResult statement ()) :: IO (Either Exception.SomeException ())
                        result `shouldSatisfy` isLeft
                        unsafeSqlExecDiscardResult "ROLLBACK TO SAVEPOINT protected_write" ()
                query @PublicHoliday |> fetchCount >>= (`shouldBe` 14)
                _ <- newRecord @PublicHoliday |> set #jurisdiction "NSW" |> set #holidayDate (fromGregorian 2026 3 9) |> set #name "Other state" |> createRecord
                pure ()

        it "uses verified coverage without faking DataVic health or bypassing FWC, expiry or other years" $ withContext do
            withCleanDb do
                mapM_ createRecord calendar
                _ <- createRecord overrideFixture
                venue <- createVenueWithConfig "Reviewed holiday source"
                facts <- loadWageSourceFactsFor [unpackId venue.id] (Set.fromList [2026, 2027])
                let diagnostics at years requirement = sourceDiagnosticsForFacts (PolicyClock at) facts (unpackId venue.id) (fromGregorian 2026 9 25) (Set.fromList years) requirement
                diagnostics verifiedAt [2026] HospitalityAwardSources `shouldBe` [FwcSnapshotMissing]
                diagnostics verifiedAt [2026, 2027] HospitalityAwardSources `shouldBe` [FwcSnapshotMissing, DataVicSnapshotMissing 2027]
                diagnostics reviewDueAt [2026] HospitalityAwardSources `shouldBe` [FwcSnapshotMissing, DataVicSnapshotMissing 2026]
                diagnostics reviewDueAt [2026] ImportedXeroOverride `shouldBe` []
                evaluateDataVicDiagnostics (PolicyClock verifiedAt) (Set.singleton 2026) facts.factDataVicSnapshots `shouldBe` [DataVicSnapshotMissing 2026]

runCorrection :: (?modelContext :: ModelContext) => IO ()
runCorrection = do
    script <- TextIO.readFile "Application/Migration/1789440001-verify-vic-2026-holidays.sql"
    withTransaction do
        case transactionRunner ?modelContext of
            Nothing -> error "Holiday correction fixture requires a transaction runner"
            Just runner -> runInTransaction runner (HasqlSession.script script)
