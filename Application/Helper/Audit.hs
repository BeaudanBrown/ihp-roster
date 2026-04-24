module Application.Helper.Audit
    ( recordUserAuthenticationAuditEvent
    ) where

import qualified Data.Aeson as Aeson
import Generated.Types
import IHP.ControllerPrelude

recordUserAuthenticationAuditEvent ::
    (?modelContext :: ModelContext) =>
    User ->
    Text ->
    Aeson.Value ->
    IO AuthAuditEvent
recordUserAuthenticationAuditEvent user eventType metadata =
    newRecord @AuthAuditEvent
        |> set #userId (Just (unpackId user.id))
        |> set #eventType eventType
        |> set #metadata metadata
        |> createRecord
