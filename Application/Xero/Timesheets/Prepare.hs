module Application.Xero.Timesheets.Prepare
    ( XeroPreparationStaffDecision (..)
    , applyXeroPreparationStaffDecision
    , approveXeroPreparationPayItemDecisions
    , approveXeroPreparationStaffStep
    , loadXeroTimesheetPreparationView
    , previewXeroTimesheetPreparation
    , refreshXeroTimesheetPreparation
    , selectXeroTimesheetPreparationPeriod
    , startXeroTimesheetPreparation
    , submitXeroTimesheetPreparation
    ) where

import Application.Helper.Pay (PayTotals (..), TimesheetPayResult (..), fetchTimesheetPayResultsForEntries, timesheetEntryIdKey)
import Application.Helper.Xero
import Application.Helper.XeroAdminTypes
import Application.Helper.TimeRules (shiftDurationMinutes)
import Application.Helper.XeroTimesheetReadiness
import Application.Helper.Audit (recordCurrentUserAuditEvent)
import Application.Helper.ControllerContext (currentVenueId)
import Application.Xero.Admin.PayItems
import Application.Xero.Admin.ReadModel
import Application.Xero.Admin.ReferenceData
import Application.Xero.Connection
import Application.Xero.Timesheets.Buckets
import Application.Xero.Timesheets.Preview
import Application.Xero.Timesheets.Submission
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Types as AesonTypes
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import Data.Scientific (Scientific)
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
                            |> set #status ("preparing" :: Text)
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
refreshCurrentVenueXeroReferenceDataForPreparation connection
    | connection.connectionStatus /= "active" = pure (Left "Reconnect Xero before preparing draft timesheets.")
    | otherwise = do
        now <- getCurrentTime
        syncRun <-
            newRecord @XeroSyncRun
                |> set #venueId (unpackId currentVenueId)
                |> set #xeroConnectionId (unpackId connection.id)
                |> set #syncStatus ("running" :: Text)
                |> set #syncKind ("payroll_reference_data" :: Text)
                |> set #startedAt now
                |> createRecord
        readXeroConfig >>= \case
            Left message -> failCurrentVenuePreparationReferenceSync syncRun connection message
            Right config ->
                refreshXeroConnectionAccessWithoutBroadcast config connection >>= \case
                    Left message -> failCurrentVenuePreparationReferenceSync syncRun connection message
                    Right (refreshedConnection, accessToken) -> do
                        xeroClient <- currentXeroClient
                        employeesResult <- fetchPayrollEmployees xeroClient accessToken refreshedConnection.tenantId
                        earningsRatesResult <- fetchEarningsRates xeroClient accessToken refreshedConnection.tenantId
                        payrollCalendarsResult <- fetchPayrollCalendars xeroClient accessToken refreshedConnection.tenantId
                        accountsResult <- fetchAccounts xeroClient accessToken refreshedConnection.tenantId
                        payrollSettingsAccountsResult <- fetchPayrollSettingsAccounts xeroClient accessToken refreshedConnection.tenantId
                        case (employeesResult, earningsRatesResult, payrollCalendarsResult, accountsResult, payrollSettingsAccountsResult) of
                            (Right employees, Right earningsRates, Right payrollCalendars, Right accounts, Right payrollSettingsAccounts) -> do
                                completePreparationReferenceSync syncRun refreshedConnection employees earningsRates payrollCalendars accounts payrollSettingsAccounts
                                pure (Right refreshedConnection)
                            (Left err, _, _, _, _) ->
                                failCurrentVenuePreparationReferenceSync syncRun refreshedConnection ("Xero employee sync failed: " <> xeroClientErrorText err)
                            (_, Left err, _, _, _) ->
                                failCurrentVenuePreparationReferenceSync syncRun refreshedConnection ("Xero earnings-rate sync failed: " <> xeroClientErrorText err)
                            (_, _, Left err, _, _) ->
                                failCurrentVenuePreparationReferenceSync syncRun refreshedConnection ("Xero payroll-calendar sync failed: " <> xeroClientErrorText err)
                            (_, _, _, Left err, _) ->
                                failCurrentVenuePreparationReferenceSync syncRun refreshedConnection ("Xero account sync failed: " <> xeroClientErrorText err)
                            (_, _, _, _, Left err) ->
                                failCurrentVenuePreparationReferenceSync syncRun refreshedConnection ("Xero payroll-settings sync failed: " <> xeroClientErrorText err)

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
                            |> set #status ("needs_reconnect" :: Text)
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
                                            |> set #status ("needs_reconnect" :: Text)
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
            approvedStaffIds <- fetchApprovedPreparationStaffIds run
            reviewRows <- fetchPreparationReviewRows run staffRows
            periodOptions <- fetchCurrentVenueXeroTimesheetPeriodOptions (Just connection)
            xeroEmployees <- fetchCurrentVenueXeroEmployees (Just connection)
            xeroEarningsRates <- fetchCurrentVenueXeroEarningsRates (Just connection)
            payItemRequirements <- fetchPreparationPayItemRequirements run connection xeroEarningsRates
            payrollCalendars <- fetchCurrentVenueXeroPayrollCalendars (Just connection)
            payrollCalendarSelection <- fetchCurrentVenueXeroPayrollCalendarSelection (Just connection)
            accountCodeOptions <- fetchCurrentVenueXeroPayItemAccountCodeOptions (Just connection)
            accountCodeSelection <- fetchCurrentVenueXeroPayItemAccountCodeSelection (Just connection)
            maybeSubmissionRun <-
                case run.xeroSubmissionRunId of
                    Nothing -> pure Nothing
                    Just submissionRunId -> Just <$> fetch (Id submissionRunId :: Id XeroSubmissionRun)
            maybeSubmissionView <-
                case maybeSubmissionRun of
                    Nothing -> pure Nothing
                    Just submissionRun -> Just <$> buildXeroTimesheetRunView connection submissionRun
            let staffDecisionRows = map (preparationStaffRow decisions) staffRows
                payItemRows = map (preparationPayItemRow decisions) (filter activePayItemRequirement payItemRequirements)
                pendingDecisionCount = length (filter pendingManualPreparationDecision decisions)
                manualStaffDecisionCount = length (filter (.preparationStaffNeedsDecision) staffDecisionRows)
                postedBlocked = preparationRunPosted run
                proposedPayItemCount = length (filter ((== "proposed") . (.payItemRequirementStatus) . (.preparationPayItemRequirement)) payItemRows)
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
                        , preparationPayrollCalendarSelection = payrollCalendarSelection
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
                        , preparationReviewRows = reviewRows
                        , preparationPreviewRows = maybe [] (\submissionView -> submissionView.timesheetRunPreviewRows) maybeSubmissionView
                        , preparationSubmissionRun = maybeSubmissionRun
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
                            _ <- applyPreparationDecision run Nothing "staff_step_approved" Nothing Nothing Nothing
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
            applyEmployeeMappingDecisionWithoutReload run connection staff "staff_auto_match" employeeId
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
                Nothing -> pure (Left "Choose a staff member from the current venue.")
                Just staff ->
                    case decision of
                        MarkStaffNotPaidThroughXero -> do
                            _ <- persistPreparationStaffMapping connection staff "not_applicable" Nothing
                            _ <- applyPreparationDecision run (Just staff) "staff_not_paid" Nothing Nothing Nothing
                            dismissPendingStaffAutoMatches run staff
                            reloadAfterLocalDecision run remoteTimesheetsFromCurrentRun
                        SelectXeroEmployee employeeId -> do
                            pendingSuggestion <- fetchPendingStaffAutoMatch run staff
                            let decisionKind =
                                    case pendingSuggestion >>= (.xeroEmployeeId) of
                                        Just suggestedEmployeeId | suggestedEmployeeId == employeeId -> "staff_auto_match"
                                        _ -> "staff_manual_mapping"
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
        proposedRequirements = filter (\requirement -> requirement.payItemRequirementStatus == "proposed" && requirement.payItemRequirementIsActive) requirements
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
                            |> set #status ("preparing" :: Text)
                            |> set #errorSummary Nothing
                            |> updateRecord
                    refreshXeroTimesheetPreparation updatedRun.id

syncXeroPreparationReferenceData ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Id XeroTimesheetPreparationRun ->
    IO (Either Text XeroTimesheetPreparationView)
syncXeroPreparationReferenceData runId =
    fetchPreparationRunForCurrentVenue runId >>= \case
        Nothing -> pure (Left "Xero preparation run was not found for this venue.")
        Just run -> do
            connection <- fetch (Id run.xeroConnectionId :: Id XeroConnection)
            if connection.connectionStatus /= "active"
                then refreshXeroTimesheetPreparation run.id
                else do
                    now <- getCurrentTime
                    syncRun <-
                        newRecord @XeroSyncRun
                            |> set #venueId (unpackId currentVenueId)
                            |> set #xeroConnectionId (unpackId connection.id)
                            |> set #syncStatus ("running" :: Text)
                            |> set #syncKind ("payroll_reference_data" :: Text)
                            |> set #startedAt now
                            |> createRecord
                    readXeroConfig >>= \case
                        Left message -> failPreparationReferenceSync run syncRun connection message
                        Right config ->
                            refreshXeroConnectionAccessWithoutBroadcast config connection >>= \case
                                Left message -> failPreparationReferenceSync run syncRun connection message
                                Right (refreshedConnection, accessToken) -> do
                                    xeroClient <- currentXeroClient
                                    employeesResult <- fetchPayrollEmployees xeroClient accessToken refreshedConnection.tenantId
                                    earningsRatesResult <- fetchEarningsRates xeroClient accessToken refreshedConnection.tenantId
                                    payrollCalendarsResult <- fetchPayrollCalendars xeroClient accessToken refreshedConnection.tenantId
                                    accountsResult <- fetchAccounts xeroClient accessToken refreshedConnection.tenantId
                                    payrollSettingsAccountsResult <- fetchPayrollSettingsAccounts xeroClient accessToken refreshedConnection.tenantId
                                    case (employeesResult, earningsRatesResult, payrollCalendarsResult, accountsResult, payrollSettingsAccountsResult) of
                                        (Right employees, Right earningsRates, Right payrollCalendars, Right accounts, Right payrollSettingsAccounts) -> do
                                            completePreparationReferenceSync syncRun refreshedConnection employees earningsRates payrollCalendars accounts payrollSettingsAccounts
                                            refreshXeroTimesheetPreparation run.id
                                        (Left err, _, _, _, _) ->
                                            failPreparationReferenceSync run syncRun refreshedConnection ("Xero employee sync failed: " <> xeroClientErrorText err)
                                        (_, Left err, _, _, _) ->
                                            failPreparationReferenceSync run syncRun refreshedConnection ("Xero earnings-rate sync failed: " <> xeroClientErrorText err)
                                        (_, _, Left err, _, _) ->
                                            failPreparationReferenceSync run syncRun refreshedConnection ("Xero payroll-calendar sync failed: " <> xeroClientErrorText err)
                                        (_, _, _, Left err, _) ->
                                            failPreparationReferenceSync run syncRun refreshedConnection ("Xero account sync failed: " <> xeroClientErrorText err)
                                        (_, _, _, _, Left err) ->
                                            failPreparationReferenceSync run syncRun refreshedConnection ("Xero payroll-settings sync failed: " <> xeroClientErrorText err)

saveXeroPreparationPayrollCalendar ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Id XeroTimesheetPreparationRun ->
    Text ->
    IO (Either Text XeroTimesheetPreparationView)
saveXeroPreparationPayrollCalendar runId payrollCalendarId =
    fetchPreparationRunForCurrentVenue runId >>= \case
        Nothing -> pure (Left "Xero preparation run was not found for this venue.")
        Just run -> do
            connection <- fetch (Id run.xeroConnectionId :: Id XeroConnection)
            case Text.strip payrollCalendarId of
                "" -> pure (Left "Choose a synced Xero payroll calendar.")
                selectedCalendarId -> do
                    maybePayrollCalendar <-
                        query @XeroPayrollCalendar
                            |> filterWhere (#venueId, unpackId currentVenueId)
                            |> filterWhere (#xeroConnectionId, unpackId connection.id)
                            |> filterWhere (#xeroPayrollCalendarId, selectedCalendarId)
                            |> fetchOneOrNothing
                    case maybePayrollCalendar of
                        Nothing -> pure (Left "Choose a synced Xero payroll calendar from this venue.")
                        Just payrollCalendar ->
                            case (run.payPeriodStart, run.payPeriodEnd) of
                                (Just periodStart, Just periodEnd) -> do
                                    _ <-
                                        run
                                            |> set #selectedPayrollCalendarId (Just payrollCalendar.xeroPayrollCalendarId)
                                            |> set #selectedPayrollCalendarName (Just payrollCalendar.name)
                                            |> set #selectedPeriodKey (Just (preparationPeriodKey payrollCalendar.xeroPayrollCalendarId periodStart periodEnd))
                                            |> set #paymentDate payrollCalendar.paymentDate
                                            |> set #xeroPayRunId Nothing
                                            |> set #xeroPayRunStatus Nothing
                                            |> updateRecord
                                    refreshXeroTimesheetPreparation run.id
                                _ -> pure (Left "Choose a Xero pay period before choosing a payroll calendar.")

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
                        markPayItemCreateDecisionsApplied run []
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
                                |> set #status ("previewed" :: Text)
                                |> set #xeroSubmissionRunId (Just (unpackId submissionRun.id))
                                |> set #readinessSnapshotJson (xeroReadinessSnapshotJson readiness)
                                |> set #previewPayloadJson submissionRun.previewPayloadJson
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
            | otherwise ->
                ensurePreparationPayItemsReady view.preparationRun maybeAccountCode >>= \case
                    Left message -> pure (Left message)
                    Right () -> do
                        refreshedRun <- fetch view.preparationRun.id
                        latestDecisions <- fetchPreparationDecisions refreshedRun
                        let remoteTimesheets = remoteTimesheetsFromRun refreshedRun
                            readinessRequest = preparationReadinessRequest refreshedRun remoteTimesheets
                        readiness <- validateXeroTimesheetReadiness readinessRequest
                        if not readiness.xeroTimesheetReady
                            then pure (Left (readinessErrorSummary readiness))
                            else
                                submitXeroDraftTimesheetsForPreparation currentUser.id refreshedRun.id readinessRequest >>= \case
                                    Left message -> pure (Left message)
                                    Right submissionRun -> do
                                        completedAt <- getCurrentTime
                                        _ <-
                                            refreshedRun
                                                |> set #status (if submissionRun.status == "submitted" then "submitted" else "failed" :: Text)
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

fetchPreparationDecisions ::
    (?modelContext :: ModelContext) =>
    XeroTimesheetPreparationRun ->
    IO [XeroTimesheetPreparationDecision]
fetchPreparationDecisions run =
    query @XeroTimesheetPreparationDecision
        |> filterWhere (#xeroTimesheetPreparationRunId, unpackId run.id)
        |> orderBy #createdAt
        |> fetch

fetchApprovedPreparationStaffIds ::
    (?modelContext :: ModelContext) =>
    XeroTimesheetPreparationRun ->
    IO [UUID]
fetchApprovedPreparationStaffIds run = do
    entries <- fetchApprovedPreparationEntries run
    pure $
        entries
            |> map (.staffId)
            |> List.nub

fetchPreparationReviewRows ::
    (?modelContext :: ModelContext) =>
    XeroTimesheetPreparationRun ->
    [XeroStaffMappingRow] ->
    IO [XeroPreparationReviewRow]
fetchPreparationReviewRows run staffRows = do
    entries <- fetchApprovedPreparationEntries run
    payResultsByEntryId <- fetchTimesheetPayResultsForEntries entries
    let xeroMappedStaffRows =
            staffRows
                |> filter (staffMappingVerified . (.mappingRowMapping))
                |> filter (\row -> unpackId row.mappingRowStaff.id `elem` map (.staffId) entries)
                |> List.sortOn (staffSortKey . (.mappingRowStaff))
    pure (map (reviewRowForStaff entries payResultsByEntryId) xeroMappedStaffRows)

fetchApprovedPreparationEntries ::
    (?modelContext :: ModelContext) =>
    XeroTimesheetPreparationRun ->
    IO [TimesheetEntry]
fetchApprovedPreparationEntries run =
    case (run.payPeriodStart, run.payPeriodEnd) of
        (Just periodStart, Just periodEnd) ->
            query @TimesheetEntry
                |> filterWhere (#venueId, run.venueId)
                |> filterWhereGreaterThanOrEqualTo (#workedOn, periodStart)
                |> filterWhereLessThanOrEqualTo (#workedOn, periodEnd)
                |> filterWhere (#isApproved, True)
                |> filterWhere (#deletedAt, Nothing)
                |> fetch
        _ -> pure []

reviewRowForStaff :: [TimesheetEntry] -> Map.Map Text TimesheetPayResult -> XeroStaffMappingRow -> XeroPreparationReviewRow
reviewRowForStaff entries payResultsByEntryId row =
    let staff = row.mappingRowStaff
        staffEntries = filter (\entry -> entry.staffId == unpackId staff.id) entries
     in XeroPreparationReviewRow
            { reviewRowStaff = staff
            , reviewRowEntryCount = length staffEntries
            , reviewRowTotalUnits = totalEntryUnits staffEntries
            , reviewRowTotalAmount = totalEntryAmount payResultsByEntryId staffEntries
            }

totalEntryAmount :: Map.Map Text TimesheetPayResult -> [TimesheetEntry] -> Scientific
totalEntryAmount payResultsByEntryId entries =
    sum (map entryAmount entries)
    where
        entryAmount entry =
            case Map.lookup (timesheetEntryIdKey entry.id) payResultsByEntryId of
                Nothing -> 0
                Just result -> result.totals.totalAmount

totalEntryUnits :: [TimesheetEntry] -> Scientific
totalEntryUnits entries =
    fromIntegral (sum (map paidEntryMinutes entries)) / 60

paidEntryMinutes :: TimesheetEntry -> Int
paidEntryMinutes entry =
    max 0 (shiftDurationMinutes entry.startTime entry.endTime - entry.breakMinutes)

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
            buckets <- fetchPeriodXeroLocalEarningsBuckets (Id run.venueId) periodStart periodEnd skippedStaffIds
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
            |> filterWhere (#mappingStatus, "not_applicable" :: Text)
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
                        "staff_auto_match"
                        (Just employee.xeroEmployeeId)
                        (Just employee.displayName)
                        Nothing
                        (Aeson.object ["suggestedEmployeeId" Aeson..= employee.xeroEmployeeId, "suggestedEmployeeName" Aeson..= employee.displayName])
            _ -> pure ()
    xeroEarningsRates <- fetchCurrentVenueXeroEarningsRates (Just connection)
    requirements <- fetchPreparationPayItemRequirements run connection xeroEarningsRates
    forM_ (filter (\requirement -> requirement.payItemRequirementStatus == "proposed") requirements) \requirement ->
        void $
            ensurePendingPreparationDecision
                run
                Nothing
                "pay_item_create"
                Nothing
                Nothing
                (Just requirement.payItemRequirementKey)
                (Aeson.object ["requirementName" Aeson..= requirement.payItemRequirementName])

ensurePendingPreparationDecision ::
    (?modelContext :: ModelContext) =>
    XeroTimesheetPreparationRun ->
    Maybe Staff ->
    Text ->
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
            |> filterWhereIn (#decisionStatus, ["pending" :: Text, "applied"])
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
                |> set #decisionStatus ("pending" :: Text)
                |> set #xeroEmployeeId maybeEmployeeId
                |> set #xeroEmployeeName maybeEmployeeName
                |> set #localBucketKey maybeLocalBucketKey
                |> set #payloadJson payload
                |> createRecord

applyPreparationDecision ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    XeroTimesheetPreparationRun ->
    Maybe Staff ->
    Text ->
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
        |> set #decisionStatus ("applied" :: Text)
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
    Text ->
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
    Text ->
    Text ->
    IO (Either Text ())
applyEmployeeMappingDecisionWithoutReload run connection staff decisionKind employeeId = do
    maybeEmployee <-
        query @XeroEmployee
            |> filterWhere (#venueId, unpackId currentVenueId)
            |> filterWhere (#xeroConnectionId, unpackId connection.id)
            |> filterWhere (#xeroEmployeeId, employeeId)
            |> fetchOneOrNothing
    case maybeEmployee of
        Nothing -> pure (Left "Choose a synced Xero employee from this venue.")
        Just employee -> do
            duplicateMapping <-
                query @XeroStaffMapping
                    |> filterWhere (#venueId, unpackId currentVenueId)
                    |> filterWhere (#xeroConnectionId, unpackId connection.id)
                    |> filterWhere (#xeroEmployeeId, Just employeeId)
                    |> filterWhere (#mappingStatus, "verified" :: Text)
                    |> filterWhereNot (#staffId, unpackId staff.id)
                    |> fetchOneOrNothing
            case duplicateMapping of
                Just _ -> pure (Left "That Xero employee is already mapped to another staff member.")
                Nothing -> do
                    _ <- persistPreparationStaffMapping connection staff "verified" (Just employee)
                    _ <- applyPreparationDecision run (Just staff) decisionKind (Just employee.xeroEmployeeId) (Just employee.displayName) Nothing
                    dismissPendingStaffAutoMatches run staff
                    pure (Right ())

persistPreparationStaffMapping ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    XeroConnection ->
    Staff ->
    Text ->
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
                |> set #lastVerifiedAt (if mappingStatus == "verified" then Just now else Nothing)
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
            |> filterWhere (#decisionKind, "staff_auto_match" :: Text)
            |> filterWhere (#decisionStatus, "pending" :: Text)
            |> fetch
    now <- getCurrentTime
    forM_ pending \decision ->
        decision
            |> set #decisionStatus ("dismissed" :: Text)
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
        |> filterWhere (#decisionKind, "staff_auto_match" :: Text)
        |> filterWhere (#decisionStatus, "pending" :: Text)
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

completePreparationReferenceSync ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    XeroSyncRun ->
    XeroConnection ->
    [XeroEmployeeRef] ->
    [XeroEarningsRateRef] ->
    [XeroPayrollCalendarRef] ->
    [XeroAccountRef] ->
    [XeroAccountRef] ->
    IO ()
completePreparationReferenceSync syncRun connection employees earningsRates payrollCalendars accounts payrollSettingsAccounts = do
    now <- getCurrentTime
    withTransaction do
        mapM_ (upsertXeroEmployee connection now) employees
        mapM_ (upsertXeroEarningsRate connection now) earningsRates
        mapM_ (upsertXeroPayrollCalendar connection now) payrollCalendars
        mapM_ (upsertXeroAccount connection now) accounts
        markStaleXeroStaffMappings connection employees
        markStaleXeroEarningsRateMappings connection earningsRates
        reconcileXeroPayItemAccountCodeSelection connection accounts payrollSettingsAccounts
        reconcileXeroPayrollCalendarSelection connection payrollCalendars
        _ <-
            syncRun
                |> set #syncStatus ("succeeded" :: Text)
                |> set #employeesCount (length employees)
                |> set #earningsRatesCount (length earningsRates)
                |> set #payrollCalendarsCount (length payrollCalendars)
                |> set #finishedAt (Just now)
                |> updateRecord
        _ <-
            connection
                |> set #lastSyncAt (Just now)
                |> set #lastError Nothing
                |> updateRecord
        void $
            recordCurrentUserAuditEvent
                "xero_reference_sync_succeeded"
                "xero_sync_runs"
                (unpackId syncRun.id)
                (Aeson.object
                    [ "tenantId" Aeson..= connection.tenantId
                    , "employeesCount" Aeson..= length employees
                    , "earningsRatesCount" Aeson..= length earningsRates
                    , "payrollCalendarsCount" Aeson..= length payrollCalendars
                    ]
                )

failCurrentVenuePreparationReferenceSync ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    XeroSyncRun ->
    XeroConnection ->
    Text ->
    IO (Either Text XeroConnection)
failCurrentVenuePreparationReferenceSync syncRun connection message = do
    now <- getCurrentTime
    withTransaction do
        _ <-
            syncRun
                |> set #syncStatus ("failed" :: Text)
                |> set #errorMessage (Just message)
                |> set #finishedAt (Just now)
                |> updateRecord
        latestConnection <- fetch connection.id
        _ <-
            latestConnection
                |> set #lastError (Just message)
                |> updateRecord
        void $
            recordCurrentUserAuditEvent
                "xero_reference_sync_failed"
                "xero_sync_runs"
                (unpackId syncRun.id)
                (Aeson.object
                    [ "tenantId" Aeson..= connection.tenantId
                    , "failure" Aeson..= message
                    ]
                )
    pure (Left message)

failPreparationReferenceSync ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    XeroTimesheetPreparationRun ->
    XeroSyncRun ->
    XeroConnection ->
    Text ->
    IO (Either Text XeroTimesheetPreparationView)
failPreparationReferenceSync run syncRun connection message = do
    now <- getCurrentTime
    withTransaction do
        _ <-
            syncRun
                |> set #syncStatus ("failed" :: Text)
                |> set #errorMessage (Just message)
                |> set #finishedAt (Just now)
                |> updateRecord
        latestConnection <- fetch connection.id
        _ <-
            latestConnection
                |> set #lastError (Just message)
                |> updateRecord
        _ <-
            run
                |> set #status ("failed" :: Text)
                |> set #errorSummary (Just message)
                |> updateRecord
        void $
            recordCurrentUserAuditEvent
                "xero_reference_sync_failed"
                "xero_sync_runs"
                (unpackId syncRun.id)
                (Aeson.object
                    [ "tenantId" Aeson..= connection.tenantId
                    , "failure" Aeson..= message
                    ]
                )
    loadXeroTimesheetPreparationView run.id

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
                    |> set #selectionStatus ("verified" :: Text)
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
                |> filterWhere (#decisionKind, "pay_item_create" :: Text)
                |> filterWhere (#decisionStatus, "pending" :: Text)
                |> fetch
        pure $ if null requirementKeys
            then pendingDecisions
            else filter (\decision -> decision.localBucketKey `elem` map Just requirementKeys) pendingDecisions
    now <- getCurrentTime
    forM_ decisions \decision ->
        decision
            |> set #decisionStatus ("applied" :: Text)
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

pendingManualPreparationDecision :: XeroTimesheetPreparationDecision -> Bool
pendingManualPreparationDecision decision =
    decision.decisionStatus == "pending" && decision.decisionKind /= "pay_item_create"

pendingPayItemCreateDecision :: XeroTimesheetPreparationDecision -> Bool
pendingPayItemCreateDecision decision =
    decision.decisionStatus == "pending" && decision.decisionKind == "pay_item_create"

isPendingStaffAutoMatch :: XeroTimesheetPreparationDecision -> Bool
isPendingStaffAutoMatch decision =
    decision.decisionStatus == "pending" && decision.decisionKind == "staff_auto_match"

staffStepApprovalApplied :: XeroTimesheetPreparationDecision -> Bool
staffStepApprovalApplied decision =
    decision.decisionStatus == "applied" && decision.decisionKind == "staff_step_approved"

readinessAllowsAutomaticPayItemSubmit :: XeroTimesheetReadiness -> Bool
readinessAllowsAutomaticPayItemSubmit readiness =
    all automaticPayItemBlocker readiness.xeroReadinessBlockers
    where
        automaticPayItemBlocker blocker =
            blocker.xeroBlockerCode == "managed_pay_item_not_ready"
                || blocker.xeroBlockerCode == "missing_pay_item_account_code"

readinessHasMissingPayItemAccountCode :: XeroTimesheetReadiness -> Bool
readinessHasMissingPayItemAccountCode readiness =
    any ((== "missing_pay_item_account_code") . (.xeroBlockerCode)) readiness.xeroReadinessBlockers

refreshPreparationRunStatus ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    XeroTimesheetPreparationRun ->
    [XeroTimesheetRef] ->
    IO XeroTimesheetPreparationRun
refreshPreparationRunStatus run remoteTimesheets = do
    decisions <- fetchPreparationDecisions run
    readiness <- preparationReadinessForRun run remoteTimesheets
    connection <- fetch (Id run.xeroConnectionId :: Id XeroConnection)
    staffRows <- fetchCurrentVenueXeroStaffMappingRows (Just connection)
    let pendingDecisionCount = length (filter pendingManualPreparationDecision decisions)
        manualStaffCount = length (filter staffNeedsXeroDecision staffRows)
        postedBlocked = preparationRunPosted run
        hasSelectedPeriod = preparationRunHasPeriod run
        (status, errorSummary)
            | pendingDecisionCount > 0 || manualStaffCount > 0 = ("needs_approval", Nothing)
            | not hasSelectedPeriod = ("started", Nothing)
            | postedBlocked = ("blocked", Just "The selected Xero pay run is posted. Draft timesheet creation is blocked.")
            | readinessHasMissingPayItemAccountCode readiness = ("needs_approval", Nothing)
            | not (readinessAllowsAutomaticPayItemSubmit readiness) = ("blocked", Just (readinessErrorSummary readiness))
            | otherwise = ("ready_for_preview", Nothing)
    run
        |> set #status (status :: Text)
        |> set #readinessSnapshotJson (xeroReadinessSnapshotJson readiness)
        |> set #proposedActionsJson (preparationProposedActionsJson pendingDecisionCount manualStaffCount)
        |> set #errorSummary errorSummary
        |> updateRecord

markPreparationFailed :: (?modelContext :: ModelContext) => XeroTimesheetPreparationRun -> Text -> IO XeroTimesheetPreparationRun
markPreparationFailed run message =
    run
        |> set #status ("failed" :: Text)
        |> set #errorSummary (Just message)
        |> updateRecord

fetchXeroPayRunsForPreparation :: XeroClient -> Text -> Text -> XeroTimesheetPreparationRun -> IO (Either Text [XeroPayRunRef])
fetchXeroPayRunsForPreparation xeroClient accessToken tenantId run =
    fetchPage 1 []
    where
        fetchPage page acc = do
            let query =
                    XeroPayRunQuery
                        { xeroPayRunIfModifiedSince = Nothing
                        , xeroPayRunWhere = Just ("PayrollCalendarID==Guid(\"" <> fromMaybe "" run.selectedPayrollCalendarId <> "\")")
                        , xeroPayRunOrder = Just "PayRunPeriodStartDate DESC"
                        , xeroPayRunPage = Just page
                        }
            fetchPayRuns xeroClient accessToken tenantId query >>= \case
                Left err -> pure (Left ("Xero pay-run check failed: " <> xeroClientErrorText err))
                Right refs ->
                    let nextAcc = acc <> refs
                     in if length refs < 100
                            then pure (Right nextAcc)
                            else fetchPage (page + 1) nextAcc

findSelectedPayRun :: XeroTimesheetPreparationRun -> [XeroPayRunRef] -> Maybe XeroPayRunRef
findSelectedPayRun run =
    List.find \payRun ->
        payRun.xeroPayRunCalendarId == fromMaybe "" run.selectedPayrollCalendarId
            && Just payRun.xeroPayRunPeriodStart == run.payPeriodStart
            && Just payRun.xeroPayRunPeriodEnd == run.payPeriodEnd

preparationRunHasPeriod :: XeroTimesheetPreparationRun -> Bool
preparationRunHasPeriod run =
    isJust run.selectedPayrollCalendarId
        && isJust run.selectedPeriodKey
        && isJust run.payPeriodStart
        && isJust run.payPeriodEnd

preparationReadinessForRun :: (?modelContext :: ModelContext) => XeroTimesheetPreparationRun -> [XeroTimesheetRef] -> IO XeroTimesheetReadiness
preparationReadinessForRun run remoteTimesheets =
    if preparationRunHasPeriod run
        then validateXeroTimesheetReadiness (preparationReadinessRequest run remoteTimesheets)
        else do
            today <- utctDay <$> getCurrentTime
            pure
                XeroTimesheetReadiness
                    { xeroTimesheetReady = False
                    , xeroReadinessPeriodStart = today
                    , xeroReadinessPeriodEnd = today
                    , xeroReadinessBlockers = []
                    , xeroReadinessWarnings = []
                    , xeroReadinessStaffCount = 0
                    , xeroReadinessEntryCount = 0
                    , xeroReadinessPayBucketCount = 0
                    }

preparationReadinessRequest :: XeroTimesheetPreparationRun -> [XeroTimesheetRef] -> XeroTimesheetReadinessRequest
preparationReadinessRequest run remoteTimesheets =
    XeroTimesheetReadinessRequest
        { readinessVenueId = Id run.venueId
        , readinessPayrollCalendarId = run.selectedPayrollCalendarId
        , readinessPayrollCalendarName = run.selectedPayrollCalendarName
        , readinessSelectedPeriodKey = run.selectedPeriodKey
        , readinessPeriodStart = fromMaybe (error "preparationReadinessRequest requires payPeriodStart") run.payPeriodStart
        , readinessPeriodEnd = fromMaybe (error "preparationReadinessRequest requires payPeriodEnd") run.payPeriodEnd
        , readinessPaymentDate = run.paymentDate
        , readinessXeroPayRunId = run.xeroPayRunId
        , readinessXeroPayRunStatus = run.xeroPayRunStatus
        , readinessRemoteTimesheets = remoteTimesheets
        , readinessSkippedStaffIds = []
        }

preparationReadinessView :: XeroTimesheetPreparationRun -> XeroTimesheetReadiness -> XeroTimesheetReadinessView
preparationReadinessView run readiness =
    let baseView = xeroTimesheetReadinessView readiness
     in if preparationRunPosted run
            then
                baseView
                    { timesheetReadinessReady = False
                    , timesheetReadinessBlockers =
                        XeroTimesheetIssueView
                            { timesheetIssueCode = "xero_pay_run_posted"
                            , timesheetIssueSeverity = "blocker"
                            , timesheetIssueMessage = "The selected Xero pay run is posted. Draft timesheet creation is blocked."
                            , timesheetIssueHint = Nothing
                            }
                            : baseView.timesheetReadinessBlockers
                    }
            else baseView

preparationStaffRow :: [XeroTimesheetPreparationDecision] -> XeroStaffMappingRow -> XeroPreparationStaffRow
preparationStaffRow decisions row =
    let maybeDecision =
            decisions
                |> List.find
                    ( \decision ->
                        decision.staffId == Just (unpackId row.mappingRowStaff.id)
                            && decision.decisionStatus == "pending"
                            && decision.decisionKind `elem` ["staff_auto_match", "staff_manual_mapping", "staff_not_paid"]
                    )
        needsDecision = staffNeedsXeroDecision row && isNothing maybeDecision
     in XeroPreparationStaffRow
            { preparationStaffMappingRow = row
            , preparationStaffDecision = maybeDecision
            , preparationStaffNeedsDecision = needsDecision
            }

preparationPayItemRow :: [XeroTimesheetPreparationDecision] -> XeroPayItemRequirement -> XeroPreparationPayItemRow
preparationPayItemRow decisions requirement =
    XeroPreparationPayItemRow
        { preparationPayItemRequirement = requirement
        , preparationPayItemDecision =
            decisions
                |> List.find
                    ( \decision ->
                        decision.localBucketKey == Just requirement.payItemRequirementKey
                            && decision.decisionKind == "pay_item_create"
                            && decision.decisionStatus `elem` ["pending", "applied"]
                    )
        }

staffRowHasApprovedEntry :: [UUID] -> XeroStaffMappingRow -> Bool
staffRowHasApprovedEntry approvedStaffIds row =
    unpackId row.mappingRowStaff.id `elem` approvedStaffIds

staffNeedsXeroDecision :: XeroStaffMappingRow -> Bool
staffNeedsXeroDecision row =
    not (staffMappingResolved row.mappingRowMapping)

staffMappingResolved :: XeroStaffMapping -> Bool
staffMappingResolved mapping =
    staffMappingVerified mapping
        || (mapping.mappingStatus == "not_applicable" && isJust mapping.updatedByUserId)

staffMappingVerified :: XeroStaffMapping -> Bool
staffMappingVerified mapping =
    mapping.mappingStatus == "verified" && isJust mapping.xeroEmployeeId

activePayItemRequirement :: XeroPayItemRequirement -> Bool
activePayItemRequirement requirement =
    requirement.payItemRequirementStatus /= "ignored"

preparationRunPosted :: XeroTimesheetPreparationRun -> Bool
preparationRunPosted run =
    maybe False ((== "posted") . Text.toCaseFold . Text.strip) run.xeroPayRunStatus

preparationPeriodKey :: Text -> Day -> Day -> Text
preparationPeriodKey calendarId periodStart periodEnd =
    calendarId <> ":" <> tshow periodStart <> ":" <> tshow periodEnd

periodOptionFromPreparationRun :: XeroTimesheetPreparationRun -> Maybe XeroTimesheetPeriodOption
periodOptionFromPreparationRun run = do
    selectedPeriodKey <- run.selectedPeriodKey
    selectedPayrollCalendarId <- run.selectedPayrollCalendarId
    periodStart <- run.payPeriodStart
    periodEnd <- run.payPeriodEnd
    pure
        XeroTimesheetPeriodOption
            { periodOptionKey = selectedPeriodKey
            , periodOptionPayrollCalendarId = selectedPayrollCalendarId
            , periodOptionPayrollCalendarName = fromMaybe selectedPayrollCalendarId run.selectedPayrollCalendarName
            , periodOptionStart = periodStart
            , periodOptionEnd = periodEnd
            , periodOptionPaymentDate = run.paymentDate
            , periodOptionXeroPayRunId = run.xeroPayRunId
            , periodOptionXeroPayRunStatus = run.xeroPayRunStatus
            , periodOptionBlocked = preparationRunPosted run
            , periodOptionBlockReason =
                if preparationRunPosted run
                    then Just "This Xero pay run is posted."
                    else Nothing
            , periodOptionDerivedFromSyncedXero = isJust run.xeroPayRunId
            , periodOptionLatestSubmissionStatus = Nothing
            , periodOptionLatestSubmissionRunId = Nothing
            }

remoteTimesheetsFromRun :: XeroTimesheetPreparationRun -> [XeroTimesheetRef]
remoteTimesheetsFromRun run =
    fromMaybe [] $
        AesonTypes.parseMaybe
            (AesonTypes.withObject "Xero duplicate snapshot" \object -> object AesonTypes..: "remoteTimesheets")
            run.remoteTimesheetsJson

xeroConnectionSnapshotJson :: XeroConnection -> Aeson.Value
xeroConnectionSnapshotJson connection =
    Aeson.object
        [ "connectionId" Aeson..= tshow connection.id
        , "tenantId" Aeson..= connection.tenantId
        , "status" Aeson..= connection.connectionStatus
        , "lastSyncAt" Aeson..= connection.lastSyncAt
        , "lastError" Aeson..= connection.lastError
        ]

payRunsSnapshotJson :: [XeroPayRunRef] -> Aeson.Value
payRunsSnapshotJson refs =
    Aeson.object
        [ "remotePayRunCount" Aeson..= length refs
        , "remotePayRuns" Aeson..= map xeroPayRunRefJson refs
        ]

xeroPayRunRefJson :: XeroPayRunRef -> Aeson.Value
xeroPayRunRefJson ref =
    Aeson.object
        [ "PayRunID" Aeson..= ref.xeroPayRunId
        , "PayrollCalendarID" Aeson..= ref.xeroPayRunCalendarId
        , "PayRunPeriodStartDate" Aeson..= ref.xeroPayRunPeriodStart
        , "PayRunPeriodEndDate" Aeson..= ref.xeroPayRunPeriodEnd
        , "PaymentDate" Aeson..= ref.xeroPayRunPaymentDate
        , "PayRunStatus" Aeson..= ref.xeroPayRunStatus
        , "Raw" Aeson..= ref.xeroPayRunRaw
        ]

preparationProposedActionsJson :: Int -> Int -> Aeson.Value
preparationProposedActionsJson pendingDecisionCount manualStaffDecisionCount =
    Aeson.object
        [ "pendingDecisionCount" Aeson..= pendingDecisionCount
        , "manualStaffDecisionCount" Aeson..= manualStaffDecisionCount
        ]

preparationInitialEventsJson :: UTCTime -> Text -> Aeson.Value
preparationInitialEventsJson occurredAt selectedPeriodKey =
    Aeson.toJSON
        [ Aeson.object
            [ "event" Aeson..= ("preparation_started" :: Text)
            , "status" Aeson..= ("preparing" :: Text)
            , "selectedPeriodKey" Aeson..= selectedPeriodKey
            , "occurredAt" Aeson..= occurredAt
            ]
        ]

readinessErrorSummary :: XeroTimesheetReadiness -> Text
readinessErrorSummary readiness =
    readiness.xeroReadinessBlockers
        |> map (.xeroBlockerMessage)
        |> List.nub
        |> Text.intercalate "\n"
