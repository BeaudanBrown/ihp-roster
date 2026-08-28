module Application.Helper.Telemetry.Semantic
    ( JobRetryState (..)
    , boundedAttempt
    , boundedRetryNumber
    , nextBoundedRetryNumber
    , retryNumberAtLimit
    , httpStatusClass
    , jobRetryState
    , telemetryHttpMethod
    ) where

import qualified Data.ByteString as ByteString
import qualified Data.Text.Encoding as TextEncoding
import IHP.Prelude

data JobRetryState
    = RetryPossible
    | FinalAttempt
    deriving (Eq, Show)

boundedAttempt :: Int -> Int -> Int
boundedAttempt maximumAttempts attempt =
    max 1 (min (max 1 maximumAttempts) attempt)

boundedRetryNumber :: Int -> Int
boundedRetryNumber = max 0 . min 100

nextBoundedRetryNumber :: Int -> Int
nextBoundedRetryNumber retryNumber
    | retryNumber >= 100 = 100
    | otherwise = boundedRetryNumber (retryNumber + 1)

retryNumberAtLimit :: Int -> Bool
retryNumberAtLimit retryNumber = boundedRetryNumber retryNumber >= 100

jobRetryState :: Int -> Int -> JobRetryState
jobRetryState maximumAttempts attempt
    | boundedAttempt maximumAttempts attempt >= max 1 maximumAttempts = FinalAttempt
    | otherwise = RetryPossible

httpStatusClass :: Int -> Text
httpStatusClass status
    | status >= 100 && status < 600 = tshow (status `div` 100) <> "xx"
    | otherwise = "invalid"

telemetryHttpMethod :: ByteString.ByteString -> Text
telemetryHttpMethod method =
    case TextEncoding.decodeUtf8' method of
        Right "GET"    -> "GET"
        Right "POST"   -> "POST"
        Right "PUT"    -> "PUT"
        Right "PATCH"  -> "PATCH"
        Right "DELETE" -> "DELETE"
        _              -> "OTHER"
