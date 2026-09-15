module Application.OperationalIncident.Persistence
    ( lockIncidentIdentity
    ) where

import Application.Error.Runtime (ExternalRuntimeCategory (..), externalRuntimeInvariantFailure)
import IHP.ControllerPrelude

-- QueryBuilder has no advisory-lock operation. This transaction-scoped lock is
-- the sole serialization primitive for one stable incident identity.
lockIncidentIdentity :: (?modelContext :: ModelContext) => Text -> IO ()
lockIncidentIdentity identity = do
    rows :: [Only Bool] <-
        unsafeSqlQuery
            "SELECT TRUE FROM (SELECT pg_advisory_xact_lock(hashtext(?))) AS operational_incident_lock"
            (Only identity)
    unless (rows == [Only True]) $
        externalRuntimeInvariantFailure PersistedRuntimeInvariant "Unable to lock operational incident identity"
