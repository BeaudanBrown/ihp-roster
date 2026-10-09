{-# LANGUAGE DeriveDataTypeable #-}

module Application.Error.Transaction
    ( withAppResultTransaction
    ) where

import Application.Error.Types
import qualified Control.Exception as Exception
import IHP.ModelSupport (unsafeSqlExecDiscardResult, withTransaction)
import IHP.Prelude

-- Private and caught immediately outside the owned transaction or savepoint.
-- It makes exception-driven database boundaries roll back a typed 'Left'.
newtype AppResultRollback = AppResultRollback AppError
    deriving (Show, Typeable)

instance Exception.Exception AppResultRollback

withAppResultTransaction ::
    (?modelContext :: ModelContext) =>
    ((?modelContext :: ModelContext) => IO (AppResult value)) ->
    IO (AppResult value)
withAppResultTransaction operation = do
    result <- Exception.try @AppResultRollback $
        if isJust ?modelContext.transactionRunner
            then withResultSavepoint (operation >>= rollbackOnLeft)
            else withTransaction (operation >>= rollbackOnLeft)
    pure case result of
        Right value                       -> Right value
        Left (AppResultRollback appError) -> Left appError

  where
    rollbackOnLeft :: AppResult value -> IO value
    rollbackOnLeft = either (Exception.throwIO . AppResultRollback) pure

-- IHP rejects nested withTransaction calls. A local typed operation composed
-- inside a durable mutation must roll back its own Left without committing or
-- replacing the caller's transaction. Every command uses the existing Hasql
-- transaction runner; never acquire a second database connection here.
-- PostgreSQL resolves repeated savepoint names to the innermost active one.
withResultSavepoint :: (?modelContext :: ModelContext) => IO value -> IO value
withResultSavepoint operation = Exception.mask \restore -> do
    unsafeSqlExecDiscardResult "SAVEPOINT bepis_app_result" ()
    value <- restore operation `Exception.onException` do
        unsafeSqlExecDiscardResult "ROLLBACK TO SAVEPOINT bepis_app_result" ()
        unsafeSqlExecDiscardResult "RELEASE SAVEPOINT bepis_app_result" ()
    unsafeSqlExecDiscardResult "RELEASE SAVEPOINT bepis_app_result" ()
    pure value
