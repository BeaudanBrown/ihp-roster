module Application.Async.Boundary
    ( runAppJobBoundary
    , throwAppJobError
    , trySynchronousAppJobAction
    ) where

import Application.Async.Error
import Application.Error.Domain (projectDomainError)
import Application.Error.Telemetry (recordAppError)
import Application.Error.Types
import Control.Exception (Exception (..))
import qualified Control.Exception as BaseException
import qualified Control.Exception.Safe as Exception
import IHP.ModelSupport (HasqlError)
import IHP.Prelude
import Prelude (Show (..))
import qualified Prelude

-- This is the only exception Bepis deliberately exposes to IHP's AppJob
-- worker. Its Show instance contains only the already-sanitized projection.
data AppJobBoundaryException = AppJobBoundaryException !AppError

instance Show AppJobBoundaryException where
    show (AppJobBoundaryException appError) =
        cs (appErrorCode appError <> ": " <> appErrorSafeMessage appError)

instance Exception AppJobBoundaryException where
    displayException = Prelude.show
    backtraceDesired _ = False

throwAppJobError :: AppJobError -> IO value
throwAppJobError = throwProjectedAppError . projectDomainError

runAppJobBoundary :: IO value -> IO value
runAppJobBoundary action =
    trySynchronousAppJobAction action >>= \case
        Right value -> pure value
        Left exception ->
            case Exception.fromException exception of
                Just boundaryException -> BaseException.throwIO (boundaryException :: AppJobBoundaryException)
                Nothing -> throwProjectedAppError (projectDomainError (classifyUnexpectedJobException exception))

-- | Captures only synchronous failures. IHP remains the sole owner of
-- asynchronous worker cancellation.
trySynchronousAppJobAction :: IO value -> IO (Either Exception.SomeException value)
trySynchronousAppJobAction action =
    BaseException.try action >>= \case
        Left exception
            | Exception.isAsyncException exception -> BaseException.throwIO (exception :: Exception.SomeException)
            | otherwise -> pure (Left exception)
        Right value -> pure (Right value)

classifyUnexpectedJobException :: Exception.SomeException -> AppJobError
classifyUnexpectedJobException exception
    | isJust (Exception.fromException exception :: Maybe HasqlError) = JobDatabaseUnavailable
    | otherwise = JobUnexpectedSynchronousFailure

throwProjectedAppError :: AppError -> IO value
throwProjectedAppError appError = do
    recordAppError appError
    BaseException.throwIO (AppJobBoundaryException appError)
