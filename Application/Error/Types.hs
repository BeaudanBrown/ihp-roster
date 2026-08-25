module Application.Error.Types
    ( AppError
    , AppResult
    , ErrorSeverity (..)
    , Recovery (..)
    , RetryDirective (..)
    , appErrorCode
    , appErrorRecovery
    , appErrorRetryDirective
    , appErrorSafeMessage
    , appErrorSeverity
    ) where

import Application.Error.Types.Internal
