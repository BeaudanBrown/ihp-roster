{-# OPTIONS_GHC -Werror=incomplete-patterns #-}

-- | Pure reconciliation decisions for one Xero employee and exact pay period.
-- Callers own database/provider reads and must scope the supplied remote references.
module Application.Xero.Timesheets.Reconciliation
    ( ExistingXeroTimesheetSubmission (..)
    , XeroTimesheetReconciliationDecision (..)
    , reconcileXeroTimesheet
    ) where

import Application.Helper.Xero.Types (XeroTimesheetRef (..))
import Application.Xero.WorkflowState (xeroSubmissionIsInProgress,
                                       xeroSubmissionIsSubmitted)
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import qualified Data.Text as Text
import Generated.Types
import IHP.Prelude

data ExistingXeroTimesheetSubmission = ExistingXeroTimesheetSubmission
    { existingSubmissionStatus          :: !XeroTimesheetSubmissionStatusEnum
    , existingSubmissionTimesheetId     :: !(Maybe Text)
    , existingSubmissionTimesheetStatus :: !(Maybe Text)
    }
    deriving (Eq, Show)

data XeroTimesheetReconciliationDecision
    = CreateXeroTimesheet
    | UpdateXeroDraft !Text
    | ReplaceMissingXeroDraft !Text
    | XeroSubmissionInProgress
    | BlockXeroNonDraft !Text !Text
    | BlockDistinctXeroTimesheets ![Text]
    | BlockUnknownXeroStatus !Text !(Maybe Text)
    | BlockMissingXeroTimesheetId !(Maybe Text)
    deriving (Eq, Show)

reconcileXeroTimesheet ::
    Maybe ExistingXeroTimesheetSubmission ->
    [XeroTimesheetRef] ->
    XeroTimesheetReconciliationDecision
reconcileXeroTimesheet (Just local) _
    | xeroSubmissionIsInProgress local.existingSubmissionStatus = XeroSubmissionInProgress
reconcileXeroTimesheet local remoteReferences =
    case List.find (isNothing . (.xeroTimesheetId)) remoteReferences of
        Just remoteReference -> BlockMissingXeroTimesheetId remoteReference.xeroTimesheetStatus
        Nothing -> reconcileIdentifiedRemoteTimesheets local (groupRemoteStatuses remoteReferences)

reconcileIdentifiedRemoteTimesheets ::
    Maybe ExistingXeroTimesheetSubmission ->
    Map Text (Maybe Text) ->
    XeroTimesheetReconciliationDecision
reconcileIdentifiedRemoteTimesheets local groupedStatuses =
    case Map.toAscList groupedStatuses of
        [] -> decisionWhenRemoteMissing local
        [(timesheetId, status)] -> decisionForOneRemote timesheetId status
        distinctTimesheets -> BlockDistinctXeroTimesheets (map fst distinctTimesheets)

decisionWhenRemoteMissing :: Maybe ExistingXeroTimesheetSubmission -> XeroTimesheetReconciliationDecision
decisionWhenRemoteMissing (Just local)
    | xeroSubmissionIsSubmitted local.existingSubmissionStatus =
        case local.existingSubmissionTimesheetId of
            Just priorTimesheetId -> decisionForMissingPriorTimesheet priorTimesheetId local.existingSubmissionTimesheetStatus
            Nothing -> BlockMissingXeroTimesheetId local.existingSubmissionTimesheetStatus
decisionWhenRemoteMissing _ = CreateXeroTimesheet

decisionForMissingPriorTimesheet :: Text -> Maybe Text -> XeroTimesheetReconciliationDecision
decisionForMissingPriorTimesheet = decisionForProviderStatus ReplaceMissingXeroDraft

decisionForOneRemote :: Text -> Maybe Text -> XeroTimesheetReconciliationDecision
decisionForOneRemote = decisionForProviderStatus UpdateXeroDraft

decisionForProviderStatus ::
    (Text -> XeroTimesheetReconciliationDecision) ->
    Text ->
    Maybe Text ->
    XeroTimesheetReconciliationDecision
decisionForProviderStatus _ timesheetId Nothing = BlockUnknownXeroStatus timesheetId Nothing
decisionForProviderStatus draftDecision timesheetId (Just status)
    | statusEquals "DRAFT" status = draftDecision timesheetId
    | isKnownNonDraftStatus status = BlockXeroNonDraft timesheetId status
    | otherwise = BlockUnknownXeroStatus timesheetId (Just status)

isKnownNonDraftStatus :: Text -> Bool
isKnownNonDraftStatus status =
    any (`statusEquals` status) ["APPROVED", "PROCESSED", "REJECTED", "REQUESTED"]

statusEquals :: Text -> Text -> Bool
statusEquals expected actual = Text.toCaseFold expected == Text.toCaseFold actual

canonicalRemoteStatus :: Maybe Text -> Maybe Text -> Maybe Text
canonicalRemoteStatus left right =
    if remoteStatusPriority left <= remoteStatusPriority right then left else right

remoteStatusPriority :: Maybe Text -> (Int, Text)
remoteStatusPriority Nothing = (1, "")
remoteStatusPriority (Just status)
    | statusEquals "DRAFT" status = (3, status)
    | isKnownNonDraftStatus status = (2, status)
    | otherwise = (0, status)

groupRemoteStatuses :: [XeroTimesheetRef] -> Map Text (Maybe Text)
groupRemoteStatuses =
    foldl'
        ( \grouped remoteReference ->
            case remoteReference.xeroTimesheetId of
                Nothing -> grouped
                Just timesheetId ->
                    Map.insertWith canonicalRemoteStatus timesheetId remoteReference.xeroTimesheetStatus grouped
        )
        Map.empty
