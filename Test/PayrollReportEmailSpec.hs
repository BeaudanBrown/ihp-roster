module Test.PayrollReportEmailSpec where

import Application.EmailDelivery.Group
import Application.EmailDelivery.ResendWebhook (handleResendWebhook)
import Application.EmailDelivery.Correlation (emailDeliveryMessageId)
import Test.ResendWebhookSpec (signedFixture, webhookBody)
import Application.PayrollReports.Email (buildPayrollReportMail)
import Application.PayrollReports.Generation (generatePayrollReportSnapshot)
import Application.Helper.Export.PayrollWorkbookConfiguration
import Control.Monad (void)
import Data.Either (isLeft)
import Data.IORef
import Data.Time (fromGregorian)
import qualified Data.Aeson as Aeson
import qualified Data.Text as Text
import Generated.Types
import IHP.ControllerPrelude
import IHP.Test.Mocking (withContext)
import Network.Mail.Mime (Mail (..), Address (..), Part (..), PartContent (..), renderMail')
import Test.Hspec
import Test.Support
import Test.PayrollWorkbookConfigurationSpec (expectRight)

makeRun :: (?modelContext :: ModelContext) => Bool -> IO PayrollReportRun
makeRun approved = do
    venue <- createVenueWithConfig "Payroll <Venue>"
    admin <- createUserRecord "payroll-owner@example.com" "admin" True
    _ <- createVenueMembershipRecord venue admin VenueOwner
    template <- createStandardPayrollWorkbookConfigurationInCurrentTransaction venue admin
    _ <- newRecord @PayrollReportSetting
        |> set #venueId (unpackId venue.id)
        |> set #configurationId (Just (unpackId template.savedPayrollWorkbookConfigurationRecord.id))
        |> set #recipients ["accountant@example.com", "owner@example.com"]
        |> set #updatedByUserId (unpackId admin.id)
        |> createRecord
    when approved do
        staff <- createStaffRecord venue (Just admin) "Payroll" "Staff"
        void (createApprovedTimesheetEntryRecord venue staff admin (fromGregorian 2025 1 6))
    now <- getCurrentTime
    generatePayrollReportSnapshot venue.id (unpackId admin.id) PayrollReportManual Nothing (fromGregorian 2025 1 6) now >>= expectRight

queuedJob :: (?modelContext :: ModelContext) => PayrollReportRun -> IO AppJob
queuedJob run = do
    enqueuePayrollReportOutcome run
    query @AppJob |> filterWhere (#relatedId, Just (unpackId run.id)) |> filterWhere (#payloadSchemaVersion, 2) |> fetchOne

mailTextBodies :: Mail -> [Text]
mailTextBodies mail = concatMap body (concat mail.mailParts)
  where
    body part = case part.partContent of
        PartContent bytes | "text/" `Text.isPrefixOf` part.partType -> [cs bytes]
        NestedParts parts -> concatMap body parts
        _ -> []

tests :: Spec
tests = aroundAll withDatabaseTestContext do
    describe "Payroll group email delivery" do
        it "sends one XLSX email with all recipients in To and Reply-To and permanent run dedupe" $ withContext do
            withCleanDb do
                run <- makeRun True
                job <- queuedJob run
                messages <- newIORef []
                let runtime = GroupDeliveryRuntime (pure False) (\mail -> modifyIORef' messages (mail :))
                performGroupEmailDeliveryWith runtime job
                performGroupEmailDeliveryWith runtime job
                sent <- readIORef messages
                length sent `shouldBe` 1
                case sent of
                    [mail] -> do
                        map addressEmail mail.mailTo `shouldBe` run.recipients
                        addressEmail mail.mailFrom `shouldBe` "reports@bepis.lol"
                        lookup "Reply-To" mail.mailHeaders `shouldBe` Just "<accountant@example.com>, <owner@example.com>"
                        lookup "Message-ID" mail.mailHeaders `shouldSatisfy` isJust
                        rendered <- renderMail' mail
                        (cs rendered :: Text) `shouldSatisfy` Text.isInfixOf "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
                        lookup "Subject" mail.mailHeaders `shouldBe` Just "Bepis - Payroll Workbook - 6–12 January 2025"
                        (cs rendered :: Text) `shouldSatisfy` (not . Text.isInfixOf "Payroll &lt;Venue&gt;")
                        length (mailTextBodies mail) `shouldBe` 2
                        forM_ (mailTextBodies mail) \body -> do
                            body `shouldSatisfy` Text.isInfixOf "The attached workbook includes approved timesheets only."
                            body `shouldSatisfy` Text.isInfixOf "No timesheets are awaiting approval for this period."
                            body `shouldSatisfy` Text.isInfixOf "This email was generated automatically by Bepis."
                        (cs rendered :: Text) `shouldSatisfy` (not . Text.isInfixOf "All recipients can see")
                        (cs rendered :: Text) `shouldSatisfy` (not . Text.isInfixOf "Any scheduled send")
                        (cs rendered :: Text) `shouldSatisfy` Text.isInfixOf "<p>"
                        (cs rendered :: Text) `shouldSatisfy` (not . Text.isInfixOf "<pre>")
                    _ -> expectationFailure "Expected one grouped email"
                current <- fetch run.id
                current.status `shouldBe` PayrollReportAccepted
                enqueuePayrollReportOutcome run
                query @AppJob |> filterWhere (#relatedId, Just (unpackId run.id)) |> filterWhere (#payloadSchemaVersion, 2) |> fetchCount `shouldReturn` 1

        it "uses the frozen template name and readable dates, not a later template rename" $ withContext do
            withCleanDb do
                run <- makeRun False
                forM_ run.configurationId \configurationId -> do
                    template <- fetch (Id configurationId :: Id PayrollWorkbookConfiguration)
                    void (template |> set #name "Renamed after preparation" |> updateRecord)
                original <- buildPayrollReportMail run Nothing |> expectRight
                lookup "Subject" original.mailHeaders `shouldBe` Just "Bepis - Payroll Workbook - 6–12 January 2025"
                forM_
                    [ (fromGregorian 2026 9 22, fromGregorian 2026 9 28, "22–28 September 2026")
                    , (fromGregorian 2026 9 28, fromGregorian 2026 10 4, "28 September–4 October 2026")
                    , (fromGregorian 2026 12 28, fromGregorian 2027 1 3, "28 December 2026–3 January 2027")
                    ] \(start, end, dates) -> do
                        mail <- buildPayrollReportMail (run |> set #reportingWeek start |> set #rangeEnd end) Nothing |> expectRight
                        lookup "Subject" mail.mailHeaders `shouldBe` Just ("Bepis - Payroll Workbook - " <> dates)
                sanitized <- buildPayrollReportMail (run |> set #templateSnapshot (Aeson.object ["name" Aeson..= ("Weekly\r\nPayroll" :: Text)])) Nothing |> expectRight
                lookup "Subject" sanitized.mailHeaders `shouldBe` Just "Bepis - WeeklyPayroll - 6–12 January 2025"
                buildPayrollReportMail (run |> set #templateSnapshot (Aeson.object [])) Nothing `shouldSatisfy` isLeft

        it "retains missing-attachment, excluded-entry and exceptional delivery warnings" $ withContext do
            withCleanDb do
                run <- makeRun False
                forM_
                    [ (run, ["No approved timesheets were found. No workbook is attached.", "No timesheets are awaiting approval"])
                    , (run |> set #excludedEntryCount 2, ["2 unapproved timesheets were excluded", "This report may be incomplete."])
                    , (run |> set #origin PayrollReportUpdated, ["UPDATED REPORT:"])
                    , (run |> set #origin PayrollReportScheduled |> set #scheduledAt (Just (addUTCTime (-120) run.createdAt)), ["This scheduled report was delayed."])
                    ] \(variant, expected) -> do
                        mail <- buildPayrollReportMail variant Nothing |> expectRight
                        forM_ (mailTextBodies mail) \body -> do
                            forM_ expected \message -> body `shouldSatisfy` Text.isInfixOf message
                            body `shouldSatisfy` Text.isInfixOf "This email was generated automatically by Bepis."
                buildPayrollReportMail (run |> set #approvedEntryCount 1) Nothing `shouldSatisfy` isLeft

        it "never blindly retries an ambiguous SMTP result and emits one minimal support incident" $ withContext do
            withCleanDb do
                _ <- createUserRecordWithPlatformRole "support@example.com" "staff" (Just SuperAdmin) True
                inactive <- createUserRecordWithPlatformRole "inactive@example.com" "staff" (Just SuperAdmin) True
                now <- getCurrentTime
                _ <- inactive |> set #deactivatedAt (Just now) |> updateRecord
                run <- makeRun False
                job <- queuedJob run
                attempts <- newIORef (0 :: Int)
                let runtime = GroupDeliveryRuntime (pure False) (\_ -> modifyIORef' attempts (+ 1) >> ioError (userError "private provider diagnostic"))
                performGroupEmailDeliveryWith runtime job
                performGroupEmailDeliveryWith runtime job
                readIORef attempts `shouldReturn` 1
                current <- fetch run.id
                current.status `shouldBe` PayrollReportAmbiguous
                finished <- fetch job.id
                (cs (Aeson.encode finished.result) :: Text) `shouldSatisfy` (not . Text.isInfixOf "private")
                incidents <- query @OperationalIncident |> filterWhere (#category, "payroll_report") |> fetch
                length incidents `shouldBe` 1
                recipients <- query @OperationalIncidentEventRecipient |> fetch
                map (.recipientAddress) recipients `shouldBe` ["support@example.com"]

        it "cancels revoked snapshots and never replays disabled delivery" $ withContext do
            withCleanDb do
                run <- makeRun False
                job <- queuedJob run
                Just settingsId <- pure run.settingsId
                setting <- fetch (Id settingsId :: Id PayrollReportSetting)
                _ <- setting |> set #deliveryRevision (setting.deliveryRevision + 1) |> updateRecord
                let noSend = \_ -> expectationFailure "Transport must not run"
                performGroupEmailDeliveryWith (GroupDeliveryRuntime (pure False) noSend) job
                cancelled <- fetch run.id
                cancelled.status `shouldBe` PayrollReportCancelled
                now <- getCurrentTime
                next <- generatePayrollReportSnapshot (Id run.venueId) run.requestedByUserId PayrollReportUpdated Nothing run.reportingWeek now >>= expectRight
                nextJob <- queuedJob next
                performGroupEmailDeliveryWith (GroupDeliveryRuntime (pure True) noSend) nextJob
                performGroupEmailDeliveryWith (GroupDeliveryRuntime (pure False) noSend) nextJob
                disabled <- fetch next.id
                disabled.status `shouldBe` PayrollReportDisabled

        it "retains a group recipient failure even after another recipient is reported delivered" $ withContext do
            withCleanDb do
                run <- makeRun False
                job <- queuedJob run
                performGroupEmailDeliveryWith (GroupDeliveryRuntime (pure False) (const (pure ()))) job
                now <- getCurrentTime
                let delivered = webhookBody "email.delivered" now "payroll-group-test" (Just (emailDeliveryMessageId job))
                    (secret, deliveredHeaders) = signedFixture now delivered "group-delivered"
                _ <- handleResendWebhook now secret deliveredHeaders delivered
                let bounced = webhookBody "email.bounced" (addUTCTime (-60) now) "payroll-group-test" (Just (emailDeliveryMessageId job))
                    (_, bouncedHeaders) = signedFixture now bounced "group-bounced"
                _ <- handleResendWebhook now secret bouncedHeaders bounced
                _ <- handleResendWebhook now secret bouncedHeaders bounced
                recordPayrollReportProviderFailure job "delivered"
                current <- fetch run.id
                current.status `shouldBe` PayrollReportBounced

        it "refuses expired payroll attachments without sending or regenerating them" $ withContext do
            withCleanDb do
                run <- makeRun True
                job <- queuedJob run
                forM_ run.exportJobId \exportId -> do
                    export <- fetch (Id exportId :: Id ExportJob)
                    _ <- export |> set #expiresAt (UTCTime (fromGregorian 2025 1 1) 0) |> updateRecord
                    pure ()
                performGroupEmailDeliveryWith (GroupDeliveryRuntime (pure False) (const (expectationFailure "Expired payroll must not be sent"))) job
                current <- fetch run.id
                current.status `shouldBe` PayrollReportFailed
