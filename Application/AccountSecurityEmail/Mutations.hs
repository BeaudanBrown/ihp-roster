module Application.AccountSecurityEmail.Mutations
    ( withEmailVerificationTokenLock
    , withPasskeySetupTokenLock
    , withPasswordResetTokenLock
    ) where

import qualified Database.PostgreSQL.Simple as PG
import IHP.ControllerPrelude

withEmailVerificationTokenLock ::
    (?modelContext :: ModelContext) =>
    UUID ->
    ((?modelContext :: ModelContext) => IO result) ->
    IO (Maybe result)
withEmailVerificationTokenLock tokenId action =
    withTokenLock
        "SELECT id FROM email_verification_tokens WHERE id = ? FOR UPDATE"
        tokenId
        action

withPasswordResetTokenLock ::
    (?modelContext :: ModelContext) =>
    UUID ->
    ((?modelContext :: ModelContext) => IO result) ->
    IO (Maybe result)
withPasswordResetTokenLock tokenId action =
    withTokenLock
        "SELECT id FROM password_reset_tokens WHERE id = ? FOR UPDATE"
        tokenId
        action

withPasskeySetupTokenLock ::
    (?modelContext :: ModelContext) =>
    UUID ->
    ((?modelContext :: ModelContext) => IO result) ->
    IO (Maybe result)
withPasskeySetupTokenLock tokenId action =
    withTokenLock
        "SELECT id FROM passkey_setup_tokens WHERE id = ? FOR UPDATE"
        tokenId
        action

withTokenLock ::
    (?modelContext :: ModelContext) =>
    PG.Query ->
    UUID ->
    ((?modelContext :: ModelContext) => IO result) ->
    IO (Maybe result)
withTokenLock lockQuery tokenId action =
    withTransaction do
        lockedIds :: [PG.Only UUID] <- sqlQuery lockQuery (PG.Only tokenId)
        case lockedIds of
            [_] -> Just <$> action
            []  -> pure Nothing
            _   -> error "Account-security token lock returned multiple rows"
