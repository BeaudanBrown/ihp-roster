module Application.Helper.View.Status where

import qualified Data.Text as Text
import IHP.ViewPrelude

data AppStatusTone
    = AppStatusNeutral
    | AppStatusSuccess
    | AppStatusWarning
    | AppStatusDanger
    | AppStatusInfo

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

renderInvitationLifecycleStatusBadge :: Text -> Html
renderInvitationLifecycleStatusBadge status =
    uncurry renderAppStatusBadge (invitationLifecycleStatus status)

renderInvitationDeliveryStatusBadge :: Text -> Html
renderInvitationDeliveryStatusBadge deliveryStatus =
    uncurry renderAppStatusBadge (invitationDeliveryStatus deliveryStatus)

renderInvitationStatusOrDeliveryBadge :: Text -> Text -> Html
renderInvitationStatusOrDeliveryBadge status deliveryStatus =
    case status of
        "accepted" -> renderInvitationLifecycleStatusBadge status
        "revoked"  -> renderInvitationLifecycleStatusBadge status
        _          -> renderInvitationDeliveryStatusBadge deliveryStatus

invitationLifecycleStatus :: Text -> (AppStatusTone, Text)
invitationLifecycleStatus "accepted" = (AppStatusSuccess, "Accepted")
invitationLifecycleStatus "revoked"  = (AppStatusNeutral, "Revoked")
invitationLifecycleStatus _          = (AppStatusWarning, "Pending")

invitationDeliveryStatus :: Text -> (AppStatusTone, Text)
invitationDeliveryStatus "sent"   = (AppStatusSuccess, "Sent")
invitationDeliveryStatus "failed" = (AppStatusDanger, "Send Failed")
invitationDeliveryStatus _        = (AppStatusWarning, "Queued")
