module Test.PayrollReportSelectionSpec where

import Application.EmailDelivery.Group
import Application.Helper.Export.PayrollWorkbookConfiguration
import Application.PayrollReports.Generation hiding (week)
import qualified Application.PayrollReports.Generation as Generation
import Application.PayrollReports.Manual
import Application.PayrollReports.Selection
import qualified Application.PayrollReports.Selection as Selection
import Application.PayrollReports.Settings
import qualified Application.PayrollReports.Settings as Settings
import Application.RecipientGroups
import qualified Application.RecipientGroups as Groups
import Control.Concurrent.Async (concurrently)
import Data.Either (isLeft, isRight)
import Data.IORef
import qualified Data.UUID.V4 as UUID
import Generated.Types
import IHP.ControllerPrelude hiding (request)
import IHP.Test.Mocking (withContext)
import Network.Mail.Mime (Mail (..), Address (..))
import Test.Hspec
import Test.Support
import Test.PayrollWorkbookConfigurationSpec (asCurrentVenueUser, expectRight)
import qualified Test.RecipientGroupsSpec as GroupsFixture
import qualified Test.PayrollReportSettingsSpec as SettingsFixture

week :: Day
week = fromGregorian 2025 1 6

-- No schedule is created by this fixture or by standalone preparation.
setup :: (?modelContext :: ModelContext) => IO (Venue, User, UUID)
setup = do
    venue <- createVenueWithConfig "Selected exports"
    admin <- createUserRecord "selected-admin@example.com" "admin" True
    _ <- createVenueMembershipRecord venue admin VenueAdmin
    template <- createStandardPayrollWorkbookConfigurationInCurrentTransaction venue admin
    pure (venue, admin, unpackId template.savedPayrollWorkbookConfigurationRecord.id)

request :: Id Venue -> UUID -> UUID -> ManualReportSelection -> ReportGenerationRequest
request venueId actorId runId selection = ReportGenerationRequest
    { venueId, actorId, runId
    , origin = PayrollReportManual, scheduledAt = Nothing
    , Generation.week = week, now = UTCTime (fromGregorian 2025 1 14) 0
    , expectedRevision = Nothing, previousRunId = Nothing, manualSelection = Just selection
    }

tests :: Spec
tests = aroundAll withDatabaseTestContext do
    describe "Payroll report selection" do
        it "prepares and delivers approved data for an explicit template/group without automatic settings" $ withContext do
            withCleanDb do
                (venue, admin, templateId) <- setup
                staff <- createStaffRecord venue (Just admin) "Selected" "Staff"
                _ <- createApprovedTimesheetEntryRecord venue staff admin week
                asCurrentVenueUser admin venue.id do
                    group <- saveRecipientGroup Nothing GroupsFixture.input >>= expectRight
                    preview <- previewManualPayrollReport templateId (unpackId group.id) week >>= expectRight
                    preview.repeatWarning `shouldBe` False
                    preview.selected.group.recipients `shouldBe` group.recipients
                    token <- UUID.nextRandom
                    run <- requestSelectedManualPayrollReport token preview.selection week >>= expectRight
                    run.settingsId `shouldBe` Nothing
                    run.configurationId `shouldBe` Just templateId
                    run.recipientGroupId `shouldBe` Just (unpackId group.id)
                    run.recipientGroupRevision `shouldBe` Just 0
                    run.approvedEntryCount `shouldBe` 1
                    run.exportJobId `shouldSatisfy` isJust
                    run.status `shouldBe` PayrollReportReady
                    query @PayrollReportSetting |> fetchCount `shouldReturn` 0
                    Just exportId <- pure run.exportJobId
                    artifact <- fetch (Id exportId :: Id ExportJob)
                    _ <- saveRecipientGroup (Just group.id) (GroupsFixture.input { Groups.expectedRevision = Just 0, Groups.recipients = ["later@example.com"] }) >>= expectRight
                    retained <- fetch (Id exportId :: Id ExportJob)
                    retained.fileContents `shouldBe` artifact.fileContents
                    job <- query @AppJob |> filterWhere (#relatedId, Just token) |> filterWhere (#payloadSchemaVersion, 2) |> fetchOne
                    sent <- newIORef []
                    performGroupEmailDeliveryWith (GroupDeliveryRuntime (pure False) (\mail -> modifyIORef' sent (map addressEmail mail.mailTo :))) job
                    readIORef sent `shouldReturn` [group.recipients]
                    accepted <- fetch run.id
                    accepted.status `shouldBe` PayrollReportAccepted

        it "keeps no-data snapshots eligible after group edits/deletion and unrelated schedule changes" $ withContext do
            withCleanDb do
                (venue, admin, templateId) <- setup
                asCurrentVenueUser admin venue.id do
                    group <- saveRecipientGroup Nothing GroupsFixture.input >>= expectRight
                    preview <- previewManualPayrollReport templateId (unpackId group.id) week >>= expectRight
                    token <- UUID.nextRandom
                    run <- requestSelectedManualPayrollReport token preview.selection week >>= expectRight
                    run.status `shouldBe` PayrollReportNoData
                    run.exportJobId `shouldBe` Nothing
                    queued <- fetch run.id
                    changed <- saveRecipientGroup (Just group.id) (GroupsFixture.input { Groups.expectedRevision = Just 0, Groups.recipients = ["replacement@example.com"] }) >>= expectRight
                    settings <- savePayrollReportSettings (SettingsFixture.input { Settings.configurationId = Just templateId }) >>= expectRight
                    _ <- savePayrollReportSettings (SettingsFixture.input { Settings.expectedRevision = Just settings.revision, Settings.recipients = ["different@example.com"], Settings.configurationId = Just templateId }) >>= expectRight
                    deleteRecipientGroup group.id changed.revision False `shouldReturn` Right ()
                    deleteSavedPayrollWorkbookConfiguration (Id templateId) `shouldReturn` Left PayrollWorkbookConfigurationScheduleConfirmationRequired
                    deleteSavedPayrollWorkbookConfigurationConfirmingScheduleDisable True (Id templateId) `shouldReturn` Right ()
                    fetch run.id `shouldReturn` queued
                    replay <- requestSelectedManualPayrollReport token preview.selection week >>= expectRight
                    replay.id `shouldBe` run.id
                    replay.recipients `shouldBe` group.recipients
                    job <- query @AppJob |> filterWhere (#relatedId, Just token) |> filterWhere (#payloadSchemaVersion, 2) |> fetchOne
                    sent <- newIORef []
                    performGroupEmailDeliveryWith (GroupDeliveryRuntime (pure False) (\mail -> modifyIORef' sent (map addressEmail mail.mailTo :))) job
                    readIORef sent `shouldReturn` [group.recipients]

        it "requires re-review after group/template/calendar changes before preparation" $ withContext do
            withCleanDb do
                (venue, admin, templateId) <- setup
                asCurrentVenueUser admin venue.id do
                    group <- saveRecipientGroup Nothing GroupsFixture.input >>= expectRight
                    preview <- previewManualPayrollReport templateId (unpackId group.id) week >>= expectRight
                    _ <- saveRecipientGroup (Just group.id) (GroupsFixture.input { Groups.expectedRevision = Just 0, Groups.recipients = ["new@example.com"] }) >>= expectRight
                    token <- UUID.nextRandom
                    requestSelectedManualPayrollReport token preview.selection week >>= (`shouldSatisfy` isLeft)
                    fresh <- previewManualPayrollReport templateId (unpackId group.id) week >>= expectRight
                    template <- fetch (Id templateId :: Id PayrollWorkbookConfiguration)
                    _ <- template |> set #revision (template.revision + 1) |> updateRecord
                    requestSelectedManualPayrollReport token fresh.selection week >>= (`shouldSatisfy` isLeft)
                    refreshed <- previewManualPayrollReport templateId (unpackId group.id) week >>= expectRight
                    config <- query @VenueConfig |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                    _ <- config |> set #timezone "Australia/Perth" |> updateRecord
                    requestSelectedManualPayrollReport token refreshed.selection week >>= (`shouldSatisfy` isLeft)
                    query @PayrollReportRun |> fetchCount `shouldReturn` 0

        it "rejects managers, foreign IDs, and unfinished or misaligned periods" $ withContext do
            withCleanDb do
                (venue, admin, templateId) <- setup
                other <- createVenueWithConfig "Other"
                _ <- createVenueMembershipRecord other admin VenueAdmin
                manager <- createUserRecord "selected-manager@example.com" "manager" True
                _ <- createVenueMembershipRecord venue manager Manager
                group <- asCurrentVenueUser admin venue.id (saveRecipientGroup Nothing GroupsFixture.input) >>= expectRight
                foreignGroup <- asCurrentVenueUser admin other.id (saveRecipientGroup Nothing GroupsFixture.input) >>= expectRight
                foreignTemplate <- createStandardPayrollWorkbookConfigurationInCurrentTransaction other admin
                asCurrentVenueUser admin venue.id do
                    (isLeft <$> previewManualPayrollReport templateId (unpackId foreignGroup.id) week) `shouldReturn` True
                    (isLeft <$> previewManualPayrollReport (unpackId foreignTemplate.savedPayrollWorkbookConfigurationRecord.id) (unpackId group.id) week) `shouldReturn` True
                    forM_ [fromGregorian 2099 1 5, addDays 1 week] \period ->
                        (isLeft <$> previewManualPayrollReport templateId (unpackId group.id) period) `shouldReturn` True
                    preview <- previewManualPayrollReport templateId (unpackId group.id) week >>= expectRight
                    token <- UUID.nextRandom
                    requestSelectedManualPayrollReport token (preview.selection { Selection.recipientGroupId = unpackId foreignGroup.id }) week >>= (`shouldSatisfy` isLeft)
                    asCurrentVenueUser manager venue.id do
                        (isLeft <$> previewManualPayrollReport templateId (unpackId group.id) week) `shouldReturn` True
                        requestSelectedManualPayrollReport token preview.selection week `shouldReturn` Left "Payroll report access denied."

        it "warns on same-template/week repeats across different groups and requires explicit acknowledgement" $ withContext do
            withCleanDb do
                (venue, admin, templateId) <- setup
                asCurrentVenueUser admin venue.id do
                    group <- saveRecipientGroup Nothing GroupsFixture.input >>= expectRight
                    other <- saveRecipientGroup Nothing (GroupsFixture.input { Groups.name = "Other", Groups.recipients = ["other@example.com"] }) >>= expectRight
                    preview <- previewManualPayrollReport templateId (unpackId group.id) week >>= expectRight
                    firstToken <- UUID.nextRandom
                    first <- requestSelectedManualPayrollReport firstToken preview.selection week >>= expectRight
                    secondPreview <- previewManualPayrollReport templateId (unpackId other.id) week >>= expectRight
                    secondPreview.repeatWarning `shouldBe` True
                    secondToken <- UUID.nextRandom
                    requestSelectedManualPayrollReport secondToken secondPreview.selection week >>= (`shouldSatisfy` isLeft)
                    second <- requestSelectedManualPayrollReport secondToken (secondPreview.selection { Selection.repeatSendConfirmed = True }) week >>= expectRight
                    second.id `shouldNotBe` first.id
                    second.recipients `shouldBe` other.recipients
                    query @PayrollReportRun |> fetchCount `shouldReturn` 2
                    third <- createSavedPayrollWorkbookConfiguration (NewPayrollWorkbookConfiguration "Another template" 1 ["summary"]) >>= expectRight
                    thirdPreview <- previewManualPayrollReport (unpackId third.savedPayrollWorkbookConfigurationRecord.id) (unpackId group.id) week >>= expectRight
                    thirdPreview.repeatWarning `shouldBe` False

        it "distinguishes prepared/accepted/uncertain repeat warnings from unsent terminal outcomes" $ withContext do
            withCleanDb do
                (venue, admin, templateId) <- setup
                asCurrentVenueUser admin venue.id do
                    group <- saveRecipientGroup Nothing GroupsFixture.input >>= expectRight
                    preview <- previewManualPayrollReport templateId (unpackId group.id) week >>= expectRight
                    token <- UUID.nextRandom
                    run <- requestSelectedManualPayrollReport token preview.selection week >>= expectRight
                    forM_ [PayrollReportReady, PayrollReportNoData, PayrollReportQueued, PayrollReportAccepted, PayrollReportBounced, PayrollReportAmbiguous] \status -> do
                        _ <- run |> set #status status |> updateRecord
                        payrollReportAlreadyPrepared venue.id templateId week `shouldReturn` True
                    forM_ [PayrollReportFailed, PayrollReportCancelled, PayrollReportMissed, PayrollReportDisabled] \status -> do
                        _ <- run |> set #status status |> updateRecord
                        payrollReportAlreadyPrepared venue.id templateId week `shouldReturn` False

        it "does not blindly retry standalone SMTP uncertainty" $ withContext do
            withCleanDb do
                (venue, admin, templateId) <- setup
                asCurrentVenueUser admin venue.id do
                    group <- saveRecipientGroup Nothing GroupsFixture.input >>= expectRight
                    preview <- previewManualPayrollReport templateId (unpackId group.id) week >>= expectRight
                    token <- UUID.nextRandom
                    run <- requestSelectedManualPayrollReport token preview.selection week >>= expectRight
                    job <- query @AppJob |> filterWhere (#relatedId, Just token) |> filterWhere (#payloadSchemaVersion, 2) |> fetchOne
                    attempts <- newIORef (0 :: Int)
                    let runtime = GroupDeliveryRuntime (pure False) (\_ -> modifyIORef' attempts (+ 1) >> ioError (userError "synthetic transport failure"))
                    performGroupEmailDeliveryWith runtime job
                    performGroupEmailDeliveryWith runtime job
                    readIORef attempts `shouldReturn` 1
                    current <- fetch run.id
                    current.status `shouldBe` PayrollReportAmbiguous

        it "deduplicates simultaneous confirmations and rejects changing immutable selection facts on retry" $ withContext do
            withCleanDb do
                (venue, admin, templateId) <- setup
                group <- asCurrentVenueUser admin venue.id (saveRecipientGroup Nothing GroupsFixture.input) >>= expectRight
                preview <- asCurrentVenueUser admin venue.id (previewManualPayrollReport templateId (unpackId group.id) week) >>= expectRight
                token <- UUID.nextRandom
                let generation = request venue.id (unpackId admin.id) token preview.selection
                (first, second) <- concurrently (generatePayrollReportRequest generation) (generatePayrollReportRequest generation)
                firstRun <- expectRight first
                secondRun <- expectRight second
                firstRun.id `shouldBe` secondRun.id
                query @PayrollReportRun |> fetchCount `shouldReturn` 1
                let changed = preview.selection { Selection.recipientGroupRevision = preview.selection.recipientGroupRevision + 1 }
                generatePayrollReportRequest (generation { manualSelection = Just changed }) >>= (`shouldSatisfy` isLeft)
                generatePayrollReportRequest (generation { Generation.week = addDays (-7) week }) >>= (`shouldSatisfy` isLeft)

        it "rechecks repeat facts after waiting for a concurrent different confirmation" $ withContext do
            withCleanDb do
                (venue, admin, templateId) <- setup
                group <- asCurrentVenueUser admin venue.id (saveRecipientGroup Nothing GroupsFixture.input) >>= expectRight
                preview <- asCurrentVenueUser admin venue.id (previewManualPayrollReport templateId (unpackId group.id) week) >>= expectRight
                firstToken <- UUID.nextRandom
                secondToken <- UUID.nextRandom
                (first, second) <- concurrently
                    (generatePayrollReportRequest (request venue.id (unpackId admin.id) firstToken preview.selection))
                    (generatePayrollReportRequest (request venue.id (unpackId admin.id) secondToken preview.selection))
                length (filter isRight [first, second]) `shouldBe` 1
                length (filter isLeft [first, second]) `shouldBe` 1
                query @PayrollReportRun |> fetchCount `shouldReturn` 1

        it "uses current group addresses for future automatic preparation without revoking earlier snapshots" $ withContext do
            withCleanDb do
                (venue, admin, templateId) <- setup
                asCurrentVenueUser admin venue.id do
                    group <- saveRecipientGroup Nothing GroupsFixture.input >>= expectRight
                    setting <- savePayrollReportSettings (SettingsFixture.input { Settings.enabled = True, Settings.configurationId = Just templateId }) >>= expectRight
                    _ <- setting |> set #recipientGroupId (Just (unpackId group.id))
                        |> set #scheduleActivatedAt (UTCTime (fromGregorian 2025 1 1) 0) |> updateRecord
                    let due = UTCTime (fromGregorian 2025 1 13) (22 * 3600)
                    first <- generatePayrollReportSnapshot venue.id (unpackId admin.id) PayrollReportScheduled (Just due) week due >>= expectRight
                    first.recipients `shouldBe` group.recipients
                    changed <- saveRecipientGroup (Just group.id) (GroupsFixture.input { Groups.expectedRevision = Just 0, Groups.recipients = ["new@example.com"] }) >>= expectRight
                    let later = addUTCTime 604800 due
                    second <- generatePayrollReportSnapshot venue.id (unpackId admin.id) PayrollReportScheduled (Just later) (addDays 7 week) later >>= expectRight
                    second.recipients `shouldBe` changed.recipients
                    second.recipientGroupRevision `shouldBe` Just changed.revision
                    fetch first.id `shouldReturn` first
