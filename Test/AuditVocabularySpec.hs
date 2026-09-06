module Test.AuditVocabularySpec where

import Application.Helper.Audit.Vocabulary
import IHP.Prelude
import Test.Hspec

tests :: Spec
tests = describe "AuditVocabulary" do
    it "renders the complete audit event contract to its exact persisted wire values" do
        map fst auditEventWireContract `shouldBe` [minBound .. maxBound]
        map (auditEventTypeText . fst) auditEventWireContract `shouldBe` map snd auditEventWireContract

    it "renders the complete source-channel contract, including retained system and application channels" do
        map fst auditSourceChannelWireContract `shouldBe` [minBound .. maxBound]
        map (auditSourceChannelText . fst) auditSourceChannelWireContract `shouldBe` map snd auditSourceChannelWireContract

auditEventWireContract :: [(AuditEventType, Text)]
auditEventWireContract =
    [ (TimesheetApprovedAudit, "timesheet_approved")
    , (TimesheetUnapprovedAudit, "timesheet_unapproved")
    , (TimesheetApprovalResetAudit, "timesheet_approval_reset")
    , (LeaveApprovedAudit, "leave_approved")
    , (LeaveDeniedAudit, "leave_denied")
    , (LeaveDeletedAudit, "leave_deleted")
    , (VenueRoleAssignedAudit, "venue_role_assigned")
    , (VenueRoleChangedAudit, "venue_role_changed")
    , (VenueBootstrappedAudit, "venue_bootstrapped")
    , (ExportGeneratedAudit, "export_generated")
    , (ExportDownloadedAudit, "export_downloaded")
    , (SupportAccessGrantedAudit, "support_access_granted")
    , (SupportImpersonationEnteredAudit, "support_impersonation_entered")
    , (SupportImpersonationExitedAudit, "support_impersonation_exited")
    , (SupportImpersonationExpiredAudit, "support_impersonation_expired")
    , (LoginSucceededAudit, "login_succeeded")
    , (LoginFailedAudit, "login_failed")
    , (LoginBlockedAudit, "login_blocked")
    , (PasskeyStepUpSucceededAudit, "passkey_step_up_succeeded")
    , (PasskeyStepUpFailedAudit, "passkey_step_up_failed")
    , (StaffPasskeySetupRequestedAudit, "staff_passkey_setup_requested")
    , (StaffPasskeyRecoveryRequestedAudit, "staff_passkey_recovery_requested")
    , (StaffPasswordResetRequestedAudit, "staff_password_reset_requested")
    , (PasswordResetCompletedAudit, "password_reset_completed")
    , (TimesheetDeletedAudit, "timesheet_deleted")
    , (StaffRemovedAudit, "staff_removed")
    , (RsaDocumentUploadedAudit, "rsa_document_uploaded")
    , (RsaDocumentReviewedAudit, "rsa_document_reviewed")
    , (BillingCustomerCreatedAudit, "billing_customer_created")
    , (VenueBillingControlUpdatedAudit, "venue_billing_control_updated")
    , (BillingReconciliationRequestedAudit, "billing_reconciliation_requested")
    , (BillingCheckoutStartedAudit, "billing_checkout_started")
    , (BillingPortalStartedAudit, "billing_portal_started")
    , (XeroConnectionStartedAudit, "xero_connection_started")
    , (XeroConnectionDisconnectedAudit, "xero_connection_disconnected")
    , (XeroConnectionCompletedAudit, "xero_connection_completed")
    , (XeroConnectionFailedAudit, "xero_connection_failed")
    , (XeroReferenceSyncSucceededAudit, "xero_reference_sync_succeeded")
    , (XeroReferenceSyncFailedAudit, "xero_reference_sync_failed")
    , (FeedbackSubmittedAudit, "feedback_submitted")
    , (FeedbackEditedAudit, "feedback_edited")
    , (FeedbackPublishedAudit, "feedback_published")
    , (FeedbackArchivedAudit, "feedback_archived")
    , (FeedbackRestoredAudit, "feedback_restored")
    ]

auditSourceChannelWireContract :: [(AuditSourceChannel, Text)]
auditSourceChannelWireContract =
    [ (WebAuditSource, "web")
    , (HtmxAuditSource, "htmx")
    , (SystemAuditSource, "system")
    , (ApplicationAuditSource, "application")
    ]
