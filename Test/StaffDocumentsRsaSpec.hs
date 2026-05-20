module Test.StaffDocumentsRsaSpec where

import Application.Async.Queue
import Application.StaffDocuments.Rsa
import Application.StaffDocuments.RsaExtraction
import Config (config)
import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Text as Text
import Data.Time.Calendar (addDays, fromGregorian)
import Data.Time.Clock (getCurrentTime, utctDay)
import Generated.Types
import IHP.ControllerPrelude
import IHP.FrameworkConfig (withFrameworkConfig)
import IHP.Job.Types
import IHP.Prelude
import IHP.Test.Mocking
import Test.Hspec
import Test.Support

tests :: Spec
tests = beforeAll testContext do
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

    describe "RSA staff documents" do
        it "calculates compliance status from the latest document state" $ withContext do
            let today = fromGregorian 2026 5 2
            effectiveRsaComplianceStatus today Nothing `shouldBe` StaffRsaMissing
            effectiveRsaComplianceStatus today (Just (rsaStatusFixture PendingReview (addDays 60 today))) `shouldBe` StaffRsaPendingReview
            effectiveRsaComplianceStatus today (Just (rsaStatusFixture Rejected (addDays 60 today))) `shouldBe` StaffRsaRejected
            effectiveRsaComplianceStatus today (Just (rsaStatusFixture Expired (addDays 60 today))) `shouldBe` StaffRsaExpired
            effectiveRsaComplianceStatus today (Just (rsaStatusFixture Verified (addDays (-1) today))) `shouldBe` StaffRsaExpired
            effectiveRsaComplianceStatus today (Just (rsaStatusFixture Verified (addDays 20 today))) `shouldBe` StaffRsaExpiringSoon 20
            effectiveRsaComplianceStatus today (Just (rsaStatusFixture Verified (addDays 60 today))) `shouldBe` StaffRsaVerified

        it "creates RSA document rows without storing onboarding-sensitive data" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "RSA Venue"
                user <- createUserRecord "rsa-worker@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user "worker"
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
                _ <- createVenueMembershipRecord venue user "worker"
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

                [job] <- query @AppJob |> filterWhere (#jobKind, rsaReminderJobKind) |> fetch
                job.venueId `shouldBe` Just (unpackId venue.id)
                job.relatedTable `shouldBe` Just "staff_documents"
                job.relatedId `shouldBe` Just (unpackId staffDocument.id)
                job.dedupeKey `shouldBe` Just (rsaDocumentReminderDedupeKey staffDocument.id "expiring_soon")

        it "marks expired RSA reminders as sent and expires the document" $ withContext do
            withCleanDb do
                today <- utctDay <$> getCurrentTime
                venue <- createVenueWithConfig "RSA Expired Reminder Venue"
                user <- createUserRecord "rsa-expired@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user "worker"
                staff <- createStaffRecord venue (Just user) "Eli" "Expired"
                staffDocument <- createVerifiedRsaDocument user staff (addDays (-1) today)
                EnqueuedAppJob appJob <- enqueueAppJob (expiredReminderRequest staffDocument)

                withFrameworkConfig config \frameworkConfig -> do
                    let ?context = frameworkConfig
                    performRsaReminderJob appJob

                updatedDocument <- fetch staffDocument.id
                updatedDocument.status `shouldBe` Expired
                updatedDocument.expiredReminderSentAt `shouldSatisfy` isJust
                updatedJob <- fetch appJob.id
                updatedJob.status `shouldBe` JobStatusSucceeded

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
        }

createVerifiedRsaDocument :: (?modelContext :: ModelContext) => User -> Staff -> Day -> IO StaffDocument
createVerifiedRsaDocument actor staff expiryDate =
    createRsaDocument actor.id staff (testRsaUpload expiryDate)
        >>= updateRecord . set #status Verified

expiredReminderRequest :: StaffDocument -> AppJobRequest
expiredReminderRequest staffDocument =
    AppJobRequest
        { jobKind = rsaReminderJobKind
        , payload =
            Aeson.object
                [ "staffDocumentId" Aeson..= tshow staffDocument.id
                , "reminderKind" Aeson..= ("expired" :: Text)
                ]
        , payloadSchemaVersion = 1
        , requestedByUserId = Nothing
        , venueId = Just staffDocument.venueId
        , relatedTable = Just "staff_documents"
        , relatedId = Just (unpackId staffDocument.id)
        , dedupeKey = Just (rsaDocumentReminderDedupeKey staffDocument.id "expired")
        , runAt = Nothing
        }
