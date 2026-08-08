module Application.Xero.ReferenceTrust.Presentation
    ( XeroPreparationReferencePresentation (..)
    , XeroPayItemImportReferencePresentation (..)
    , xeroPreparationReferencePresentation
    , xeroPayItemImportReferencePresentation
    , xeroReferenceSyncActivityText
    , xeroReferenceSyncPhaseText
    ) where

import Application.Xero.ReferenceTrust
import IHP.Prelude

data XeroPreparationReferencePresentation
    = XeroPreparationReferenceReady
    | XeroPreparationReferenceWaiting !Text
    | XeroPreparationReferenceBlocked !Text
    deriving (Eq, Show)

data XeroPayItemImportReferencePresentation
    = XeroPayItemImportReferenceReady
    | XeroPayItemImportReferenceWaiting
    | XeroPayItemImportReferenceBlocked !Text
    deriving (Eq, Show)

xeroPayItemImportReferencePresentation :: XeroReferenceTrustDecision -> XeroPayItemImportReferencePresentation
xeroPayItemImportReferencePresentation = \case
    UseTrustedXeroReferenceSnapshot -> XeroPayItemImportReferenceReady
    StartOrJoinXeroReferenceSync -> XeroPayItemImportReferenceWaiting
    WaitForTrustedXeroReferenceSnapshot _ -> XeroPayItemImportReferenceWaiting
    ReconnectXeroForReferenceData -> XeroPayItemImportReferenceBlocked "Reconnect Xero before importing pay items."
    BlockStaleXeroReferenceData _ -> XeroPayItemImportReferenceBlocked "Xero reference data is out of date and could not be refreshed. Contact support before importing pay items."

xeroPreparationReferencePresentation :: XeroReferenceTrustDecision -> XeroPreparationReferencePresentation
xeroPreparationReferencePresentation = \case
    UseTrustedXeroReferenceSnapshot -> XeroPreparationReferenceReady
    StartOrJoinXeroReferenceSync -> XeroPreparationReferenceWaiting "Xero payroll reference data is starting in the background."
    WaitForTrustedXeroReferenceSnapshot _ -> XeroPreparationReferenceWaiting "Xero payroll reference data is syncing in the background."
    ReconnectXeroForReferenceData -> XeroPreparationReferenceBlocked "Reconnect Xero before preparing draft timesheets."
    BlockStaleXeroReferenceData _ -> XeroPreparationReferenceBlocked "Xero reference data is out of date and could not be refreshed. Contact support before preparing draft timesheets."

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
        "pay_items"         -> "Fetching Xero earnings rates"
        "payroll_calendars" -> "Fetching Xero payroll calendars"
        "accounts"          -> "Fetching Xero accounts"
        "payroll_settings"  -> "Fetching Xero payroll settings"
        "retry_wait"        -> "Waiting to retry"
        _                   -> "Refreshing Xero reference data"
