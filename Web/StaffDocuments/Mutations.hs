module Web.StaffDocuments.Mutations
    ( reviewStaffDocument
    , uploadRsaDocument
    ) where

import Application.Helper.SurfaceResource
import Application.StaffDocuments.Rsa
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import Web.Controller.Prelude
import Web.SurfaceInvalidation (withDurableLiveMutation)

uploadRsaDocument :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id User -> Staff -> RsaDocumentUpload -> IO (LiveMutationResult StaffDocument)
uploadRsaDocument actorUserId staff upload =
    withDurableLiveMutation "staff_document.rsa.upload" do
        staffDocument <- createRsaDocument actorUserId staff upload
        void $
            recordCurrentUserAuditEvent
                RsaDocumentUploadedAudit
                "staff_documents"
                (unpackId staffDocument.id)
                ( Aeson.object
                    [ "staffId" Aeson..= staffDocument.staffId
                    , "documentType" Aeson..= inputValue staffDocument.documentType
                    , "expiryDate" Aeson..= staffDocument.expiryDate
                    , "status" Aeson..= inputValue staffDocument.status
                    ]
                )
        pure (liveMutationResult staffDocument [])

reviewStaffDocument :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id User -> StaffDocument -> StaffDocumentStatusEnum -> Maybe Text -> IO (LiveMutationResult StaffDocument)
reviewStaffDocument reviewerUserId staffDocument newStatus maybeRejectionReason =
    withDurableLiveMutation "staff_document.rsa.review" do
        updatedDocument <- reviewRsaDocument reviewerUserId staffDocument newStatus maybeRejectionReason
        void $
            recordCurrentUserAuditEvent
                RsaDocumentReviewedAudit
                "staff_documents"
                (unpackId updatedDocument.id)
                ( Aeson.object
                    [ "staffId" Aeson..= updatedDocument.staffId
                    , "documentType" Aeson..= inputValue updatedDocument.documentType
                    , "previousStatus" Aeson..= inputValue staffDocument.status
                    , "newStatus" Aeson..= inputValue updatedDocument.status
                    , "reviewedByUserId" Aeson..= updatedDocument.reviewedByUserId
                    ]
                )
        pure (liveMutationResult updatedDocument [])
