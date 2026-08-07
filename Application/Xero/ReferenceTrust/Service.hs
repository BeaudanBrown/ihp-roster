module Application.Xero.ReferenceTrust.Service
    ( requestTrustedXeroReferenceData
    ) where

import Application.Xero.ReferenceDemand (fetchXeroMissingReferenceDemand)
import Application.Xero.ReferenceSyncJob (requestXeroReferenceSyncJob)
import Application.Xero.ReferenceTrust
import Application.Xero.ReferenceTrust.ReadModel
import Generated.Types
import IHP.ControllerPrelude

requestTrustedXeroReferenceData ::
    (?modelContext :: ModelContext) =>
    UTCTime ->
    Maybe (Id User) ->
    XeroConnection ->
    XeroMissingReferenceDemand ->
    IO XeroReferenceTrustState
requestTrustedXeroReferenceData now maybeActorUserId connection requestedDemand = do
    currentConnection <- fetch connection.id
    currentDemand <- case requestedDemand of
        MissingPayrollEligibleStaffReference -> fetchXeroMissingReferenceDemand currentConnection
        _ -> pure requestedDemand
    initialState <- fetchXeroReferenceTrustState now currentConnection currentDemand
    case initialState.trustDecision of
        StartOrJoinXeroReferenceSync -> do
            _ <- requestXeroReferenceSyncJob maybeActorUserId currentConnection
            fetchXeroReferenceTrustState now currentConnection currentDemand
        _ -> pure initialState
