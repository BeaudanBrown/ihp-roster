module Application.Xero.Admin.ReferenceSyncPolicy
    ( XeroReferencePacer
    , XeroReferenceSyncRetryDecision (..)
    , fetchPacedXeroEarningsRates
    , newXeroReferencePacer
    , newXeroReferencePacerAfter
    , runPacedXeroReferenceRequest
    , xeroReferenceRequestDelayMicros
    , xeroReferenceSyncRetryDecision
    ) where

import Application.Helper.Xero
import Control.Concurrent (MVar, modifyMVar, newMVar)
import qualified Data.Set as Set
import qualified Data.Text as Text
import IHP.Prelude

newtype XeroReferencePacer = XeroReferencePacer (MVar (Maybe UTCTime))

data XeroReferenceSyncRetryDecision
    = RetryXeroReferenceSyncAt !UTCTime
    | FailXeroReferenceSync
    deriving (Eq, Show)

xeroReferenceSyncRetryDecision ::
    UTCTime ->
    UTCTime ->
    Int ->
    Int ->
    XeroClientError ->
    XeroReferenceSyncRetryDecision
xeroReferenceSyncRetryDecision startedAt now attemptNumber jitterSeconds errorValue
    | now >= retryDeadline = FailXeroReferenceSync
    | not (xeroReferenceSyncErrorIsTransient errorValue) = FailXeroReferenceSync
    | retryAt >= retryDeadline = FailXeroReferenceSync
    | otherwise = RetryXeroReferenceSyncAt retryAt
    where
        retryDeadline = addUTCTime (24 * 60 * 60) startedAt
        retryAt =
            fromMaybe
                (addUTCTime (fromIntegral (exponentialDelaySeconds attemptNumber + boundedJitterSeconds)) now)
                (xeroRetryAfterTime now errorValue)
        boundedJitterSeconds = max 0 (min 30 jitterSeconds)

xeroReferenceSyncErrorIsTransient :: XeroClientError -> Bool
xeroReferenceSyncErrorIsTransient = \case
    XeroHttpResponseError { statusCode } ->
        statusCode == 408
            || statusCode == 425
            || statusCode == 429
            || statusCode >= 500
    XeroHttpError message ->
        let normalized = Text.toLower message
         in not ("pagination exceeded" `Text.isInfixOf` normalized)
                && not ("pagination repeated" `Text.isInfixOf` normalized)
                && not ("tenant lease was lost" `Text.isInfixOf` normalized)
    XeroSemanticError _ -> False
    XeroDecodeError _ -> False
    XeroNoTenantsError -> False

xeroRetryAfterTime :: UTCTime -> XeroClientError -> Maybe UTCTime
xeroRetryAfterTime now XeroHttpResponseError { retryAfter = Just (XeroRetryAfterDelay seconds) } =
    Just (addUTCTime (fromIntegral (max 0 seconds)) now)
xeroRetryAfterTime now XeroHttpResponseError { retryAfter = Just (XeroRetryAfterAt retryAt) }
    | retryAt > now = Just retryAt
xeroRetryAfterTime _ _ = Nothing

exponentialDelaySeconds :: Int -> Int
exponentialDelaySeconds attemptNumber =
    min 3600 (30 * (2 ^ min 7 (max 0 attemptNumber)))

newXeroReferencePacer :: IO XeroReferencePacer
newXeroReferencePacer = newXeroReferencePacerAfter Nothing

newXeroReferencePacerAfter :: Maybe UTCTime -> IO XeroReferencePacer
newXeroReferencePacerAfter previousStart = XeroReferencePacer <$> newMVar previousStart

xeroReferenceRequestDelayMicros :: Maybe UTCTime -> UTCTime -> Int
xeroReferenceRequestDelayMicros Nothing _ = 0
xeroReferenceRequestDelayMicros (Just previousStart) now =
    max 0 (ceiling ((1.2 - realToFrac (diffUTCTime now previousStart)) * 1000000 :: Double))

runPacedXeroReferenceRequest ::
    XeroReferencePacer ->
    IO UTCTime ->
    (Int -> IO ()) ->
    IO value ->
    IO value
runPacedXeroReferenceRequest (XeroReferencePacer state) currentTime sleepMicros action =
    modifyMVar state \previousStart -> do
        now <- currentTime
        sleepMicros (xeroReferenceRequestDelayMicros previousStart now)
        requestStartedAt <- currentTime
        result <- action
        pure (Just requestStartedAt, result)

fetchPacedXeroEarningsRates ::
    (Int -> IO ()) ->
    (Int -> IO (Either XeroClientError [XeroEarningsRateRef])) ->
    (Int -> IO ()) ->
    IO (Either XeroClientError [XeroEarningsRateRef])
fetchPacedXeroEarningsRates paceBeforePage fetchPage recordCompletedPage =
    go 1 Set.empty []
    where
        go page seenIds acc = do
            paceBeforePage page
            fetchPage page >>= \case
                Left err -> pure (Left err)
                Right pageRates -> do
                    recordCompletedPage page
                    let pageIds = Set.fromList (map (.xeroEarningsRateId) pageRates)
                    let repeatedFullPage = length pageRates >= xeroPayItemsPageSize && pageIds `Set.isSubsetOf` seenIds
                    let accumulated = acc <> pageRates
                    if repeatedFullPage
                        then pure (Left (XeroHttpError "Xero payroll pay items pagination repeated a full page without new items."))
                        else if length pageRates < xeroPayItemsPageSize
                            then pure (Right accumulated)
                            else go (page + 1) (seenIds <> pageIds) accumulated
