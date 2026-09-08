{-# LANGUAGE DeriveDataTypeable #-}

module Application.Error.Transaction
    ( withAppResultTransaction
    ) where

import Application.Error.Types
import qualified Control.Exception as Exception
import IHP.ModelSupport (withTransaction)
import IHP.Prelude

-- Private and caught immediately outside 'withTransaction'. It exists only to
-- make IHP's exception-driven transaction runner roll back a typed 'Left'.
newtype AppResultRollback = AppResultRollback AppError
    deriving (Show, Typeable)

instance Exception.Exception AppResultRollback

withAppResultTransaction ::
    (?modelContext :: ModelContext) =>
    ((?modelContext :: ModelContext) => IO (AppResult value)) ->
    IO (AppResult value)
withAppResultTransaction operation = do
    result <- Exception.try @AppResultRollback $ withTransaction do
        operation >>= \case
            Right value -> pure value
            Left appError -> Exception.throwIO (AppResultRollback appError)
    pure case result of
        Right value                       -> Right value
        Left (AppResultRollback appError) -> Left appError
