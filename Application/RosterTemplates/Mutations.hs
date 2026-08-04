module Application.RosterTemplates.Mutations
    ( lockRosterTemplateName
    , lockRosterTemplateVersion
    ) where

import qualified Data.Text as Text
import Database.PostgreSQL.Simple (Only (..))
import Generated.Types
import IHP.ModelSupport (sqlQuery, sqlQueryScalar, unpackId)
import IHP.Prelude

-- PostgreSQL row locking is intentionally isolated here; ordinary template reads
-- use IHP QueryBuilder.
lockRosterTemplateName :: (?modelContext :: ModelContext) => Id RosterGroup -> Text -> IO ()
lockRosterTemplateName rosterGroupId normalizedName = do
    let lockKey = "roster-template-name:" <> tshow (unpackId rosterGroupId) <> ":" <> Text.toCaseFold normalizedName
    lockResults :: [Only Bool] <- sqlQuery
        "SELECT TRUE FROM (SELECT pg_advisory_xact_lock(hashtext(?))) AS roster_template_name_lock"
        (Only (Text.take 300 lockKey))
    unless (lockResults == [Only True]) do
        error "Unable to lock roster template name key"

lockRosterTemplateVersion :: (?modelContext :: ModelContext) => Id RosterTemplate -> IO Int
lockRosterTemplateVersion templateId =
    sqlQueryScalar
        "SELECT current_version FROM roster_templates WHERE id = ? FOR UPDATE"
        (Only (unpackId templateId))
