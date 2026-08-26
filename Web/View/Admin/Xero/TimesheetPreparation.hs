{-# LANGUAGE TypeApplications #-}
{-# OPTIONS_GHC -Werror=incomplete-patterns #-}

module Web.View.Admin.Xero.TimesheetPreparation
    ( renderXeroTimesheetPreparationDialog
    , renderXeroTimesheetPreparationReferenceSyncWaitingDialog
    , renderXeroTimesheetPreparationReferenceSyncWaitFragment
    , renderXeroTimesheetPreparationReferenceSyncWaitFragmentError
    , renderXeroTimesheetPreparationStaffMappingsFragment
    , renderXeroTimesheetPreparationSubmittingDialog
    , renderXeroTimesheetPreparationBlockingDialog
    , renderXeroTimesheetPreparationPeriodSelectionDialog
    , renderXeroTimesheetPreparationStaffSelectionDialog
    , renderXeroTimesheetPreparationStaffSelectionErrorDialog
    ) where

import Application.Helper.FrontendContract.AppShell (AccountCodeField,
                                                     ApproveXeroTimesheetPreparationPayItemsOverlay,
                                                     ContinueXeroTimesheetPreparationStaffOverlay,
                                                     ExpectedActiveCalculationIdField,
                                                     ExpectedApprovalTimestampField,
                                                     PeriodKeyField,
                                                     RefreshXeroProblemTimesheetApprovalOverlay,
                                                     RefreshXeroTimesheetPreparationOverlay,
                                                     RunXeroTimesheetPreparationOverlay,
                                                     RunXeroTimesheetPreparationSubmissionOverlay,
                                                     SelectXeroTimesheetPreparationPeriodOverlay)
import Application.Helper.FrontendContract.AppShell.Request (AppShellActionFields,
                                                             appShellActionFields,
                                                             appShellActionFor,
                                                             noAppShellActionFields)
import Application.Helper.FrontendContract.AppShell.Runtime (AppShellActionRoute (..),
                                                             AppShellFieldValue (..),
                                                             RegisteredAppShellAction,
                                                             appShellActionByMarker,
                                                             renderAppShellActionForm)
import qualified Application.Helper.FrontendContract.Surface.Admin as Surface
import Application.Helper.FrontendContract.Surface.Runtime (renderFrontendSurfaceMount)
import Application.Helper.FrontendContract.Surface.Values
import Application.Helper.View.Overlay
import Application.Helper.XeroAdminTypes
import Application.Xero.ReferenceTrust (XeroReferenceSyncProgressFacts (..))
import Application.Xero.ReferenceTrust.Presentation
import Application.Xero.ReferenceTrust.ReadModel (XeroReferenceTrustState (..))
import Application.Xero.WorkflowState
import Control.Monad (guard)
import qualified Data.List as List
import qualified Data.Text as Text
import Data.Time.Calendar (Day)
import Data.Time.Format (defaultTimeLocale, formatTime)
import Web.Admin.FrontendSurface (AdminVenueScopeValue (..),
                                  adminXeroTimesheetPreparationWaitSurfaceImpl)
import Web.View.Admin.Xero.TimesheetPreparation.Review
import Web.View.Admin.Xero.TimesheetPreparation.StaffMappings
import Web.View.Prelude

xeroPreparationAppShellActionRoute :: Text -> AppShellActionRoute
xeroPreparationAppShellActionRoute actionUrl =
    AppShellActionRoute
        { appShellActionRouteUrl = actionUrl
        , appShellActionRouteFields = []
        , appShellActionRouteCustomHtmx = []
        , appShellActionRouteStandardUrl = Nothing
        , appShellActionRouteExtraAttrs = []
        }

renderXeroPreparationOverlayForm :: (Typeable action, RegisteredAppShellAction action) => AppShellActionFields action -> Text -> [(Text, Text)] -> Html -> Html
renderXeroPreparationOverlayForm fields actionUrl attrs =
    renderAppShellActionForm
        (appShellActionFor fields)
        (xeroPreparationAppShellActionRoute actionUrl)
            { appShellActionRouteExtraAttrs = attrs
            }

renderXeroTimesheetPreparationDialog :: XeroTimesheetPreparationView -> Html
renderXeroTimesheetPreparationDialog view
    | needsStaffStep view = renderXeroTimesheetPreparationStaffStep view
    | needsPeriodStep view = renderXeroTimesheetPreparationPeriodStep view
    | view.preparationState == XeroPreparationSubmitted = renderXeroTimesheetPreparationSubmittedDialog view
    | view.preparationState == XeroPreparationFailed = renderXeroTimesheetPreparationFailureDialog view
    | Just message <- preparationBlockingMessage view = renderXeroTimesheetPreparationBlockingDialog view message
    | needsPayItemStep view = renderXeroTimesheetPreparationPayItemsStep view
    | otherwise = renderXeroTimesheetPreparationSubmittingDialog view



renderXeroTimesheetPreparationReferenceSyncWaitingDialog :: UUID -> XeroReferenceTrustState -> Html
renderXeroTimesheetPreparationReferenceSyncWaitingDialog venueId trustState =
    renderDialogOverlayBodyOnly "Prepare Xero draft timesheets" "" $
        renderFrontendSurfaceMount
            (adminXeroTimesheetPreparationWaitSurfaceImpl AdminVenueScopeValue { adminVenueId = venueId, adminRosterGroupId = Nothing })
            (renderXeroTimesheetPreparationReferenceSyncWaitFragment trustState)

renderXeroTimesheetPreparationReferenceSyncWaitFragment :: XeroReferenceTrustState -> Html
renderXeroTimesheetPreparationReferenceSyncWaitFragment trustState = [hsx|
    <div id={surfaceFragmentTargetId @Surface.AdminXeroSurface @Surface.AdminXeroTimesheetPreparationWaitFragment noSurfaceFields}>
        {renderPreparationReferenceSyncState trustState}
    </div>
|]

renderXeroTimesheetPreparationReferenceSyncWaitFragmentError :: Text -> Html
renderXeroTimesheetPreparationReferenceSyncWaitFragmentError message = [hsx|
    <div id={surfaceFragmentTargetId @Surface.AdminXeroSurface @Surface.AdminXeroTimesheetPreparationWaitFragment noSurfaceFields}>
        {renderPreparationReferenceError message}
    </div>
|]

renderPreparationReferenceSyncState :: XeroReferenceTrustState -> Html
renderPreparationReferenceSyncState trustState =
    case xeroPreparationReferencePresentation trustState.trustDecision of
        XeroPreparationReferenceReady -> [hsx|
            <div class="d-flex align-items-start gap-3">
                <div id="xero-timesheet-preparation-modal-loading-indicator" class="spinner-border text-primary mt-1" role="status" aria-hidden="true"></div>
                <div class="fw-semibold">Opening Xero timesheet preparation</div>
                {renderXeroPreparationReferenceReadyForm}
            </div>
        |]
        XeroPreparationReferenceBlocked message -> renderPreparationReferenceError message
        XeroPreparationReferenceWaiting _ -> [hsx|
            <div class="d-flex align-items-start gap-3" data-xero-reference-sync-waiting="true">
                <div id="xero-timesheet-preparation-modal-loading-indicator" class="spinner-border text-primary mt-1" role="status" aria-hidden="true"></div>
                <div class="d-flex flex-column gap-1">
                    <div class="fw-semibold">Refreshing Xero reference data</div>
                    <div>{xeroReferenceSyncActivityText trustState.syncActivity}</div>
                    {renderPreparationReferenceSyncPhase trustState.syncProgress.progressPhase}
                    {renderPreparationCompletedPayItemsPage trustState.syncProgress.progressCompletedPayItemsPage}
                    <div class="small app-muted">This dialog will continue automatically when trusted reference data is ready.</div>
                </div>
            </div>
        |]

renderXeroPreparationReferenceReadyForm :: Html
renderXeroPreparationReferenceReadyForm =
    renderAppShellActionForm
        (appShellActionByMarker @RunXeroTimesheetPreparationOverlay)
        (xeroPreparationAppShellActionRoute (pathTo RunXeroTimesheetPreparationAction))
        mempty

renderPreparationReferenceError :: Text -> Html
renderPreparationReferenceError message = [hsx|<div class="alert alert-danger mb-0">{message}</div>|]

renderPreparationReferenceSyncPhase :: Maybe Text -> Html
renderPreparationReferenceSyncPhase Nothing = mempty
renderPreparationReferenceSyncPhase (Just phase) = [hsx|<div class="small app-muted">{xeroReferenceSyncPhaseText phase}</div>|]

renderPreparationCompletedPayItemsPage :: Maybe Int -> Html
renderPreparationCompletedPayItemsPage Nothing = mempty
renderPreparationCompletedPayItemsPage (Just page) = [hsx|<div class="small app-muted">Completed page {page}</div>|]

renderXeroTimesheetPreparationStaffStep :: XeroTimesheetPreparationView -> Html
renderXeroTimesheetPreparationStaffStep = renderXeroTimesheetPreparationStaffStepWithError Nothing

renderXeroTimesheetPreparationStaffSelectionDialog :: XeroTimesheetPreparationView -> Html
renderXeroTimesheetPreparationStaffSelectionDialog = renderXeroTimesheetPreparationStaffStep

renderXeroTimesheetPreparationStaffSelectionErrorDialog :: Text -> XeroTimesheetPreparationView -> Html
renderXeroTimesheetPreparationStaffSelectionErrorDialog message =
    renderXeroTimesheetPreparationStaffStepWithError (Just message)

renderXeroTimesheetPreparationStaffStepWithError :: Maybe Text -> XeroTimesheetPreparationView -> Html
renderXeroTimesheetPreparationStaffStepWithError maybeError view =
    renderDialogOverlay DialogOverlayConfig
        { dialogOverlayTitle = preparationDialogTitle view
        , dialogOverlayBody = [hsx|
            <div class="d-flex flex-column gap-3" data-xero-timesheet-preparation-dialog="true">
                {renderStepNotice "Staff matches" "Confirm proposed matches or choose the right Xero employee."}
                {maybe mempty renderStaffSelectionError maybeError}
                {renderConnectionNotice view}
                {renderStaffMappings view}
                {renderXeroPreparationOverlayForm (noAppShellActionFields @ContinueXeroTimesheetPreparationStaffOverlay) (pathTo (ContinueXeroTimesheetPreparationStaffStepAction view.preparationRun.id)) [("id", "xero-preparation-staff-continue-form")] mempty}
            </div>
        |]
        , dialogOverlayStartButtons = []
        , dialogOverlayButtons = closeButton : [continueStaffButton view]
        , dialogOverlayDialogClass = "modal-xl"
        }

renderStaffSelectionError :: Text -> Html
renderStaffSelectionError message = [hsx|<div class="alert alert-danger mb-0">{message}</div>|]

renderXeroTimesheetPreparationPeriodStep :: XeroTimesheetPreparationView -> Html
renderXeroTimesheetPreparationPeriodStep view =
    renderDialogOverlay DialogOverlayConfig
        { dialogOverlayTitle = preparationDialogTitle view
        , dialogOverlayBody = [hsx|
            <div class="d-flex flex-column gap-3" data-xero-timesheet-preparation-dialog="true">
                {renderStepNotice "Pay period" "Choose the Xero payroll period to upload."}
                {renderPeriodSelection view}
                {renderXeroPreparationPeriodForm view}
            </div>
        |]
        , dialogOverlayStartButtons = []
        , dialogOverlayButtons = closeButton : [selectPeriodButton view]
        , dialogOverlayDialogClass = "modal-lg"
        }

renderXeroPreparationPeriodForm :: XeroTimesheetPreparationView -> Html
renderXeroPreparationPeriodForm view =
    renderXeroPreparationOverlayForm
        fields
        (pathTo (SelectXeroTimesheetPreparationPeriodAction view.preparationRun.id))
        [("id", "xero-preparation-period-form")]
        [hsx|
            <select name={surfaceFieldNameFrom @PeriodKeyField fields}
                    id="xero-preparation-period-select"
                    class="form-select"
                    aria-label="Xero pay period"
                    disabled={null view.preparationPeriodOptions}>
                {renderEmptyPreparationPeriodOption view}
                {forEach view.preparationPeriodOptions (renderPreparationPeriodOption (firstSelectablePeriodKey view))}
            </select>
        |]
  where
    fields =
        appShellActionFields @SelectXeroTimesheetPreparationPeriodOverlay
            (surfaceField @PeriodKeyField "")
            noSurfaceFields

renderXeroTimesheetPreparationPayItemsStep :: XeroTimesheetPreparationView -> Html
renderXeroTimesheetPreparationPayItemsStep view =
    renderDialogOverlay DialogOverlayConfig
        { dialogOverlayTitle = preparationDialogTitle view
        , dialogOverlayBody = [hsx|
            <div class="d-flex flex-column gap-3" data-xero-timesheet-preparation-dialog="true">
                {renderStepNotice "Xero account" "Choose the account for new Xero pay items."}
                {renderExclusionWarnings view}
                {renderManagedPayItemBlockers view}
                {renderAccountCodeSelection view}
                {renderXeroPreparationOverlayForm fields (pathTo (ApproveXeroTimesheetPreparationPayItemsAction view.preparationRun.id)) [("id", "xero-preparation-pay-items-form")] mempty}
            </div>
        |]
        , dialogOverlayStartButtons = []
        , dialogOverlayButtons = closeButton : [approvePayItemsButton]
        , dialogOverlayDialogClass = "modal-lg"
        }
  where
    fields =
        appShellActionFields @ApproveXeroTimesheetPreparationPayItemsOverlay
            (surfaceOptionalField @AccountCodeField (selectedAccountCode view))
            noSurfaceFields

renderXeroTimesheetPreparationSubmittingDialog :: XeroTimesheetPreparationView -> Html
renderXeroTimesheetPreparationSubmittingDialog view =
    renderDialogOverlay DialogOverlayConfig
        { dialogOverlayTitle = "Confirm Xero draft timesheets"
        , dialogOverlayBody = [hsx|
            <div class="d-flex flex-column gap-3" data-xero-timesheet-preparation-dialog="true">
                {renderExclusionWarnings view}
                <div>Confirm Xero draft timesheet submission? Existing draft timesheets will be replaced.</div>
                {renderXeroPreparationOverlayForm (noAppShellActionFields @RunXeroTimesheetPreparationSubmissionOverlay) (pathTo (RunXeroTimesheetPreparationSubmissionAction view.preparationRun.id)) [("id", "xero-preparation-reviewed-submit-form")] mempty}
            </div>
        |]
        , dialogOverlayStartButtons = []
        , dialogOverlayButtons = closeButton : [reviewedSubmitButton | view.preparationCanSubmit]
        , dialogOverlayDialogClass = "modal-lg"
        }

renderXeroTimesheetPreparationBlockingDialog :: XeroTimesheetPreparationView -> Text -> Html
renderXeroTimesheetPreparationBlockingDialog view message =
    renderDialogOverlay DialogOverlayConfig
        { dialogOverlayTitle = "Xero submission blocked"
        , dialogOverlayBody = [hsx|
            <div class="d-flex flex-column gap-2">
                {renderPreparationBlockingIssues view message}
            </div>
            {renderXeroPreparationOverlayForm (noAppShellActionFields @RefreshXeroTimesheetPreparationOverlay) (pathTo (ShowXeroTimesheetPreparationSummaryAction view.preparationRun.id)) [("id", "xero-preparation-back-form")] mempty}
        |]
        , dialogOverlayStartButtons = []
        , dialogOverlayButtons = [closeButton, backButton]
        , dialogOverlayDialogClass = "modal-lg"
        }

renderXeroTimesheetPreparationPeriodSelectionDialog :: XeroTimesheetPreparationView -> Html
renderXeroTimesheetPreparationPeriodSelectionDialog = renderXeroTimesheetPreparationPeriodStep

renderXeroTimesheetPreparationFailureDialog :: XeroTimesheetPreparationView -> Html
renderXeroTimesheetPreparationFailureDialog view =
    renderDialogOverlay DialogOverlayConfig
        { dialogOverlayTitle = preparationDialogTitle view
        , dialogOverlayBody = [hsx|
            <div class="d-flex flex-column gap-3">
                <div class="alert alert-danger mb-0">{fromMaybe "Xero draft-timesheet submission did not complete successfully." view.preparationRun.errorSummary}</div>
                {renderPreparationPreview view}
                <div class="small app-muted">Review employee-level submission status below.</div>
            </div>
        |]
        , dialogOverlayStartButtons = []
        , dialogOverlayButtons = [closeButton]
        , dialogOverlayDialogClass = "modal-xl"
        }

renderXeroTimesheetPreparationSubmittedDialog :: XeroTimesheetPreparationView -> Html
renderXeroTimesheetPreparationSubmittedDialog view =
    renderDialogOverlay DialogOverlayConfig
        { dialogOverlayTitle = preparationDialogTitle view
        , dialogOverlayBody = [hsx|
            <div class="d-flex flex-column gap-3">
                <div class="alert alert-success mb-0">Submitted Xero draft timesheets.</div>
                {renderPreparationPreview view}
            </div>
        |]
        , dialogOverlayStartButtons = []
        , dialogOverlayButtons = [closeButton]
        , dialogOverlayDialogClass = "modal-xl"
        }

preparationDialogTitle :: XeroTimesheetPreparationView -> Text
preparationDialogTitle view =
    case view.preparationPeriodOption of
        Nothing -> "Prepare Xero draft timesheets"
        Just option ->
            "Pay period: "
                <> formatDateDisplay option.periodOptionStart
                <> " to "
                <> formatDateDisplay option.periodOptionEnd

renderStepNotice :: Text -> Text -> Html
renderStepNotice label detail = [hsx|
    <div class={appSurfaceClasses "p-3"}>
        <div class="small text-uppercase app-muted fw-semibold">{label}</div>
        <div>{detail}</div>
    </div>
|]

closeButton :: OverlayButton
closeButton = OverlayButton
    { overlayButtonLabel = "Close"
    , overlayButtonClass = "btn btn-outline-secondary"
    , overlayButtonAction = OverlayCloseAction
    }

continueStaffButton :: XeroTimesheetPreparationView -> OverlayButton
continueStaffButton _view = OverlayButton
    { overlayButtonLabel = "Continue"
    , overlayButtonClass = "btn btn-primary"
    , overlayButtonAction = OverlaySubmitFormLoadingAction "xero-preparation-staff-continue-form" "Loading…"
    }

selectPeriodButton :: XeroTimesheetPreparationView -> OverlayButton
selectPeriodButton view = OverlayButton
    { overlayButtonLabel = "Continue"
    , overlayButtonClass = "btn btn-primary"
    , overlayButtonAction = OverlaySubmitFormLoadingAction "xero-preparation-period-form" "Loading…"
    }

approvePayItemsButton :: OverlayButton
approvePayItemsButton = OverlayButton
    { overlayButtonLabel = "Continue"
    , overlayButtonClass = "btn btn-primary"
    , overlayButtonAction = OverlaySubmitFormLoadingAction "xero-preparation-pay-items-form" "Loading…"
    }

backButton :: OverlayButton
backButton = OverlayButton
    { overlayButtonLabel = "Back"
    , overlayButtonClass = "btn btn-outline-primary"
    , overlayButtonAction = OverlaySubmitFormLoadingAction "xero-preparation-back-form" "Loading…"
    }

reviewedSubmitButton :: OverlayButton
reviewedSubmitButton = OverlayButton
    { overlayButtonLabel = "Confirm and submit"
    , overlayButtonClass = "btn btn-primary"
    , overlayButtonAction = OverlaySubmitFormLoadingAction "xero-preparation-reviewed-submit-form" "Loading…"
    }

needsStaffStep :: XeroTimesheetPreparationView -> Bool
needsStaffStep view =
    not (null view.preparationStaffRows)
        && preparationStaffMappingsNeedAttention view.preparationStaffRows

needsPeriodStep :: XeroTimesheetPreparationView -> Bool
needsPeriodStep view = isNothing view.preparationPeriodOption

needsPayItemStep :: XeroTimesheetPreparationView -> Bool
needsPayItemStep view = isJust view.preparationPeriodOption && (any payItemRowNeedsApproval proposedRows || (not (null proposedRows) && isNothing (selectedAccountCode view)))
    where
        proposedRows = proposedPayItemRows view

payItemRowNeedsApproval :: XeroPreparationPayItemRow -> Bool
payItemRowNeedsApproval row =
    maybe True (xeroPreparationDecisionIsPending . (.decisionStatus)) row.preparationPayItemDecision

proposedPayItemRows :: XeroTimesheetPreparationView -> [XeroPreparationPayItemRow]
proposedPayItemRows view =
    view.preparationPayItemRows
        |> filter \row ->
            xeroPayItemRequirementIsProposed row.preparationPayItemRequirement.payItemRequirementStatus

renderPeriodSelection :: XeroTimesheetPreparationView -> Html
renderPeriodSelection view
    | null view.preparationPeriodOptions = [hsx|
        <div class="alert alert-secondary mb-0">
            No eligible Xero pay periods are available yet. Check that staff are matched to synced Xero employees and approved shifts exist for a synced Xero payroll calendar.
        </div>
    |]
    | otherwise = mempty

renderEmptyPreparationPeriodOption :: XeroTimesheetPreparationView -> Html
renderEmptyPreparationPeriodOption view
    | null view.preparationPeriodOptions = [hsx|<option value="">No eligible Xero pay periods available</option>|]
    | otherwise = mempty

firstSelectablePeriodKey :: XeroTimesheetPreparationView -> Maybe Text
firstSelectablePeriodKey view =
    preservedSelection <|> ((.periodOptionKey) <$> List.find (not . (.periodOptionBlocked)) view.preparationPeriodOptions)
  where
    preservedSelection = do
        selected <- view.preparationPeriodOption
        option <- List.find (\candidate -> candidate.periodOptionKey == selected.periodOptionKey && not candidate.periodOptionBlocked) view.preparationPeriodOptions
        pure option.periodOptionKey

renderPreparationPeriodOption :: Maybe Text -> XeroTimesheetPeriodOption -> Html
renderPreparationPeriodOption selectedPeriodKey option = [hsx|
    <option value={option.periodOptionKey}
            disabled={option.periodOptionBlocked}
            selected={selectedPeriodKey == Just option.periodOptionKey}>{preparationPeriodOptionLabel option}</option>
|]

preparationPeriodOptionLabel :: XeroTimesheetPeriodOption -> Text
preparationPeriodOptionLabel option =
    option.periodOptionPayrollCalendarName
        <> " · "
        <> formatDateDisplay option.periodOptionStart
        <> " to "
        <> formatDateDisplay option.periodOptionEnd
        <> maybe "" (\status -> " · " <> Text.toUpper status) option.periodOptionXeroPayRunStatus
        <> preparationPeriodSubmissionStatusLabel option.periodOptionLatestSubmissionStatus
        <> maybe "" (" · blocked: " <>) option.periodOptionBlockReason

preparationPeriodSubmissionStatusLabel :: Maybe XeroSubmissionRunStatusEnum -> Text
preparationPeriodSubmissionStatusLabel = maybe "" xeroSubmissionRunPeriodLabel

renderConnectionNotice :: XeroTimesheetPreparationView -> Html
renderConnectionNotice view
    | view.preparationConnection.connectionStatus == "active" = mempty
    | otherwise = [hsx|
        <div class="alert alert-warning mb-0 d-flex flex-column flex-md-row justify-content-between gap-2 align-items-md-center">
            <div>Reconnect Xero before continuing this preparation run.</div>
            <a href={pathTo StartXeroConnectionAction} class="btn btn-sm btn-warning">Reconnect Xero</a>
        </div>
    |]

renderAccountCodeSelection :: XeroTimesheetPreparationView -> Html
renderAccountCodeSelection view = [hsx|
    <div>
        <label class="form-label small fw-semibold" for="xero-preparation-submit-account-code">Account for new Xero pay items</label>
        <select id="xero-preparation-submit-account-code"
                form="xero-preparation-pay-items-form"
                name={surfaceFieldNameFrom @AccountCodeField fields}
                class="form-select"
                aria-label="Xero account code"
                required={isNothing (selectedAccountCode view)}>
            <option value="">Choose account code</option>
            {forEach view.preparationPayItemAccountCodeOptions (renderAccountCodeOption (fromMaybe "" (selectedAccountCode view)))}
        </select>
    </div>
|]
    where
        fields =
            appShellActionFields @ApproveXeroTimesheetPreparationPayItemsOverlay
                (surfaceOptionalField @AccountCodeField (selectedAccountCode view))
                noSurfaceFields

renderExclusionWarnings :: XeroTimesheetPreparationView -> Html
renderExclusionWarnings view =
    forEach exclusionWarnings \warning -> [hsx|
        <div class="alert alert-warning mb-0">{warning.timesheetIssueMessage}</div>
    |]
  where
    exclusionWarnings =
        view.preparationReadiness.timesheetReadinessWarnings
            |> filter \warning -> warning.timesheetIssueCode `elem` ["entry_not_approved", "imported_pay_item_previous_connection", "staff_mapping_not_verified"]

preparationBlockingMessage :: XeroTimesheetPreparationView -> Maybe Text
preparationBlockingMessage view =
    ((.timesheetIssueMessage) <$> listToMaybe (preparationBlockingIssues view))
        <|> (if view.preparationPostedPayRunBlocked then view.preparationRun.errorSummary else Nothing)

preparationBlockingIssues :: XeroTimesheetPreparationView -> [XeroTimesheetIssueView]
preparationBlockingIssues view =
    view.preparationReadiness.timesheetReadinessBlockers
        |> filter \blocker -> blocker.timesheetIssueCode `notElem` ["managed_pay_item_not_ready", "missing_pay_item_account_code"]

renderPreparationBlockingIssues :: XeroTimesheetPreparationView -> Text -> Html
renderPreparationBlockingIssues view fallbackMessage =
    case preparationBlockingIssues view of
        [] -> [hsx|<div class="alert alert-danger mb-0">{fallbackMessage}</div>|]
        issues -> forEach issues (renderPreparationBlockingIssue view)

renderPreparationBlockingIssue :: XeroTimesheetPreparationView -> XeroTimesheetIssueView -> Html
renderPreparationBlockingIssue view issue = [hsx|
    <div class="alert alert-danger mb-0">
        {renderPreparationBlockingIssueIdentity issue.timesheetIssueTimesheetEntryId}
        <div>{issue.timesheetIssueMessage}</div>
        {renderPreparationBlockingIssueHint issue.timesheetIssueHint}
        {renderProblemApprovalRefresh view issue}
    </div>
|]

renderPreparationBlockingIssueIdentity :: Maybe UUID -> Html
renderPreparationBlockingIssueIdentity = \case
    Nothing -> mempty
    Just entryId -> [hsx|<div class="small fw-semibold">Timesheet {tshow entryId}</div>|]

renderProblemApprovalRefresh :: XeroTimesheetPreparationView -> XeroTimesheetIssueView -> Html
renderProblemApprovalRefresh view issue
    | issue.timesheetIssueCode `notElem` refreshableApprovalBlockerCodes = mempty
    | otherwise = case (issue.timesheetIssueTimesheetEntryId, issue.timesheetIssueExpectedActiveCalculationId, issue.timesheetIssueExpectedApprovalTimestamp) of
        (Just entryId, Just calculationId, Just approvedAt) ->
            let fields =
                    appShellActionFields @RefreshXeroProblemTimesheetApprovalOverlay
                        (surfaceField @ExpectedActiveCalculationIdField calculationId)
                        ( surfaceField @ExpectedApprovalTimestampField (Text.pack (formatTime defaultTimeLocale "%Y-%m-%dT%H:%M:%S%QZ" approvedAt))
                            &: noSurfaceFields
                        )
                route =
                    (xeroPreparationAppShellActionRoute (pathTo (RefreshXeroProblemTimesheetApprovalAction view.preparationRun.id (Id entryId))))
                        { appShellActionRouteFields =
                            [ AppShellFieldValue (surfaceFieldNameFrom @ExpectedActiveCalculationIdField fields, tshow calculationId)
                            , AppShellFieldValue (surfaceFieldNameFrom @ExpectedApprovalTimestampField fields, Text.pack (formatTime defaultTimeLocale "%Y-%m-%dT%H:%M:%S%QZ" approvedAt))
                            ]
                        , appShellActionRouteExtraAttrs = [("class", "mt-2")]
                        }
             in renderAppShellActionForm
                    (appShellActionFor fields)
                    route
                    [hsx|<button type="submit" class="btn btn-sm btn-outline-danger">Refresh approval</button>|]
        _ -> mempty
  where
    refreshableApprovalBlockerCodes =
        [ "wage_publication_failed"
        , "wage_source_policy"
        , "earnings_mapping_not_verified"
        , "managed_pay_item_not_ready"
        ]

renderPreparationBlockingIssueHint :: Maybe Text -> Html
renderPreparationBlockingIssueHint = \case
    Nothing -> mempty
    Just hint -> [hsx|<div class="small mt-1">{hint}</div>|]

renderManagedPayItemBlockers :: XeroTimesheetPreparationView -> Html
renderManagedPayItemBlockers view =
    view.preparationReadiness.timesheetReadinessBlockers
        |> filter ((== "managed_pay_item_not_ready") . (.timesheetIssueCode))
        |> map (renderPreparationBlockingIssue view)
        |> mconcat

renderAccountCodeOption :: Text -> XeroPayItemAccountCodeOption -> Html
renderAccountCodeOption currentSelection option = [hsx|
    <option value={option.accountCodeOptionValue} selected={currentSelection == option.accountCodeOptionValue}>{option.accountCodeOptionLabel}</option>
|]

selectedAccountCode :: XeroTimesheetPreparationView -> Maybe Text
selectedAccountCode view = do
    selection <- view.preparationPayItemAccountCodeSelection
    guard (xeroAccountCodeSelectionIsVerified selection.selectionStatus)
    Text.strip <$> selection.accountCode
