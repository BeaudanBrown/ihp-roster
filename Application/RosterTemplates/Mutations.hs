module Application.RosterTemplates.Mutations
    ( lockRosterTemplateVersion
    ) where

import Database.PostgreSQL.Simple (Only (..))
import Generated.Types
import IHP.ModelSupport (sqlQueryScalar, unpackId)
import IHP.Prelude

-- PostgreSQL row locking is intentionally isolated here; ordinary template reads
-- use IHP QueryBuilder.
lockRosterTemplateVersion :: (?modelContext :: ModelContext) => Id RosterTemplate -> IO Int
lockRosterTemplateVersion templateId =
    sqlQueryScalar
        "SELECT current_version FROM roster_templates WHERE id = ? FOR UPDATE"
        (Only (unpackId templateId))
