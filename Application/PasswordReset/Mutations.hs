{-# LANGUAGE RankNTypes #-}

module Application.PasswordReset.Mutations
    ( withPasswordResetCompletionLock
    , withPasswordResetUserLock
    ) where

import Application.Error.Runtime (ExternalRuntimeCategory (..), externalRuntimeInvariantFailure)
import qualified Database.PostgreSQL.Simple as PG
import IHP.ControllerPrelude

-- IHP QueryBuilder does not expose row locks. Keep the unavoidable locking SQL
-- isolated here; callers perform all credential reads and writes through
-- QueryBuilder while these locks serialize issue and consumption per account.
withPasswordResetUserLock ::
    (?modelContext :: ModelContext) =>
    UUID ->
    ((?modelContext :: ModelContext) => IO result) ->
    IO (Maybe result)
withPasswordResetUserLock userId action =
    withTransaction do
        lockedIds :: [PG.Only UUID] <- sqlQuery
            "SELECT id FROM users WHERE id = ? FOR UPDATE"
            (PG.Only userId)
        case lockedIds of
            [_] -> Just <$> action
            []  -> pure Nothing
            _   -> externalRuntimeInvariantFailure PersistedRuntimeInvariant "Password reset user lock returned multiple rows"

withPasswordResetCompletionLock ::
    (?modelContext :: ModelContext) =>
    UUID ->
    UUID ->
    ((?modelContext :: ModelContext) => IO result) ->
    IO (Maybe result)
withPasswordResetCompletionLock userId tokenId action = do
    nestedResult <- withPasswordResetUserLock userId do
        lockedIds :: [PG.Only UUID] <- sqlQuery
            "SELECT id FROM password_reset_tokens WHERE id = ? AND user_id = ? FOR UPDATE"
            (tokenId, userId)
        case lockedIds of
            [_] -> Just <$> action
            []  -> pure Nothing
            _   -> externalRuntimeInvariantFailure PersistedRuntimeInvariant "Password reset completion lock returned multiple rows"
    pure (join nestedResult)
