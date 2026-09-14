module Web.Controller.Admin.Xero.Timesheets
    ( applyXeroTimesheetPreparationStaffDecisionAction
    , approveXeroTimesheetPreparationPayItemsAction
    , confirmXeroTimesheetPreparationSubmissionAction
    , continueXeroTimesheetPreparationStaffStepAction
    , openXeroTimesheetPreparationAction
    , refreshXeroProblemTimesheetApprovalAction
    , refreshXeroTimesheetPreparationAction
    , runXeroTimesheetPreparationAction
    , runXeroTimesheetPreparationSubmissionAction
    , showXeroTimesheetPreparationWaitFragmentAction
    , selectXeroTimesheetPreparationPeriodAction
    , showXeroTimesheetPreparationStaffMappingsFragmentAction
    , showXeroTimesheetPreparationSummaryAction
    , submitXeroTimesheetPreparationAction
    ) where

import Application.Error.Boundary (appErrorRequestKind, respondWithAppErrorAndStop, runAppResultBoundary,
                                   withSynchronousAppErrorFallback)
import Application.Error.Domain (projectDomainError)
import Application.Helper.FrontendContract.AppShell (AccountCodeField,
                                                     ApplyXeroTimesheetPreparationStaffDecisionOverlay,
                                                     ApproveXeroTimesheetPreparationPayItemsOverlay,
                                                     ConfirmXeroTimesheetPreparationSubmissionOverlay,
                                                     ContinueXeroTimesheetPreparationStaffOverlay,
                                                     ExpectedActiveCalculationIdField,
                                                     ExpectedApprovalTimestampField,
                                                     OpenXeroTimesheetPreparationOverlay,
                                                     PeriodKeyField,
                                                     RefreshXeroProblemTimesheetApprovalOverlay,
                                                     RefreshXeroTimesheetPreparationOverlay,
                                                     RunXeroTimesheetPreparationOverlay,
                                                     RunXeroTimesheetPreparationSubmissionOverlay,
                                                     SelectXeroTimesheetPreparationPeriodOverlay,
                                                     StaffIdField,
                                                     SubmitXeroTimesheetPreparationOverlay,
                                                     XeroEmployeeSelectionField)
import Application.Helper.FrontendContract.AppShell.Request (AppShellActionFields,
                                                             parseAppShellActionParams)
import qualified Application.Helper.FrontendContract.Surface.Admin as Surface
import qualified Application.Helper.FrontendContract.Surface.Admin.Action as AdminAction
import Application.Helper.FrontendContract.Surface.Request (surfaceRequestFieldErrorsMessage)
import Application.Helper.FrontendContract.Surface.Values (surfaceFieldValue)
import Application.Helper.View (ToastOverlayPosition (ToastBottomCenter),
                                renderToastOverlayHostOob)
import Application.Helper.XeroAdminTypes (XeroTimesheetIssueView (..),
                                          XeroTimesheetPreparationState (XeroPreparationSubmitted),
                                          XeroTimesheetPreparationView (..),
                                          XeroTimesheetReadinessView (..))
import Application.TimesheetApproval (ExpectedApprovalIdentity (..),
                                      TimesheetApprovalError (ApprovalControlStale),
                                      refreshProblemApprovalWithAudit)
import Application.Xero.Admin.ReadModel
import Application.Xero.EmployeeId (XeroEmployeeSelection (..))
import Application.Xero.ReferenceDemand (fetchXeroMissingReferenceDemand)
import Application.Xero.ReferenceTrust.Presentation (XeroPreparationReferencePresentation (..),
                                                     xeroPreparationReferencePresentation)
import Application.Xero.ReferenceTrust.ReadModel (XeroReferenceTrustState (..),
                                                  fetchXeroReferenceTrustState)
import Application.Xero.ReferenceTrust.Service
import Application.Xero.Timesheets.Error (XeroPreparationError (..))
import Application.Xero.Timesheets.Prepare (XeroPreparationOutcome (..), XeroPreparationResult,
                                            XeroPreparationStaffDecision (..),
                                            loadXeroTimesheetPreparationView)
import qualified Data.Text as Text
import qualified Application.Xero.Timesheets.Prepare as Prepare
import Web.Controller.Admin.Xero.Responses
import Web.Controller.Prelude
import Web.View.Admin.Xero.TimesheetPreparation

openXeroTimesheetPreparationAction ::
    (?respond :: Respond, ?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    IO ResponseReceived
openXeroTimesheetPreparationAction =
    case parseAppShellActionParams @OpenXeroTimesheetPreparationOverlay of
        Left errors -> respondWithPreparationDialog (Left (surfaceRequestFieldErrorsMessage errors))
        Right _ -> startOrWaitForXeroTimesheetPreparation

runXeroTimesheetPreparationAction ::
    (?respond :: Respond, ?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    IO ResponseReceived
runXeroTimesheetPreparationAction =
    case parseAppShellActionParams @RunXeroTimesheetPreparationOverlay of
        Left errors -> respondWithPreparationDialog (Left (surfaceRequestFieldErrorsMessage errors))
        Right _ -> observeXeroTimesheetPreparationReferenceState >>= respondToPreparationReferenceState

startOrWaitForXeroTimesheetPreparation ::
    (?respond :: Respond, ?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    IO ResponseReceived
startOrWaitForXeroTimesheetPreparation = do
    maybeConnection <- fetchCurrentVenueXeroConnection
    case maybeConnection of
        Nothing -> respondWithPreparationErrorToast "Connect Xero before preparing draft timesheets."
        Just connection -> do
            now <- getCurrentTime
            missingReferenceDemand <- fetchXeroMissingReferenceDemand connection
            trustState <- requestTrustedXeroReferenceData now (Just currentUser.id) connection missingReferenceDemand
            respondToPreparationReferenceState (Right trustState)

observeXeroTimesheetPreparationReferenceState ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    IO (Either Text XeroReferenceTrustState)
observeXeroTimesheetPreparationReferenceState = do
    fetchCurrentVenueXeroConnection >>= \case
        Nothing -> pure (Left "Connect Xero before preparing draft timesheets.")
        Just connection -> do
            now <- getCurrentTime
            missingReferenceDemand <- fetchXeroMissingReferenceDemand connection
            Right <$> fetchXeroReferenceTrustState now connection missingReferenceDemand

respondToPreparationReferenceState ::
    (?respond :: Respond, ?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Either Text XeroReferenceTrustState ->
    IO ResponseReceived
respondToPreparationReferenceState = \case
    Left message -> respondWithPreparationErrorToast message
    Right trustState ->
        case xeroPreparationReferencePresentation trustState.trustDecision of
            XeroPreparationReferenceReady -> do
                result <- resolvePreparationResult Prepare.startXeroTimesheetPreparation
                respondWithPreparationDialog result
            XeroPreparationReferenceWaiting _ -> respondWithPreparationReferenceWait trustState
            XeroPreparationReferenceBlocked message -> respondWithPreparationErrorToast message

respondWithPreparationReferenceWait ::
    (?respond :: Respond, ?context :: ControllerContext, ?request :: Request) =>
    XeroReferenceTrustState ->
    IO ResponseReceived
respondWithPreparationReferenceWait trustState =
    if isHtmxRequest
        then respondHtml (renderXeroTimesheetPreparationReferenceSyncWaitingDialog (unpackId currentVenueId) trustState)
        else do
            setSuccessMessage "Xero payroll reference data is syncing in the background."
            redirectTo XeroAction

showXeroTimesheetPreparationWaitFragmentAction ::
    (?respond :: Respond, ?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    IO ResponseReceived
showXeroTimesheetPreparationWaitFragmentAction = do
    trustState <- observeXeroTimesheetPreparationReferenceState
    respondHtml $
        either
            renderXeroTimesheetPreparationReferenceSyncWaitFragmentError
            renderXeroTimesheetPreparationReferenceSyncWaitFragment
            trustState

refreshXeroTimesheetPreparationAction ::
    (?respond :: Respond, ?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Id XeroTimesheetPreparationRun ->
    IO ResponseReceived
refreshXeroTimesheetPreparationAction runId =
    case parseAppShellActionParams @RefreshXeroTimesheetPreparationOverlay of
        Left errors -> respondWithPreparationDialog (Left (surfaceRequestFieldErrorsMessage errors))
        Right _ -> do
            result <- resolvePreparationResult (Prepare.refreshXeroTimesheetPreparation runId)
            respondWithPreparationDialog result

refreshXeroProblemTimesheetApprovalAction ::
    (?respond :: Respond, ?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Id XeroTimesheetPreparationRun ->
    Id TimesheetEntry ->
    IO ResponseReceived
refreshXeroProblemTimesheetApprovalAction runId entryId =
    case parseAppShellActionParams @RefreshXeroProblemTimesheetApprovalOverlay of
        Left _ -> rejectStaleControl
        Right fields -> case parseExpectedApprovalIdentity fields of
            Nothing -> rejectStaleControl
            Just expected ->
                resolvePreparationResult (loadXeroTimesheetPreparationView runId) >>= \case
                    Left loadMessage -> respondWithPreparationDialog (Left loadMessage)
                    Right view
                        | refreshControlIsCurrent view entryId expected ->
                            runAppResultBoundary
                                (appErrorRequestKind ?request)
                                (refreshProblemApprovalWithAudit currentUser.id currentVenueId entryId expected currentRequestAuditPayload requestAuditSourceChannel)
                                (const (resolvePreparationResult (loadXeroTimesheetPreparationView runId) >>= respondWithPreparationDialog))
                        | otherwise -> rejectStaleControl
  where
    rejectStaleControl =
        respondWithAppErrorAndStop
            (appErrorRequestKind ?request)
            (projectDomainError ApprovalControlStale)

    parseExpectedApprovalIdentity fields = do
        approvedAt <- parseTimeM True defaultTimeLocale "%Y-%m-%dT%H:%M:%S%QZ" (Text.unpack (surfaceFieldValue @ExpectedApprovalTimestampField fields))
        pure ExpectedApprovalIdentity
            { expectedActiveCalculationId = surfaceFieldValue @ExpectedActiveCalculationIdField fields
            , expectedApprovedAt = approvedAt
            }

    refreshControlIsCurrent view candidateEntryId expected =
        any (issueMatches candidateEntryId expected) view.preparationReadiness.timesheetReadinessBlockers

    issueMatches candidateEntryId expected issue =
        issue.timesheetIssueCode `elem` refreshableApprovalBlockerCodes
            && issue.timesheetIssueTimesheetEntryId == Just (unpackId candidateEntryId)
            && issue.timesheetIssueExpectedActiveCalculationId == Just expected.expectedActiveCalculationId
            && issue.timesheetIssueExpectedApprovalTimestamp == Just expected.expectedApprovedAt

    refreshableApprovalBlockerCodes =
        [ "wage_publication_failed"
        , "wage_source_policy"
        , "earnings_mapping_not_verified"
        , "managed_pay_item_not_ready"
        ]

showXeroTimesheetPreparationStaffMappingsFragmentAction ::
    (?respond :: Respond, ?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Id XeroTimesheetPreparationRun ->
    IO ResponseReceived
showXeroTimesheetPreparationStaffMappingsFragmentAction runId = do
    result <- resolvePreparationResult (loadXeroTimesheetPreparationView runId)
    respondHtml $
        case (AdminAction.parseShowXeroTimesheetPreparationStaffMappingsActionParams, result) of
            (Left errors, _) -> [hsx|<section id="xero-preparation-staff-mappings"><div class="alert alert-danger mb-0">{surfaceRequestFieldErrorsMessage errors}</div></section>|]
            (_, Left message) -> [hsx|<section id="xero-preparation-staff-mappings"><div class="alert alert-danger mb-0">{message}</div></section>|]
            (Right fields, Right view) ->
                renderXeroTimesheetPreparationStaffMappingsFragment
                    (surfaceFieldValue @Surface.ShowMatched fields)
                    (Id <$> surfaceFieldValue @Surface.EditStaffId fields)
                    view

applyXeroTimesheetPreparationStaffDecisionAction ::
    (?respond :: Respond, ?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Id XeroTimesheetPreparationRun ->
    IO ResponseReceived
applyXeroTimesheetPreparationStaffDecisionAction runId =
    case parseAppShellActionParams @ApplyXeroTimesheetPreparationStaffDecisionOverlay of
        Left errors -> respondWithPreparationDialog (Left (surfaceRequestFieldErrorsMessage errors))
        Right fields ->
            case parseStaffDecision fields of
                Left message -> respondWithPreparationDialog (Left message)
                Right decision -> do
                    let staffId = Id (surfaceFieldValue @StaffIdField fields)
                    result <- resolvePreparationResult (Prepare.applyXeroPreparationStaffDecision runId staffId decision)
                    respondWithPreparationStaffSelectionDialog runId result

continueXeroTimesheetPreparationStaffStepAction ::
    (?respond :: Respond, ?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Id XeroTimesheetPreparationRun ->
    IO ResponseReceived
continueXeroTimesheetPreparationStaffStepAction runId =
    case parseAppShellActionParams @ContinueXeroTimesheetPreparationStaffOverlay of
        Left errors -> respondWithPreparationDialog (Left (surfaceRequestFieldErrorsMessage errors))
        Right _ -> do
            result <- resolvePreparationResult (Prepare.approveXeroPreparationStaffStep runId)
            respondWithPreparationDialog result

selectXeroTimesheetPreparationPeriodAction ::
    (?respond :: Respond, ?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Id XeroTimesheetPreparationRun ->
    IO ResponseReceived
selectXeroTimesheetPreparationPeriodAction runId =
    case parseAppShellActionParams @SelectXeroTimesheetPreparationPeriodOverlay of
        Left errors -> respondWithPreparationDialog (Left (surfaceRequestFieldErrorsMessage errors))
        Right fields -> do
            let selectedPeriodKey = Text.strip (surfaceFieldValue @PeriodKeyField fields)
            result <- resolvePreparationResult (Prepare.selectXeroTimesheetPreparationPeriod runId selectedPeriodKey)
            respondWithPreparationPeriodSelection result

approveXeroTimesheetPreparationPayItemsAction ::
    (?respond :: Respond, ?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Id XeroTimesheetPreparationRun ->
    IO ResponseReceived
approveXeroTimesheetPreparationPayItemsAction runId =
    case parseAppShellActionParams @ApproveXeroTimesheetPreparationPayItemsOverlay of
        Left errors -> respondWithPreparationDialog (Left (surfaceRequestFieldErrorsMessage errors))
        Right fields -> do
            let maybeAccountCode = Text.strip <$> surfaceFieldValue @AccountCodeField fields
            result <- resolvePreparationResult (Prepare.approveXeroPreparationPayItemDecisions runId maybeAccountCode)
            respondWithPreparationDialog result

showXeroTimesheetPreparationSummaryAction ::
    (?respond :: Respond, ?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Id XeroTimesheetPreparationRun ->
    IO ResponseReceived
showXeroTimesheetPreparationSummaryAction runId = do
    result <- resolvePreparationResult (loadXeroTimesheetPreparationView runId)
    if isHtmxRequest
        then respondHtml (either (\message -> [hsx|<div class="alert alert-danger mb-0">{message}</div>|]) renderXeroTimesheetPreparationPeriodSelectionDialog result)
        else redirectTo XeroAction

confirmXeroTimesheetPreparationSubmissionAction ::
    (?respond :: Respond, ?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Id XeroTimesheetPreparationRun ->
    IO ResponseReceived
confirmXeroTimesheetPreparationSubmissionAction runId =
    case parseAppShellActionParams @ConfirmXeroTimesheetPreparationSubmissionOverlay of
        Left errors -> respondWithPreparationErrorToast (surfaceRequestFieldErrorsMessage errors)
        Right _ ->
            resolvePreparationResult (loadXeroTimesheetPreparationView runId) >>= respondWithPreparationDialog

runXeroTimesheetPreparationSubmissionAction ::
    (?respond :: Respond, ?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Id XeroTimesheetPreparationRun ->
    IO ResponseReceived
runXeroTimesheetPreparationSubmissionAction runId =
    case parseAppShellActionParams @RunXeroTimesheetPreparationSubmissionOverlay of
        Left errors -> respondWithPreparationDialog (Left (surfaceRequestFieldErrorsMessage errors))
        Right _ -> submitXeroTimesheetPreparation runId Nothing

submitXeroTimesheetPreparationAction ::
    (?respond :: Respond, ?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Id XeroTimesheetPreparationRun ->
    IO ResponseReceived
submitXeroTimesheetPreparationAction runId =
    case parseAppShellActionParams @SubmitXeroTimesheetPreparationOverlay of
        Left errors -> respondWithPreparationDialog (Left (surfaceRequestFieldErrorsMessage errors))
        Right fields ->
            submitXeroTimesheetPreparation runId (Text.strip <$> surfaceFieldValue @AccountCodeField fields)

submitXeroTimesheetPreparation ::
    (?respond :: Respond, ?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Id XeroTimesheetPreparationRun ->
    Maybe Text ->
    IO ResponseReceived
submitXeroTimesheetPreparation runId maybeAccountCode = do
    result <- resolvePreparationResult (Prepare.submitXeroTimesheetPreparation runId maybeAccountCode)
    case result of
        Right view | view.preparationState == XeroPreparationSubmitted ->
            if isHtmxRequest
                then respondWithXeroTimesheetMutationAndCloseDialog (Just (xeroSuccessToast "Submitted Xero draft timesheets."))
                else do
                    setSuccessMessage "Submitted Xero draft timesheets."
                    redirectTo XeroAction
        Left message -> respondWithPreparationBlockingDialog runId message
        Right view -> respondWithPreparationDialog (Right view)

respondWithPreparationStaffSelectionDialog ::
    (?respond :: Respond, ?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Id XeroTimesheetPreparationRun ->
    Either Text XeroTimesheetPreparationView ->
    IO ResponseReceived
respondWithPreparationStaffSelectionDialog runId result =
    if isHtmxRequest
        then case result of
            Right view -> respondHtml (renderXeroTimesheetPreparationStaffSelectionDialog view)
            Left message ->
                resolvePreparationResult (loadXeroTimesheetPreparationView runId) >>= \case
                    Left loadMessage -> respondWithPreparationErrorToast loadMessage
                    Right view -> respondHtml (renderXeroTimesheetPreparationStaffSelectionErrorDialog message view)
        else case result of
            Left message -> setErrorMessage message >> redirectTo XeroAction
            Right _      -> redirectTo XeroAction

respondWithPreparationBlockingDialog ::
    (?respond :: Respond, ?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Id XeroTimesheetPreparationRun ->
    Text ->
    IO ResponseReceived
respondWithPreparationBlockingDialog runId message =
    resolvePreparationResult (loadXeroTimesheetPreparationView runId) >>= \case
        Left loadMessage -> respondWithPreparationErrorToast loadMessage
        Right view ->
            if isHtmxRequest
                then respondHtml (renderXeroTimesheetPreparationBlockingDialog view message)
                else do
                    setErrorMessage message
                    redirectTo XeroAction

resolvePreparationResult ::
    (?respond :: Respond, ?request :: Request) =>
    IO (XeroPreparationResult value) ->
    IO (Either Text value)
resolvePreparationResult operation = do
    outcome <-
        runAppResultBoundary
            (appErrorRequestKind ?request)
            (withSynchronousAppErrorFallback operation (const (pure (Left (projectDomainError XeroPreparationStateUnavailable)))))
            pure
    pure case outcome of
        XeroPreparationOutcomeBlocked message -> Left message
        XeroPreparationOutcomeAvailable value -> Right value

parseStaffDecision :: AppShellActionFields ApplyXeroTimesheetPreparationStaffDecisionOverlay -> Either Text XeroPreparationStaffDecision
parseStaffDecision fields =
    case surfaceFieldValue @XeroEmployeeSelectionField fields of
        XeroEmployeeUnmapped            -> Left "Choose a Xero employee or Not paid through Xero."
        XeroEmployeeNotApplicable       -> Right MarkStaffNotPaidThroughXero
        XeroEmployeeSelected employeeId -> Right (SelectXeroEmployee employeeId)

respondWithPreparationPeriodSelection ::
    (?respond :: Respond, ?context :: ControllerContext, ?request :: Request) =>
    Either Text XeroTimesheetPreparationView ->
    IO ResponseReceived
respondWithPreparationPeriodSelection result =
    case result of
        Right view
            | Just blocker <- find ((== "wage_publication_failed") . (.timesheetIssueCode)) view.preparationReadiness.timesheetReadinessBlockers
            , isHtmxRequest ->
                respondHtml (renderXeroTimesheetPreparationBlockingDialog view blocker.timesheetIssueMessage)
        _ -> respondWithPreparationDialog result

respondWithPreparationDialog ::
    (?respond :: Respond, ?context :: ControllerContext, ?request :: Request) =>
    Either Text XeroTimesheetPreparationView ->
    IO ResponseReceived
respondWithPreparationDialog result =
    if isHtmxRequest
        then do
            case result of
                Left message -> respondWithPreparationErrorToast message
                Right view -> respondHtml (renderXeroTimesheetPreparationDialog view)
        else
            case result of
                Left message -> do
                    setErrorMessage message
                    redirectTo XeroAction
                Right _ -> do
                    setSuccessMessage "Updated Xero timesheet preparation."
                    redirectTo XeroAction

respondWithPreparationErrorToast :: (?context :: ControllerContext, ?request :: Request, ?respond :: Respond) => Text -> IO ResponseReceived
respondWithPreparationErrorToast message = do
    setHeader ("HX-Reswap", "none")
    respondHtml (renderToastOverlayHostOob ToastBottomCenter [xeroErrorToast message])
