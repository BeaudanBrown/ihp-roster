{-# LANGUAGE DeriveGeneric #-}

module Application.Async.Error
    ( AppJobError (..)
    ) where

import Application.Error.Domain
import Application.Error.Types
import GHC.Generics (Generic)
import IHP.Prelude

-- | Closed, payload-free classifications that may cross the final AppJob
-- boundary. Provider payloads, identifiers, parser diagnostics, and exception
-- text must be retained only by their owning subsystem, never in this value.
data AppJobError
    = JobAuthenticationRequired
    | JobRateLimited
    | JobValidationRejected
    | JobRemoteConflict
    | JobMalformedResponse
    | JobTransportUnavailable
    | JobConfigurationUnavailable
    | JobCryptoUnavailable
    | JobDatabaseUnavailable
    | JobMalformedPersistedPayload
    | JobUnsupportedPayloadSchemaVersion
    | JobInvalidProvenance
    | JobUnknownKind
    | JobUnexpectedSynchronousFailure
    deriving (Eq, Generic, Show)

instance DomainError AppJobError where
    appErrorProjection = \case
        JobAuthenticationRequired -> actionRequired "The provider connection requires attention before this job can continue."
        JobRateLimited -> retryable "The provider asked Bepis to retry this job later."
        JobValidationRejected -> terminal "The job's validated data was rejected."
        JobRemoteConflict -> terminal "The provider state conflicts with this job."
        JobMalformedResponse -> retryable "The provider returned a response Bepis could not safely read."
        JobTransportUnavailable -> retryable "The provider could not be reached."
        JobConfigurationUnavailable -> terminal "Job configuration is unavailable."
        JobCryptoUnavailable -> terminal "Secure job processing is unavailable."
        JobDatabaseUnavailable -> retryable "The job could not update its durable state."
        JobMalformedPersistedPayload -> terminal "The stored job payload is invalid."
        JobUnsupportedPayloadSchemaVersion -> terminal "The stored job payload version is unsupported."
        JobInvalidProvenance -> terminal "The stored job provenance is invalid."
        JobUnknownKind -> terminal "The stored job kind is unsupported."
        JobUnexpectedSynchronousFailure -> retryable "The job could not be completed."
      where
        actionRequired message = AppErrorProjection
            { safeMessage = message
            , severity = Blocking
            , recovery = UserActionRequired
            , retryDirective = DoNotRetry
            }
        terminal message = AppErrorProjection
            { safeMessage = message
            , severity = Critical
            , recovery = Terminal
            , retryDirective = DoNotRetry
            }
        retryable message = AppErrorProjection
            { safeMessage = message
            , severity = Critical
            , recovery = Retryable
            , retryDirective = RetryUsingBoundaryPolicy
            }
