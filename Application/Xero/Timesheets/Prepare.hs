module Application.Xero.Timesheets.Prepare
    ( XeroPreparationStaffDecision (..)
    , applyXeroPreparationStaffDecision
    , approveXeroPreparationPayItemDecisions
    , approveXeroPreparationStaffStep
    , loadXeroTimesheetPreparationView
    , previewXeroTimesheetPreparation
    , refreshXeroTimesheetPreparation
    , reviewXeroTimesheetPreparationSubmission
    , selectXeroTimesheetPreparationPeriod
    , startXeroTimesheetPreparation
    , submitXeroTimesheetPreparation
    ) where

import Application.Helper.Audit (recordCurrentUserAuditEvent)
import Application.Helper.ControllerContext (currentVenueId)
import Application.Helper.Staff (isLinkedActiveStaff)
import Application.Helper.Xero
import Application.Helper.XeroAdminTypes
import Application.Helper.XeroTimesheetReadiness
import Application.VenueTime.Model (timesheetEntryPaidElapsedSeconds)
import Application.WageEngine (WageCalculation (..))
import Application.WagePublication (PublishedEarningsLine (..),
                                    datedEarningsComponents,
                                    derivePublishedEarnings)
import Application.Xero.Admin.PayItems
import Application.Xero.Admin.ReadModel
import Application.Xero.Admin.ReferenceData
import Application.Xero.Connection
import Application.Xero.ReferenceDemand (fetchXeroMissingReferenceDemand)
import Application.Xero.ReferenceTrust
import Application.Xero.ReferenceTrust.ReadModel (XeroReferenceTrustState (..))
import Application.Xero.ReferenceTrust.Service
import Application.Xero.Timesheets.Buckets
import Application.Xero.Timesheets.Prepare.Helpers
import Application.Xero.Timesheets.Preview
import Application.Xero.Timesheets.ReconciliationReview
import Application.Xero.Timesheets.Submission
import Application.Xero.WorkflowState (xeroPayItemRequirementIsProposed,
                                       xeroStaffMappingIsVerified)
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Types as AesonTypes
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import Data.Scientific (Scientific)
import qualified Data.Scientific as Scientific
import qualified Data.Text as Text
import Data.Time.Calendar (Day)
import Generated.Types
import IHP.ControllerPrelude

data XeroPreparationStaffDecision
    = SelectXeroEmployee !Text
    | MarkStaffNotPaidThroughXero
    deriving (Eq, Show)

startXeroTimesheetPreparation ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    IO (Either Text XeroTimesheetPreparationView)
startXeroTimesheetPreparation = do
    maybeConnection <- fetchCurrentVenueXeroConnection
    case maybeConnection of
        Nothing -> pure (Left "Connect Xero before preparing draft timesheets.")
        Just connection ->
            refreshCurrentVenueXeroReferenceDataForPreparation connection >>= \case
                Left message -> pure (Left message)
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
                    ensurePreparationDecisionProposals run
                    _ <- refreshPreparationRunStatus run []
                    loadXeroTimesheetPreparationView run.id

refreshCurrentVenueXeroReferenceDataForPreparation ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    XeroConnection ->
    IO (Either Text XeroConnection)
refreshCurrentVenueXeroReferenceDataForPreparation connection = do
    now <- getCurrentTime
    missingReferenceDemand <- fetchXeroMissingReferenceDemand connection
    trustState <- requestTrustedXeroReferenceData now (Just currentUser.id) connection missingReferenceDemand
    pure case trustState.trustDecision of
        UseTrustedXeroReferenceSnapshot -> Right connection
        StartOrJoinXeroReferenceSync -> Left "Xero payroll reference data is starting in the background."
        WaitForTrustedXeroReferenceSnapshot _ -> Left "Xero payroll reference data is syncing in the background."
        ReconnectXeroForReferenceData -> Left "Reconnect Xero before preparing draft timesheets."
        BlockStaleXeroReferenceData _ -> Left "Xero reference data is out of date and could not be refreshed. Contact support before preparing draft timesheets."

refreshXeroTimesheetPreparation ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Id XeroTimesheetPreparationRun ->
    IO (Either Text XeroTimesheetPreparationView)
refreshXeroTimesheetPreparation runId = do
    fetchPreparationRunForCurrentVenue runId >>= \case
        Nothing -> pure (Left "Xero preparation run was not found for this venue.")
        Just run -> do
            connection <- fetch (Id run.xeroConnectionId :: Id XeroConnection)
            if not (preparationRunHasPeriod run)
                then do
                    ensurePreparationDecisionProposals run
                    _ <- refreshPreparationRunStatus run []
                    loadXeroTimesheetPreparationView runId
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
                            refreshXeroConnectionAccessWithoutBroadcast config connection >>= \case
                                Left message -> do
                                    _ <-
                                        run
                                            |> set #status NeedsReconnect
                                            |> set #errorSummary (Just message)
                                            |> updateRecord
                                    loadXeroTimesheetPreparationView runId
                                Right (refreshedConnection, accessToken) -> do
                                    xeroClient <- currentXeroClient
                                    payRunsResult <- fetchXeroPayRunsForPreparation xeroClient accessToken refreshedConnection.tenantId run
                                    remoteTimesheetsResult <- fetchRemoteTimesheetsForDuplicateCheck xeroClient accessToken refreshedConnection.tenantId
                                    case (payRunsResult, remoteTimesheetsResult) of
                                        (Left message, _) -> do
                                            _ <- markPreparationFailed run message
                                            loadXeroTimesheetPreparationView runId
                                        (_, Left message) -> do
                                            _ <- markPreparationFailed run message
                                            loadXeroTimesheetPreparationView runId
                                        (Right payRuns, Right remoteTimesheets) -> do
                                            refreshedRun <- persistRemotePreparationState refreshedConnection run payRuns remoteTimesheets
                                            ensurePreparationDecisionProposals refreshedRun
                                            _ <- refreshPreparationRunStatus refreshedRun remoteTimesheets
                                            loadXeroTimesheetPreparationView runId

loadXeroTimesheetPreparationView ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Id XeroTimesheetPreparationRun ->
    IO (Either Text XeroTimesheetPreparationView)
loadXeroTimesheetPreparationView runId = do
    fetchPreparationRunForCurrentVenue runId >>= \case
        Nothing -> pure (Left "Xero preparation run was not found for this venue.")
        Just run -> do
            connection <- fetch (Id run.xeroConnectionId :: Id XeroConnection)
            decisions <- fetchPreparationDecisions run
            let remoteTimesheets = remoteTimesheetsFromRun run
            readiness <- preparationReadinessForRun run remoteTimesheets
            let readinessView = preparationReadinessView run readiness
            staffRows <- fetchCurrentVenueXeroStaffMappingRows (Just connection)
            reviewRows <-
                if preparationRunHasPeriod run
                    then fetchPreparationReviewRows (preparationReadinessRequest run remoteTimesheets) connection staffRows
                    else pure []
            periodOptions <- fetchCurrentVenueXeroTimesheetPeriodOptions (Just connection)
            xeroEmployees <- fetchCurrentVenueXeroEmployees (Just connection)
            xeroEarningsRates <- fetchCurrentVenueXeroEarningsRates (Just connection)
            payItemRequirements <- fetchPreparationPayItemRequirements run connection xeroEarningsRates
            payrollCalendars <- fetchCurrentVenueXeroPayrollCalendars (Just connection)
            accountCodeOptions <- fetchCurrentVenueXeroPayItemAccountCodeOptions (Just connection)
            accountCodeSelection <- fetchCurrentVenueXeroPayItemAccountCodeSelection (Just connection)
            maybeSubmissionRun <-
                case run.xeroSubmissionRunId of
                    Nothing -> pure Nothing
                    Just submissionRunId -> Just <$> fetch (Id submissionRunId :: Id XeroSubmissionRun)
            let submissionPreviewRows =
                    maybe
                        []
                        (xeroTimesheetPreviewRowsFromJson xeroEmployees xeroEarningsRates . (.previewPayloadJson))
                        maybeSubmissionRun
                staffDecisionRows = map (preparationStaffRow decisions) staffRows
                payItemRows = map (preparationPayItemRow decisions) (filter activePayItemRequirement payItemRequirements)
                pendingDecisionCount = length (filter pendingManualPreparationDecision decisions)
                manualStaffDecisionCount = length (filter (.preparationStaffNeedsDecision) staffDecisionRows)
                postedBlocked = preparationRunPosted run
                proposedPayItemCount = length (filter ((== XeroPayItemRequirementStatusEnumProposed) . (.payItemRequirementStatus) . (.preparationPayItemRequirement)) payItemRows)
                pendingPayItemDecisionCount = length (filter pendingPayItemCreateDecision decisions)
                staffStepApproved = any staffStepApprovalApplied decisions
                hasSelectedPeriod = preparationRunHasPeriod run
                canPreview =
                    hasSelectedPeriod
                        && connection.connectionStatus == "active"
                        && not postedBlocked
                        && pendingDecisionCount == 0
                        && manualStaffDecisionCount == 0
                        && readiness.xeroTimesheetReady
                canSubmit =
                    hasSelectedPeriod
                        && connection.connectionStatus == "active"
                        && not postedBlocked
                        && pendingDecisionCount == 0
                        && pendingPayItemDecisionCount == 0
                        && manualStaffDecisionCount == 0
                        && readinessAllowsAutomaticPayItemSubmit readiness
                        && (proposedPayItemCount == 0 || not (null accountCodeOptions))
                reconciliationReviewed = reconciliationReviewSnapshotIsConfirmed run.proposedActionsJson
                reconciliationNotices =
                    either (const []) (map reconciliationNoticeView) (reconciliationReviewNotices run.proposedActionsJson)
                reconciliationCanSubmit =
                    reconciliationReviewed
                        && either (const False) (\value -> value) (reconciliationReviewAllowsSubmission run.proposedActionsJson)
            pure $
                Right
                    XeroTimesheetPreparationView
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
                        , preparationCanPreview = canPreview
                        , preparationCanSubmit = canSubmit
                        , preparationReconciliationReviewed = reconciliationReviewed
                        , preparationReconciliationCanSubmit = reconciliationCanSubmit
                        , preparationReconciliationNotices = reconciliationNotices
                        , preparationReviewRows = reviewRows
                        , preparationPreviewRows = submissionPreviewRows
                        , preparationSubmissionRun = maybeSubmissionRun
                        }

reconciliationNoticeView :: XeroTimesheetReconciliationNotice -> XeroTimesheetIssueView
reconciliationNoticeView notice =
    XeroTimesheetIssueView
        { timesheetIssueCode = "xero_reconciliation"
        , timesheetIssueSeverity = case notice.reconciliationNoticeSeverity of
            ReconciliationWarning -> "warning"
            ReconciliationBlocker -> "blocker"
        , timesheetIssueMessage = notice.reconciliationNoticeMessage
        , timesheetIssueHint = Nothing
        }

approveXeroPreparationStaffStep ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Id XeroTimesheetPreparationRun ->
    IO (Either Text XeroTimesheetPreparationView)
approveXeroPreparationStaffStep runId = do
    fetchPreparationRunForCurrentVenue runId >>= \case
        Nothing -> pure (Left "Xero preparation run was not found for this venue.")
        Just run -> do
            connection <- fetch (Id run.xeroConnectionId :: Id XeroConnection)
            decisions <- fetchPreparationDecisions run
            let pendingAutoMatches = filter isPendingStaffAutoMatch decisions
            autoMatchResults <- mapM (applyPendingAutoMatchDecision run connection) pendingAutoMatches
            case lefts autoMatchResults of
                message : _ -> pure (Left message)
                [] -> do
                    refreshedStaffRows <- fetchCurrentVenueXeroStaffMappingRows (Just connection)
                    let unresolvedRows = filter staffNeedsXeroDecision refreshedStaffRows
                    if not (null unresolvedRows)
                        then pure (Left "Resolve staff matches before continuing.")
                        else do
                            _ <- applyPreparationDecision run Nothing StaffStepApproved Nothing Nothing Nothing
                            reloadAfterLocalDecision run remoteTimesheetsFromRun

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
    IO (Either Text XeroTimesheetPreparationView)
applyXeroPreparationStaffDecision runId staffId decision = do
    fetchPreparationRunForCurrentVenue runId >>= \case
        Nothing -> pure (Left "Xero preparation run was not found for this venue.")
        Just run -> do
            connection <- fetch (Id run.xeroConnectionId :: Id XeroConnection)
            maybeStaff <-
                query @Staff
                    |> filterWhere (#id, staffId)
                    |> filterWhere (#venueId, unpackId currentVenueId)
                    |> fetchOneOrNothing
            case maybeStaff of
                Nothing -> pure (Left "Choose a linked active staff member from the current venue.")
                Just staff | not (isLinkedActiveStaff staff) -> pure (Left "Choose a linked active staff member from the current venue.")
                Just staff ->
                    case decision of
                        MarkStaffNotPaidThroughXero -> do
                            _ <- persistPreparationStaffMapping connection staff NotApplicable Nothing
                            _ <- applyPreparationDecision run (Just staff) StaffNotPaid Nothing Nothing Nothing
                            dismissPendingStaffAutoMatches run staff
                            reloadAfterLocalDecision run remoteTimesheetsFromCurrentRun
                        SelectXeroEmployee employeeId -> do
                            pendingSuggestion <- fetchPendingStaffAutoMatch run staff
                            let decisionKind =
                                    case pendingSuggestion >>= (.xeroEmployeeId) of
                                        Just suggestedEmployeeId | suggestedEmployeeId == employeeId -> StaffAutoMatch
                                        _ -> StaffManualMapping
                            applyEmployeeMappingDecision run connection staff decisionKind employeeId
    where
        remoteTimesheetsFromCurrentRun updatedRun = remoteTimesheetsFromRun updatedRun

ensurePreparationPayItemsReady ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    XeroTimesheetPreparationRun ->
    Maybe Text ->
    IO (Either Text ())
ensurePreparationPayItemsReady run maybeAccountCode = do
    connection <- fetch (Id run.xeroConnectionId :: Id XeroConnection)
    xeroEarningsRates <- fetchCurrentVenueXeroEarningsRates (Just connection)
    requirements <- fetchPreparationPayItemRequirements run connection xeroEarningsRates
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
                        refreshXeroConnectionAccessWithoutBroadcast config connection >>= \case
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
    IO (Either Text XeroTimesheetPreparationView)
selectXeroTimesheetPreparationPeriod runId selectedPeriodKey =
    fetchPreparationRunForCurrentVenue runId >>= \case
        Nothing -> pure (Left "Xero preparation run was not found for this venue.")
        Just run -> do
            connection <- fetch (Id run.xeroConnectionId :: Id XeroConnection)
            options <- fetchCurrentVenueXeroTimesheetPeriodOptions (Just connection)
            case List.find (\option -> option.periodOptionKey == Text.strip selectedPeriodKey) options of
                Nothing -> pure (Left "Choose a Xero pay period before preparing draft timesheets.")
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
    IO (Either Text XeroTimesheetPreparationView)
approveXeroPreparationPayItemDecisions runId maybeAccountCode = do
    let accountCode = Text.strip (fromMaybe "" maybeAccountCode)
    if Text.null accountCode
        then pure (Left "Choose a Xero account code before continuing.")
        else saveXeroPreparationAccountCode runId accountCode

saveXeroPreparationAccountCode ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Id XeroTimesheetPreparationRun ->
    Text ->
    IO (Either Text XeroTimesheetPreparationView)
saveXeroPreparationAccountCode runId accountCode =
    fetchPreparationRunForCurrentVenue runId >>= \case
        Nothing -> pure (Left "Xero preparation run was not found for this venue.")
        Just run -> do
            connection <- fetch (Id run.xeroConnectionId :: Id XeroConnection)
            accountCodeOptions <- fetchCurrentVenueXeroPayItemAccountCodeOptions (Just connection)
            case Text.strip accountCode of
                "" -> pure (Left "Choose a Xero account code.")
                selectedAccountCode
                    | selectedAccountCode `notElem` xeroPayItemAccountCodeOptionValues accountCodeOptions ->
                        pure (Left "Choose a synced Xero account code from the dropdown.")
                    | otherwise -> do
                        persistPreparationAccountCodeSelection connection accountCodeOptions selectedAccountCode
                        proposedRequirements <- ensurePreparationPayItemDecisionProposals run
                        markPayItemCreateDecisionsApplied run proposedRequirements
                        reloadAfterLocalDecision run remoteTimesheetsFromRun

previewXeroTimesheetPreparation ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Id XeroTimesheetPreparationRun ->
    IO (Either Text XeroTimesheetPreparationView)
previewXeroTimesheetPreparation runId =
    loadXeroTimesheetPreparationView runId >>= \case
        Left message -> pure (Left message)
        Right view
            | not view.preparationCanPreview ->
                pure (Left "Resolve Xero preparation blockers before previewing draft timesheets.")
            | otherwise -> do
                let run = view.preparationRun
                    remoteTimesheets = remoteTimesheetsFromRun run
                    readinessRequest = preparationReadinessRequest run remoteTimesheets
                readiness <- validateXeroTimesheetReadiness readinessRequest
                createPersistedXeroTimesheetPreparationPreview currentUser.id run.id readinessRequest readiness run.remoteTimesheetsJson >>= \case
                    Left message -> pure (Left message)
                    Right submissionRun -> do
                        _ <-
                            run
                                |> set #status XeroTimesheetPreparationRunStatusEnumPreviewed
                                |> set #xeroSubmissionRunId (Just (unpackId submissionRun.id))
                                |> set #readinessSnapshotJson (xeroReadinessSnapshotJson readiness)
                                |> set #previewPayloadJson submissionRun.previewPayloadJson
                                |> set #errorSummary Nothing
                                |> updateRecord
                        loadXeroTimesheetPreparationView runId

reviewXeroTimesheetPreparationSubmission ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Id XeroTimesheetPreparationRun ->
    IO (Either Text XeroTimesheetPreparationView)
reviewXeroTimesheetPreparationSubmission runId =
    loadXeroTimesheetPreparationView runId >>= \case
        Left message -> pure (Left message)
        Right view
            | not view.preparationCanSubmit ->
                pure (Left "Resolve Xero preparation blockers before reviewing draft timesheets.")
            | otherwise -> do
                let run = view.preparationRun
                    readinessRequest = preparationReadinessRequest run (remoteTimesheetsFromRun run)
                reviewXeroDraftTimesheets readinessRequest >>= \case
                    Left message -> pure (Left message)
                    Right snapshot -> do
                        _ <-
                            run
                                |> set #proposedActionsJson snapshot
                                |> set #errorSummary Nothing
                                |> updateRecord
                        loadXeroTimesheetPreparationView runId

submitXeroTimesheetPreparation ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Id XeroTimesheetPreparationRun ->
    Maybe Text ->
    IO (Either Text XeroTimesheetPreparationView)
submitXeroTimesheetPreparation runId maybeAccountCode =
    loadXeroTimesheetPreparationView runId >>= \case
        Left message -> pure (Left message)
        Right view
            | not view.preparationCanSubmit ->
                pure (Left "Resolve Xero preparation blockers before submitting draft timesheets.")
            | not view.preparationReconciliationReviewed ->
                pure (Left "Review the latest Xero reconciliation outcome before submitting draft timesheets.")
            | not view.preparationReconciliationCanSubmit ->
                pure (Left "Resolve the Xero reconciliation blockers before submitting draft timesheets.")
            | otherwise ->
                ensurePreparationPayItemsReady view.preparationRun maybeAccountCode >>= \case
                    Left message -> pure (Left message)
                    Right () -> do
                        refreshedRun <- fetch view.preparationRun.id
                        let remoteTimesheets = remoteTimesheetsFromRun refreshedRun
                            readinessRequest = preparationReadinessRequest refreshedRun remoteTimesheets
                        readiness <- validateXeroTimesheetReadiness readinessRequest
                        if not readiness.xeroTimesheetReady
                            then pure (Left (readinessErrorSummary readiness))
                            else
                                submitReviewedXeroDraftTimesheetsForPreparation currentUser.id refreshedRun.id refreshedRun.proposedActionsJson readinessRequest >>= \case
                                    Left message -> pure (Left message)
                                    Right (XeroTimesheetReviewedStateChanged freshSnapshot) -> do
                                        _ <-
                                            refreshedRun
                                                |> set #proposedActionsJson (reconciliationReviewRequiresReviewJson freshSnapshot)
                                                |> set #errorSummary Nothing
                                                |> updateRecord
                                        loadXeroTimesheetPreparationView runId
                                    Right (XeroTimesheetReviewedSubmissionCompleted submissionRun) -> do
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

fetchPreparationRunForCurrentVenue ::
    (?modelContext :: ModelContext, ?context :: ControllerContext) =>
    Id XeroTimesheetPreparationRun ->
    IO (Maybe XeroTimesheetPreparationRun)
fetchPreparationRunForCurrentVenue runId =
    query @XeroTimesheetPreparationRun
        |> filterWhere (#id, runId)
        |> filterWhere (#venueId, unpackId currentVenueId)
        |> fetchOneOrNothing

fetchPreparationReviewRows ::
    (?modelContext :: ModelContext) =>
    XeroTimesheetReadinessRequest ->
    XeroConnection ->
    [XeroStaffMappingRow] ->
    IO [XeroPreparationReviewRow]
fetchPreparationReviewRows request connection staffRows = do
    previewInput <- fetchPreviewInput request connection
    let entries = previewInput.previewTimesheetEntries
        calculationsByEntryId = previewInput.previewCalculationsByEntryId
    let xeroMappedStaffRows =
            staffRows
                |> filter (staffMappingVerified . (.mappingRowMapping))
                |> filter (\row -> unpackId row.mappingRowStaff.id `elem` map (.staffId) entries)
                |> List.sortOn (staffSortKey . (.mappingRowStaff))
    pure (map (reviewRowForStaff entries calculationsByEntryId) xeroMappedStaffRows)

reviewRowForStaff :: [TimesheetEntry] -> Map.Map UUID WageCalculation -> XeroStaffMappingRow -> XeroPreparationReviewRow
reviewRowForStaff entries calculationsByEntryId row =
    let staff = row.mappingRowStaff
        staffEntries = filter (\entry -> entry.staffId == unpackId staff.id) entries
     in XeroPreparationReviewRow
            { reviewRowStaff = staff
            , reviewRowEntryCount = length staffEntries
            , reviewRowTotalUnits = totalEntryUnits staffEntries
            , reviewRowTotalAmount = totalEntryAmount calculationsByEntryId staffEntries
            }

totalEntryAmount :: Map.Map UUID WageCalculation -> [TimesheetEntry] -> Scientific
totalEntryAmount calculationsByEntryId entries =
    let calculations = mapMaybe (\entry -> Map.lookup (unpackId entry.id) calculationsByEntryId) entries
        componentsByDay =
            Map.fromListWith (<>)
                [ (componentDate, [component])
                | calculation <- calculations
                , (componentDate, component) <- datedEarningsComponents calculation
                ]
        total =
            sum
                [ line.publishedAmount
                | components <- Map.elems componentsByDay
                , line <- derivePublishedEarnings components
                ]
     in fst (Scientific.fromRationalRepetendUnlimited total)

totalEntryUnits :: [TimesheetEntry] -> Rational
totalEntryUnits = sum . map paidEntryUnits

paidEntryUnits :: TimesheetEntry -> Rational
paidEntryUnits entry =
    max 0 (toRational (timesheetEntryPaidElapsedSeconds entry) / 3600)

staffSortKey :: Staff -> (Text, Text)
staffSortKey staff = (staff.lastName, staff.firstName)

fetchPreparationPayItemRequirements ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    XeroTimesheetPreparationRun ->
    XeroConnection ->
    [XeroEarningsRate] ->
    IO [XeroPayItemRequirement]
fetchPreparationPayItemRequirements run connection xeroEarningsRates = do
    requirements <- fetchCurrentVenueXeroPayItemRequirements (Just connection) xeroEarningsRates
    case (run.payPeriodStart, run.payPeriodEnd) of
        (Just periodStart, Just periodEnd) -> do
            skippedStaffIds <- fetchPreparationNotPaidStaffIds connection
            bucketResult <- fetchPeriodXeroLocalEarningsBuckets (Id run.venueId) periodStart periodEnd skippedStaffIds
            buckets <- case bucketResult of
                Left message -> fail (cs ("Cannot derive managed pay items from approved wage facts: " <> message))
                Right values  -> pure values
            let bucketKeys = map (.localBucketKey) buckets
            pure (filter (\requirement -> requirement.payItemRequirementKey `elem` bucketKeys) requirements)
        _ -> pure []

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
    pure (map (.staffId) (filter (isJust . (.updatedByUserId)) mappings))

ensurePreparationDecisionProposals ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    XeroTimesheetPreparationRun ->
    IO ()
ensurePreparationDecisionProposals run = do
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
    void (ensurePreparationPayItemDecisionProposals run)

ensurePreparationPayItemDecisionProposals ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    XeroTimesheetPreparationRun ->
    IO [XeroPayItemRequirement]
ensurePreparationPayItemDecisionProposals run = do
    connection <- fetch (Id run.xeroConnectionId :: Id XeroConnection)
    xeroEarningsRates <- fetchCurrentVenueXeroEarningsRates (Just connection)
    requirements <- fetchPreparationPayItemRequirements run connection xeroEarningsRates
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
    pure proposedRequirements

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
    IO (Either Text XeroTimesheetPreparationView)
applyEmployeeMappingDecision run connection staff decisionKind employeeId = do
    applyEmployeeMappingDecisionWithoutReload run connection staff decisionKind employeeId >>= \case
        Left message -> pure (Left message)
        Right () -> reloadAfterLocalDecision run remoteTimesheetsFromRun

applyEmployeeMappingDecisionWithoutReload ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    XeroTimesheetPreparationRun ->
    XeroConnection ->
    Staff ->
    XeroTimesheetPreparationDecisionKindEnum ->
    Text ->
    IO (Either Text ())
applyEmployeeMappingDecisionWithoutReload run connection staff decisionKind employeeId = do
    maybeEmployee <-
        query @XeroEmployee
            |> filterWhere (#venueId, unpackId currentVenueId)
            |> filterWhere (#xeroConnectionId, unpackId connection.id)
            |> filterWhere (#xeroEmployeeId, employeeId)
            |> filterWhere (#providerAvailable, True)
            |> fetchOneOrNothing
    case maybeEmployee of
        Nothing -> pure (Left "Choose a synced Xero employee from this venue.")
        Just employee -> do
            duplicateMapping <-
                query @XeroStaffMapping
                    |> filterWhere (#venueId, unpackId currentVenueId)
                    |> filterWhere (#xeroConnectionId, unpackId connection.id)
                    |> filterWhere (#xeroEmployeeId, Just employeeId)
                    |> filterWhere (#mappingStatus, XeroStaffMappingStatusEnumVerified)
                    |> filterWhereNot (#staffId, unpackId staff.id)
                    |> fetchOneOrNothing
            case duplicateMapping of
                Just _ -> pure (Left "That Xero employee is already mapped to another staff member.")
                Nothing -> do
                    _ <- persistPreparationStaffMapping connection staff XeroStaffMappingStatusEnumVerified (Just employee)
                    _ <- applyPreparationDecision run (Just staff) decisionKind (Just employee.xeroEmployeeId) (Just employee.displayName) Nothing
                    dismissPendingStaffAutoMatches run staff
                    pure (Right ())

persistPreparationStaffMapping ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    XeroConnection ->
    Staff ->
    XeroStaffMappingStatusEnum ->
    Maybe XeroEmployee ->
    IO XeroStaffMapping
persistPreparationStaffMapping connection staff mappingStatus maybeEmployee = do
    now <- getCurrentTime
    existingMapping <-
        query @XeroStaffMapping
            |> filterWhere (#staffId, unpackId staff.id)
            |> filterWhere (#xeroConnectionId, unpackId connection.id)
            |> fetchOneOrNothing
    let prepared record =
            record
                |> set #venueId (unpackId currentVenueId)
                |> set #staffId (unpackId staff.id)
                |> set #xeroConnectionId (unpackId connection.id)
                |> set #xeroEmployeeId ((.xeroEmployeeId) <$> maybeEmployee)
                |> set #xeroEmployeeName ((.displayName) <$> maybeEmployee)
                |> set #xeroEmployeeEmail (maybeEmployee >>= (.email))
                |> set #mappingStatus mappingStatus
                |> set #lastVerifiedAt (if xeroStaffMappingIsVerified mappingStatus then Just now else Nothing)
                |> set #updatedByUserId (Just (unpackId currentUser.id))
    case existingMapping of
        Just existing -> prepared existing |> updateRecord
        Nothing ->
            prepared (newRecord @XeroStaffMapping)
                |> set #createdByUserId (Just (unpackId currentUser.id))
                |> createRecord

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
    IO (Either Text XeroTimesheetPreparationView)
reloadAfterLocalDecision run remoteTimesheetReader = do
    latestRun <- fetch run.id
    _ <- refreshPreparationRunStatus latestRun (remoteTimesheetReader latestRun)
    loadXeroTimesheetPreparationView latestRun.id

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
