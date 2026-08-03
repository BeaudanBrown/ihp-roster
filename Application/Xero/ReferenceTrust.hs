module Application.Xero.ReferenceTrust
    ( XeroMissingReferenceDemand (..)
    , XeroReferenceSyncActivity (..)
    , XeroReferenceSyncProgressFacts (..)
    , XeroReferenceTrustDecision (..)
    , decideXeroReferenceTrust
    , xeroReferenceSnapshotMaxAge
    ) where

import IHP.Prelude

data XeroMissingReferenceDemand
    = NoMissingPayrollReferenceDemand
    | MissingPayrollEligibleStaffReference
    | MissingRosterOnlyStaffReference
    deriving (Eq, Show)

data XeroReferenceSyncProgressFacts = XeroReferenceSyncProgressFacts
    { progressPhase                 :: !(Maybe Text)
    , progressCompletedPayItemsPage :: !(Maybe Int)
    , progressFailedPhase           :: !(Maybe Text)
    , progressRetryAt               :: !(Maybe UTCTime)
    }
    deriving (Eq, Show)

data XeroReferenceSyncActivity
    = XeroReferenceSyncIdle
    | XeroReferenceSyncQueued
    | XeroReferenceSyncRunning
    | XeroReferenceSyncRetryWaiting UTCTime
    | XeroReferenceSyncFailed Text
    deriving (Eq, Show)

data XeroReferenceTrustDecision
    = UseTrustedXeroReferenceSnapshot
    | StartOrJoinXeroReferenceSync
    | WaitForTrustedXeroReferenceSnapshot XeroReferenceSyncActivity
    | ReconnectXeroForReferenceData
    | BlockStaleXeroReferenceData Text
    deriving (Eq, Show)

xeroReferenceSnapshotMaxAge :: NominalDiffTime
xeroReferenceSnapshotMaxAge = 7 * 24 * 60 * 60

decideXeroReferenceTrust ::
    UTCTime ->
    Text ->
    Maybe UTCTime ->
    XeroMissingReferenceDemand ->
    XeroReferenceSyncActivity ->
    XeroReferenceTrustDecision
decideXeroReferenceTrust now connectionStatus maybeLastSyncAt missingReferenceDemand syncActivity
    | connectionStatus /= "active" = ReconnectXeroForReferenceData
    | snapshotIsTrusted, XeroReferenceSyncRetryWaiting _ <- syncActivity = UseTrustedXeroReferenceSnapshot
    | snapshotIsTrusted && missingReferenceDemand /= MissingPayrollEligibleStaffReference = UseTrustedXeroReferenceSnapshot
    | otherwise =
        case syncActivity of
            XeroReferenceSyncQueued -> WaitForTrustedXeroReferenceSnapshot syncActivity
            XeroReferenceSyncRunning -> WaitForTrustedXeroReferenceSnapshot syncActivity
            XeroReferenceSyncRetryWaiting _ -> WaitForTrustedXeroReferenceSnapshot syncActivity
            XeroReferenceSyncFailed message -> BlockStaleXeroReferenceData message
            XeroReferenceSyncIdle -> StartOrJoinXeroReferenceSync
  where
    snapshotIsTrusted =
        case maybeLastSyncAt of
            Nothing -> False
            Just lastSyncAt -> diffUTCTime now lastSyncAt < xeroReferenceSnapshotMaxAge
