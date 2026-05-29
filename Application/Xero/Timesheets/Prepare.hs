module Application.Xero.Timesheets.Prepare
    ( XeroPreparationStaffDecision (..)
    , applyXeroPreparationStaffDecision
    , approveXeroPreparationPayItemDecisions
    , loadXeroTimesheetPreparationView
    , previewXeroTimesheetPreparation
    , refreshXeroTimesheetPreparation
    , startXeroTimesheetPreparation
    , submitXeroTimesheetPreparation
    ) where

import Application.Helper.Xero
import Application.Helper.XeroAdminTypes
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
    Text ->
    IO (Either Text XeroTimesheetPreparationView)
startXeroTimesheetPreparation selectedPeriodKey = do
    maybeConnection <- fetchCurrentVenueXeroConnection
    case maybeConnection of
        Nothing -> pure (Left "Connect Xero before preparing draft timesheets.")
        Just connection -> do
            options <- fetchCurrentVenueXeroTimesheetPeriodOptions (Just connection)
            case List.find (\option -> option.periodOptionKey == selectedPeriodKey) options of
                Nothing -> pure (Left "Choose a Xero pay period before preparing draft timesheets.")
                Just option -> do
                    now <- getCurrentTime
                    run <-
                        newRecord @XeroTimesheetPreparationRun
                            |> set #venueId (unpackId currentVenueId)
                            |> set #xeroConnectionId (unpackId connection.id)
                            |> set #createdByUserId (unpackId currentUser.id)
                            |> set #selectedPayrollCalendarId option.periodOptionPayrollCalendarId
                            |> set #selectedPayrollCalendarName (Just option.periodOptionPayrollCalendarName)
                            |> set #selectedPeriodKey option.periodOptionKey
                            |> set #payPeriodStart option.periodOptionStart
                            |> set #payPeriodEnd option.periodOptionEnd
                            |> set #paymentDate option.periodOptionPaymentDate
                            |> set #xeroPayRunId option.periodOptionXeroPayRunId
                            |> set #xeroPayRunStatus option.periodOptionXeroPayRunStatus
                            |> set #status ("preparing" :: Text)
                            |> set #connectionSnapshotJson (xeroConnectionSnapshotJson connection)
                            |> set #eventsJson (preparationInitialEventsJson now selectedPeriodKey)
                            |> set #startedAt now
                            |> createRecord
                    refreshXeroTimesheetPreparation run.id

refreshXeroTimesheetPreparation ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Id XeroTimesheetPreparationRun ->
    IO (Either Text XeroTimesheetPreparationView)
refreshXeroTimesheetPreparation runId = do
    fetchPreparationRunForCurrentVenue runId >>= \case
        Nothing -> pure (Left "Xero preparation run was not found for this venue.")
        Just run -> do
            connection <- fetch (Id run.xeroConnectionId :: Id XeroConnection)
            if connection.connectionStatus /= "active"
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
                readinessRequest = preparationReadinessRequest run remoteTimesheets
            readiness <- validateXeroTimesheetReadiness readinessRequest
            let readinessView = preparationReadinessView run readiness
            staffRows <- fetchCurrentVenueXeroStaffMappingRows (Just connection)
            approvedStaffIds <- fetchApprovedPreparationStaffIds run
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
            let staffDecisionRows =
                    staffRows
                        |> filter (staffRowHasApprovedEntry approvedStaffIds)
                        |> map (preparationStaffRow decisions)
                payItemRows = map (preparationPayItemRow decisions) (filter activePayItemRequirement payItemRequirements)
                pendingDecisionCount = length (filter pendingManualPreparationDecision decisions)
                manualStaffDecisionCount = length (filter (.preparationStaffNeedsDecision) staffDecisionRows)
                postedBlocked = preparationRunPosted run
                proposedPayItemCount = length (filter ((== "proposed") . (.payItemRequirementStatus) . (.preparationPayItemRequirement)) payItemRows)
                canPreview =
                    connection.connectionStatus == "active"
                        && not postedBlocked
                        && pendingDecisionCount == 0
                        && manualStaffDecisionCount == 0
                        && readiness.xeroTimesheetReady
                canSubmit =
                    connection.connectionStatus == "active"
                        && not postedBlocked
                        && pendingDecisionCount == 0
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
                        , preparationPostedPayRunBlocked = postedBlocked
                        , preparationCanPreview = canPreview
                        , preparationCanSubmit = canSubmit
                        , preparationPreviewRows = maybe [] (\submissionView -> submissionView.timesheetRunPreviewRows) maybeSubmissionView
                        , preparationSubmissionRun = maybeSubmissionRun
                        }

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

approveXeroPreparationPayItems ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Id XeroTimesheetPreparationRun ->
    Maybe Text ->
    IO (Either Text XeroTimesheetPreparationView)
approveXeroPreparationPayItems runId maybeAccountCode = do
    fetchPreparationRunForCurrentVenue runId >>= \case
        Nothing -> pure (Left "Xero preparation run was not found for this venue.")
        Just run -> do
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
                proposedRequirements = filter (\requirement -> requirement.payItemRequirementStatus == "proposed") requirements
            case selectedAccountCode of
                Nothing -> pure (Left "Choose a Xero account code before creating managed pay items.")
                Just accountCode
                    | null proposedRequirements -> reloadAfterLocalDecision run remoteTimesheetsFromRun
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
                                            Right _ -> do
                                                markPayItemCreateDecisionsApplied run proposedRequirements
                                                refreshXeroTimesheetPreparation run.id

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
                                    Right _ -> do
                                        markPayItemCreateDecisionsApplied run proposedRequirements
                                        pure (Right ())

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
                        Just payrollCalendar -> do
                            _ <-
                                run
                                    |> set #selectedPayrollCalendarId payrollCalendar.xeroPayrollCalendarId
                                    |> set #selectedPayrollCalendarName (Just payrollCalendar.name)
                                    |> set #selectedPeriodKey (preparationPeriodKey payrollCalendar.xeroPayrollCalendarId run.payPeriodStart run.payPeriodEnd)
                                    |> set #paymentDate payrollCalendar.paymentDate
                                    |> set #xeroPayRunId Nothing
                                    |> set #xeroPayRunStatus Nothing
                                    |> updateRecord
                            refreshXeroTimesheetPreparation run.id

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
    entries <-
        query @TimesheetEntry
            |> filterWhere (#venueId, run.venueId)
            |> filterWhereGreaterThanOrEqualTo (#workedOn, run.payPeriodStart)
            |> filterWhereLessThanOrEqualTo (#workedOn, run.payPeriodEnd)
            |> filterWhere (#isApproved, True)
            |> filterWhere (#deletedAt, Nothing)
            |> fetch
    pure $
        entries
            |> map (.staffId)
            |> List.nub

fetchPreparationPayItemRequirements ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    XeroTimesheetPreparationRun ->
    XeroConnection ->
    [XeroEarningsRate] ->
    IO [XeroPayItemRequirement]
fetchPreparationPayItemRequirements run connection xeroEarningsRates = do
    requirements <- fetchCurrentVenueXeroPayItemRequirements (Just connection) xeroEarningsRates
    skippedStaffIds <- fetchPreparationNotPaidStaffIds connection
    buckets <- fetchPeriodXeroLocalEarningsBuckets (Id run.venueId) run.payPeriodStart run.payPeriodEnd skippedStaffIds
    let bucketKeys = map (.localBucketKey) buckets
    pure (filter (\requirement -> requirement.payItemRequirementKey `elem` bucketKeys) requirements)

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
    approvedStaffIds <- fetchApprovedPreparationStaffIds run
    connection <- fetch (Id run.xeroConnectionId :: Id XeroConnection)
    staffRows <- fetchCurrentVenueXeroStaffMappingRows (Just connection)
    forM_ (filter (staffRowHasApprovedEntry approvedStaffIds) staffRows) \row ->
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
                    reloadAfterLocalDecision run remoteTimesheetsFromRun

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
    decisions <-
        query @XeroTimesheetPreparationDecision
            |> filterWhere (#xeroTimesheetPreparationRunId, unpackId run.id)
            |> filterWhere (#decisionKind, "pay_item_create" :: Text)
            |> filterWhereIn (#localBucketKey, map Just requirementKeys)
            |> filterWhere (#decisionStatus, "pending" :: Text)
            |> fetch
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
    let readinessRequest = preparationReadinessRequest run remoteTimesheets
    readiness <- validateXeroTimesheetReadiness readinessRequest
    connection <- fetch (Id run.xeroConnectionId :: Id XeroConnection)
    staffRows <- fetchCurrentVenueXeroStaffMappingRows (Just connection)
    approvedStaffIds <- fetchApprovedPreparationStaffIds run
    let pendingDecisionCount = length (filter pendingManualPreparationDecision decisions)
        manualStaffCount = length (filter staffNeedsXeroDecision (filter (staffRowHasApprovedEntry approvedStaffIds) staffRows))
        postedBlocked = preparationRunPosted run
        (status, errorSummary)
            | postedBlocked = ("blocked", Just "The selected Xero pay run is posted. Draft timesheet creation is blocked.")
            | pendingDecisionCount > 0 || manualStaffCount > 0 || readinessHasMissingPayItemAccountCode readiness = ("needs_approval", Nothing)
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
                        , xeroPayRunWhere = Just ("PayrollCalendarID==Guid(\"" <> run.selectedPayrollCalendarId <> "\")")
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
        payRun.xeroPayRunCalendarId == run.selectedPayrollCalendarId
            && payRun.xeroPayRunPeriodStart == run.payPeriodStart
            && payRun.xeroPayRunPeriodEnd == run.payPeriodEnd

preparationReadinessRequest :: XeroTimesheetPreparationRun -> [XeroTimesheetRef] -> XeroTimesheetReadinessRequest
preparationReadinessRequest run remoteTimesheets =
    XeroTimesheetReadinessRequest
        { readinessVenueId = Id run.venueId
        , readinessPayrollCalendarId = Just run.selectedPayrollCalendarId
        , readinessPayrollCalendarName = run.selectedPayrollCalendarName
        , readinessSelectedPeriodKey = Just run.selectedPeriodKey
        , readinessPeriodStart = run.payPeriodStart
        , readinessPeriodEnd = run.payPeriodEnd
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
                            { timesheetIssueSeverity = "blocker"
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
                            && decision.decisionStatus == "pending"
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
    (mapping.mappingStatus == "verified" && isJust mapping.xeroEmployeeId)
        || (mapping.mappingStatus == "not_applicable" && isJust mapping.updatedByUserId)

activePayItemRequirement :: XeroPayItemRequirement -> Bool
activePayItemRequirement requirement =
    requirement.payItemRequirementStatus /= "ignored"

preparationRunPosted :: XeroTimesheetPreparationRun -> Bool
preparationRunPosted run =
    maybe False ((== "posted") . Text.toCaseFold . Text.strip) run.xeroPayRunStatus

preparationPeriodKey :: Text -> Day -> Day -> Text
preparationPeriodKey calendarId periodStart periodEnd =
    calendarId <> ":" <> tshow periodStart <> ":" <> tshow periodEnd

periodOptionFromPreparationRun :: XeroTimesheetPreparationRun -> XeroTimesheetPeriodOption
periodOptionFromPreparationRun run =
    XeroTimesheetPeriodOption
        { periodOptionKey = run.selectedPeriodKey
        , periodOptionPayrollCalendarId = run.selectedPayrollCalendarId
        , periodOptionPayrollCalendarName = fromMaybe run.selectedPayrollCalendarId run.selectedPayrollCalendarName
        , periodOptionStart = run.payPeriodStart
        , periodOptionEnd = run.payPeriodEnd
        , periodOptionPaymentDate = run.paymentDate
        , periodOptionXeroPayRunId = run.xeroPayRunId
        , periodOptionXeroPayRunStatus = run.xeroPayRunStatus
        , periodOptionBlocked = preparationRunPosted run
        , periodOptionBlockReason =
            if preparationRunPosted run
                then Just "This Xero pay run is posted."
                else Nothing
        , periodOptionDerivedFromSyncedXero = isJust run.xeroPayRunId
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
