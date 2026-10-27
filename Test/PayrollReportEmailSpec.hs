module Test.PayrollReportEmailSpec where

import Application.EmailDelivery.Group
import Application.EmailDelivery.ResendWebhook (handleResendWebhook)
import Application.EmailDelivery.Correlation (emailDeliveryMessageId)
import Test.ResendWebhookSpec (signedFixture, webhookBody)
import Application.PayrollReports.Generation (generatePayrollReportSnapshot)
import Application.Helper.Export.PayrollWorkbookConfiguration
import Control.Monad (void)
import Data.IORef
import Data.Time (fromGregorian)
import qualified Data.Aeson as Aeson
import qualified Data.Text as Text
import Generated.Types
import IHP.ControllerPrelude
import IHP.Test.Mocking (withContext)
import Network.Mail.Mime (Mail (..), Address (..), renderMail')
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
                        (cs rendered :: Text) `shouldSatisfy` Text.isInfixOf "Payroll &lt;Venue&gt;"
                    _ -> expectationFailure "Expected one grouped email"
                current <- fetch run.id
                current.status `shouldBe` PayrollReportAccepted
                enqueuePayrollReportOutcome run
                query @AppJob |> filterWhere (#relatedId, Just (unpackId run.id)) |> filterWhere (#payloadSchemaVersion, 2) |> fetchCount `shouldReturn` 1

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
