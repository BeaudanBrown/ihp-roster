module Application.Helper.Audit.Vocabulary
    ( AuditEventType (..)
    , AuditSourceChannel (..)
    , auditEventTypeText
    , auditSourceChannelText
    ) where

import IHP.Prelude

data AuditEventType
    = TimesheetApprovedAudit
    | TimesheetUnapprovedAudit
    | TimesheetApprovalResetAudit
    | LeaveApprovedAudit
    | LeaveDeniedAudit
    | LeaveDeletedAudit -- Retained persisted vocabulary; currently has no emitter.
    | VenueRoleAssignedAudit
    | VenueRoleChangedAudit
    | VenueBootstrappedAudit
    | ExportGeneratedAudit
    | ExportDownloadedAudit
    | SupportAccessGrantedAudit -- Reserved existing contract; #102 behavior remains separate.
    | LoginSucceededAudit
    | LoginFailedAudit
    | LoginBlockedAudit
    | PasskeyStepUpSucceededAudit
    | PasskeyStepUpFailedAudit
    | TimesheetDeletedAudit
    | StaffRemovedAudit
    | RsaDocumentUploadedAudit
    | RsaDocumentReviewedAudit
    | BillingCustomerCreatedAudit
    | VenueBillingControlUpdatedAudit
    | BillingReconciliationRequestedAudit
    | BillingCheckoutStartedAudit
    | BillingPortalStartedAudit
    | XeroConnectionStartedAudit
    | XeroConnectionDisconnectedAudit
    | XeroConnectionCompletedAudit
    | XeroConnectionFailedAudit
    | XeroReferenceSyncSucceededAudit
    | XeroReferenceSyncFailedAudit
    deriving (Bounded, Enum, Eq, Show)

data AuditSourceChannel
    = WebAuditSource
    | HtmxAuditSource
    | SystemAuditSource
    | ApplicationAuditSource
    deriving (Bounded, Enum, Eq, Show)

auditEventTypeText :: AuditEventType -> Text
auditEventTypeText TimesheetApprovedAudit = "timesheet_approved"
auditEventTypeText TimesheetUnapprovedAudit = "timesheet_unapproved"
auditEventTypeText TimesheetApprovalResetAudit = "timesheet_approval_reset"
auditEventTypeText LeaveApprovedAudit = "leave_approved"
auditEventTypeText LeaveDeniedAudit = "leave_denied"
auditEventTypeText LeaveDeletedAudit = "leave_deleted"
auditEventTypeText VenueRoleAssignedAudit = "venue_role_assigned"
auditEventTypeText VenueRoleChangedAudit = "venue_role_changed"
auditEventTypeText VenueBootstrappedAudit = "venue_bootstrapped"
auditEventTypeText ExportGeneratedAudit = "export_generated"
auditEventTypeText ExportDownloadedAudit = "export_downloaded"
auditEventTypeText SupportAccessGrantedAudit = "support_access_granted"
auditEventTypeText LoginSucceededAudit = "login_succeeded"
auditEventTypeText LoginFailedAudit = "login_failed"
auditEventTypeText LoginBlockedAudit = "login_blocked"
auditEventTypeText PasskeyStepUpSucceededAudit = "passkey_step_up_succeeded"
auditEventTypeText PasskeyStepUpFailedAudit = "passkey_step_up_failed"
auditEventTypeText TimesheetDeletedAudit = "timesheet_deleted"
auditEventTypeText StaffRemovedAudit = "staff_removed"
auditEventTypeText RsaDocumentUploadedAudit = "rsa_document_uploaded"
auditEventTypeText RsaDocumentReviewedAudit = "rsa_document_reviewed"
auditEventTypeText BillingCustomerCreatedAudit = "billing_customer_created"
auditEventTypeText VenueBillingControlUpdatedAudit = "venue_billing_control_updated"
auditEventTypeText BillingReconciliationRequestedAudit = "billing_reconciliation_requested"
auditEventTypeText BillingCheckoutStartedAudit = "billing_checkout_started"
auditEventTypeText BillingPortalStartedAudit = "billing_portal_started"
auditEventTypeText XeroConnectionStartedAudit = "xero_connection_started"
auditEventTypeText XeroConnectionDisconnectedAudit = "xero_connection_disconnected"
auditEventTypeText XeroConnectionCompletedAudit = "xero_connection_completed"
auditEventTypeText XeroConnectionFailedAudit = "xero_connection_failed"
auditEventTypeText XeroReferenceSyncSucceededAudit = "xero_reference_sync_succeeded"
auditEventTypeText XeroReferenceSyncFailedAudit = "xero_reference_sync_failed"

auditSourceChannelText :: AuditSourceChannel -> Text
auditSourceChannelText WebAuditSource         = "web"
auditSourceChannelText HtmxAuditSource        = "htmx"
auditSourceChannelText SystemAuditSource      = "system"
auditSourceChannelText ApplicationAuditSource = "application"
