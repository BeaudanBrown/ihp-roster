module Test.Controller.StaffDocumentsSpec where

import Application.Helper.LiveResource
import Application.StaffDocuments.Rsa
import qualified Data.Aeson as Aeson
import Data.Time.Calendar (fromGregorian)
import Generated.Types
import IHP.ControllerPrelude
import IHP.Prelude
import IHP.Test.Mocking
import Network.HTTP.Types.Header (hContentDisposition, hContentType)
import Network.HTTP.Types.Status
import Network.Wai (responseHeaders)
import Test.Hspec
import Test.Support
import Web.Controller.StaffDocuments ()
import Web.FrontController ()
import Web.Routes
import Web.StaffDocuments.Mutations (rsaStaffDocumentTouchedResources)
import Web.Types

tests :: Spec
tests = beforeAll testContext do
    describe "StaffDocumentsController" do
        it "redirects unauthenticated users from RSA document actions" $ withContext do
            let staffDocumentId = Id "00000000-0000-0000-0000-000000000000"
            scanResponse <- callAction ScanStaffDocumentAction
            createResponse <- callAction CreateStaffDocumentAction
            downloadResponse <- callAction DownloadStaffDocumentAction { staffDocumentId }
            reviewResponse <- callAction ReviewStaffDocumentAction { staffDocumentId }

            scanResponse `responseStatusShouldBe` status302
            createResponse `responseStatusShouldBe` status302
            downloadResponse `responseStatusShouldBe` status302
            reviewResponse `responseStatusShouldBe` status302

        it "allows staff to download their own RSA document" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "RSA Download Venue"
                user <- createUserRecord "rsa-download@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user "worker"
                staff <- createStaffRecord venue (Just user) "Drew" "Download"
                staffDocument <- createRsaDocument user.id staff (testRsaUpload (fromGregorian 2027 5 2))

                response <- withUserAndCurrentVenue user venue.id do
                    callAction DownloadStaffDocumentAction { staffDocumentId = staffDocument.id }

                response `responseStatusShouldBe` status200
                lookup hContentType (responseHeaders response) `shouldBe` Just "application/pdf"
                lookup hContentDisposition (responseHeaders response) `shouldBe` Just "attachment; filename=\"rsa.pdf\""

        it "prevents staff from downloading another staff member's RSA document" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "RSA Private Venue"
                owner <- createUserRecord "rsa-owner@example.com" "staff" True
                other <- createUserRecord "rsa-other@example.com" "staff" True
                _ <- createVenueMembershipRecord venue owner "worker"
                _ <- createVenueMembershipRecord venue other "worker"
                ownerStaff <- createStaffRecord venue (Just owner) "Owner" "RSA"
                _ <- createStaffRecord venue (Just other) "Other" "RSA"
                staffDocument <- createRsaDocument owner.id ownerStaff (testRsaUpload (fromGregorian 2027 5 2))

                response <- withUserAndCurrentVenue other venue.id do
                    callAction DownloadStaffDocumentAction { staffDocumentId = staffDocument.id }

                response `responseStatusShouldBe` status403

        it "creates an RSA document from confirmed scan metadata" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "RSA Confirm Venue"
                user <- createUserRecord "rsa-confirm@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user "worker"
                staff <- createStaffRecord venue (Just user) "Casey" "Confirm"

                response <- withUserAndCurrentVenue user venue.id do
                    callActionWithParams CreateStaffDocumentAction
                        [ ("staffId", idToParam staff.id)
                        , ("expiryDate", "2028-08-09")
                        , ("issueDate", "2025-08-09")
                        , ("issuingAuthority", "Victorian RSA")
                        , ("documentNumber", "RSA-SCAN-123")
                        , ("confirmedFileName", "scanned-rsa.pdf")
                        , ("confirmedContentType", "application/pdf")
                        , ("confirmedFileContentsBase64", "c2Nhbm5lZC1yc2E=")
                        , ("extractionMethod", "pdftotext 24.02")
                        , ("extractionConfidence", "82")
                        , ("extractionWarningsJson", "[\"Confirm recipient name.\"]")
                        , ("extractedSubjectName", "Casey Confirm")
                        ]

                response `responseStatusShouldBe` status302
                [staffDocument] <- query @StaffDocument |> filterWhere (#staffId, unpackId staff.id) |> fetch
                staffDocument.status `shouldBe` PendingReview
                staffDocument.issueDate `shouldBe` Just (fromGregorian 2025 8 9)
                staffDocument.expiryDate `shouldBe` fromGregorian 2028 8 9
                staffDocument.issuingAuthority `shouldBe` Just "Victorian RSA"
                staffDocument.documentNumber `shouldBe` Just "RSA-SCAN-123"
                staffDocument.fileName `shouldBe` "scanned-rsa.pdf"
                staffDocument.extractionMethod `shouldBe` Just "pdftotext 24.02"
                staffDocument.extractionConfidence `shouldBe` Just 82
                staffDocument.extractionWarningsJson `shouldBe` Just (Aeson.toJSON (["Confirm recipient name."] :: [Text]))
                staffDocument.extractedSubjectName `shouldBe` Just "Casey Confirm"
                decodeStaffDocumentFile staffDocument `shouldBe` Right "scanned-rsa"

        it "keeps manual image uploads on the existing confirmation path" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "RSA Image Venue"
                user <- createUserRecord "rsa-image@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user "worker"
                staff <- createStaffRecord venue (Just user) "Iris" "Image"

                response <- withUserAndCurrentVenue user venue.id do
                    callActionWithParams CreateStaffDocumentAction
                        [ ("staffId", idToParam staff.id)
                        , ("expiryDate", "2028-10-11")
                        , ("confirmedFileName", "manual-rsa.png")
                        , ("confirmedContentType", "image/png")
                        , ("confirmedFileContentsBase64", "aW1hZ2UtcnNh")
                        ]

                response `responseStatusShouldBe` status302
                [staffDocument] <- query @StaffDocument |> filterWhere (#staffId, unpackId staff.id) |> fetch
                staffDocument.status `shouldBe` PendingReview
                staffDocument.expiryDate `shouldBe` fromGregorian 2028 10 11
                staffDocument.contentType `shouldBe` "image/png"
                staffDocument.fileName `shouldBe` "manual-rsa.png"
                staffDocument.extractionMethod `shouldBe` Nothing
                staffDocument.extractionWarningsJson `shouldBe` Nothing
                decodeStaffDocumentFile staffDocument `shouldBe` Right "image-rsa"

        it "allows managers to upload a pending replacement for venue staff" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "RSA Manager Upload Venue"
                manager <- createUserRecord "rsa-manager-upload@example.com" "staff" True
                worker <- createUserRecord "rsa-worker-upload@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                _ <- createVenueMembershipRecord venue worker "worker"
                staff <- createStaffRecord venue (Just worker) "Mina" "Managed"
                current <- createRsaDocument worker.id staff (testRsaUpload (fromGregorian 2027 5 2)) >>= updateRecord . set #status Verified

                response <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams CreateStaffDocumentAction
                        [ ("staffId", idToParam staff.id)
                        , ("expiryDate", "2029-05-02")
                        , ("issueDate", "2026-05-02")
                        , ("issuingAuthority", "NSW RSA")
                        , ("documentNumber", "MANAGER-RSA-1")
                        , ("confirmedFileName", "replacement-rsa.pdf")
                        , ("confirmedContentType", "application/pdf")
                        , ("confirmedFileContentsBase64", "cmVwbGFjZW1lbnQ=")
                        ]

                response `responseStatusShouldBe` status302
                documents <- query @StaffDocument |> filterWhere (#staffId, unpackId staff.id) |> orderByDesc #createdAt |> fetch
                length documents `shouldBe` 2
                let state = effectiveRsaState (fromGregorian 2026 5 20) documents
                fmap (.id) state.rsaCurrentDocument `shouldBe` Just current.id
                fmap (.documentNumber) state.rsaPendingReplacement `shouldBe` Just (Just "MANAGER-RSA-1")

        it "records touched resources for RSA document changes" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "RSA Touch Venue"
                user <- createUserRecord "rsa-touch@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user "worker"
                staff <- createStaffRecord venue (Just user) "Touch" "Worker"
                staffDocument <- createRsaDocument user.id staff (testRsaUpload (fromGregorian 2027 5 2))

                rsaStaffDocumentTouchedResources staffDocument
                    `shouldBe` [ StaffRsaDocumentsResource (unpackId staff.id)
                               ]

        it "allows managers to review RSA documents in their venue" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "RSA Review Venue"
                manager <- createUserRecord "rsa-manager@example.com" "staff" True
                worker <- createUserRecord "rsa-review-worker@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                _ <- createVenueMembershipRecord venue worker "worker"
                staff <- createStaffRecord venue (Just worker) "Review" "Worker"
                staffDocument <- createRsaDocument worker.id staff (testRsaUpload (fromGregorian 2027 5 2))

                response <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams ReviewStaffDocumentAction { staffDocumentId = staffDocument.id }
                        [ ("status", "verified")
                        , ("returnTo", "admin")
                        ]

                response `responseStatusShouldBe` status302
                updatedDocument <- fetch staffDocument.id
                updatedDocument.status `shouldBe` Verified
                updatedDocument.reviewedByUserId `shouldBe` Just (unpackId manager.id)
                updatedDocument.reviewedAt `shouldSatisfy` isJust
                [auditEvent] <-
                    query @AuditEvent
                        |> filterWhere (#eventType, "rsa_document_reviewed")
                        |> filterWhere (#targetTable, "staff_documents")
                        |> filterWhere (#targetId, unpackId staffDocument.id)
                        |> fetch
                auditEvent.actorUserId `shouldBe` unpackId manager.id

        it "blocks cross-venue RSA document access for managers" $ withContext do
            withCleanDb do
                venueA <- createVenueWithConfig "RSA Venue A"
                venueB <- createVenueWithConfig "RSA Venue B"
                managerA <- createUserRecord "rsa-manager-a@example.com" "staff" True
                workerB <- createUserRecord "rsa-worker-b@example.com" "staff" True
                _ <- createVenueMembershipRecord venueA managerA "manager"
                _ <- createVenueMembershipRecord venueB workerB "worker"
                staffB <- createStaffRecord venueB (Just workerB) "Cross" "Venue"
                staffDocument <- createRsaDocument workerB.id staffB (testRsaUpload (fromGregorian 2027 5 2))

                response <- withUserAndCurrentVenue managerA venueA.id do
                    callAction DownloadStaffDocumentAction { staffDocumentId = staffDocument.id }

                response `responseStatusShouldBe` status403

testRsaUpload :: Day -> RsaDocumentUpload
testRsaUpload expiryDate =
    RsaDocumentUpload
        { rsaUploadIssueDate = Just (fromGregorian 2026 5 2)
        , rsaUploadExpiryDate = expiryDate
        , rsaUploadIssuingAuthority = Just "Victorian RSA"
        , rsaUploadDocumentNumber = Just "RSA-123"
        , rsaUploadFileName = "rsa.pdf"
        , rsaUploadContentType = "application/pdf"
        , rsaUploadFileContentsBase64 = "cnNhLWJ5dGVz"
        , rsaUploadExtraction = Nothing
        }
