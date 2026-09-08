{-# OPTIONS_GHC -Werror=incomplete-patterns #-}

module Application.Helper.View.Status where

import qualified Data.Text as Text
import Generated.Types (InvitationDeliveryStatusEnum (..),
                        InvitationStatusEnum (..))
import IHP.ViewPrelude

data AppStatusTone
    = AppStatusNeutral
    | AppStatusSuccess
    | AppStatusWarning
    | AppStatusDanger
    | AppStatusInfo
    deriving (Eq, Show)

appStatusBadgeClass :: AppStatusTone -> Text
appStatusBadgeClass tone =
    Text.unwords ["badge", "app-status-badge", toneClass]
    where
        toneClass =
            case tone of
                AppStatusNeutral -> "app-status-neutral"
                AppStatusSuccess -> "app-status-success"
                AppStatusWarning -> "app-status-warning"
                AppStatusDanger  -> "app-status-danger"
                AppStatusInfo    -> "app-status-info"

renderAppStatusBadge :: AppStatusTone -> Text -> Html
renderAppStatusBadge tone label = [hsx|
    <span class={appStatusBadgeClass tone}>{label}</span>
|]

jobStatusBadgeClass :: JobStatus -> Text
jobStatusBadgeClass JobStatusNotStarted = "badge text-bg-secondary"
jobStatusBadgeClass JobStatusRunning    = "badge text-bg-secondary"
jobStatusBadgeClass JobStatusRetry      = "badge text-bg-warning"
jobStatusBadgeClass JobStatusSucceeded  = "badge text-bg-success"
jobStatusBadgeClass JobStatusFailed     = "badge text-bg-danger"
jobStatusBadgeClass JobStatusTimedOut   = "badge text-bg-danger"

renderInvitationLifecycleStatusBadge :: InvitationStatusEnum -> Html
renderInvitationLifecycleStatusBadge status =
    uncurry renderAppStatusBadge (invitationLifecycleStatus status)

renderInvitationDeliveryStatusBadge :: InvitationDeliveryStatusEnum -> Html
renderInvitationDeliveryStatusBadge deliveryStatus =
    uncurry renderAppStatusBadge (invitationDeliveryStatus deliveryStatus)

renderInvitationStatusOrDeliveryBadge :: InvitationStatusEnum -> InvitationDeliveryStatusEnum -> Html
renderInvitationStatusOrDeliveryBadge status deliveryStatus =
    case status of
        InvitationStatusEnumPending -> renderInvitationDeliveryStatusBadge deliveryStatus
        Accepted                    -> renderInvitationLifecycleStatusBadge status
        Revoked                     -> renderInvitationLifecycleStatusBadge status

invitationLifecycleStatus :: InvitationStatusEnum -> (AppStatusTone, Text)
invitationLifecycleStatus InvitationStatusEnumPending = (AppStatusWarning, "Pending")
invitationLifecycleStatus Accepted                    = (AppStatusSuccess, "Accepted")
invitationLifecycleStatus Revoked                     = (AppStatusNeutral, "Revoked")

invitationDeliveryStatus :: InvitationDeliveryStatusEnum -> (AppStatusTone, Text)
invitationDeliveryStatus Queued = (AppStatusWarning, "Queued")
invitationDeliveryStatus Sent   = (AppStatusSuccess, "Sent")
invitationDeliveryStatus InvitationDeliveryStatusEnumFailed = (AppStatusDanger, "Send Failed")
