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
import Data.Time.Calendar (Day)
import qualified Data.Vector as Vector
import IHP.Prelude

data XeroTimesheetWriteOperation
    = InitialXeroTimesheetCreate
    | UpdateXeroTimesheetDraft !Text
    | ReplaceMissingXeroTimesheetDraft !Text
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
xeroTimesheetOperationForDecision (ReplaceMissingXeroDraft priorTimesheetId) = Just (ReplaceMissingXeroTimesheetDraft priorTimesheetId)
xeroTimesheetOperationForDecision XeroSubmissionInProgress = Nothing
xeroTimesheetOperationForDecision BlockXeroNonDraft {} = Nothing
xeroTimesheetOperationForDecision BlockDistinctXeroTimesheets {} = Nothing
xeroTimesheetOperationForDecision BlockUnknownXeroStatus {} = Nothing
xeroTimesheetOperationForDecision BlockMissingXeroTimesheetId {} = Nothing

xeroTimesheetOperationCreatesTimesheet :: XeroTimesheetWriteOperation -> Bool
xeroTimesheetOperationCreatesTimesheet InitialXeroTimesheetCreate = True
xeroTimesheetOperationCreatesTimesheet UpdateXeroTimesheetDraft {} = False
xeroTimesheetOperationCreatesTimesheet ReplaceMissingXeroTimesheetDraft {} = True

xeroTimesheetWriteIdempotencyKey ::
    Text ->
    Day ->
    Day ->
    XeroTimesheetWriteOperation ->
    Text
xeroTimesheetWriteIdempotencyKey employeeId periodStart periodEnd operation =
    Text.take 128 $
        Text.intercalate
            ":"
            ( [ "xero-timesheet"
              , operationName operation
              , employeeId
              , tshow periodStart
              , tshow periodEnd
              ]
                <> operationTarget operation
            )
  where
    operationName InitialXeroTimesheetCreate          = "create"
    operationName UpdateXeroTimesheetDraft {}         = "update"
    operationName ReplaceMissingXeroTimesheetDraft {} = "replace"

    operationTarget InitialXeroTimesheetCreate = []
    operationTarget (UpdateXeroTimesheetDraft timesheetId) = [timesheetId]
    operationTarget (ReplaceMissingXeroTimesheetDraft priorTimesheetId) = [priorTimesheetId]

xeroTimesheetRequestForOperation :: XeroTimesheetWriteOperation -> Aeson.Value -> Aeson.Value
xeroTimesheetRequestForOperation operation (Aeson.Array values) =
    Aeson.Array (Vector.map updateRequestObject values)
  where
    updateRequestObject (Aeson.Object object) =
        Aeson.Object $
            case operation of
                InitialXeroTimesheetCreate -> AesonKeyMap.delete timesheetIdKey object
                UpdateXeroTimesheetDraft timesheetId -> AesonKeyMap.insert timesheetIdKey (Aeson.String timesheetId) object
                ReplaceMissingXeroTimesheetDraft _ -> AesonKeyMap.delete timesheetIdKey object
    updateRequestObject value = value
    timesheetIdKey = AesonKey.fromText "TimesheetID"
xeroTimesheetRequestForOperation _ value = value

xeroTimesheetWriteOperationFromPersistence ::
    Text ->
    Day ->
    Day ->
    Text ->
    Aeson.Value ->
    Either Text XeroTimesheetWriteOperation
xeroTimesheetWriteOperationFromPersistence employeeId periodStart periodEnd idempotencyKey requestPayload =
    case requestTimesheetId requestPayload of
        Just timesheetId -> verifyPersistedKey (UpdateXeroTimesheetDraft timesheetId)
        Nothing ->
            case Text.stripPrefix replacementPrefix idempotencyKey of
                Just priorTimesheetId
                    | not (Text.null priorTimesheetId) -> verifyPersistedKey (ReplaceMissingXeroTimesheetDraft priorTimesheetId)
                _ -> verifyPersistedKey InitialXeroTimesheetCreate
  where
    replacementPrefix =
        Text.intercalate ":" ["xero-timesheet", "replace", employeeId, tshow periodStart, tshow periodEnd] <> ":"
    verifyPersistedKey operation
        | xeroTimesheetWriteIdempotencyKey employeeId periodStart periodEnd operation == idempotencyKey = Right operation
        | otherwise = Left "Persisted Xero timesheet operation does not match its idempotency key."

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
