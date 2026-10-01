module Test.PublicHolidaySyncSpec where

import Application.Helper.FrontendContract.Surface.Support.Resource (supportPublicHolidaysResource)
import Application.Helper.LiveUpdate.DurableCodec (decodeDurableResource, encodeDurableResource)
import Application.PublicHolidays.ActiveImport
import Application.PublicHolidays.Client (DataVicDate (..))
import Application.PublicHolidays.Coverage
import Application.PublicHolidays.Override (verifiedVic2026Holidays, verifiedVic2026Key, verifiedVic2026SourceUrl)
import Application.Script.PublicHolidayCutover (requireCutoverDatabase)
import qualified Control.Exception as Exception
import qualified Data.Aeson as Aeson
import Data.Time.Calendar (fromGregorian)
import Data.Time.Clock (addUTCTime)
import Generated.Types
import IHP.ControllerPrelude
import IHP.Test.Mocking
import Test.Hspec
import Test.Support

databaseTests :: Spec
databaseTests = do
    aroundAll withDatabaseTestContext do
        describe "DataVic cutover database identity" do
            it "decodes PostgreSQL's database name and accepts only the explicitly selected database" $ withContext do
                withCleanDb do
                    actualDatabase :: Text <- unsafeSqlQueryScalar "SELECT current_database()::text" ()
                    requireCutoverDatabase actualDatabase
                    requireCutoverDatabase (actualDatabase <> "_wrong_target") `shouldThrow` anyException
                    query @PublicHolidayImportBatch |> fetchCount >>= (`shouldBe` 0)

        describe "DataVic active public holiday import" do
            it "replaces accepted dates and records durable acceptance plus recovery evidence" $ withContext do
                withCleanDb do
                    let now = UTCTime (fromGregorian 2026 1 1) 0
                    let candidate = DataVicDate (fromGregorian 2027 3 29) "Easter Monday" Nothing Nothing "https://example.test/calendar"
                    _ <- newRecord @PublicHoliday |> set #jurisdiction "VIC" |> set #holidayDate (fromGregorian 2027 3 28) |> set #name "Old date" |> createRecord
                    outsideYear <- newRecord @PublicHoliday |> set #jurisdiction "VIC" |> set #holidayDate (fromGregorian 2028 1 1) |> set #name "Outside year" |> createRecord
                    interstate <- newRecord @PublicHoliday |> set #jurisdiction "NSW" |> set #holidayDate candidate.date |> set #name "Interstate date" |> createRecord
                    regional <- newRecord @PublicHoliday |> set #jurisdiction "VIC" |> set #isRegional True |> set #holidayDate candidate.date |> set #name "Regional date" |> createRecord
                    summary <- importPublicHolidayCalendars now [2027] [(2027, [candidate])]
                    summary.prunedCount `shouldBe` 1
                    imported <- query @PublicHoliday |> filterWhere (#source, Just "datavic_v2") |> fetchOne
                    imported.holidayDate `shouldBe` candidate.date
                    query @PublicHoliday |> fetchCount >>= (`shouldBe` 4)
                    forM_ [outsideYear, interstate, regional] \unchanged ->
                        (fetch unchanged.id >>= pure . (.name)) `shouldReturn` unchanged.name
                    receipt <- query @PublicHolidayImportBatch |> fetchOne
                    receipt.targetYears `shouldBe` [2027]
                    receipt.source `shouldBe` "datavic_v2"
                    receipt.previousCalendar `shouldNotBe` Aeson.toJSON ([] :: [Text])
                    receipt.acceptedCalendar `shouldNotBe` Aeson.toJSON ([] :: [Text])

            it "rejects an empty year before replacing any requested year" $ withContext do
                withCleanDb do
                    let now = UTCTime (fromGregorian 2026 1 1) 0
                    original <- newRecord @PublicHoliday |> set #jurisdiction "VIC" |> set #holidayDate (fromGregorian 2026 1 1) |> set #name "Existing" |> createRecord
                    let candidate = DataVicDate (fromGregorian 2026 1 1) "Changed" Nothing Nothing "https://example.test/calendar"
                    importPublicHolidayCalendars now [2026, 2027] [(2026, [candidate]), (2027, [])] `shouldThrow` anyException
                    rows <- query @PublicHoliday |> fetch
                    map (.id) rows `shouldBe` [original.id]
                    query @PublicHolidayImportBatch |> fetchCount >>= (`shouldBe` 0)

            it "rejects a slow candidate older than an already accepted batch" $ withContext do
                withCleanDb do
                    let now = UTCTime (fromGregorian 2026 1 1) 0
                    let candidate = DataVicDate (fromGregorian 2027 1 1) "New Year" Nothing Nothing "https://example.test/calendar"
                    _ <- importPublicHolidayCalendars now [2027] [(2027, [candidate])]
                    importPublicHolidayCalendars now [2027] [(2027, [candidate])] `shouldThrow` anyException
                    query @PublicHolidayImportBatch |> fetchCount >>= (`shouldBe` 1)

            it "keeps normal imports from retiring an expired protected override" $ withContext do
                withCleanDb do
                    let now = UTCTime (fromGregorian 2026 1 1) 0
                    _ <- newRecord @PublicHolidayOverride |> set #jurisdiction "VIC" |> set #targetYear 2026
                        |> set #snapshotKey verifiedVic2026Key |> set #sourceUrl verifiedVic2026SourceUrl
                        |> set #verifiedAt (addUTCTime (-100) now) |> set #reviewDueAt (addUTCTime (-50) now) |> createRecord
                    let candidate = DataVicDate (fromGregorian 2026 1 1) "New Year" Nothing Nothing "https://example.test/calendar"
                    importPublicHolidayCalendars now [2026] [(2026, [candidate])] `shouldThrow` anyException
                    query @PublicHolidayImportBatch |> fetchCount >>= (`shouldBe` 0)

            it "retires the verified override only within the explicit audited import" $ withContext do
                withCleanDb do
                    let now = UTCTime (fromGregorian 2026 1 1) 0
                    actor <- createUserRecord "datavic-reviewer@example.com" "staff" True
                        >>= updateRecord . set #platformRole (Just SuperAdmin)
                    forM_ verifiedVic2026Holidays \(day, name) -> do
                        _ <- newRecord @PublicHoliday |> set #jurisdiction "VIC" |> set #holidayDate day |> set #name name |> createRecord
                        pure ()
                    override <- newRecord @PublicHolidayOverride |> set #jurisdiction "VIC" |> set #targetYear 2026
                        |> set #snapshotKey verifiedVic2026Key |> set #sourceUrl verifiedVic2026SourceUrl
                        |> set #verifiedAt (addUTCTime (-100) now) |> set #reviewDueAt (addUTCTime (-50) now) |> createRecord
                    let candidate = DataVicDate (fromGregorian 2026 1 1) "Provider is authoritative" Nothing Nothing "https://example.test/calendar"
                    -- Force a database failure after retirement/deletion, not a
                    -- preflight validation failure: every write must roll back.
                    Exception.bracket_
                        (unsafeSqlExecDiscardResult "ALTER TABLE public_holidays ADD CONSTRAINT datavic_test_reject CHECK (name <> 'Provider is authoritative')" ())
                        (unsafeSqlExecDiscardResult "ALTER TABLE public_holidays DROP CONSTRAINT datavic_test_reject" ())
                        (cutoverPublicHolidayCalendars actor now [2026] [(2026, [candidate])] `shouldThrow` anyException)
                    unchanged <- fetch override.id
                    unchanged.retiredAt `shouldBe` Nothing
                    query @PublicHoliday |> fetchCount >>= (`shouldBe` 14)
                    query @PublicHolidayImportBatch |> fetchCount >>= (`shouldBe` 0)
                    _ <- cutoverPublicHolidayCalendars actor now [2026] [(2026, [candidate])]
                    retired <- fetch override.id
                    retired.retiredAt `shouldSatisfy` isJust
                    retired.reviewedByUserId `shouldBe` Just (unpackId actor.id)
                    rows <- query @PublicHoliday |> fetch
                    map (.name) rows `shouldBe` [candidate.name]
                    query @PublicHolidayImportBatch |> fetchCount >>= (`shouldBe` 1)

            it "durably publishes the Support holiday resource after an accepted import" $ withContext do
                withCleanDb do
                    let startedAt = UTCTime (fromGregorian 2026 1 1) 0
                    let entry = DataVicDate (fromGregorian 2026 1 1) "New Year" Nothing Nothing "https://example.test/calendar"
                    _ <- importPublicHolidayCalendars startedAt [2026] [(2026, [entry])]
                    event <- query @LiveInvalidationEvent |> filterWhere (#source, "support.public_holidays.sync" :: Text) |> fetchOne
                    resources <- query @LiveInvalidationEventResource |> filterWhere (#eventId, unpackId event.id) |> fetch
                    map (\resource -> decodeDurableResource resource.resourceKey resource.resourcePayload) resources
                        `shouldBe` [encodeDurableResource supportPublicHolidaysResource]

            it "reports missing public holiday coverage as warnings" $ withContext do
                withCleanDb do
                    coverage <- fetchPublicHolidayCoverage
                    length coverage `shouldBe` 3
                    map (.status) coverage `shouldSatisfy` all (== PublicHolidayCoverageMissing)
