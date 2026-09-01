module Test.StaffDocumentsRsaSpec where

import Application.EmailDelivery
import Application.StaffDocuments.Rsa
import Application.StaffDocuments.RsaExtraction
import Config (config)
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as AesonKey
import qualified Data.Aeson.Types as AesonTypes
import qualified Data.ByteString.Lazy as LBS
import Data.IORef (modifyIORef', newIORef, readIORef)
import qualified Data.Text as Text
import qualified Data.Text.Lazy as LText
import Data.Time.Calendar (addDays, fromGregorian)
import Data.Time.Clock (getCurrentTime, utctDay)
import Generated.Types
import IHP.ControllerPrelude
import IHP.FrameworkConfig (withFrameworkConfig)
import IHP.Job.Types
import IHP.Prelude
import IHP.Test.Mocking
import qualified IHP.ViewSupport as ViewSupport
import Test.Hspec
import Test.Support
import Test.Support.EmailDelivery
import qualified Text.Blaze.Html.Renderer.Text as HtmlRenderer
import Web.View.StaffDocuments.Rsa (RsaReturnContext (..))
import Web.View.StaffDocuments.RsaScan

tests :: Spec
tests = aroundAll withDatabaseTestContext do
    describe "RSA PDF extraction" do
        let sampleText = Text.unlines
                [ "Victorian Responsible Service of Alcohol Certificate"
                , "This is to certify that Riley RSA has successfully completed RSA training"
                , "Certificate Number: RSA-12345"
                , "Issued by: Victorian Commission for Gambling and Liquor Regulation"
                , "Valid from/until: 21 January 2024 - 21 January 2027"
                ]

        it "extracts candidate RSA metadata from sanitized certificate text" \_ -> do
            let result = parseRsaCertificateText sampleText
            result.failureReason `shouldBe` Nothing
            result.candidate.issueDate `shouldBe` Just (fromGregorian 2024 1 21)
            result.candidate.expiryDate `shouldBe` Just (fromGregorian 2027 1 21)
            result.candidate.documentNumber `shouldBe` Just "RSA-12345"
            result.candidate.issuingAuthority `shouldBe` Just "Victorian Commission for Gambling and Liquor Regulation"
            result.candidate.recipientName `shouldBe` Just "Riley RSA"
            result.confidence `shouldSatisfy` (>= 80)

        it "extracts recipient names that appear after a certify marker line" \_ -> do
            let result = parseRsaCertificateText (Text.unlines
                    [ "Certificate of Completion"
                    , "this is to certify that"
                    , "Beaudan Campbell-Brown"
                    , "has completed to satisfaction the"
                    , "Responsible Service of Alcohol Program"
                    , "(online refresher course)"
                    , "approved by Liquor Control Victoria for the"
                    , "Victorian Liquor Commission"
                    , "valid from"
                    , "21 January 2024 - 21 January 2027"
                    , "Chris Carter"
                    , "Chief Operating Officer"
                    , "Certificate No: gsp0130044"
                    ])
            result.candidate.issueDate `shouldBe` Just (fromGregorian 2024 1 21)
            result.candidate.expiryDate `shouldBe` Just (fromGregorian 2027 1 21)
            result.candidate.documentNumber `shouldBe` Just "gsp0130044"
            result.candidate.recipientName `shouldBe` Just "Beaudan Campbell-Brown"

        it "parses numeric date ranges and certificate-number variants" \_ -> do
            let result = parseRsaCertificateText (Text.unlines
                    [ "RSA Statement of Attainment"
                    , "Name: Jordan Worker"
                    , "Document No: CERT/9876"
                    , "RTO: Example Training Pty Ltd"
                    , "10/02/2025 - 10/02/2028"
                    ])
            result.candidate.issueDate `shouldBe` Just (fromGregorian 2025 2 10)
            result.candidate.expiryDate `shouldBe` Just (fromGregorian 2028 2 10)
            result.candidate.documentNumber `shouldBe` Just "CERT/9876"
            result.candidate.issuingAuthority `shouldBe` Just "Example Training Pty Ltd"
            result.candidate.recipientName `shouldBe` Just "Jordan Worker"

        it "reports scanned or empty PDF text as a manual-entry fallback" \_ -> do
            let result = parseRsaCertificateText "   \n"
            result.failureReason `shouldBe` Just RsaExtractionNoTextLayer
            result.confidence `shouldBe` 0
            result.warnings `shouldSatisfy` elem "No text was extracted from the PDF; manual entry is required."

        it "warns when parser confidence is low" \_ -> do
            let result = parseRsaCertificateText "Certificate\nSome unrelated training text\n"
            result.failureReason `shouldBe` Nothing
            result.warnings `shouldSatisfy` elem "Extracted text does not contain an obvious RSA keyword."
            result.warnings `shouldSatisfy` elem "Expiry date was not confidently detected."

        it "renders extracted recipient mismatch as a confirmation warning" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "RSA Mismatch Venue"
                user <- createUserRecord "rsa-mismatch@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user Worker
                staff <- createStaffRecord venue (Just user) "Casey" "Certificate"
                let baseResult = parseRsaCertificateText sampleText
                    scanResult = baseResult { candidate = baseResult.candidate { recipientName = Just "Riley RSA" } }
                    confirmation = RsaScanConfirmation
                        { scanStaff = staff
                        , scanIssueDate = scanResult.candidate.issueDate
                        , scanExpiryDate = scanResult.candidate.expiryDate
                        , scanIssuingAuthority = scanResult.candidate.issuingAuthority
                        , scanDocumentNumber = scanResult.candidate.documentNumber
                        , scanFileName = "mismatch-rsa.pdf"
                        , scanContentType = "application/pdf"
                        , scanFileContents = "bWlzbWF0Y2g="
                        , scanExtractionResult = scanResult
                        , scanReturnContext = RsaReturnContext "profile" Nothing Nothing
                        }

                rendered <- withUserAndCurrentVenue user venue.id do
                    withCurrentControllerContext do
                        let view = ScanView { scanConfirmation = confirmation }
                        let ?view = view
                        pure (LText.toStrict (HtmlRenderer.renderHtml (ViewSupport.html view)))

                rendered `shouldSatisfy` Text.isInfixOf "does not exactly match selected staff member"
                rendered `shouldSatisfy` Text.isInfixOf "Confirm RSA metadata"
                rendered `shouldSatisfy` Text.isInfixOf "href=\"/EditProfile\""
                rendered `shouldNotSatisfy` Text.isInfixOf "section=rsa"

    describe "RSA staff documents" do
        it "calculates compliance status from the latest document state" $ withContext do
            let today = fromGregorian 2026 5 2
            effectiveRsaComplianceStatus today Nothing `shouldBe` StaffRsaMissing
            effectiveRsaComplianceStatus today (Just (rsaStatusFixture PendingReview (addDays 60 today))) `shouldBe` StaffRsaPendingReview
            effectiveRsaComplianceStatus today (Just (rsaStatusFixture Rejected (addDays 60 today))) `shouldBe` StaffRsaRejected
            effectiveRsaComplianceStatus today (Just (rsaStatusFixture Expired (addDays 60 today))) `shouldBe` StaffRsaExpired
            effectiveRsaComplianceStatus today (Just (rsaStatusFixture StaffDocumentStatusEnumVerified (addDays (-1) today))) `shouldBe` StaffRsaExpired
            effectiveRsaComplianceStatus today (Just (rsaStatusFixture StaffDocumentStatusEnumVerified (addDays 20 today))) `shouldBe` StaffRsaExpiringSoon 20
            effectiveRsaComplianceStatus today (Just (rsaStatusFixture StaffDocumentStatusEnumVerified (addDays 60 today))) `shouldBe` StaffRsaVerified

        it "models pending RSA uploads as replacements without discarding the older current row" $ withContext do
            let today = fromGregorian 2026 5 2
                current = rsaStatusFixture StaffDocumentStatusEnumVerified (addDays 60 today)
                pending = rsaStatusFixture PendingReview (addDays 365 today)
                state = effectiveRsaState today [pending, current]

            state.rsaCurrentDocument `shouldBe` Just current
            state.rsaPendingReplacement `shouldBe` Just pending
            state.rsaRejectedReplacement `shouldBe` Nothing
            state.rsaEffectiveStatus `shouldBe` StaffRsaPendingReplacement

        it "keeps an older verified RSA current when a replacement is rejected" $ withContext do
            let today = fromGregorian 2026 5 2
                current = rsaStatusFixture StaffDocumentStatusEnumVerified (addDays 60 today)
                rejected = rsaStatusFixture Rejected (addDays 365 today)
                state = effectiveRsaState today [rejected, current]

            state.rsaCurrentDocument `shouldBe` Just current
            state.rsaPendingReplacement `shouldBe` Nothing
            state.rsaRejectedReplacement `shouldBe` Just rejected
            state.rsaEffectiveStatus `shouldBe` StaffRsaVerified

        it "creates RSA document rows without storing onboarding-sensitive data" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "RSA Venue"
                user <- createUserRecord "rsa-worker@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user Worker
                staff <- createStaffRecord venue (Just user) "Riley" "RSA"

                staffDocument <- createRsaDocument user.id staff (testRsaUpload (fromGregorian 2027 5 2))

                staffDocument.venueId `shouldBe` unpackId venue.id
                staffDocument.staffId `shouldBe` unpackId staff.id
                staffDocument.documentType `shouldBe` RsaStatementOfAttainment
                staffDocument.status `shouldBe` PendingReview
                staffDocument.contentType `shouldBe` "application/pdf"
                staffDocument.fileEncoding `shouldBe` "base64"
                decodeStaffDocumentFile staffDocument `shouldBe` Right (LBS.fromStrict "rsa-bytes")

                [row] <- staffRsaComplianceRowsForVenue venue.id
                row.complianceStaff.id `shouldBe` staff.id
                fmap (.id) row.complianceDocument `shouldBe` Just staffDocument.id

        it "enqueues due RSA reminders and deduplicates active jobs" $ withContext do
            withCleanDb do
                today <- utctDay <$> getCurrentTime
                venue <- createVenueWithConfig "RSA Reminder Venue"
                user <- createUserRecord "rsa-reminder@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user Worker
                staff <- createStaffRecord venue (Just user) "Remy" "Reminder"
                staffDocument <- createVerifiedRsaDocument user staff (addDays 20 today)

                firstSummary <- enqueueDueRsaReminderJobs today
                firstSummary.dueRsaReminderCount `shouldBe` 1
                firstSummary.enqueuedRsaReminderCount `shouldBe` 1
                firstSummary.existingRsaReminderCount `shouldBe` 0

                secondSummary <- enqueueDueRsaReminderJobs today
                secondSummary.dueRsaReminderCount `shouldBe` 1
                secondSummary.enqueuedRsaReminderCount `shouldBe` 0
                secondSummary.existingRsaReminderCount `shouldBe` 1

                [job] <- query @AppJob |> filterWhere (#jobKind, emailDeliveryJobKind) |> fetch
                job.venueId `shouldBe` Just (unpackId venue.id)
                job.relatedTable `shouldBe` Just "staff_documents"
                job.relatedId `shouldBe` Just (unpackId staffDocument.id)
                payloadText "mailKind" job `shouldBe` Just (rsaReminderMailKind RsaReminderExpiringSoon)
                payloadText "recipientAddress" job `shouldBe` Just user.email
                tshow job.dedupeKey `shouldSatisfy` not . Text.isInfixOf user.email

        it "marks expired RSA reminders as sent and expires the document" $ withContext do
            withCleanDb do
                today <- utctDay <$> getCurrentTime
                venue <- createVenueWithConfig "RSA Expired Reminder Venue"
                user <- createUserRecord "rsa-expired@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user Worker
                staff <- createStaffRecord venue (Just user) "Eli" "Expired"
                staffDocument <- createVerifiedRsaDocument user staff (addDays (-1) today)
                _ <- enqueueDueRsaReminderJobs today
                appJob <- query @AppJob |> filterWhere (#jobKind, emailDeliveryJobKind) |> fetchOne
                calls <- newIORef (0 :: Int)

                withFrameworkConfig config \frameworkConfig -> do
                    let ?context = frameworkConfig
                    performEmailDeliveryJobWith
                        (capturingEmailDeliveryRuntime (\_ -> modifyIORef' calls (+ 1)))
                        appJob

                readIORef calls `shouldReturn` 1
                updatedDocument <- fetch staffDocument.id
                updatedDocument.status `shouldBe` Expired
                updatedDocument.expiredReminderSentAt `shouldSatisfy` isJust
                updatedJob <- fetch appJob.id
                updatedJob.status `shouldBe` JobStatusSucceeded
                payloadText "deliveryStatus" updatedJob `shouldBe` Just "sent"

        it "marks disabled RSA delivery complete without transport or later replay" $ withContext do
            withCleanDb do
                today <- utctDay <$> getCurrentTime
                venue <- createVenueWithConfig "RSA Disabled Reminder Venue"
                user <- createUserRecord "rsa-disabled@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user Worker
                staff <- createStaffRecord venue (Just user) "Drew" "Disabled"
                staffDocument <- createVerifiedRsaDocument user staff (addDays 10 today)
                _ <- enqueueDueRsaReminderJobs today
                appJob <- query @AppJob |> filterWhere (#jobKind, emailDeliveryJobKind) |> fetchOne

                withFrameworkConfig config \frameworkConfig -> do
                    let ?context = frameworkConfig
                    performEmailDeliveryJobWith
                        disabledEmailDeliveryRuntime
                        appJob

                completedDocument <- fetch staffDocument.id
                completedDocument.expiryReminderSentAt `shouldSatisfy` isJust
                completedJob <- fetch appJob.id
                payloadText "deliveryStatus" completedJob `shouldBe` Just "delivery_disabled"
                repeatSummary <- enqueueDueRsaReminderJobs today
                repeatSummary.dueRsaReminderCount `shouldBe` 0

        it "does not mark disabled RSA reminders when account eligibility changed" $ withContext do
            withCleanDb do
                today <- utctDay <$> getCurrentTime
                venue <- createVenueWithConfig "RSA Disabled Eligibility Venue"
                user <- createUserRecord "rsa-disabled-unlinked@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user Worker
                staff <- createStaffRecord venue (Just user) "Uma" "Unlinked"
                staffDocument <- createVerifiedRsaDocument user staff (addDays 10 today)
                _ <- enqueueDueRsaReminderJobs today
                appJob <- query @AppJob |> filterWhere (#jobKind, emailDeliveryJobKind) |> fetchOne
                _ <- staff |> set #userId Nothing |> updateRecord

                withFrameworkConfig config \frameworkConfig -> do
                    let ?context = frameworkConfig
                    performEmailDeliveryJobWith
                        disabledEmailDeliveryRuntime
                        appJob

                unchangedDocument <- fetch staffDocument.id
                unchangedDocument.expiryReminderSentAt `shouldBe` Nothing
                completedJob <- fetch appJob.id
                payloadText "deliveryStatus" completedJob `shouldBe` Just "delivery_disabled"

        it "skips RSA reminders that are no longer due or linked to the snapshotted account" $ withContext do
            withCleanDb do
                today <- utctDay <$> getCurrentTime
                venue <- createVenueWithConfig "RSA Superseded Reminder Venue"
                user <- createUserRecord "rsa-superseded@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user Worker
                staff <- createStaffRecord venue (Just user) "Sam" "Superseded"
                staffDocument <- createVerifiedRsaDocument user staff (addDays 10 today)
                _ <- enqueueDueRsaReminderJobs today
                appJob <- query @AppJob |> filterWhere (#jobKind, emailDeliveryJobKind) |> fetchOne
                now <- getCurrentTime
                _ <- staffDocument |> set #expiryReminderSentAt (Just now) |> updateRecord

                withFrameworkConfig config \frameworkConfig -> do
                    let ?context = frameworkConfig
                    performEmailDeliveryJobWith
                        (capturingEmailDeliveryRuntime (\_ -> expectationFailure "obsolete RSA reminder must not send"))
                        appJob

                skippedJob <- fetch appJob.id
                payloadText "deliveryStatus" skippedJob `shouldBe` Just "delivery_skipped"
                payloadText "reason" skippedJob `shouldBe` Just "reminder_no_longer_due"

rsaStatusFixture :: StaffDocumentStatusEnum -> Day -> StaffDocument
rsaStatusFixture status expiryDate =
    newRecord @StaffDocument
        |> set #status status
        |> set #expiryDate expiryDate

testRsaUpload :: Day -> RsaDocumentUpload
testRsaUpload expiryDate =
    RsaDocumentUpload
        { rsaUploadIssueDate = Just (addDays (-365) expiryDate)
        , rsaUploadExpiryDate = expiryDate
        , rsaUploadIssuingAuthority = Just "Victorian RSA"
        , rsaUploadDocumentNumber = Just "RSA-123"
        , rsaUploadFileName = "rsa.pdf"
        , rsaUploadContentType = "application/pdf"
        , rsaUploadFileContentsBase64 = "cnNhLWJ5dGVz"
        , rsaUploadExtraction = Nothing
        }

createVerifiedRsaDocument :: (?modelContext :: ModelContext) => User -> Staff -> Day -> IO StaffDocument
createVerifiedRsaDocument actor staff expiryDate =
    createRsaDocument actor.id staff (testRsaUpload expiryDate)
        >>= updateRecord . set #status StaffDocumentStatusEnumVerified

payloadText :: Text -> AppJob -> Maybe Text
payloadText key appJob =
    AesonTypes.parseMaybe (Aeson.withObject "job JSON" (Aeson..: AesonKey.fromText key)) source
  where
    source
        | key == "deliveryStatus" || key == "reason" = appJob.result
        | otherwise = appJob.payload
