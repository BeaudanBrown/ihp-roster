{-# LANGUAGE DeriveFunctor #-}

module Application.Xero.Timesheets.Prepare
    ( XeroPreparationOutcome (..)
    , XeroPreparationResult
    , PayItemRequirementsBlocker (..)
    , PayItemRequirementsState (..)
    , XeroPreparationStaffDecision (..)
    , applyXeroPreparationStaffDecision
    , approveXeroPreparationPayItemDecisions
    , approveXeroPreparationStaffStep
    , loadXeroTimesheetPreparationView
    , fetchPreparationPayItemRequirements
    , refreshXeroTimesheetPreparation
    , selectXeroTimesheetPreparationPeriod
    , startXeroTimesheetPreparation
    , submitXeroTimesheetPreparation
    ) where

import Application.Error.Types (AppResult)
import Application.Helper.Audit (recordCurrentUserAuditEvent)
import Application.Helper.ControllerContext (currentVenueId)
import Application.Helper.Staff (isLinkedActiveStaff)
import Application.Helper.Xero
import Application.Helper.XeroAdminTypes
import Application.Helper.XeroTimesheetReadiness
import Application.Xero.Admin.PayItems
import Application.Xero.Admin.ReadModel
import Application.Xero.Admin.ReferenceData
import Application.Xero.Connection
import Application.Xero.EmployeeId (XeroEmployeeId, XeroEmployeeSelection (..),
                                    parseXeroEmployeeId, xeroEmployeeIdText)
import Application.Xero.ReferenceDemand (fetchXeroMissingReferenceDemand)
import Application.Xero.ReferenceTrust.Presentation (XeroPreparationReferencePresentation (..),
                                                     xeroPreparationReferencePresentation)
import Application.Xero.ReferenceTrust.ReadModel (XeroReferenceTrustState (..))
import Application.Xero.ReferenceTrust.Service
import Application.Xero.StaffMappings (applyXeroStaffMappingSelection)
import Application.Xero.Timesheets.Buckets
import Application.Xero.Timesheets.Prepare.Helpers
import Application.Xero.Timesheets.Preview
import Application.Xero.Timesheets.ReconciliationReview (XeroTimesheetReconciliationNotice (..),
                                                         reconciliationReviewNotices)
import Application.Xero.Timesheets.Submission
import Application.Xero.WorkflowState (xeroPayItemRequirementIsProposed,
                                       xeroStaffMappingIsVerified)
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Types as AesonTypes
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import qualified Data.Text as Text
import Data.Time.Calendar (Day)
import Generated.Types
import IHP.ControllerPrelude

data XeroPreparationOutcome value
    = XeroPreparationOutcomeBlocked !Text
    | XeroPreparationOutcomeAvailable value
    deriving (Eq, Functor, Show)

type XeroPreparationResult value = AppResult (XeroPreparationOutcome value)

preparationFailure :: Text -> XeroPreparationResult value
preparationFailure = Right . XeroPreparationOutcomeBlocked

preparationSuccess :: value -> XeroPreparationResult value
preparationSuccess = Right . XeroPreparationOutcomeAvailable

data PayItemRequirementsBlocker
    = PayItemRequirementsPeriodBlocked !SelectedPreparationPeriodError
    | PayItemRequirementsBucketsBlocked ![XeroBucketProblem]
    | PayItemRequirementsNoApprovedBuckets
    deriving (Eq, Show)

data PayItemRequirementsState
    = PayItemRequirementsAvailable ![XeroPayItemRequirement]
    | PayItemRequirementsBlocked !PayItemRequirementsBlocker

data XeroPreparationStaffDecision
    = SelectXeroEmployee !XeroEmployeeId
    | MarkStaffNotPaidThroughXero
    deriving (Eq, Show)

startXeroTimesheetPreparation ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    IO (XeroPreparationResult XeroTimesheetPreparationView)
startXeroTimesheetPreparation = do
    maybeConnection <- fetchCurrentVenueXeroConnection
    case maybeConnection of
        Nothing -> pure (preparationFailure "Connect Xero before preparing draft timesheets.")
        Just connection ->
            refreshCurrentVenueXeroReferenceDataForPreparation connection >>= \case
                Left message -> pure (preparationFailure message)
                Right refreshedConnection -> do
                    now <- getCurrentTime
                    run <-
                        newRecord @XeroTimesheetPreparationRun
                            |> set #venueId (unpackId currentVenueId)
                            |> set #xeroConnectionId (unpackId refreshedConnection.id)
                            |> set #createdByUserId (unpackId currentUser.id)
                            |> set #status Preparing
                            |> set #connectionSnapshotJson (xeroConnectionSnapshotJson refreshedConnection)
                            |> set #eventsJson (preparationInitialEventsJson now "staff-first")
                            |> set #startedAt now
                            |> createRecord
                    finalizePreparationRun run []

refreshCurrentVenueXeroReferenceDataForPreparation ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    XeroConnection ->
    IO (Either Text XeroConnection)
refreshCurrentVenueXeroReferenceDataForPreparation connection = do
    now <- getCurrentTime
    missingReferenceDemand <- fetchXeroMissingReferenceDemand connection
    trustState <- requestTrustedXeroReferenceData now (Just currentUser.id) connection missingReferenceDemand
    pure case xeroPreparationReferencePresentation trustState.trustDecision of
        XeroPreparationReferenceReady           -> Right connection
        XeroPreparationReferenceWaiting message -> Left message
        XeroPreparationReferenceBlocked message -> Left message

refreshXeroTimesheetPreparation ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Id XeroTimesheetPreparationRun ->
    IO (XeroPreparationResult XeroTimesheetPreparationView)
refreshXeroTimesheetPreparation runId = do
    fetchPreparationRunForCurrentVenue runId >>= \case
        Nothing -> pure (preparationFailure "Xero preparation run was not found for this venue.")
        Just run -> do
            connection <- fetch (Id run.xeroConnectionId :: Id XeroConnection)
            if not (preparationRunHasPeriod run)
                then finalizePreparationRun run []
                else if connection.connectionStatus /= "active"
                then do
                    _ <-
                        run
                            |> set #status NeedsReconnect
                            |> set #errorSummary (Just "Reconnect Xero before preparing draft timesheets.")
                            |> set #connectionSnapshotJson (xeroConnectionSnapshotJson connection)
                            |> updateRecord
                    loadXeroTimesheetPreparationView runId
                else
                    readXeroConfig >>= \case
                        Left message -> do
                            _ <- markPreparationFailed run message
                            loadXeroTimesheetPreparationView runId
                        Right config ->
                            refreshXeroConnectionAccess config connection >>= \case
                                Left message -> do
                                    _ <-
                                        run
                                            |> set #status NeedsReconnect
                                            |> set #errorSummary (Just message)
                                            |> updateRecord
                                    loadXeroTimesheetPreparationView runId
                                Right (refreshedConnection, accessToken) -> do
                                    xeroClient <- currentXeroClient
                                    fetchXeroPayRunsForPreparation xeroClient accessToken refreshedConnection.tenantId run >>= \case
                                        Left message -> do
                                            _ <- markPreparationFailed run message
                                            loadXeroTimesheetPreparationView runId
                                        Right payRuns -> do
                                            refreshedRun <- persistRemotePreparationState refreshedConnection run payRuns []
                                            finalizePreparationRun refreshedRun []

finalizePreparationRun ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    XeroTimesheetPreparationRun ->
    [XeroTimesheetRef] ->
    IO (XeroPreparationResult XeroTimesheetPreparationView)
finalizePreparationRun run remoteTimesheets =
    ensurePreparationDecisionProposals run >>= \case
        Left appError -> pure (Left appError)
        Right () ->
            refreshPreparationRunStatus run remoteTimesheets >>= \case
                Left appError -> pure (Left appError)
                Right _       -> loadXeroTimesheetPreparationView run.id

loadXeroTimesheetPreparationView ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Id XeroTimesheetPreparationRun ->
    IO (XeroPreparationResult XeroTimesheetPreparationView)
loadXeroTimesheetPreparationView runId = do
    fetchPreparationRunForCurrentVenue runId >>= \case
        Nothing -> pure (preparationFailure "Xero preparation run was not found for this venue.")
        Just run -> do
            connection <- fetch (Id run.xeroConnectionId :: Id XeroConnection)
            decisions <- fetchPreparationDecisions run
            let remoteTimesheets = remoteTimesheetsFromRun run
            preparationReadinessForRun run remoteTimesheets >>= \case
                Left appError -> pure (Left appError)
                Right readiness -> loadPreparationView run connection decisions readiness

loadPreparationView ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    XeroTimesheetPreparationRun ->
    XeroConnection ->
    [XeroTimesheetPreparationDecision] ->
    XeroTimesheetReadiness ->
    IO (XeroPreparationResult XeroTimesheetPreparationView)
loadPreparationView run connection decisions readiness = do
    let baseReadinessView = preparationReadinessView run readiness
        issueEntryIds =
            mapMaybe (.timesheetIssueTimesheetEntryId)
                (baseReadinessView.timesheetReadinessBlockers <> baseReadinessView.timesheetReadinessWarnings)
                |> List.nub
    issueEntries <- if null issueEntryIds
        then pure []
        else query @TimesheetEntry |> filterWhereIn (#id, map Id issueEntryIds) |> fetch
    let issueEntryById = Map.fromList [(unpackId entry.id, entry) | entry <- issueEntries]
        enrichIssue issue = case issue.timesheetIssueTimesheetEntryId >>= (`Map.lookup` issueEntryById) of
            Nothing -> issue
            Just entry -> issue
                { timesheetIssueExpectedActiveCalculationId = unpackId <$> entry.activePayCalculationId
                , timesheetIssueExpectedApprovalTimestamp = entry.approvedAt
                }
        readinessView = baseReadinessView
            { timesheetReadinessBlockers = map enrichIssue baseReadinessView.timesheetReadinessBlockers
            , timesheetReadinessWarnings = map enrichIssue baseReadinessView.timesheetReadinessWarnings
            }
    staffRows <- fetchCurrentVenueXeroStaffMappingRows (Just connection)
    periodOptions <- fetchCurrentVenueXeroTimesheetPeriodOptions (Just connection)
    xeroEmployees <- fetchCurrentVenueXeroEmployees (Just connection)
    xeroEarningsRates <- fetchCurrentVenueXeroEarningsRates (Just connection)
    fetchPreparationPayItemRequirements run connection xeroEarningsRates >>= \case
        Left appError -> pure (Left appError)
        Right payItemRequirementsState -> do
            let payItemRequirements = case payItemRequirementsState of
                    PayItemRequirementsAvailable values -> values
                    PayItemRequirementsBlocked _        -> []
                requirementsBlocked = case payItemRequirementsState of
                    PayItemRequirementsAvailable _ -> False
                    PayItemRequirementsBlocked _   -> True
            payrollCalendars <- fetchCurrentVenueXeroPayrollCalendars (Just connection)
            accountCodeOptions <- fetchCurrentVenueXeroPayItemAccountCodeOptions (Just connection)
            accountCodeSelection <- fetchCurrentVenueXeroPayItemAccountCodeSelection (Just connection)
            maybeSubmissionRun <-
                case run.xeroSubmissionRunId of
                    Nothing -> pure Nothing
                    Just submissionRunId -> Just <$> fetch (Id submissionRunId :: Id XeroSubmissionRun)
            let submissionPreviewRows = maybe [] (xeroTimesheetPreviewRowsFromJson xeroEmployees xeroEarningsRates . (.previewPayloadJson)) maybeSubmissionRun
                staffDecisionRows = map (preparationStaffRow decisions) staffRows
                payItemRows = map (preparationPayItemRow decisions) (filter activePayItemRequirement payItemRequirements)
                pendingDecisionCount = length (filter pendingManualPreparationDecision decisions)
                manualStaffDecisionCount = length (filter (.preparationStaffNeedsDecision) staffDecisionRows)
                postedBlocked = preparationRunPosted run
                proposedPayItemCount = length (filter ((== XeroPayItemRequirementStatusEnumProposed) . (.payItemRequirementStatus) . (.preparationPayItemRequirement)) payItemRows)
                pendingPayItemDecisionCount = length (filter pendingPayItemCreateDecision decisions)
                staffStepApproved = any staffStepApprovalApplied decisions
                canSubmit =
                    preparationRunHasPeriod run
                        && not requirementsBlocked
                        && connection.connectionStatus == "active"
                        && not postedBlocked
                        && pendingDecisionCount == 0
                        && pendingPayItemDecisionCount == 0
                        && manualStaffDecisionCount == 0
                        && readinessAllowsAutomaticPayItemSubmit readiness
                        && (proposedPayItemCount == 0 || not (null accountCodeOptions))
            pure $ preparationSuccess XeroTimesheetPreparationView
                { preparationRun = run
                , preparationState = xeroPreparationStateFromStatus run.status
                , preparationConnection = connection
                , preparationPeriodOption = periodOptionFromPreparationRun run
                , preparationPeriodOptions = periodOptions
                , preparationReadiness = readinessView
                , preparationPayrollCalendars = payrollCalendars
                , preparationStaffRows = staffDecisionRows
                , preparationEmployees = xeroEmployees
                , preparationPayItemRows = payItemRows
                , preparationPayItemAccountCodeOptions = accountCodeOptions
                , preparationPayItemAccountCodeSelection = accountCodeSelection
                , preparationPendingDecisionCount = pendingDecisionCount
                , preparationManualStaffDecisionCount = manualStaffDecisionCount
                , preparationStaffStepApproved = staffStepApproved
                , preparationPostedPayRunBlocked = postedBlocked
                , preparationCanSubmit = canSubmit
                , preparationPreviewRows = submissionPreviewRows
                , preparationSubmissionRun = maybeSubmissionRun
                }

approveXeroPreparationStaffStep ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Id XeroTimesheetPreparationRun ->
    IO (XeroPreparationResult XeroTimesheetPreparationView)
approveXeroPreparationStaffStep runId = do
    fetchPreparationRunForCurrentVenue runId >>= \case
        Nothing -> pure (preparationFailure "Xero preparation run was not found for this venue.")
        Just run -> do
            connection <- fetch (Id run.xeroConnectionId :: Id XeroConnection)
            decisions <- fetchPreparationDecisions run
            let pendingAutoMatches = filter isPendingStaffAutoMatch decisions
            autoMatchResults <- mapM (applyPendingAutoMatchDecision run connection) pendingAutoMatches
            case lefts autoMatchResults of
                message : _ -> pure (preparationFailure message)
                [] -> do
                    refreshedStaffRows <- fetchCurrentVenueXeroStaffMappingRows (Just connection)
                    let unmatchedRows = filter staffNeedsXeroDecision refreshedStaffRows
                    forM_ unmatchedRows (applyDefaultNotPaidDecision run connection)
                    remainingUnresolvedRows <-
                        filter staffNeedsXeroDecision
                            <$> fetchCurrentVenueXeroStaffMappingRows (Just connection)
                    if not (null remainingUnresolvedRows)
                        then pure (preparationFailure "Resolve staff matches before continuing.")
                        else do
                            _ <- applyPreparationDecision run Nothing StaffStepApproved Nothing Nothing Nothing
                            reloadAfterLocalDecision run remoteTimesheetsFromRun

applyDefaultNotPaidDecision ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    XeroTimesheetPreparationRun ->
    XeroConnection ->
    XeroStaffMappingRow ->
    IO ()
applyDefaultNotPaidDecision run connection row = do
    let staff = row.mappingRowStaff
    applyXeroStaffMappingSelection currentVenueId currentUser.id connection staff.id XeroEmployeeNotApplicable >>= \case
        Left _ -> pure ()
        Right _ -> do
            _ <- applyPreparationDecision run (Just staff) StaffNotPaid Nothing Nothing Nothing
            dismissPendingStaffAutoMatches run staff

applyPendingAutoMatchDecision ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    XeroTimesheetPreparationRun ->
    XeroConnection ->
    XeroTimesheetPreparationDecision ->
    IO (Either Text ())
applyPendingAutoMatchDecision run connection decision =
    case (decision.staffId, decision.xeroEmployeeId) of
        (Just staffUuid, Just employeeId) -> do
            staff <- fetch (Id staffUuid :: Id Staff)
            applyEmployeeMappingDecisionWithoutReload run connection staff StaffAutoMatch employeeId
        _ -> pure (Left "A proposed staff match is missing staff or Xero employee details.")

applyXeroPreparationStaffDecision ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Id XeroTimesheetPreparationRun ->
    Id Staff ->
    XeroPreparationStaffDecision ->
    IO (XeroPreparationResult XeroTimesheetPreparationView)
applyXeroPreparationStaffDecision runId staffId decision = do
    fetchPreparationRunForCurrentVenue runId >>= \case
        Nothing -> pure (preparationFailure "Xero preparation run was not found for this venue.")
        Just run -> do
            connection <- fetch (Id run.xeroConnectionId :: Id XeroConnection)
            maybeStaff <-
                query @Staff
                    |> filterWhere (#id, staffId)
                    |> filterWhere (#venueId, unpackId currentVenueId)
                    |> fetchOneOrNothing
            case maybeStaff of
                Nothing -> pure (preparationFailure "Choose a linked active staff member from the current venue.")
                Just staff | not (isLinkedActiveStaff staff) -> pure (preparationFailure "Choose a linked active staff member from the current venue.")
                Just staff ->
                    case decision of
                        MarkStaffNotPaidThroughXero ->
                            applyXeroStaffMappingSelection currentVenueId currentUser.id connection staff.id XeroEmployeeNotApplicable >>= \case
                                Left message -> pure (preparationFailure message)
                                Right _ -> do
                                    _ <- applyPreparationDecision run (Just staff) StaffNotPaid Nothing Nothing Nothing
                                    dismissPendingStaffAutoMatches run staff
                                    reloadAfterLocalDecision run remoteTimesheetsFromCurrentRun
                        SelectXeroEmployee employeeId -> do
                            pendingSuggestion <- fetchPendingStaffAutoMatch run staff
                            let employeeIdText = xeroEmployeeIdText employeeId
                                decisionKind =
                                    case pendingSuggestion >>= (.xeroEmployeeId) of
                                        Just suggestedEmployeeId | suggestedEmployeeId == employeeIdText -> StaffAutoMatch
                                        _ -> StaffManualMapping
                            applyEmployeeMappingDecision run connection staff decisionKind employeeIdText
    where
        remoteTimesheetsFromCurrentRun updatedRun = remoteTimesheetsFromRun updatedRun

ensurePreparationPayItemsReady ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    XeroTimesheetPreparationRun ->
    Maybe Text ->
    IO (XeroPreparationResult ())
ensurePreparationPayItemsReady run maybeAccountCode = do
    connection <- fetch (Id run.xeroConnectionId :: Id XeroConnection)
    xeroEarningsRates <- fetchCurrentVenueXeroEarningsRates (Just connection)
    requirementsResult <- fetchPreparationPayItemRequirements run connection xeroEarningsRates
    case requirementsResult of
        Left appError -> pure (Left appError)
        Right (PayItemRequirementsBlocked blocker) -> pure (preparationFailure (preparationPayItemRequirementsError blocker))
        Right (PayItemRequirementsAvailable requirements) ->
            ensureRequirementsReady connection requirements >>= \case
                Left message -> pure (preparationFailure message)
                Right () -> pure (preparationSuccess ())
  where
    ensureRequirementsReady connection requirements = do
        accountCodeOptions <- fetchCurrentVenueXeroPayItemAccountCodeOptions (Just connection)
        accountCodeSelection <- fetchCurrentVenueXeroPayItemAccountCodeSelection (Just connection)
        forM_ (Text.strip <$> maybeAccountCode) \accountCode ->
            when (not (Text.null accountCode)) do
                persistPreparationAccountCodeSelection connection accountCodeOptions accountCode
        latestSelection <- fetchCurrentVenueXeroPayItemAccountCodeSelection (Just connection)
        let selectedAccountCode = selectedXeroPayItemAccountCode accountCodeOptions latestSelection <|> selectedXeroPayItemAccountCode accountCodeOptions accountCodeSelection
            proposedRequirements = filter (\requirement -> xeroPayItemRequirementIsProposed requirement.payItemRequirementStatus && requirement.payItemRequirementIsActive) requirements
        case selectedAccountCode of
            Nothing
                | null proposedRequirements -> pure (Right ())
                | otherwise -> pure (Left "Choose a Xero account code before submitting; the missing managed pay items need one.")
            Just accountCode
                | null proposedRequirements -> pure (Right ())
                | otherwise ->
                    readXeroConfig >>= \case
                        Left message -> pure (Left message)
                        Right config ->
                            refreshXeroConnectionAccess config connection >>= \case
                                Left message -> pure (Left message)
                                Right (refreshedConnection, accessToken) -> do
                                    xeroClient <- currentXeroClient
                                    now <- getCurrentTime
                                    createProposedXeroPayItems xeroClient refreshedConnection accessToken now accountCode proposedRequirements >>= \case
                                        Left message -> pure (Left message)
                                        Right verification
                                            | verification.missingCount > 0 ->
                                                pure (Left (xeroPayItemVerificationFailureMessage verification))
                                            | otherwise -> do
                                                markPayItemCreateDecisionsApplied run proposedRequirements
                                                pure (Right ())

selectXeroTimesheetPreparationPeriod ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Id XeroTimesheetPreparationRun ->
    Text ->
    IO (XeroPreparationResult XeroTimesheetPreparationView)
selectXeroTimesheetPreparationPeriod runId selectedPeriodKey =
    fetchPreparationRunForCurrentVenue runId >>= \case
        Nothing -> pure (preparationFailure "Xero preparation run was not found for this venue.")
        Just run -> do
            connection <- fetch (Id run.xeroConnectionId :: Id XeroConnection)
            options <- fetchCurrentVenueXeroTimesheetPeriodOptions (Just connection)
            case List.find (\option -> option.periodOptionKey == Text.strip selectedPeriodKey) options of
                Nothing -> pure (preparationFailure "Choose a Xero pay period before preparing draft timesheets.")
                Just option | option.periodOptionBlocked ->
                    pure (preparationFailure (fromMaybe "This Xero pay period cannot be prepared." option.periodOptionBlockReason))
                Just option -> do
                    updatedRun <-
                        run
                            |> set #selectedPayrollCalendarId (Just option.periodOptionPayrollCalendarId)
                            |> set #selectedPayrollCalendarName (Just option.periodOptionPayrollCalendarName)
                            |> set #selectedPeriodKey (Just option.periodOptionKey)
                            |> set #payPeriodStart (Just option.periodOptionStart)
                            |> set #payPeriodEnd (Just option.periodOptionEnd)
                            |> set #paymentDate option.periodOptionPaymentDate
                            |> set #xeroPayRunId option.periodOptionXeroPayRunId
                            |> set #xeroPayRunStatus option.periodOptionXeroPayRunStatus
                            |> set #status Preparing
                            |> set #errorSummary Nothing
                            |> updateRecord
                    refreshXeroTimesheetPreparation updatedRun.id


approveXeroPreparationPayItemDecisions ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Id XeroTimesheetPreparationRun ->
    Maybe Text ->
    IO (XeroPreparationResult XeroTimesheetPreparationView)
approveXeroPreparationPayItemDecisions runId maybeAccountCode = do
    let accountCode = Text.strip (fromMaybe "" maybeAccountCode)
    if Text.null accountCode
        then pure (preparationFailure "Choose a Xero account code before continuing.")
        else saveXeroPreparationAccountCode runId accountCode

saveXeroPreparationAccountCode ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Id XeroTimesheetPreparationRun ->
    Text ->
    IO (XeroPreparationResult XeroTimesheetPreparationView)
saveXeroPreparationAccountCode runId accountCode =
    fetchPreparationRunForCurrentVenue runId >>= \case
        Nothing -> pure (preparationFailure "Xero preparation run was not found for this venue.")
        Just run -> do
            connection <- fetch (Id run.xeroConnectionId :: Id XeroConnection)
            accountCodeOptions <- fetchCurrentVenueXeroPayItemAccountCodeOptions (Just connection)
            case Text.strip accountCode of
                "" -> pure (preparationFailure "Choose a Xero account code.")
                selectedAccountCode
                    | selectedAccountCode `notElem` xeroPayItemAccountCodeOptionValues accountCodeOptions ->
                        pure (preparationFailure "Choose a synced Xero account code from the dropdown.")
                    | otherwise ->
                        ensurePreparationPayItemDecisionProposals run >>= \case
                            Left appError -> pure (Left appError)
                            Right (PayItemRequirementsBlocked blocker) -> pure (preparationFailure (preparationPayItemRequirementsError blocker))
                            Right (PayItemRequirementsAvailable proposedRequirements) -> do
                                persistPreparationAccountCodeSelection connection accountCodeOptions selectedAccountCode
                                markPayItemCreateDecisionsApplied run proposedRequirements
                                reloadAfterLocalDecision run remoteTimesheetsFromRun

submitXeroTimesheetPreparation ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Id XeroTimesheetPreparationRun ->
    Maybe Text ->
    IO (XeroPreparationResult XeroTimesheetPreparationView)
submitXeroTimesheetPreparation runId maybeAccountCode =
    loadXeroTimesheetPreparationView runId >>= \case
        Left appError -> pure (Left appError)
        Right (XeroPreparationOutcomeBlocked message) -> pure (preparationFailure message)
        Right (XeroPreparationOutcomeAvailable view)
            | not view.preparationCanSubmit ->
                pure (preparationFailure "Resolve Xero preparation blockers before submitting draft timesheets.")
            | otherwise ->
                ensurePreparationPayItemsReady view.preparationRun maybeAccountCode >>= \case
                    Left appError -> pure (Left appError)
                    Right (XeroPreparationOutcomeBlocked message) -> pure (preparationFailure message)
                    Right (XeroPreparationOutcomeAvailable ()) -> do
                        refreshedRun <- fetch view.preparationRun.id
                        let remoteTimesheets = remoteTimesheetsFromRun refreshedRun
                        case preparationReadinessRequest refreshedRun remoteTimesheets of
                            Left _ -> pure (preparationFailure "Choose a complete Xero pay period before submitting draft timesheets.")
                            Right readinessRequest ->
                                validateXeroTimesheetReadiness readinessRequest >>= \case
                                    Left appError -> pure (Left appError)
                                    Right readiness
                                        | not readiness.xeroTimesheetReady -> pure (preparationFailure (readinessErrorSummary readiness))
                                        | otherwise ->
                                            submitXeroDraftTimesheetsForPreparation currentUser.id refreshedRun.id readinessRequest >>= \case
                                                Left appError -> pure (Left appError)
                                                Right (XeroSubmissionBlocked message) -> pure (preparationFailure message)
                                                Right (XeroSubmissionSucceeded (XeroTimesheetReviewedStateChanged snapshot)) ->
                                                    pure (preparationFailure (reconciliationStateChangedMessage snapshot))
                                                Right (XeroSubmissionSucceeded (XeroTimesheetReviewedSubmissionCompleted submissionRun))
                                                    | submissionRun.status == XeroSubmissionRunStatusEnumBlocked ->
                                                        pure (preparationFailure (fromMaybe "Xero submission is blocked." submissionRun.errorSummary))
                                                    | otherwise -> do
                                                        completedAt <- getCurrentTime
                                                        _ <-
                                                            refreshedRun
                                                                |> set #status (if submissionRun.status == XeroSubmissionRunStatusEnumSubmitted then XeroTimesheetPreparationRunStatusEnumSubmitted else XeroTimesheetPreparationRunStatusEnumFailed)
                                                                |> set #xeroSubmissionRunId (Just (unpackId submissionRun.id))
                                                                |> set #previewPayloadJson submissionRun.previewPayloadJson
                                                                |> set #readinessSnapshotJson submissionRun.readinessSnapshotJson
                                                                |> set #errorSummary submissionRun.errorSummary
                                                                |> set #completedAt (Just completedAt)
                                                                |> updateRecord
                                                        loadXeroTimesheetPreparationView runId

reconciliationStateChangedMessage :: Aeson.Value -> Text
reconciliationStateChangedMessage snapshot =
    fromMaybe "Xero timesheet state changed during submission. Try again." do
        notices <- either (const Nothing) Just (reconciliationReviewNotices snapshot)
        notice <- listToMaybe notices
        pure notice.reconciliationNoticeMessage

fetchPreparationRunForCurrentVenue ::
    (?modelContext :: ModelContext, ?context :: ControllerContext) =>
    Id XeroTimesheetPreparationRun ->
    IO (Maybe XeroTimesheetPreparationRun)
fetchPreparationRunForCurrentVenue runId =
    query @XeroTimesheetPreparationRun
        |> filterWhere (#id, runId)
        |> filterWhere (#venueId, unpackId currentVenueId)
        |> fetchOneOrNothing

fetchPreparationPayItemRequirements ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    XeroTimesheetPreparationRun ->
    XeroConnection ->
    [XeroEarningsRate] ->
    IO (AppResult PayItemRequirementsState)
fetchPreparationPayItemRequirements run connection xeroEarningsRates =
    case selectedPreparationPeriod run of
        Left periodError -> pure (Right (PayItemRequirementsBlocked (PayItemRequirementsPeriodBlocked periodError)))
        Right period -> do
            periodOptions <- fetchCurrentVenueXeroTimesheetPeriodOptions (Just connection)
            if not (any (matchesSelectedPeriod period) periodOptions)
                then pure (Right (PayItemRequirementsBlocked (PayItemRequirementsPeriodBlocked PreparationPeriodNotAvailable)))
                else fetchForPeriod period
  where
    fetchForPeriod period = do
        skippedStaffIds <- fetchPreparationNotPaidStaffIds connection
        fetchPeriodXeroLocalEarningsBuckets
                (Id run.venueId)
                period.selectedPreparationPeriodStart
                period.selectedPreparationPeriodEnd
                skippedStaffIds >>= \case
                    Left appError -> pure (Left appError)
                    Right (XeroBucketsBlocked problems) ->
                        pure (Right (PayItemRequirementsBlocked (PayItemRequirementsBucketsBlocked problems)))
                    Right (XeroBucketsAvailable availableBuckets)
                        | null availableBuckets.xeroAvailableBucketValues ->
                            pure (Right (PayItemRequirementsBlocked PayItemRequirementsNoApprovedBuckets))
                    Right (XeroBucketsAvailable availableBuckets) -> do
                        let buckets = availableBuckets.xeroAvailableBucketValues
                        requirements <- fetchCurrentVenueXeroPayItemRequirements (Just connection) xeroEarningsRates
                        let bucketKeys = map (.localBucketKey) buckets
                        pure $ Right $ PayItemRequirementsAvailable
                            (filter (\requirement -> requirement.payItemRequirementKey `elem` bucketKeys) requirements)
    matchesSelectedPeriod period option =
        not option.periodOptionBlocked
            && option.periodOptionKey == period.selectedPreparationPeriodKey
            && option.periodOptionPayrollCalendarId == period.selectedPreparationCalendarId
            && option.periodOptionStart == period.selectedPreparationPeriodStart
            && option.periodOptionEnd == period.selectedPreparationPeriodEnd

preparationPayItemRequirementsError :: PayItemRequirementsBlocker -> Text
preparationPayItemRequirementsError = \case
    PayItemRequirementsPeriodBlocked _ -> "Choose a complete Xero pay period before preparing managed pay items."
    PayItemRequirementsBucketsBlocked _ -> "Cannot derive managed pay items until the approved pay-ledger blockers are corrected."
    PayItemRequirementsNoApprovedBuckets -> "There are no approved pay buckets in the selected Xero period."

fetchPreparationNotPaidStaffIds ::
    (?modelContext :: ModelContext) =>
    XeroConnection ->
    IO [UUID]
fetchPreparationNotPaidStaffIds connection = do
    mappings <-
        query @XeroStaffMapping
            |> filterWhere (#xeroConnectionId, unpackId connection.id)
            |> filterWhere (#mappingStatus, NotApplicable)
            |> fetch
    pure (map (.staffId) mappings)

ensurePreparationDecisionProposals ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    XeroTimesheetPreparationRun ->
    IO (AppResult ())
ensurePreparationDecisionProposals run =
    ensurePreparationPayItemDecisionProposals run >>= \case
        Left appError -> pure (Left appError)
        Right _ -> do
            connection <- fetch (Id run.xeroConnectionId :: Id XeroConnection)
            staffRows <- fetchCurrentVenueXeroStaffMappingRows (Just connection)
            forM_ staffRows \row ->
                case row.mappingRowSuggestedEmployee of
                    Just employee | staffNeedsXeroDecision row ->
                        void $
                            ensurePendingPreparationDecision
                                run
                                (Just row.mappingRowStaff)
                                StaffAutoMatch
                                (Just employee.xeroEmployeeId)
                                (Just employee.displayName)
                                Nothing
                                (Aeson.object ["suggestedEmployeeId" Aeson..= employee.xeroEmployeeId, "suggestedEmployeeName" Aeson..= employee.displayName])
                    _ -> pure ()
            pure (Right ())

ensurePreparationPayItemDecisionProposals ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    XeroTimesheetPreparationRun ->
    IO (AppResult PayItemRequirementsState)
ensurePreparationPayItemDecisionProposals run = do
    connection <- fetch (Id run.xeroConnectionId :: Id XeroConnection)
    xeroEarningsRates <- fetchCurrentVenueXeroEarningsRates (Just connection)
    fetchPreparationPayItemRequirements run connection xeroEarningsRates >>= \case
        Left appError -> pure (Left appError)
        Right blocked@(PayItemRequirementsBlocked _) -> pure (Right blocked)
        Right (PayItemRequirementsAvailable requirements) -> do
            let proposedRequirements = filter (\requirement -> xeroPayItemRequirementIsProposed requirement.payItemRequirementStatus && requirement.payItemRequirementIsActive) requirements
            forM_ proposedRequirements \requirement ->
                void $
                    ensurePendingPreparationDecision
                        run
                        Nothing
                        PayItemCreate
                        Nothing
                        Nothing
                        (Just requirement.payItemRequirementKey)
                        (Aeson.object ["requirementName" Aeson..= requirement.payItemRequirementName])
            pure (Right (PayItemRequirementsAvailable proposedRequirements))

ensurePendingPreparationDecision ::
    (?modelContext :: ModelContext) =>
    XeroTimesheetPreparationRun ->
    Maybe Staff ->
    XeroTimesheetPreparationDecisionKindEnum ->
    Maybe Text ->
    Maybe Text ->
    Maybe Text ->
    Aeson.Value ->
    IO XeroTimesheetPreparationDecision
ensurePendingPreparationDecision run maybeStaff decisionKind maybeEmployeeId maybeEmployeeName maybeLocalBucketKey payload = do
    existing <-
        query @XeroTimesheetPreparationDecision
            |> filterWhere (#xeroTimesheetPreparationRunId, unpackId run.id)
            |> filterWhere (#decisionKind, decisionKind)
            |> filterWhere (#staffId, unpackId . (.id) <$> maybeStaff)
            |> filterWhere (#localBucketKey, maybeLocalBucketKey)
            |> filterWhereIn (#decisionStatus, [XeroTimesheetPreparationDecisionStatusEnumPending, Applied])
            |> fetchOneOrNothing
    case existing of
        Just decision -> pure decision
        Nothing ->
            newRecord @XeroTimesheetPreparationDecision
                |> set #xeroTimesheetPreparationRunId (unpackId run.id)
                |> set #venueId run.venueId
                |> set #xeroConnectionId run.xeroConnectionId
                |> set #staffId (unpackId . (.id) <$> maybeStaff)
                |> set #decisionKind decisionKind
                |> set #decisionStatus XeroTimesheetPreparationDecisionStatusEnumPending
                |> set #xeroEmployeeId maybeEmployeeId
                |> set #xeroEmployeeName maybeEmployeeName
                |> set #localBucketKey maybeLocalBucketKey
                |> set #payloadJson payload
                |> createRecord

applyPreparationDecision ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    XeroTimesheetPreparationRun ->
    Maybe Staff ->
    XeroTimesheetPreparationDecisionKindEnum ->
    Maybe Text ->
    Maybe Text ->
    Maybe Text ->
    IO XeroTimesheetPreparationDecision
applyPreparationDecision run maybeStaff decisionKind maybeEmployeeId maybeEmployeeName maybeLocalBucketKey = do
    decision <-
        ensurePendingPreparationDecision
            run
            maybeStaff
            decisionKind
            maybeEmployeeId
            maybeEmployeeName
            maybeLocalBucketKey
            Aeson.Null
    now <- getCurrentTime
    decision
        |> set #decisionStatus Applied
        |> set #xeroEmployeeId maybeEmployeeId
        |> set #xeroEmployeeName maybeEmployeeName
        |> set #decidedByUserId (Just (unpackId currentUser.id))
        |> set #decidedAt (Just now)
        |> updateRecord

applyEmployeeMappingDecision ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    XeroTimesheetPreparationRun ->
    XeroConnection ->
    Staff ->
    XeroTimesheetPreparationDecisionKindEnum ->
    Text ->
    IO (XeroPreparationResult XeroTimesheetPreparationView)
applyEmployeeMappingDecision run connection staff decisionKind employeeId = do
    applyEmployeeMappingDecisionWithoutReload run connection staff decisionKind employeeId >>= \case
        Left message -> pure (preparationFailure message)
        Right () -> reloadAfterLocalDecision run remoteTimesheetsFromRun

applyEmployeeMappingDecisionWithoutReload ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    XeroTimesheetPreparationRun ->
    XeroConnection ->
    Staff ->
    XeroTimesheetPreparationDecisionKindEnum ->
    Text ->
    IO (Either Text ())
applyEmployeeMappingDecisionWithoutReload run connection staff decisionKind employeeId =
    case parseXeroEmployeeId employeeId of
        Left _ -> pure (Left "Choose a synced Xero employee from this venue.")
        Right selectedEmployeeId ->
            applyXeroStaffMappingSelection currentVenueId currentUser.id connection staff.id (XeroEmployeeSelected selectedEmployeeId) >>= \case
                Left message -> pure (Left message)
                Right mapping -> do
                    _ <- applyPreparationDecision run (Just staff) decisionKind mapping.xeroEmployeeId mapping.xeroEmployeeName Nothing
                    dismissPendingStaffAutoMatches run staff
                    pure (Right ())

dismissPendingStaffAutoMatches ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    XeroTimesheetPreparationRun ->
    Staff ->
    IO ()
dismissPendingStaffAutoMatches run staff = do
    pending <-
        query @XeroTimesheetPreparationDecision
            |> filterWhere (#xeroTimesheetPreparationRunId, unpackId run.id)
            |> filterWhere (#staffId, Just (unpackId staff.id))
            |> filterWhere (#decisionKind, StaffAutoMatch)
            |> filterWhere (#decisionStatus, XeroTimesheetPreparationDecisionStatusEnumPending)
            |> fetch
    now <- getCurrentTime
    forM_ pending \decision ->
        decision
            |> set #decisionStatus Dismissed
            |> set #decidedByUserId (Just (unpackId currentUser.id))
            |> set #decidedAt (Just now)
            |> updateRecord
            |> void

fetchPendingStaffAutoMatch ::
    (?modelContext :: ModelContext) =>
    XeroTimesheetPreparationRun ->
    Staff ->
    IO (Maybe XeroTimesheetPreparationDecision)
fetchPendingStaffAutoMatch run staff =
    query @XeroTimesheetPreparationDecision
        |> filterWhere (#xeroTimesheetPreparationRunId, unpackId run.id)
        |> filterWhere (#staffId, Just (unpackId staff.id))
        |> filterWhere (#decisionKind, StaffAutoMatch)
        |> filterWhere (#decisionStatus, XeroTimesheetPreparationDecisionStatusEnumPending)
        |> fetchOneOrNothing

reloadAfterLocalDecision ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    XeroTimesheetPreparationRun ->
    (XeroTimesheetPreparationRun -> [XeroTimesheetRef]) ->
    IO (XeroPreparationResult XeroTimesheetPreparationView)
reloadAfterLocalDecision run remoteTimesheetReader = do
    latestRun <- fetch run.id
    refreshPreparationRunStatus latestRun (remoteTimesheetReader latestRun) >>= \case
        Left appError -> pure (Left appError)
        Right _       -> loadXeroTimesheetPreparationView latestRun.id

persistPreparationAccountCodeSelection ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    XeroConnection ->
    [XeroPayItemAccountCodeOption] ->
    Text ->
    IO ()
persistPreparationAccountCodeSelection connection accountCodeOptions accountCode =
    when (accountCode `elem` xeroPayItemAccountCodeOptionValues accountCodeOptions) do
        now <- getCurrentTime
        existingSelection <-
            query @XeroPayItemAccountCodeSelection
                |> filterWhere (#xeroConnectionId, unpackId connection.id)
                |> fetchOneOrNothing
        let prepared record =
                record
                    |> set #venueId (unpackId currentVenueId)
                    |> set #xeroConnectionId (unpackId connection.id)
                    |> set #accountCode (Just accountCode)
                    |> set #selectionStatus XeroPayItemAccountCodeSelectionStatusEnumVerified
                    |> set #lastVerifiedAt (Just now)
                    |> set #updatedByUserId (Just (unpackId currentUser.id))
        case existingSelection of
            Just existing -> prepared existing |> updateRecord |> void
            Nothing ->
                prepared (newRecord @XeroPayItemAccountCodeSelection)
                    |> set #createdByUserId (Just (unpackId currentUser.id))
                    |> createRecord
                    |> void

markPayItemCreateDecisionsApplied ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    XeroTimesheetPreparationRun ->
    [XeroPayItemRequirement] ->
    IO ()
markPayItemCreateDecisionsApplied run requirements = do
    let requirementKeys = map (.payItemRequirementKey) requirements
    decisions <- do
        pendingDecisions <-
            query @XeroTimesheetPreparationDecision
                |> filterWhere (#xeroTimesheetPreparationRunId, unpackId run.id)
                |> filterWhere (#decisionKind, PayItemCreate)
                |> filterWhere (#decisionStatus, XeroTimesheetPreparationDecisionStatusEnumPending)
                |> fetch
        pure $ if null requirementKeys
            then pendingDecisions
            else filter (\decision -> decision.localBucketKey `elem` map Just requirementKeys) pendingDecisions
    now <- getCurrentTime
    forM_ decisions \decision ->
        decision
            |> set #decisionStatus Applied
            |> set #decidedByUserId (Just (unpackId currentUser.id))
            |> set #decidedAt (Just now)
            |> updateRecord
            |> void

persistRemotePreparationState ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    XeroConnection ->
    XeroTimesheetPreparationRun ->
    [XeroPayRunRef] ->
    [XeroTimesheetRef] ->
    IO XeroTimesheetPreparationRun
persistRemotePreparationState connection run payRuns remoteTimesheets = do
    now <- getCurrentTime
    withTransaction do
        mapM_ (upsertXeroPayRun connection now) payRuns
        let selectedPayRun = findSelectedPayRun run payRuns
        run
            |> set #connectionSnapshotJson (xeroConnectionSnapshotJson connection)
            |> set #remotePayRunsJson (payRunsSnapshotJson payRuns)
            |> set #remoteTimesheetsJson (duplicateCheckSnapshotJson remoteTimesheets)
            |> set #paymentDate ((selectedPayRun >>= (.xeroPayRunPaymentDate)) <|> run.paymentDate)
            |> set #xeroPayRunId ((.xeroPayRunId) <$> selectedPayRun)
            |> set #xeroPayRunStatus (selectedPayRun >>= (.xeroPayRunStatus))
            |> updateRecord
