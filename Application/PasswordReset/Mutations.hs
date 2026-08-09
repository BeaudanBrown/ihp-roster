{-# LANGUAGE RankNTypes #-}

module Application.PasswordReset.Mutations
    ( withPasswordResetTokenLock
    , withPasswordResetUserLock
    ) where

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
            _   -> error "Password reset user lock returned multiple rows"

withPasswordResetTokenLock ::
    (?modelContext :: ModelContext) =>
    UUID ->
    ((?modelContext :: ModelContext) => IO result) ->
    IO (Maybe result)
withPasswordResetTokenLock tokenId action =
    withTransaction do
        lockedIds :: [PG.Only UUID] <- sqlQuery
            "SELECT id FROM password_reset_tokens WHERE id = ? FOR UPDATE"
            (PG.Only tokenId)
        case lockedIds of
            [_] -> Just <$> action
            []  -> pure Nothing
            _   -> error "Password reset token lock returned multiple rows"
