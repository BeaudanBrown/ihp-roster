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
