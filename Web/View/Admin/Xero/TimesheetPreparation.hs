{-# LANGUAGE TypeApplications #-}
{-# OPTIONS_GHC -Werror=incomplete-patterns #-}

module Web.View.Admin.Xero.TimesheetPreparation
    ( renderXeroProblemTimesheetApprovalRefreshConfirmation
    , renderXeroTimesheetPreparationStaffStep
    , renderXeroTimesheetPreparationPeriodStep
    , renderXeroTimesheetPreparationPayItemsStep
    , renderXeroTimesheetPreparationSubmittedDialog
    , renderXeroTimesheetPreparationFailureDialog
    , needsStaffStep
    , needsPeriodStep
    , needsPayItemStep
    , preparationBlockingMessage
    , renderXeroTimesheetPreparationReferenceSyncWaitingDialog
    , renderXeroTimesheetPreparationReferenceSyncWaitFragment
    , renderXeroTimesheetPreparationReferenceSyncWaitFragmentError
    , renderXeroTimesheetPreparationStaffMappingsFragment
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
                                                     RefreshXeroProblemTimesheetApprovalOverlay,
                                                     RefreshXeroTimesheetPreparationOverlay,
                                                     PeriodKeyField,
                                                     RunXeroTimesheetPreparationOverlay,
                                                     SelectXeroTimesheetPreparationPeriodOverlay)
import Application.Helper.FrontendContract.AppShell.Request (AppShellActionFields,
                                                             appShellActionFields,
                                                             appShellActionFor,
                                                             noAppShellActionFields)
import Application.Helper.FrontendContract.AppShell.Runtime (AppShellActionRoute (..),
                                                             AppShellFieldValue (..),
                                                             RegisteredAppShellAction,
                                                             appShellActionByMarker,
                                                             defaultAppShellActionRoute,
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
import qualified Data.Aeson as Aeson
import qualified Data.List as List
import qualified Data.Text as Text
import Web.Admin.FrontendSurface (AdminVenueScopeValue (..),
                                  adminXeroTimesheetPreparationWaitSurfaceImpl)
import Web.View.Admin.Xero.TimesheetPreparation.Review
import Web.View.Admin.Xero.ShiftSelection (shiftSelectionBackButton)
import Web.View.Admin.Xero.TimesheetPreparation.StaffMappings
import Web.View.Prelude

xeroPreparationAppShellActionRoute :: Text -> AppShellActionRoute
xeroPreparationAppShellActionRoute actionUrl =
    (defaultAppShellActionRoute (actionUrl))

renderXeroPreparationOverlayForm :: (Typeable action, RegisteredAppShellAction action) => AppShellActionFields action -> Text -> [(Text, Text)] -> Html -> Html
renderXeroPreparationOverlayForm fields actionUrl attrs =
    renderAppShellActionForm
        (appShellActionFor fields)
        (xeroPreparationAppShellActionRoute actionUrl)
            { appShellActionRouteExtraAttrs = attrs
            }

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
    renderDialogOverlay (defaultDialogOverlayConfig
            (preparationDialogTitle view)
            [hsx|
            <div class="d-flex flex-column gap-3" data-xero-timesheet-preparation-dialog="true">
                {renderStepNotice "Staff matches" "Confirm proposed matches or choose the right Xero employee."}
                {maybe mempty renderStaffSelectionError maybeError}
                {renderConnectionNotice view}
                {renderStaffMappings view}
                {renderXeroPreparationOverlayForm (noAppShellActionFields @ContinueXeroTimesheetPreparationStaffOverlay) (pathTo (ContinueXeroTimesheetPreparationStaffStepAction view.preparationRun.id)) [("id", "xero-preparation-staff-continue-form")] mempty}
            </div>
        |]
            (closeButton : [continueStaffButton view]))
            { dialogOverlayDialogClass = "modal-xl"
            }

renderStaffSelectionError :: Text -> Html
renderStaffSelectionError message = [hsx|<div class="alert alert-danger mb-0">{message}</div>|]

renderXeroTimesheetPreparationPeriodStep :: XeroTimesheetPreparationView -> Html
renderXeroTimesheetPreparationPeriodStep view =
    renderDialogOverlay (defaultDialogOverlayConfig
            (preparationDialogTitle view)
            [hsx|
            <div class="d-flex flex-column gap-3" data-xero-timesheet-preparation-dialog="true">
                {renderStepNotice "Pay period" "Choose the Xero payroll period to upload."}
                {renderPeriodSelection view}
                {renderXeroPreparationPeriodForm view}
            </div>
        |]
            (closeButton : [selectPeriodButton view]))
            { dialogOverlayDialogClass = "modal-lg"
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
    renderDialogOverlay (defaultDialogOverlayConfig
            (preparationDialogTitle view)
            [hsx|
            <div class="d-flex flex-column gap-3" data-xero-timesheet-preparation-dialog="true">
                {renderStepNotice "Xero account" "Choose the account for new Xero pay items."}
                {renderExclusionWarnings view}
                {renderManagedPayItemBlockers view}
                {renderAccountCodeSelection view}
                {renderXeroPreparationOverlayForm fields (pathTo (ApproveXeroTimesheetPreparationPayItemsAction view.preparationRun.id)) [("id", "xero-preparation-pay-items-form")] mempty}
            </div>
        |]
            [closeButton, approvePayItemsButton])
            { dialogOverlayDialogClass = "modal-lg"
            }
  where
    fields =
        appShellActionFields @ApproveXeroTimesheetPreparationPayItemsOverlay
            (surfaceOptionalField @AccountCodeField (selectedAccountCode view))
            noSurfaceFields

renderXeroTimesheetPreparationBlockingDialog :: XeroTimesheetPreparationView -> Text -> Html
renderXeroTimesheetPreparationBlockingDialog view message =
    renderDialogOverlay (defaultDialogOverlayConfig
            "Xero submission blocked"
            [hsx|
            <div class="d-flex flex-column gap-2">
                {renderPreparationBlockingIssues view message}
            </div>
        |]
            [closeButton, shiftSelectionBackButton view.preparationRun.id])
            { dialogOverlayDialogClass = "modal-lg"
            }

renderXeroTimesheetPreparationPeriodSelectionDialog :: XeroTimesheetPreparationView -> Html
renderXeroTimesheetPreparationPeriodSelectionDialog = renderXeroTimesheetPreparationPeriodStep

renderXeroTimesheetPreparationFailureDialog :: XeroTimesheetPreparationView -> Html
renderXeroTimesheetPreparationFailureDialog view =
    renderDialogOverlay (defaultDialogOverlayConfig
            (preparationDialogTitle view)
            [hsx|
            <div class="d-flex flex-column gap-3">
                <div class="alert alert-danger mb-0">{fromMaybe "Xero draft-timesheet submission did not complete successfully." view.preparationRun.errorSummary}</div>
                {renderPreparationPreview view}
                <div class="small app-muted">Review employee-level submission status below.</div>
            </div>
        |]
            [closeButton])
            { dialogOverlayDialogClass = "modal-xl"
            }

renderXeroTimesheetPreparationSubmittedDialog :: XeroTimesheetPreparationView -> Html
renderXeroTimesheetPreparationSubmittedDialog view =
    renderDialogOverlay (defaultDialogOverlayConfig
            (preparationDialogTitle view)
            [hsx|
            <div class="d-flex flex-column gap-3">
                <div class="alert alert-success mb-0">Submitted Xero draft timesheets.</div>
                {renderPreparationPreview view}
            </div>
        |]
            [closeButton])
            { dialogOverlayDialogClass = "modal-xl"
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
closeButton = dialogOverlayCloseButton "Close"

continueStaffButton :: XeroTimesheetPreparationView -> OverlayButton
continueStaffButton _view = OverlayButton
    { overlayButtonLabel = "Continue"
    , overlayButtonClass = "btn btn-primary"
    , overlayButtonAction = OverlaySubmitFormLoadingAction "xero-preparation-staff-continue-form" "Loading…" True []
    }

selectPeriodButton :: XeroTimesheetPreparationView -> OverlayButton
selectPeriodButton view = OverlayButton
    { overlayButtonLabel = "Continue"
    , overlayButtonClass = "btn btn-primary"
    , overlayButtonAction = OverlaySubmitFormLoadingAction "xero-preparation-period-form" "Loading…" True []
    }

approvePayItemsButton :: OverlayButton
approvePayItemsButton = OverlayButton
    { overlayButtonLabel = "Continue"
    , overlayButtonClass = "btn btn-primary"
    , overlayButtonAction = OverlaySubmitFormLoadingAction "xero-preparation-pay-items-form" "Loading…" True []
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
            No draft pay runs are available. Create a draft pay run in Xero, then reopen Upload timesheets.
        </div>
    |]
    | otherwise = mempty

renderEmptyPreparationPeriodOption :: XeroTimesheetPreparationView -> Html
renderEmptyPreparationPeriodOption view
    | null view.preparationPeriodOptions = [hsx|<option value="">No draft Xero pay runs available</option>|]
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

preparationBlockingIssues :: XeroTimesheetPreparationView -> [XeroTimesheetIssueView]
preparationBlockingIssues view =
    view.preparationReadiness.timesheetReadinessBlockers
        |> filter \blocker ->
            blocker.timesheetIssueCode `notElem` ["managed_pay_item_not_ready", "missing_pay_item_account_code", "missing_approved_entries"]
                && not (blocker.timesheetIssueCode == "selection_changed" && maybe True (== Aeson.Array mempty) view.preparationRun.selectedEntriesJson)
    -- An empty period/selection belongs in the checklist, not the blocked dialog.
    -- Readiness and submission validation still reject an empty upload.

renderPreparationBlockingIssues :: XeroTimesheetPreparationView -> Text -> Html
renderPreparationBlockingIssues view fallbackMessage =
    case preparationBlockingIssues view of
        [] -> [hsx|<div class="alert alert-danger mb-0">{fallbackMessage}</div>|]
        issues -> forEach (distinctBlockingIssues issues) renderPreparationBlockingIssue

-- Show each unresolved cause once, not one recovery card per Timesheet.
distinctBlockingIssues :: [XeroTimesheetIssueView] -> [XeroTimesheetIssueView]
distinctBlockingIssues = List.nubBy (\left right -> left.timesheetIssueCode == right.timesheetIssueCode && left.timesheetIssueMessage == right.timesheetIssueMessage && left.timesheetIssueHint == right.timesheetIssueHint)

renderPreparationBlockingIssue :: XeroTimesheetIssueView -> Html
renderPreparationBlockingIssue issue = [hsx|
    <div class="alert alert-danger mb-0">
        <div>{issue.timesheetIssueMessage}</div>
        {renderPreparationBlockingIssueHint issue.timesheetIssueHint}
    </div>
|]

renderXeroProblemTimesheetApprovalRefreshConfirmation :: (?context :: ControllerContext) => Id XeroTimesheetPreparationRun -> Id TimesheetEntry -> UUID -> UTCTime -> Html
renderXeroProblemTimesheetApprovalRefreshConfirmation runId entryId calculationId approvedAt =
    renderConfirmationDialog
        (defaultConfirmationDialogConfig
            "Refresh approval?"
            [hsx|<p class="mb-0">Refresh this problem Timesheet approval using current pay facts and Xero mappings?</p>|]
            formId
            refreshForm)
            { confirmationDialogApproveLabel = "Refresh approval"
            , confirmationDialogApproveTone = ConfirmationWarning
            , confirmationDialogLoadingLabel = "Refreshing…"
            , confirmationDialogRejectButton = reopenPreparationButton
            }
  where
    formId = "refresh-xero-problem-timesheet-approval-confirmation-form"
    timestamp = Text.pack (formatTime defaultTimeLocale "%Y-%m-%dT%H:%M:%S%QZ" approvedAt)
    fields =
        appShellActionFields @RefreshXeroProblemTimesheetApprovalOverlay
            (surfaceField @ExpectedActiveCalculationIdField calculationId)
            (surfaceField @ExpectedApprovalTimestampField timestamp &: noSurfaceFields)
    refreshForm =
        renderAppShellActionForm
            (appShellActionFor fields)
            ((xeroPreparationAppShellActionRoute (pathTo (RefreshXeroProblemTimesheetApprovalAction runId entryId)))
                { appShellActionRouteFields =
                    [ AppShellFieldValue (surfaceFieldNameFrom @ExpectedActiveCalculationIdField fields, tshow calculationId)
                    , AppShellFieldValue (surfaceFieldNameFrom @ExpectedApprovalTimestampField fields, timestamp)
                    ]
                , appShellActionRouteExtraAttrs = [("id", formId)]
                })
            mempty
    reopenPreparationButton = OverlayButton
        { overlayButtonLabel = "Cancel"
        , overlayButtonClass = "btn btn-outline-secondary"
        , overlayButtonAction = GeneratedDialogFormAction
            (appShellActionByMarker @RefreshXeroTimesheetPreparationOverlay)
            (defaultAppShellActionRoute (pathTo (RefreshXeroTimesheetPreparationAction runId)))
            []
        }

renderPreparationBlockingIssueHint :: Maybe Text -> Html
renderPreparationBlockingIssueHint = \case
    Nothing -> mempty
    Just hint -> [hsx|<div class="small mt-1">{hint}</div>|]

renderManagedPayItemBlockers :: XeroTimesheetPreparationView -> Html
renderManagedPayItemBlockers view =
    view.preparationReadiness.timesheetReadinessBlockers
        |> filter ((== "managed_pay_item_not_ready") . (.timesheetIssueCode))
        |> distinctBlockingIssues
        |> map renderPreparationBlockingIssue
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
