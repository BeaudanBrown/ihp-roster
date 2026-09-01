{-# LANGUAGE DeriveGeneric #-}

module Application.Async.Error
    ( AppJobError (..)
    ) where

import Application.Error.Domain
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
        JobAuthenticationRequired -> actionRequiredErrorProjection "The provider connection requires attention before this job can continue."
        JobRateLimited -> retryableErrorProjection "The provider asked Bepis to retry this job later."
        JobValidationRejected -> terminalErrorProjection "The job's validated data was rejected."
        JobRemoteConflict -> terminalErrorProjection "The provider state conflicts with this job."
        JobMalformedResponse -> retryableErrorProjection "The provider returned a response Bepis could not safely read."
        JobTransportUnavailable -> retryableErrorProjection "The provider could not be reached."
        JobConfigurationUnavailable -> terminalErrorProjection "Job configuration is unavailable."
        JobCryptoUnavailable -> terminalErrorProjection "Secure job processing is unavailable."
        JobDatabaseUnavailable -> retryableErrorProjection "The job could not update its durable state."
        JobMalformedPersistedPayload -> terminalErrorProjection "The stored job payload is invalid."
        JobUnsupportedPayloadSchemaVersion -> terminalErrorProjection "The stored job payload version is unsupported."
        JobInvalidProvenance -> terminalErrorProjection "The stored job provenance is invalid."
        JobUnknownKind -> terminalErrorProjection "The stored job kind is unsupported."
        JobUnexpectedSynchronousFailure -> retryableErrorProjection "The job could not be completed."
