module Test.XeroTimesheetReservationSpec where

import Application.Helper.Xero.Types (XeroTimesheetRef (..))
import Application.Xero.Timesheets.ProviderWrite (XeroTimesheetWriteOperation (..),
                                                  xeroTimesheetWriteIdempotencyKey)
import Application.Xero.Timesheets.Reconciliation (XeroTimesheetReconciliationDecision (..))
import Application.Xero.Timesheets.Reservation
import Control.Concurrent.Async (concurrently)
import qualified Control.Exception as Exception
import qualified Data.Aeson as Aeson
import Data.Either (isLeft)
import Data.Time.Clock (addUTCTime)
import Data.Time.LocalTime (TimeOfDay (..))
import Generated.Types
import IHP.ControllerPrelude
import IHP.ModelSupport.Types (HasqlSessionError)
import IHP.Test.Mocking (withContext)
import Test.Hspec
import Test.Support
import Test.XeroTimesheetPreviewSpec (EntrySpec (..), PreviewFixture (..),
                                      createPreviewFixture, fixtureStaffA,
                                      fixtureStaffB)

tests :: Spec
tests =
    aroundAll withDatabaseTestContext do
        describe "Xero timesheet reservation persistence" do
            it "supersedes a terminal active submission while retaining its history and source links" $ withContext do
                withCleanDb do
                    fixture <- reservationFixture
                    first <- reserve fixture (fixture.entries)
                    (firstRun, firstSubmission) <- expectCreated first
                    submitted <-
                        firstSubmission
                            |> set #status XeroTimesheetSubmissionStatusEnumSubmitted
                            |> set #xeroTimesheetId (Just "existing-draft-id")
                            |> set #xeroTimesheetStatus (Just "DRAFT")
                            |> updateRecord

                    second <- reserveWithRemote fixture fixture.entries [remoteDraft fixture "existing-draft-id"]
                    (_, secondSubmission) <- expectCreated second

                    refreshedFirst <- fetch submitted.id
                    refreshedFirst.status `shouldBe` XeroTimesheetSubmissionStatusEnumSuperseded
                    secondSubmission.status `shouldBe` XeroTimesheetSubmissionStatusEnumPending
                    secondSubmission.id `shouldNotBe` firstSubmission.id
                    allSubmissions <- query @XeroTimesheetSubmission |> fetch
                    length allSubmissions `shouldBe` 2
                    activeSubmissions <- activeFor fixture
                    map (.id) activeSubmissions `shouldBe` [secondSubmission.id]
                    retainedLinks <- linksFor firstSubmission
                    length retainedLinks `shouldBe` length fixture.entries
                    runs <- query @XeroSubmissionRun |> fetch
                    map (.id) runs `shouldContain` [firstRun.id]

            it "assigns distinct keys to independent updates of the same Xero draft" $ withContext do
                withCleanDb do
                    fixture <- reservationFixture
                    first <- reserveWithRemote fixture fixture.entries [remoteDraft fixture "existing-draft-id"]
                    (_, firstSubmission) <- expectCreated first
                    submittedFirst <-
                        firstSubmission
                            |> set #status XeroTimesheetSubmissionStatusEnumSubmitted
                            |> set #xeroTimesheetId (Just "existing-draft-id")
                            |> set #xeroTimesheetStatus (Just "DRAFT")
                            |> updateRecord

                    second <- reserveWithRemote fixture fixture.entries [remoteDraft fixture "existing-draft-id"]
                    (_, secondSubmission) <- expectCreated second

                    firstSubmission.idempotencyKey
                        `shouldBe` xeroTimesheetWriteIdempotencyKey (unpackId firstSubmission.id) 0 (UpdateXeroTimesheetDraft "existing-draft-id")
                    secondSubmission.idempotencyKey
                        `shouldBe` xeroTimesheetWriteIdempotencyKey (unpackId secondSubmission.id) 0 (UpdateXeroTimesheetDraft "existing-draft-id")
                    secondSubmission.idempotencyKey `shouldNotBe` firstSubmission.idempotencyKey
                    fetch submittedFirst.id >>= (\record -> record.status `shouldBe` XeroTimesheetSubmissionStatusEnumSuperseded)

            it "joins existing pending work without creating an orphan or duplicate run" $ withContext do
                withCleanDb do
                    fixture <- reservationFixture
                    first <- reserve fixture fixture.entries
                    (run, submission) <- expectCreated first

                    second <- reserve fixture fixture.entries

                    second `shouldBe` XeroTimesheetReservationsInProgress [run.id]
                    query @XeroSubmissionRun |> fetchCount >>= (`shouldBe` 1)
                    query @XeroTimesheetSubmission |> fetchCount >>= (`shouldBe` 1)
                    activeSubmissions <- activeFor fixture
                    map (.id) activeSubmissions `shouldBe` [submission.id]

            it "fails an abandoned period reservation even when no replacement entry remains" $ withContext do
                withCleanDb do
                    fixture <- reservationFixture
                    first <- reserve fixture fixture.entries
                    (firstRun, firstSubmission) <- expectCreated first
                    now <- getCurrentTime
                    _ <- firstSubmission |> set #updatedAt (addUTCTime (-121) now) |> updateRecord

                    failAbandonedXeroTimesheetSubmissionsForPeriod
                        (unpackId fixture.connection.id)
                        fixture.periodStart
                        fixture.periodEnd

                    abandoned <- fetch firstSubmission.id
                    abandoned.status `shouldBe` XeroTimesheetSubmissionStatusEnumFailed
                    abandoned.lastError `shouldSatisfy` maybe False ("could not confirm whether Xero received" `isInfixOf`)
                    failedRun <- fetch firstRun.id
                    failedRun.status `shouldBe` XeroSubmissionRunStatusEnumFailed
                    failedRun.completedAt `shouldSatisfy` isJust

            it "fails and supersedes an abandoned pending reservation after two minutes" $ withContext do
                withCleanDb do
                    fixture <- reservationFixture
                    first <- reserve fixture fixture.entries
                    (firstRun, firstSubmission) <- expectCreated first
                    now <- getCurrentTime
                    _ <- firstSubmission |> set #updatedAt (addUTCTime (-121) now) |> updateRecord

                    second <- reserve fixture fixture.entries
                    (_, secondSubmission) <- expectCreated second

                    abandoned <- fetch firstSubmission.id
                    abandoned.status `shouldBe` XeroTimesheetSubmissionStatusEnumSuperseded
                    abandoned.lastError `shouldSatisfy` maybe False ("could not confirm whether Xero received" `isInfixOf`)
                    failedRun <- fetch firstRun.id
                    failedRun.status `shouldBe` XeroSubmissionRunStatusEnumFailed
                    failedRun.completedAt `shouldSatisfy` isJust
                    secondSubmission.status `shouldBe` XeroTimesheetSubmissionStatusEnumPending

            it "rejects a mixed pending and unreserved employee batch without omitting work" $ withContext do
                withCleanDb do
                    fixture <-
                        createPreviewFixture
                            "weekly"
                            [ EntrySpec 0 fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 13 0 0)
                            , EntrySpec 0 fixtureStaffB (TimeOfDay 9 0 0) (TimeOfDay 12 0 0)
                            ]
                    case fixture.entries of
                        [entryA, entryB] -> do
                            first <-
                                reserveXeroTimesheetSubmissionRun
                                    (submissionRunTemplate fixture)
                                    [submissionReservationFor fixture fixture.staffA "employee-a" [entryA]]
                                    []
                            _ <- expectCreated first

                            mixed <-
                                reserveXeroTimesheetSubmissionRun
                                    (submissionRunTemplate fixture)
                                    [ submissionReservationFor fixture fixture.staffA "employee-a" [entryA]
                                    , submissionReservationFor fixture fixture.staffB "employee-b" [entryB]
                                    ]
                                    []

                            mixed `shouldBe` XeroTimesheetReservationInvalid "Xero submission contains a mix of pending and unreserved employee periods."
                            query @XeroSubmissionRun |> fetchCount >>= (`shouldBe` 1)
                            query @XeroTimesheetSubmission |> fetchCount >>= (`shouldBe` 1)
                        _ -> expectationFailure "expected one source entry per fixture employee"

            it "blocks non-draft reconciliation without superseding history or creating a run" $ withContext do
                withCleanDb do
                    fixture <- reservationFixture
                    first <- reserve fixture fixture.entries
                    (_, firstSubmission) <- expectCreated first
                    submitted <-
                        firstSubmission
                            |> set #status XeroTimesheetSubmissionStatusEnumSubmitted
                            |> set #xeroTimesheetId (Just "approved-id")
                            |> set #xeroTimesheetStatus (Just "APPROVED")
                            |> updateRecord

                    blocked <- reserveWithRemote fixture fixture.entries [remoteTimesheet fixture "approved-id" "APPROVED"]

                    blocked `shouldBe` XeroTimesheetReservationBlocked (BlockXeroNonDraft "approved-id" "APPROVED")
                    refreshed <- fetch submitted.id
                    refreshed.status `shouldBe` XeroTimesheetSubmissionStatusEnumSubmitted
                    query @XeroSubmissionRun |> fetchCount >>= (`shouldBe` 1)
                    activeSubmissions <- activeFor fixture
                    length activeSubmissions `shouldBe` 1

            it "rejects an empty reservation set without creating a pending run" $ withContext do
                withCleanDb do
                    fixture <- reservationFixture

                    outcome <- reserveXeroTimesheetSubmissionRun (submissionRunTemplate fixture) [] []

                    outcome `shouldBe` XeroTimesheetReservationInvalid "Xero submission requires at least one timesheet reservation."
                    query @XeroSubmissionRun |> fetchCount >>= (`shouldBe` 0)

            it "serializes concurrent reservation attempts to one active row" $ withContext do
                withCleanDb do
                    fixture <- reservationFixture

                    (left, right) <- concurrently (reserve fixture fixture.entries) (reserve fixture fixture.entries)

                    sort [outcomeKind left, outcomeKind right] `shouldBe` ["created", "in_progress"]
                    query @XeroSubmissionRun |> fetchCount >>= (`shouldBe` 1)
                    activeSubmissions <- activeFor fixture
                    length activeSubmissions `shouldBe` 1

            it "rolls back the run and submission when source-link persistence fails" $ withContext do
                withCleanDb do
                    fixture <- reservationFixture
                    let duplicateSources = fixture.entries <> fixture.entries

                    result :: Either HasqlSessionError XeroTimesheetReservationOutcome <-
                        Exception.try (reserve fixture duplicateSources)

                    result `shouldSatisfy` isLeft
                    query @XeroSubmissionRun |> fetchCount >>= (`shouldBe` 0)
                    query @XeroTimesheetSubmission |> fetchCount >>= (`shouldBe` 0)
                    query @XeroTimesheetSubmissionEntry |> fetchCount >>= (`shouldBe` 0)

reservationFixture :: (?modelContext :: ModelContext) => IO PreviewFixture
reservationFixture =
    createPreviewFixture "weekly" [EntrySpec 0 fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 13 0 0)]

reserve ::
    (?modelContext :: ModelContext) =>
    PreviewFixture ->
    [TimesheetEntry] ->
    IO XeroTimesheetReservationOutcome
reserve fixture sourceEntries = reserveWithRemote fixture sourceEntries []

reserveWithRemote ::
    (?modelContext :: ModelContext) =>
    PreviewFixture ->
    [TimesheetEntry] ->
    [XeroTimesheetRef] ->
    IO XeroTimesheetReservationOutcome
reserveWithRemote fixture sourceEntries remoteTimesheets =
    reserveXeroTimesheetSubmissionRun
        (submissionRunTemplate fixture)
        [submissionReservation fixture sourceEntries]
        remoteTimesheets

submissionRunTemplate :: PreviewFixture -> XeroSubmissionRun
submissionRunTemplate fixture =
    newRecord @XeroSubmissionRun
        |> set #venueId (unpackId fixture.venue.id)
        |> set #xeroConnectionId (unpackId fixture.connection.id)
        |> set #submittedByUserId (unpackId fixture.owner.id)
        |> set #payPeriodStart fixture.periodStart
        |> set #payPeriodEnd fixture.periodEnd
        |> set #sourceKind ApprovedTimesheets
        |> set #status XeroSubmissionRunStatusEnumPending
        |> set #previewPayloadJson (Aeson.object [])
        |> set #readinessSnapshotJson (Aeson.object [])
        |> set #xeroDuplicateCheckJson (Aeson.object [])

submissionReservation :: PreviewFixture -> [TimesheetEntry] -> XeroTimesheetReservation
submissionReservation fixture = submissionReservationFor fixture fixture.staffA "employee-a"

submissionReservationFor :: PreviewFixture -> Staff -> Text -> [TimesheetEntry] -> XeroTimesheetReservation
submissionReservationFor fixture staff employeeId sourceEntries =
    XeroTimesheetReservation
        { reservationConnectionId = unpackId fixture.connection.id
        , reservationStaffId = unpackId staff.id
        , reservationXeroEmployeeId = employeeId
        , reservationPayPeriodStart = fixture.periodStart
        , reservationPayPeriodEnd = fixture.periodEnd
        , reservationRequestPayloadJson = Aeson.Array mempty
        , reservationSourceEntries = sourceEntries
        }

remoteDraft :: PreviewFixture -> Text -> XeroTimesheetRef
remoteDraft fixture timesheetId = remoteTimesheet fixture timesheetId "DRAFT"

remoteTimesheet :: PreviewFixture -> Text -> Text -> XeroTimesheetRef
remoteTimesheet fixture timesheetId status =
    XeroTimesheetRef
        { xeroTimesheetId = Just timesheetId
        , xeroTimesheetEmployeeId = "employee-a"
        , xeroTimesheetStartDate = fixture.periodStart
        , xeroTimesheetEndDate = fixture.periodEnd
        , xeroTimesheetStatus = Just status
        , xeroTimesheetHours = Nothing
        , xeroTimesheetLines = []
        , xeroTimesheetRaw = Aeson.object []
        }

expectCreated :: XeroTimesheetReservationOutcome -> IO (XeroSubmissionRun, XeroTimesheetSubmission)
expectCreated (XeroTimesheetReservationsCreated run [submission]) = pure (run, submission)
expectCreated outcome = expectationFailure (cs ("expected one created reservation, got " <> tshow outcome)) >> error "unreachable"

outcomeKind :: XeroTimesheetReservationOutcome -> Text
outcomeKind XeroTimesheetReservationsCreated {}    = "created"
outcomeKind XeroTimesheetReservationsInProgress {} = "in_progress"
outcomeKind XeroTimesheetReservationBlocked {}     = "blocked"
outcomeKind XeroTimesheetReservationInvalid {}     = "invalid"

activeFor :: (?modelContext :: ModelContext) => PreviewFixture -> IO [XeroTimesheetSubmission]
activeFor fixture =
    query @XeroTimesheetSubmission
        |> filterWhere (#xeroConnectionId, unpackId fixture.connection.id)
        |> filterWhere (#xeroEmployeeId, "employee-a" :: Text)
        |> filterWhere (#payPeriodStart, fixture.periodStart)
        |> filterWhere (#payPeriodEnd, fixture.periodEnd)
        |> filterWhereNot (#status, XeroTimesheetSubmissionStatusEnumSuperseded)
        |> fetch

linksFor :: (?modelContext :: ModelContext) => XeroTimesheetSubmission -> IO [XeroTimesheetSubmissionEntry]
linksFor submission =
    query @XeroTimesheetSubmissionEntry
        |> filterWhere (#xeroTimesheetSubmissionId, unpackId submission.id)
        |> fetch
