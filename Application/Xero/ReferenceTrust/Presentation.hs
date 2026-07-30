module Application.Xero.ReferenceTrust.Presentation
    ( xeroReferenceSyncActivityText
    , xeroReferenceSyncPhaseText
    , xeroReferenceWaitIsLongRunning
    ) where

import Application.Xero.ReferenceTrust
import IHP.Prelude

xeroReferenceSyncActivityText :: XeroReferenceSyncActivity -> Text
xeroReferenceSyncActivityText = \case
    XeroReferenceSyncIdle -> "Starting"
    XeroReferenceSyncQueued -> "Queued"
    XeroReferenceSyncRunning -> "Running"
    XeroReferenceSyncRetryWaiting retryAt -> "Retry scheduled for " <> tshow retryAt
    XeroReferenceSyncFailed _ -> "Stopped"

xeroReferenceSyncPhaseText :: Text -> Text
xeroReferenceSyncPhaseText phase =
    case phase of
        "refresh_access"    -> "Refreshing Xero access"
        "employees"         -> "Fetching Xero employees"
        "pay_items"         -> "Fetching Xero pay items"
        "payroll_calendars" -> "Fetching Xero payroll calendars"
        "accounts"          -> "Fetching Xero accounts"
        "payroll_settings"  -> "Fetching Xero payroll settings"
        "retry_wait"        -> "Waiting to retry"
        _                   -> "Refreshing Xero reference data"

xeroReferenceWaitIsLongRunning :: UTCTime -> UTCTime -> Bool
xeroReferenceWaitIsLongRunning now waitStartedAt =
    diffUTCTime now waitStartedAt >= 5 * 60
