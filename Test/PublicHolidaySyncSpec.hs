module Test.PublicHolidaySyncSpec where

import Application.Helper.FrontendContract.Surface.Support.Resource (supportPublicHolidaysResource)
import Application.Helper.LiveUpdate.DurableCodec (decodeDurableResource, encodeDurableResource)
import Application.PublicHolidays.ActiveImport
import Application.PublicHolidays.Client (DataVicDate (..))
import Application.PublicHolidays.Override (verifiedVic2026Holidays, verifiedVic2026Key, verifiedVic2026SourceUrl)
import Application.PublicHolidays.Coverage
import Application.PublicHolidays.Job (performPublicHolidayRefreshJobWith,
                                       publicHolidayRefreshJobKind)
import Application.PublicHolidays.Sync
import Application.Script.PublicHolidayCutover (requireCutoverDatabase)
import Application.WageSourceAlert.Job (wageSourceHealthCheckJobKind)
import Application.WageSourcePolicy (dataVicMaximumAge)
import Config
import qualified Control.Exception as Exception
import qualified Data.Aeson as Aeson
import Data.Either (isLeft)
import Data.Time.Calendar (fromGregorian)
import Data.Time.Clock (addUTCTime)
import Generated.Types
import IHP.ControllerPrelude
import IHP.FrameworkConfig
import IHP.HaskellSupport
import IHP.Prelude
import IHP.Test.Mocking
import Test.Hspec
import Test.Support
import Test.Support.DataVicFixture (loadDataVicHolidayFixture)
import Web.FrontController ()
import Web.Routes
import Web.Types

pureTests :: Spec
pureTests = do
    describe "DataVic public holiday parsing" do
        it "parses D/MM/YYYY dates" do
            parseDataVicDate "3/11/2026" `shouldBe` Right (fromGregorian 2026 11 3)
            parseDataVicDate "25/12/2026" `shouldBe` Right (fromGregorian 2026 12 25)

        it "does not reinterpret the incident's ambiguous provider timestamps" do
            parseDataVicDate "2026-09-03T00:00:00"
                `shouldBe` Left "Expected DataVic date in D/MM/YYYY format, got: 2026-09-03T00:00:00"
            parseDataVicDate "2019-05-11T00:00:00" `shouldSatisfy` isLeft

        it "normalizes statewide DataVic public holiday records" do
            publicHolidayImportFromDataVic melbourneCupRecord
                `shouldBe`
                    Right
                        PublicHolidayImport
                            { jurisdiction = "VIC"
                            , holidayDate = fromGregorian 2026 11 3
                            , name = "Melbourne Cup"
                            , region = Nothing
                            , isRegional = False
                            , source = Just "Business Victoria"
                            , sourceId = Just "data-vic-row-1"
                            , sourceUrl = Just "https://business.vic.gov.au/business-information/public-holidays/victorian-public-holidays-2026"
                            , description = Just "Melbourne Cup Day is a public holiday across all of Victoria unless alternate local holiday has been arranged by a non-metro council."
                            }

        it "skips non-public-holiday records" do
            publicHolidayImportFromDataVic melbourneCupRecord { dateType = "SCHOOL_TERM" }
                `shouldSatisfy` isLeft

        it "decodes the dated DataVic response fixture without a live request" do
            records <- loadDataVicHolidayFixture

            length records `shouldBe` 13
            map (.dateType) records `shouldSatisfy` all (== "PUBLIC_HOLIDAY")
            map (.importantDate) records
                `shouldSatisfy` \dates -> all (`elem` dates) ["3/11/2026", "25/12/2026", "28/12/2026"]
            map (.publisher) records `shouldSatisfy` all (== Just "Business Victoria")

validPublicHolidayJobPayload :: Aeson.Value
validPublicHolidayJobPayload = Aeson.object ["jurisdiction" Aeson..= ("VIC" :: Text)]

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
                    summary <- importPublicHolidayCalendars now [2027] [(2027, [candidate])]
                    summary.prunedCount `shouldBe` 1
                    rows <- query @PublicHoliday |> fetch
                    map (.holidayDate) rows `shouldBe` [candidate.date]
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

        describe "DataVic public holiday import" do
            it "durably publishes the support public-holiday resource without a local browser hub" $ withContext do
                withCleanDb do
                    appJob <- newRecord @AppJob |> set #jobKind publicHolidayRefreshJobKind |> set #relatedTable (Just "public_holidays") |> set #payload validPublicHolidayJobPayload |> createRecord
                    let summary = PublicHolidaySyncSummary [] 0 0 0 0 0 0 0
                    performPublicHolidayRefreshJobWith (pure summary) appJob
                    [durableEvent] <- query @LiveInvalidationEvent |> filterWhere (#source, "support.public_holidays.refresh" :: Text) |> fetch
                    resources <- query @LiveInvalidationEventResource |> filterWhere (#eventId, unpackId durableEvent.id) |> fetch
                    map (\resource -> decodeDurableResource resource.resourceKey resource.resourcePayload) resources
                        `shouldBe` [encodeDurableResource supportPublicHolidaysResource]
                    completedJob <- fetch appJob.id
                    completedJob.status `shouldBe` JobStatusSucceeded
                    now <- getCurrentTime
                    healthChecks <- query @AppJob |> filterWhere (#jobKind, wageSourceHealthCheckJobKind) |> fetch
                    map (\check -> (check.relatedId, check.runAt <= now)) healthChecks
                        `shouldMatchList` [(Nothing, True), (Just (unpackId appJob.id), False)]
                    forM_ (filter (isJust . (.relatedId)) healthChecks) \freshnessCheck ->
                        freshnessCheck.runAt `shouldSatisfy` (> addUTCTime dataVicMaximumAge appJob.createdAt)

            it "rejects malformed and wrong-jurisdiction persisted refresh payloads" $ withContext do
                withCleanDb do
                    let cases =
                            [ (Aeson.String "not-an-object", "application.async.error.app-job/job-malformed-persisted-payload: The stored job payload is invalid.")
                            , (Aeson.object ["jurisdiction" Aeson..= ("NSW" :: Text)], "application.async.error.app-job/job-invalid-provenance: The stored job provenance is invalid.")
                            ]
                    forM_ cases \(payload, expectedMessage) -> do
                        appJob <- newRecord @AppJob |> set #jobKind publicHolidayRefreshJobKind |> set #relatedTable (Just "public_holidays") |> set #payload payload |> createRecord
                        result <- Exception.try (performPublicHolidayRefreshJobWith (expectationFailure "invalid payload must fail before DataVic sync" >> pure (PublicHolidaySyncSummary [] 0 0 0 0 0 0 0)) appJob) :: IO (Either Exception.SomeException ())
                        case result of
                            Right () -> expectationFailure "Expected invalid DataVic refresh payload failure"
                            Left exception -> tshow exception `shouldBe` expectedMessage

            it "projects malformed provider responses to the safe job boundary" $ withContext do
                withCleanDb do
                    appJob <- newRecord @AppJob |> set #jobKind publicHolidayRefreshJobKind |> set #relatedTable (Just "public_holidays") |> set #payload validPublicHolidayJobPayload |> createRecord
                    result <- Exception.try (performPublicHolidayRefreshJobWith (Exception.throwIO PublicHolidayResponseMalformed) appJob) :: IO (Either Exception.SomeException ())
                    case result of
                        Right () -> expectationFailure "Expected malformed DataVic response failure"
                        Left exception -> tshow exception `shouldBe` "application.async.error.app-job/job-malformed-response: The provider returned a response Bepis could not safely read."

            it "projects the dated statewide fixture, including its additional public holiday, into the 2026 cache" $ withContext do
                withCleanDb do
                    records <- loadDataVicHolidayFixture

                    summary <- importDataVicPublicHolidayRecordsForYears [2026] records
                    holidays <- query @PublicHoliday |> orderByAsc #holidayDate |> fetch

                    summary.fetchedCount `shouldBe` 13
                    summary.importedCount `shouldBe` 13
                    summary.skippedCount `shouldBe` 0
                    length holidays `shouldBe` 13
                    map (.jurisdiction) holidays `shouldSatisfy` all (== "VIC")
                    map (.isRegional) holidays `shouldSatisfy` all not
                    map (.source) holidays `shouldSatisfy` all (== Just "Business Victoria")
                    map (.holidayDate) holidays
                        `shouldSatisfy` \dates ->
                            all
                                (`elem` dates)
                                [ fromGregorian 2026 11 3
                                , fromGregorian 2026 12 25
                                , fromGregorian 2026 12 28
                                ]

            it "replaces matching statewide holiday rows from the latest API read" $ withContext do
                withCleanDb do
                    firstSummary <- importDataVicPublicHolidayRecordsForYears [2026] [melbourneCupRecord]
                    firstSummary.targetYears `shouldBe` [2026]
                    firstSummary.fetchedCount `shouldBe` 1
                    firstSummary.importedCount `shouldBe` 1
                    firstSummary.insertedCount `shouldBe` 1
                    firstSummary.updatedCount `shouldBe` 0
                    firstSummary.skippedCount `shouldBe` 0
                    firstSummary.prunedCount `shouldBe` 0

                    secondSummary <-
                        importDataVicPublicHolidayRecordsForYears [2026]
                            [updatedMelbourneCupRecord]
                    secondSummary.fetchedCount `shouldBe` 1
                    secondSummary.importedCount `shouldBe` 1
                    secondSummary.insertedCount `shouldBe` 1
                    secondSummary.updatedCount `shouldBe` 0
                    secondSummary.skippedCount `shouldBe` 0
                    secondSummary.prunedCount `shouldBe` 1

                    holidays <- query @PublicHoliday |> fetch
                    length holidays `shouldBe` 1
                    case holidays of
                        [holiday] -> do
                            holiday.jurisdiction `shouldBe` "VIC"
                            holiday.holidayDate `shouldBe` fromGregorian 2026 11 3
                            holiday.name `shouldBe` "Melbourne Cup"
                            holiday.source `shouldBe` Just "Business Victoria"
                            holiday.sourceId `shouldBe` Just "data-vic-row-1"
                            holiday.description `shouldBe` Just "Updated description"
                            holiday.importedAt `shouldSatisfy` isJust
                        _ -> expectationFailure "Expected exactly one public holiday"

            it "skips upstream rows outside target years and reconciles stale cached VIC statewide rows" $ withContext do
                withCleanDb do
                    _ <-
                        newRecord @PublicHoliday
                            |> set #jurisdiction "VIC"
                            |> set #holidayDate (fromGregorian 2025 12 25)
                            |> set #name "Christmas Day"
                            |> set #region Nothing
                            |> set #isRegional False
                            |> createRecord
                    _ <-
                        newRecord @PublicHoliday
                            |> set #jurisdiction "NSW"
                            |> set #holidayDate (fromGregorian 2025 12 25)
                            |> set #name "Christmas Day"
                            |> set #region Nothing
                            |> set #isRegional False
                            |> createRecord

                    summary <-
                        importDataVicPublicHolidayRecordsForYears [2026, 2027]
                            [ melbourneCupRecord
                            , melbourneCupRecord { importantDate = "25/12/2025", name = "Christmas Day" }
                            ]

                    summary.targetYears `shouldBe` [2026, 2027]
                    summary.fetchedCount `shouldBe` 2
                    summary.importedCount `shouldBe` 1
                    summary.insertedCount `shouldBe` 1
                    summary.updatedCount `shouldBe` 0
                    summary.skippedCount `shouldBe` 1
                    summary.prunedCount `shouldBe` 0

                    vicHolidays <- query @PublicHoliday |> filterWhere (#jurisdiction, "VIC" :: Text) |> orderBy #holidayDate |> fetch
                    map (.holidayDate) vicHolidays `shouldBe` [fromGregorian 2025 12 25, fromGregorian 2026 11 3]

                    nswHolidayCount <- query @PublicHoliday |> filterWhere (#jurisdiction, "NSW" :: Text) |> fetchCount
                    nswHolidayCount `shouldBe` 1

            it "fails the whole import before mutating cached target years when any record is invalid" $ withContext do
                withCleanDb do
                    _ <-
                        newRecord @PublicHoliday
                            |> set #jurisdiction "VIC"
                            |> set #holidayDate (fromGregorian 2026 11 3)
                            |> set #name "Existing Melbourne Cup"
                            |> set #region Nothing
                            |> set #isRegional False
                            |> createRecord

                    result <- Exception.try (importDataVicPublicHolidayRecordsForYears [2026] [melbourneCupRecord { importantDate = "not-a-date" }])
                    case result of
                        Left (_ :: Exception.SomeException) -> pure ()
                        Right _ -> expectationFailure "Expected invalid DataVic record to fail the import"

                    holidays <- query @PublicHoliday |> filterWhere (#jurisdiction, "VIC" :: Text) |> fetch
                    map (.name) holidays `shouldBe` ["Existing Melbourne Cup"]

            it "reports missing public holiday coverage as warnings" $ withContext do
                withCleanDb do
                    coverage <- fetchPublicHolidayCoverage
                    length coverage `shouldBe` 3
                    map (.status) coverage `shouldSatisfy` all (== PublicHolidayCoverageMissing)

melbourneCupRecord :: DataVicHolidayRecord
melbourneCupRecord =
    DataVicHolidayRecord
        { arun = Just "data-vic-row-1"
        , dateType = "PUBLIC_HOLIDAY"
        , name = " Melbourne Cup "
        , importantDate = "3/11/2026"
        , publisher = Just "Business Victoria"
        , description = Just "Melbourne Cup Day is a public holiday across all of Victoria unless alternate local holiday has been arranged by a non-metro council."
        , source = Just "https://business.vic.gov.au/business-information/public-holidays/victorian-public-holidays-2026"
        }

updatedMelbourneCupRecord :: DataVicHolidayRecord
updatedMelbourneCupRecord =
    DataVicHolidayRecord
        { arun = Just "data-vic-row-1"
        , dateType = "PUBLIC_HOLIDAY"
        , name = " Melbourne Cup "
        , importantDate = "3/11/2026"
        , publisher = Just "Business Victoria"
        , description = Just "Updated description"
        , source = Just "https://business.vic.gov.au/business-information/public-holidays/victorian-public-holidays-2026"
        }
