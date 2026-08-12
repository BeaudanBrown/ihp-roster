{-# OPTIONS_GHC -Werror=incomplete-patterns #-}

-- | Stable provider-write identity and recovery policy for Xero timesheets.
module Application.Xero.Timesheets.ProviderWrite
    ( XeroTimesheetWriteFailureAction (..)
    , XeroTimesheetWriteOperation (..)
    , xeroTimesheetOperationCreatesTimesheet
    , xeroTimesheetOperationForDecision
    , xeroTimesheetRequestForOperation
    , xeroTimesheetWriteFailureAction
    , xeroTimesheetWriteIdempotencyKey
    , xeroTimesheetWriteOperationFromPersistence
    ) where

import Application.Helper.Xero.Types (XeroClientError (..))
import Application.Xero.Timesheets.Reconciliation (XeroTimesheetReconciliationDecision (..))
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as AesonKey
import qualified Data.Aeson.KeyMap as AesonKeyMap
import qualified Data.Text as Text
import qualified Data.Vector as Vector
import IHP.Prelude
import Text.Read (readMaybe)

data XeroTimesheetWriteOperation
    = InitialXeroTimesheetCreate
    | UpdateXeroTimesheetDraft !Text
    | ReplaceMissingXeroTimesheetDraft
    deriving (Eq, Show)

data XeroTimesheetWriteFailureAction
    = RefetchAfterMissingUpdate
    | RefetchAfterCreateConflict
    | FailUncertainXeroTimesheetWrite
    | FailXeroTimesheetWrite
    deriving (Eq, Show)

xeroTimesheetOperationForDecision :: XeroTimesheetReconciliationDecision -> Maybe XeroTimesheetWriteOperation
xeroTimesheetOperationForDecision CreateXeroTimesheet = Just InitialXeroTimesheetCreate
xeroTimesheetOperationForDecision (UpdateXeroDraft timesheetId) = Just (UpdateXeroTimesheetDraft timesheetId)
xeroTimesheetOperationForDecision (ReplaceMissingXeroDraft _) = Just ReplaceMissingXeroTimesheetDraft
xeroTimesheetOperationForDecision XeroSubmissionInProgress = Nothing
xeroTimesheetOperationForDecision BlockXeroNonDraft {} = Nothing
xeroTimesheetOperationForDecision BlockDistinctXeroTimesheets {} = Nothing
xeroTimesheetOperationForDecision BlockUnknownXeroStatus {} = Nothing
xeroTimesheetOperationForDecision BlockMissingXeroTimesheetId {} = Nothing

xeroTimesheetOperationCreatesTimesheet :: XeroTimesheetWriteOperation -> Bool
xeroTimesheetOperationCreatesTimesheet InitialXeroTimesheetCreate       = True
xeroTimesheetOperationCreatesTimesheet UpdateXeroTimesheetDraft {}      = False
xeroTimesheetOperationCreatesTimesheet ReplaceMissingXeroTimesheetDraft = True

xeroTimesheetWriteIdempotencyKey ::
    UUID ->
    Int ->
    XeroTimesheetWriteOperation ->
    Text
xeroTimesheetWriteIdempotencyKey submissionId operationSequence operation =
    Text.intercalate
        ":"
        [ "xero-timesheet"
        , tshow submissionId
        , tshow operationSequence
        , xeroTimesheetWriteOperationName operation
        ]

xeroTimesheetWriteOperationName :: XeroTimesheetWriteOperation -> Text
xeroTimesheetWriteOperationName InitialXeroTimesheetCreate       = "create"
xeroTimesheetWriteOperationName UpdateXeroTimesheetDraft {}      = "update"
xeroTimesheetWriteOperationName ReplaceMissingXeroTimesheetDraft = "replace"

xeroTimesheetRequestForOperation :: XeroTimesheetWriteOperation -> Aeson.Value -> Aeson.Value
xeroTimesheetRequestForOperation operation (Aeson.Array values) =
    Aeson.Array (Vector.map updateRequestObject values)
  where
    updateRequestObject (Aeson.Object object) =
        Aeson.Object $
            case operation of
                InitialXeroTimesheetCreate -> AesonKeyMap.delete timesheetIdKey object
                UpdateXeroTimesheetDraft timesheetId -> AesonKeyMap.insert timesheetIdKey (Aeson.String timesheetId) object
                ReplaceMissingXeroTimesheetDraft -> AesonKeyMap.delete timesheetIdKey object
    updateRequestObject value = value
    timesheetIdKey = AesonKey.fromText "TimesheetID"
xeroTimesheetRequestForOperation _ value = value

xeroTimesheetWriteOperationFromPersistence ::
    UUID ->
    Text ->
    Aeson.Value ->
    Either Text XeroTimesheetWriteOperation
xeroTimesheetWriteOperationFromPersistence submissionId idempotencyKey requestPayload = do
    persistedOperationName <-
        case Text.splitOn ":" idempotencyKey of
            ["xero-timesheet", persistedSubmissionId, operationSequence, operationName]
                | persistedSubmissionId == tshow submissionId
                , Just sequenceNumber <- readMaybe (cs operationSequence) :: Maybe Int
                , sequenceNumber >= 0 -> Right operationName
            _ -> Left invalidKeyMessage
    let operation =
            case requestTimesheetId requestPayload of
                Just timesheetId -> UpdateXeroTimesheetDraft timesheetId
                Nothing
                    | persistedOperationName == "replace" -> ReplaceMissingXeroTimesheetDraft
                    | otherwise -> InitialXeroTimesheetCreate
    if xeroTimesheetWriteOperationName operation == persistedOperationName
        then Right operation
        else Left invalidKeyMessage
  where
    invalidKeyMessage = "Persisted Xero timesheet operation does not match its idempotency key."

requestTimesheetId :: Aeson.Value -> Maybe Text
requestTimesheetId (Aeson.Array values) =
    listToMaybe (Vector.toList values) >>= \case
        Aeson.Object object ->
            case AesonKeyMap.lookup (AesonKey.fromText "TimesheetID") object of
                Just (Aeson.String timesheetId) -> Just timesheetId
                _                               -> Nothing
        _ -> Nothing
requestTimesheetId _ = Nothing

xeroTimesheetWriteFailureAction :: XeroTimesheetWriteOperation -> XeroClientError -> XeroTimesheetWriteFailureAction
xeroTimesheetWriteFailureAction operation error =
    case error of
        XeroHttpError _ -> FailUncertainXeroTimesheetWrite
        XeroDecodeError _ -> FailUncertainXeroTimesheetWrite
        XeroHttpResponseError { statusCode }
            | statusCode `elem` [408, 502, 503, 504] -> FailUncertainXeroTimesheetWrite
            | statusCode == 404
            , UpdateXeroTimesheetDraft {} <- operation -> RefetchAfterMissingUpdate
            | statusCode == 409
            , xeroTimesheetOperationCreatesTimesheet operation -> RefetchAfterCreateConflict
            | otherwise -> FailXeroTimesheetWrite
        XeroSemanticError _ -> FailXeroTimesheetWrite
        XeroNoTenantsError -> FailXeroTimesheetWrite
