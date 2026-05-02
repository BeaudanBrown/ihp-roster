module Test.Controller.StaffDocumentsSpec where

import Application.StaffDocuments.Rsa
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
import Web.Types

tests :: Spec
tests = beforeAll testContext do
    describe "StaffDocumentsController" do
        it "redirects unauthenticated users from RSA document actions" $ withContext do
            let staffDocumentId = Id "00000000-0000-0000-0000-000000000000"
            createResponse <- callAction CreateStaffDocumentAction
            downloadResponse <- callAction DownloadStaffDocumentAction { staffDocumentId }
            reviewResponse <- callAction ReviewStaffDocumentAction { staffDocumentId }

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
        }
