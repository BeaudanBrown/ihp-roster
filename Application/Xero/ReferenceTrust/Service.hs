module Application.Xero.ReferenceTrust.Service
    ( ensureTrustedXeroReferenceData
    ) where

import Application.Xero.ReferenceSyncJob (enqueueXeroReferenceSyncJob)
import Application.Xero.ReferenceTrust
import Application.Xero.ReferenceTrust.ReadModel
import Generated.Types
import IHP.ControllerPrelude

ensureTrustedXeroReferenceData ::
    (?modelContext :: ModelContext) =>
    UTCTime ->
    Maybe (Id User) ->
    XeroConnection ->
    XeroMissingReferenceDemand ->
    IO XeroReferenceTrustState
ensureTrustedXeroReferenceData now maybeActorUserId connection missingReferenceDemand = do
    initialState <- fetchXeroReferenceTrustState now connection missingReferenceDemand
    case initialState.trustDecision of
        StartOrJoinXeroReferenceSync -> do
            _ <- enqueueXeroReferenceSyncJob maybeActorUserId connection
            fetchXeroReferenceTrustState now connection missingReferenceDemand
        _ -> pure initialState
