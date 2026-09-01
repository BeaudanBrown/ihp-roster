module Application.Async.Payload
    ( decodeAppJobPayload
    , decodeAppJobPayloadV1
    , requireAppJobPayloadVersionIn
    , requireAppJobPayloadV1
    ) where

import Application.Async.Boundary (throwAppJobError)
import Application.Async.Error (AppJobError (..))
import qualified Data.Aeson as Aeson
import Generated.Types
import IHP.Prelude

requireAppJobPayloadVersionIn :: [Int] -> AppJob -> IO ()
requireAppJobPayloadVersionIn supportedVersions appJob =
    unless (appJob.payloadSchemaVersion `elem` supportedVersions) do
        throwAppJobError JobUnsupportedPayloadSchemaVersion

requireAppJobPayloadV1 :: AppJob -> IO ()
requireAppJobPayloadV1 = requireAppJobPayloadVersionIn [1]

decodeAppJobPayload :: Aeson.FromJSON payload => [Int] -> AppJob -> IO payload
decodeAppJobPayload supportedVersions appJob = do
    requireAppJobPayloadVersionIn supportedVersions appJob
    case Aeson.fromJSON appJob.payload of
        Aeson.Error _       -> throwAppJobError JobMalformedPersistedPayload
        Aeson.Success value -> pure value

decodeAppJobPayloadV1 :: Aeson.FromJSON payload => AppJob -> IO payload
decodeAppJobPayloadV1 = decodeAppJobPayload [1]
