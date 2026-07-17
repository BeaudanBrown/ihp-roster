{-# LANGUAGE TypeApplications #-}

module Web.View.Admin.Xero.TimesheetPreparation
    ( renderXeroTimesheetPreparationDialog
    , renderXeroTimesheetPreparationErrorDialog
    , renderXeroTimesheetPreparationLoadingDialog
    , renderXeroTimesheetPreparationStaffMappingsFragment
    , renderXeroTimesheetPreparationSubmittingDialog
    ) where

import Application.Helper.FrontendContract.AppShell (ApplyXeroTimesheetPreparationStaffDecisionOverlay,
                                                     ApproveXeroTimesheetPreparationPayItemsOverlay,
                                                     ConfirmXeroTimesheetPreparationSubmissionOverlay,
                                                     ContinueXeroTimesheetPreparationStaffOverlay,
                                                     RefreshXeroTimesheetPreparationOverlay,
                                                     RunXeroTimesheetPreparationOverlay,
                                                     RunXeroTimesheetPreparationSubmissionOverlay,
                                                     SelectXeroTimesheetPreparationPeriodOverlay,
                                                     SubmitXeroTimesheetPreparationOverlay)
import Application.Helper.FrontendContract.AppShell.Runtime (AppShellActionRoute (..),
                                                             appShellActionByMarker,
                                                             renderAppShellActionForm)
import Application.Helper.FrontendContract.IR (AppShellActionIR)
import qualified Application.Helper.FrontendContract.Surface.Admin as Surface
import qualified Application.Helper.FrontendContract.Surface.Admin.Action as AdminAction
import Application.Helper.FrontendContract.Surface.Runtime (FrontendSurfaceActionRoute (..),
                                                            renderFrontendSurfaceActionForm)
import Application.Helper.FrontendContract.Surface.Values
import Application.Helper.View.Overlay
import Application.Helper.XeroAdminTypes
import Application.Xero.Admin.ReadModel (xeroEmployeeAvailableForStaff)
import Control.Monad (guard)
import Data.Scientific (FPFormat (Fixed), Scientific, formatScientific)
import qualified Data.Text as Text
import Data.Time.Calendar (Day, diffDays)
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

renderXeroPreparationOverlayForm :: AppShellActionIR -> Text -> [(Text, Text)] -> Html -> Html
renderXeroPreparationOverlayForm action actionUrl attrs =
    renderAppShellActionForm
        action
        (xeroPreparationAppShellActionRoute actionUrl)
            { appShellActionRouteExtraAttrs = attrs
            }

renderXeroTimesheetPreparationDialog :: XeroTimesheetPreparationView -> Html
renderXeroTimesheetPreparationDialog view
    | needsStaffStep view = renderXeroTimesheetPreparationStaffStep view
    | needsPeriodStep view = renderXeroTimesheetPreparationPeriodStep view
    | needsPayItemStep view = renderXeroTimesheetPreparationPayItemsStep view
    | view.preparationState == XeroPreparationSubmitted = renderXeroTimesheetPreparationSubmittedDialog view
    | view.preparationState == XeroPreparationFailed = renderXeroTimesheetPreparationFailureDialog view
    | otherwise = renderXeroTimesheetPreparationSummaryStep view

renderXeroTimesheetPreparationErrorDialog :: Text -> Html
renderXeroTimesheetPreparationErrorDialog message =
    renderDialogOverlay DialogOverlayConfig
        { dialogOverlayTitle = "Prepare Xero draft timesheets"
        , dialogOverlayBody = [hsx|<div class="alert alert-danger mb-0">{message}</div>|]
        , dialogOverlayStartButtons = []
        , dialogOverlayButtons =
            [ OverlayButton
                { overlayButtonLabel = "Close"
                , overlayButtonClass = "btn btn-outline-secondary"
                , overlayButtonAction = OverlayCloseAction
                }
            ]
        , dialogOverlayDialogClass = ""
        }

renderXeroTimesheetPreparationLoadingDialog :: Html
renderXeroTimesheetPreparationLoadingDialog =
    renderDialogOverlayBodyOnly "Prepare Xero draft timesheets" "" [hsx|
        <div class="d-flex align-items-center gap-3" data-xero-timesheet-preparation-loading="true">
            <div id="xero-timesheet-preparation-modal-loading-indicator" class="spinner-border text-primary" role="status" aria-hidden="true"></div>
            <div>
                <div class="fw-semibold">Prepare Xero draft timesheets</div>
            </div>
            {renderXeroPreparationOverlayForm (appShellActionByMarker @RunXeroTimesheetPreparationOverlay) (pathTo RunXeroTimesheetPreparationAction) [] mempty}
        </div>
    |]

renderXeroTimesheetPreparationStaffStep :: XeroTimesheetPreparationView -> Html
renderXeroTimesheetPreparationStaffStep view =
    renderDialogOverlay DialogOverlayConfig
        { dialogOverlayTitle = preparationDialogTitle view
        , dialogOverlayBody = [hsx|
            <div class="d-flex flex-column gap-3" data-xero-timesheet-preparation-dialog="true">
                {renderStepNotice "Step 1 of 3" "Confirm proposed staff matches or choose the right Xero employee before continuing."}
                {renderConnectionNotice view}
                {renderStaffMappings view}
                {renderXeroPreparationOverlayForm (appShellActionByMarker @ContinueXeroTimesheetPreparationStaffOverlay) (pathTo (ContinueXeroTimesheetPreparationStaffStepAction view.preparationRun.id)) [("id", "xero-preparation-staff-continue-form")] mempty}
            </div>
        |]
        , dialogOverlayStartButtons = []
        , dialogOverlayButtons = closeButton : [continueStaffButton view]
        , dialogOverlayDialogClass = "modal-xl"
        }

renderXeroTimesheetPreparationPeriodStep :: XeroTimesheetPreparationView -> Html
renderXeroTimesheetPreparationPeriodStep view =
    renderDialogOverlay DialogOverlayConfig
        { dialogOverlayTitle = preparationDialogTitle view
        , dialogOverlayBody = [hsx|
            <div class="d-flex flex-column gap-3" data-xero-timesheet-preparation-dialog="true">
                {renderStepNotice "Step 2 of 4" "Choose the Xero payroll period after staff Xero mappings have been resolved."}
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
        (appShellActionByMarker @SelectXeroTimesheetPreparationPeriodOverlay)
        (pathTo (SelectXeroTimesheetPreparationPeriodAction view.preparationRun.id))
        [("id", "xero-preparation-period-form")]
        [hsx|
            <select name="periodKey"
                    id="xero-preparation-period-select"
                    class="form-select"
                    aria-label="Xero pay period"
                    disabled={null view.preparationPeriodOptions}>
                {renderEmptyPreparationPeriodOption view}
                {forEach view.preparationPeriodOptions renderPreparationPeriodOption}
            </select>
        |]

renderXeroTimesheetPreparationPayItemsStep :: XeroTimesheetPreparationView -> Html
renderXeroTimesheetPreparationPayItemsStep view =
    renderDialogOverlay DialogOverlayConfig
        { dialogOverlayTitle = preparationDialogTitle view
        , dialogOverlayBody = [hsx|
            <div class="d-flex flex-column gap-3" data-xero-timesheet-preparation-dialog="true">
                {renderStepNotice "Step 2 of 3" "Review the managed pay items Bepis will create during final submission, and choose the Xero account code to use."}
                {renderPayItemDecisions view}
                {renderXeroPreparationOverlayForm (appShellActionByMarker @ApproveXeroTimesheetPreparationPayItemsOverlay) (pathTo (ApproveXeroTimesheetPreparationPayItemsAction view.preparationRun.id)) [("id", "xero-preparation-pay-items-form")] mempty}
            </div>
        |]
        , dialogOverlayStartButtons = []
        , dialogOverlayButtons = closeButton : [approvePayItemsButton]
        , dialogOverlayDialogClass = "modal-xl"
        }

renderXeroTimesheetPreparationSummaryStep :: XeroTimesheetPreparationView -> Html
renderXeroTimesheetPreparationSummaryStep view =
    renderDialogOverlay DialogOverlayConfig
        { dialogOverlayTitle = preparationDialogTitle view
        , dialogOverlayBody = [hsx|
            <div class="d-flex flex-column gap-3" data-xero-timesheet-preparation-dialog="true">
                {renderStepNotice "Step 3 of 3" "Review the draft timesheets Bepis will submit to Xero."}
                {renderFinalSummaryCards view}
                {renderReviewReadiness view}
                {renderReviewSummary view}
                {renderFinalSubmissionCopy}
                {renderXeroPreparationOverlayForm (appShellActionByMarker @ConfirmXeroTimesheetPreparationSubmissionOverlay) (pathTo (ConfirmXeroTimesheetPreparationSubmissionAction view.preparationRun.id)) [("id", "xero-preparation-confirm-submit-form")] mempty}
            </div>
        |]
        , dialogOverlayStartButtons = []
        , dialogOverlayButtons = closeButton : [confirmSubmitButton view | view.preparationCanSubmit]
        , dialogOverlayDialogClass = "modal-xl"
        }

renderXeroTimesheetPreparationSubmittingDialog :: XeroTimesheetPreparationView -> Html
renderXeroTimesheetPreparationSubmittingDialog view =
    renderDialogOverlay DialogOverlayConfig
        { dialogOverlayTitle = preparationDialogTitle view
        , dialogOverlayBody = [hsx|
            <div class="d-flex align-items-center gap-3" data-xero-timesheet-preparation-submitting="true">
                <div id="xero-timesheet-preparation-submitting-indicator" class="spinner-border text-primary" role="status" aria-hidden="true"></div>
                <div>
                    <div class="fw-semibold">Submitting Xero draft timesheets...</div>
                    <div class="small app-muted">Bepis is creating new drafts or updating existing Xero drafts for each employee. This can take a moment.</div>
                </div>
                {renderXeroPreparationOverlayForm (appShellActionByMarker @RunXeroTimesheetPreparationSubmissionOverlay) (pathTo (RunXeroTimesheetPreparationSubmissionAction view.preparationRun.id)) [] mempty}
            </div>
        |]
        , dialogOverlayStartButtons = []
        , dialogOverlayButtons = []
        , dialogOverlayDialogClass = ""
        }

renderXeroTimesheetPreparationFailureDialog :: XeroTimesheetPreparationView -> Html
renderXeroTimesheetPreparationFailureDialog view =
    renderDialogOverlay DialogOverlayConfig
        { dialogOverlayTitle = preparationDialogTitle view
        , dialogOverlayBody = [hsx|
            <div class="d-flex flex-column gap-3">
                <div class="alert alert-danger mb-0">{fromMaybe "Xero draft-timesheet submission did not complete successfully." view.preparationRun.errorSummary}</div>
                {renderPreview view}
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
                {renderPreview view}
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
    { overlayButtonLabel = "Approve"
    , overlayButtonClass = "btn btn-primary"
    , overlayButtonAction = OverlaySubmitFormAction "xero-preparation-staff-continue-form"
    }

selectPeriodButton :: XeroTimesheetPreparationView -> OverlayButton
selectPeriodButton view = OverlayButton
    { overlayButtonLabel = "Continue"
    , overlayButtonClass = "btn btn-primary"
    , overlayButtonAction = OverlaySubmitFormAction "xero-preparation-period-form"
    }

approvePayItemsButton :: OverlayButton
approvePayItemsButton = OverlayButton
    { overlayButtonLabel = "Approve pay items and continue"
    , overlayButtonClass = "btn btn-primary"
    , overlayButtonAction = OverlaySubmitFormAction "xero-preparation-pay-items-form"
    }

confirmSubmitButton :: XeroTimesheetPreparationView -> OverlayButton
confirmSubmitButton _view = OverlayButton
    { overlayButtonLabel = "Submit draft timesheets to Xero"
    , overlayButtonClass = "btn btn-primary"
    , overlayButtonAction = OverlaySubmitFormAction "xero-preparation-confirm-submit-form"
    }

needsStaffStep :: XeroTimesheetPreparationView -> Bool
needsStaffStep view =
    not (null view.preparationStaffRows)
        && any staffRowNeedsAttention view.preparationStaffRows

needsPeriodStep :: XeroTimesheetPreparationView -> Bool
needsPeriodStep view = isNothing view.preparationPeriodOption

needsPayItemStep :: XeroTimesheetPreparationView -> Bool
needsPayItemStep view = isJust view.preparationPeriodOption && (any payItemRowNeedsApproval proposedRows || (not (null proposedRows) && isNothing (selectedAccountCode view)))
    where
        proposedRows = proposedPayItemRows view

payItemRowNeedsApproval :: XeroPreparationPayItemRow -> Bool
payItemRowNeedsApproval row =
    maybe True ((== "pending") . (.decisionStatus)) row.preparationPayItemDecision

proposedPayItemRows :: XeroTimesheetPreparationView -> [XeroPreparationPayItemRow]
proposedPayItemRows view =
    view.preparationPayItemRows
        |> filter \row ->
            row.preparationPayItemRequirement.payItemRequirementStatus == "proposed"

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
    | otherwise = [hsx|<option value="">Choose a Xero pay period</option>|]

renderPreparationPeriodOption :: XeroTimesheetPeriodOption -> Html
renderPreparationPeriodOption option = [hsx|
    <option value={option.periodOptionKey} disabled={option.periodOptionBlocked}>{preparationPeriodOptionLabel option}</option>
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

preparationPeriodSubmissionStatusLabel :: Maybe Text -> Text
preparationPeriodSubmissionStatusLabel status =
    case Text.toCaseFold . Text.strip <$> status of
        Just "submitted"        -> " · submitted already"
        Just "partially_failed" -> " · partially submitted"
        Just "failed"           -> " · failed previously"
        Just "previewed"        -> " · previewed previously"
        Just "pending"          -> " · submission pending"
        Just "blocked"          -> " · blocked previously"
        _                       -> ""

renderFinalSummaryCards :: XeroTimesheetPreparationView -> Html
renderFinalSummaryCards view = [hsx|
    <div class="row g-2">
        {renderSummaryCard "Employees" (tshow (length view.preparationReviewRows))}
        {renderSummaryCard "Approved shifts" (tshow (sum (map (.reviewRowEntryCount) view.preparationReviewRows)))}
        {renderSummaryCard "Total hours" (formatUnits (sum (map (.reviewRowTotalUnits) view.preparationReviewRows)))}
        {renderSummaryCard "Estimated wages" (formatMoney (sum (map (.reviewRowTotalAmount) view.preparationReviewRows)))}
    </div>
|]

renderSummaryCard :: Text -> Text -> Html
renderSummaryCard label value = [hsx|
    <div class="col-6 col-lg-3">
        <div class={appSurfaceClasses "p-3 h-100"}>
            <div class="small app-muted">{label}</div>
            <div class="fs-5 fw-semibold">{value}</div>
        </div>
    </div>
|]

renderReviewSummary :: XeroTimesheetPreparationView -> Html
renderReviewSummary view
    | null view.preparationReviewRows = [hsx|
        <section>
            <h6 class="mb-2">Timesheet summary</h6>
            <div class={appSurfaceClasses "p-3 small app-muted"}>
                No Xero-paid staff with approved shifts were found for this pay period.
            </div>
        </section>
    |]
    | otherwise = [hsx|
        <section>
            <h6 class="mb-2">Timesheet summary</h6>
            <div class="table-responsive">
                <table class="table table-sm align-middle mb-0">
                    <thead>
                        <tr>
                            <th>Staff member</th>
                            <th class="text-end">Approved shifts</th>
                            <th class="text-end">Hours</th>
                            <th class="text-end">Estimated wages</th>
                        </tr>
                    </thead>
                    <tbody>{forEach view.preparationReviewRows renderReviewRow}</tbody>
                </table>
            </div>
        </section>
    |]

renderReviewRow :: XeroPreparationReviewRow -> Html
renderReviewRow row = [hsx|
    <tr>
        <td><div class="fw-semibold">{staffName row.reviewRowStaff}</div></td>
        <td class="text-end">{tshow row.reviewRowEntryCount}</td>
        <td class="text-end">{formatUnits row.reviewRowTotalUnits}</td>
        <td class="text-end">{formatMoney row.reviewRowTotalAmount}</td>
    </tr>
|]

payPeriodDays :: XeroTimesheetPreparationView -> Int
payPeriodDays view =
    case view.preparationPeriodOption of
        Nothing -> 0
        Just option -> fromIntegral (diffDays option.periodOptionEnd option.periodOptionStart) + 1

renderFinalSubmissionCopy :: Html
renderFinalSubmissionCopy = mempty

renderRunSummary :: XeroTimesheetPreparationView -> Html
renderRunSummary view = [hsx|
    <div>
        <div class="fw-semibold">Pay Period</div>
        <div class="small app-muted">
            {renderRunPeriod view}
            {renderPaymentDate view.preparationRun.paymentDate}
        </div>
    </div>
|]

renderRunPeriod :: XeroTimesheetPreparationView -> Html
renderRunPeriod view =
    case view.preparationPeriodOption of
        Nothing -> [hsx|Not selected yet|]
        Just option -> [hsx|{formatDateDisplay option.periodOptionStart} to {formatDateDisplay option.periodOptionEnd}|]

renderPaymentDate :: Maybe Day -> Html
renderPaymentDate Nothing = mempty
renderPaymentDate (Just paymentDate) = [hsx|<span> · payment {formatDateDisplay paymentDate}</span>|]

renderWorkflowProgress :: XeroTimesheetPreparationView -> Html
renderWorkflowProgress view = [hsx|
    <div class={appSurfaceClasses "p-3"}>
        <div class="d-flex flex-column flex-lg-row justify-content-between gap-3">
            <div>
                <div class="fw-semibold">{workflowHeadline view}</div>
                <div class="small app-muted">{workflowDetail view}</div>
            </div>
            <div class="d-flex flex-wrap gap-2 align-items-start">
                <span class="badge app-status-badge app-status-neutral">{tshow view.preparationPendingDecisionCount} decisions</span>
                <span class="badge app-status-badge app-status-neutral">{tshow view.preparationReadiness.timesheetReadinessEntryCount} entries</span>
                <span class="badge app-status-badge app-status-neutral">{tshow view.preparationReadiness.timesheetReadinessStaffCount} staff</span>
            </div>
        </div>
    </div>
|]

workflowHeadline :: XeroTimesheetPreparationView -> Text
workflowHeadline view =
    case view.preparationState of
        XeroPreparationNeedsReconnect -> "Reconnect Xero to continue"
        XeroPreparationPreparing -> "Checking Xero readiness"
        XeroPreparationNeedsDecision -> "Resolve the next preparation decision"
        XeroPreparationBlocked -> "Preparation is blocked"
        XeroPreparationReadyForPreview -> "Ready to submit draft timesheets"
        XeroPreparationPreviewed -> "Draft timesheet preview is ready"
        XeroPreparationSubmitted -> "Draft timesheets submitted"
        XeroPreparationFailed -> "Preparation needs attention"

workflowDetail :: XeroTimesheetPreparationView -> Text
workflowDetail view =
    case view.preparationState of
        XeroPreparationNeedsReconnect -> "OAuth reconnect opens as a normal Xero navigation, then return here to continue."
        XeroPreparationPreparing -> "Connection, reference data, pay runs, duplicate timesheets, mappings, pay items, and readiness checks are run automatically."
        XeroPreparationNeedsDecision -> "Choose Xero employees, mark staff as not paid through Xero, or choose the account code needed for automatic pay item creation."
        XeroPreparationBlocked -> "Resolve the blockers shown in readiness validation before submitting."
        XeroPreparationReadyForPreview -> "All required decisions are resolved. Submit will create any missing managed pay items, then create new Xero drafts or update existing Xero drafts."
        XeroPreparationPreviewed -> "Review the preview rows, then submit only when you are ready to create or update Xero draft timesheets."
        XeroPreparationSubmitted -> "The latest submission status is recorded below."
        XeroPreparationFailed -> "Refresh checks or close the dialog and retry after fixing the reported issue."

renderConnectionNotice :: XeroTimesheetPreparationView -> Html
renderConnectionNotice view
    | view.preparationConnection.connectionStatus == "active" = mempty
    | otherwise = [hsx|
        <div class="alert alert-warning mb-0 d-flex flex-column flex-md-row justify-content-between gap-2 align-items-md-center">
            <div>Reconnect Xero before continuing this preparation run.</div>
            <a href={pathTo StartXeroConnectionAction} class="btn btn-sm btn-warning">Reconnect Xero</a>
        </div>
    |]

renderStaffMappings :: XeroTimesheetPreparationView -> Html
renderStaffMappings =
    renderXeroTimesheetPreparationStaffMappingsFragment False Nothing

renderXeroTimesheetPreparationStaffMappingsFragment :: Bool -> Maybe (Id Staff) -> XeroTimesheetPreparationView -> Html
renderXeroTimesheetPreparationStaffMappingsFragment _showMatched editStaffId view
    | null visibleRows = mempty
    | otherwise = [hsx|
        <section id="xero-preparation-staff-mappings">
            <div class="d-flex align-items-center justify-content-between gap-2 mb-2">
                <h6 class="mb-0">Staff mappings</h6>
            </div>
            <div class="table-responsive">
                <table class="table table-sm align-middle mb-0 xero-staff-mappings-table">
                    <colgroup>
                        <col class="xero-staff-mappings-col-staff" />
                        <col class="xero-staff-mappings-col-email" />
                        <col class="xero-staff-mappings-col-employee" />
                    </colgroup>
                    <thead>
                        <tr>
                            <th>Staff</th>
                            <th>Email</th>
                            <th>Xero employee</th>
                        </tr>
                    </thead>
                    <tbody>{forEach visibleRows (renderStaffMappingRow view editStaffId)}</tbody>
                </table>
            </div>
        </section>
    |]
    where
        visibleRows = filter rowVisible view.preparationStaffRows
        rowVisible row =
            staffRowNeedsAttention row
                || editStaffId == Just row.preparationStaffMappingRow.mappingRowStaff.id

renderStaffMappingRow :: XeroTimesheetPreparationView -> Maybe (Id Staff) -> XeroPreparationStaffRow -> Html
renderStaffMappingRow view editStaffId row = [hsx|
    <tr class={classes [("xero-staff-mapping-row-matched", staffRowIsConfirmed row)]}
        data-xero-staff-mapping-status={staffMappingStatus row}>
        <td>
            <div class="fw-semibold text-truncate">{staffName staff}</div>
        </td>
        <td class="small text-truncate">{staffSecondaryLabel row}</td>
        <td>{renderStaffEmployeeCell view editStaffId row}</td>
    </tr>
|]
    where
        staff = row.preparationStaffMappingRow.mappingRowStaff

renderStaffEmployeeCell :: XeroTimesheetPreparationView -> Maybe (Id Staff) -> XeroPreparationStaffRow -> Html
renderStaffEmployeeCell view editStaffId row
    | staffRowNeedsInteractiveSelection editStaffId row = renderStaffEmployeeSelectionForm view row
    | otherwise = renderStaffEmployeeReadOnly view row

staffRowNeedsInteractiveSelection :: Maybe (Id Staff) -> XeroPreparationStaffRow -> Bool
staffRowNeedsInteractiveSelection editStaffId row =
    editStaffId == Just row.preparationStaffMappingRow.mappingRowStaff.id
        || (row.preparationStaffNeedsDecision && not (staffRowHasPendingAutoMatch row))
        || Text.null (currentStaffEmployeeSelection row)

renderStaffEmployeeReadOnly :: XeroTimesheetPreparationView -> XeroPreparationStaffRow -> Html
renderStaffEmployeeReadOnly view row = [hsx|
    <div class="d-flex align-items-center justify-content-between gap-2">
        <div>
            <div class="fw-semibold small">{staffEmployeeDisplay row}</div>
            <div class="small app-muted">{staffEmployeeStatusLabel row}</div>
        </div>
        {renderStaffEmployeeEditForm view row}
    </div>
|]

renderStaffEmployeeEditForm :: XeroTimesheetPreparationView -> XeroPreparationStaffRow -> Html
renderStaffEmployeeEditForm view row =
    renderFrontendSurfaceActionForm
        (AdminAction.showXeroTimesheetPreparationStaffMappingsAction fields)
        FrontendSurfaceActionRoute
            { actionRouteUrl = pathTo (ShowXeroTimesheetPreparationStaffMappingsFragmentAction view.preparationRun.id)
            , actionRouteCustomHtmx = []
            , actionRouteStandardUrl = Just (pathTo (ShowXeroTimesheetPreparationStaffMappingsFragmentAction view.preparationRun.id))
            , actionRouteExtraAttrs = []
            }
        [hsx|
            <input type="hidden" name={surfaceFieldNameFrom @Surface.ShowMatched fields} value="true" />
            <input type="hidden" name={surfaceFieldNameFrom @Surface.EditStaffId fields} value={tshow row.preparationStaffMappingRow.mappingRowStaff.id} />
            <button type="submit" class="btn btn-sm btn-outline-secondary">Edit</button>
        |]
  where
    fields = AdminAction.showXeroTimesheetPreparationStaffMappingsActionFields True (Just (unpackId row.preparationStaffMappingRow.mappingRowStaff.id))

staffEmployeeDisplay :: XeroPreparationStaffRow -> Text
staffEmployeeDisplay row
    | currentStaffEmployeeSelection row == "not_applicable" = "Not paid through Xero"
    | otherwise =
        fromMaybe (currentStaffEmployeeSelection row) $
            decisionEmployeeName <|> mappingEmployeeName
    where
        decisionEmployeeName = row.preparationStaffDecision >>= (.xeroEmployeeName)
        mappingEmployeeName = row.preparationStaffMappingRow.mappingRowMapping.xeroEmployeeName

staffEmployeeStatusLabel :: XeroPreparationStaffRow -> Text
staffEmployeeStatusLabel row
    | staffRowHasPendingAutoMatch row = "Suggested match — click Approve to confirm"
    | staffRowIsConfirmed row = "Approved"
    | otherwise = "Selected"

renderStaffEmployeeSelectionForm :: XeroTimesheetPreparationView -> XeroPreparationStaffRow -> Html
renderStaffEmployeeSelectionForm view row =
    renderXeroPreparationOverlayForm
        (appShellActionByMarker @ApplyXeroTimesheetPreparationStaffDecisionOverlay)
        (pathTo (ApplyXeroTimesheetPreparationStaffDecisionAction view.preparationRun.id))
        [ ("class", "d-inline-flex gap-2")

        ]
        [hsx|
            <input type="hidden" name="staffId" value={tshow staff.id} />
            <input type="hidden" name="decision" value="select_employee" />
            <select name="xeroEmployeeSelection" class="form-select form-select-sm w-auto xero-employee-selection" aria-label={"Xero employee for " <> staffName staff}>
                {forEach selectableEmployees (renderEmployeeOption currentSelection)}
                <option value="not_applicable" selected={currentSelection == "not_applicable" || (Text.null currentSelection && null selectableEmployees)}>Not paid through Xero</option>
            </select>
            {renderStaffSelectionSubmitButton row currentSelection}
        |]
    where
        staff = row.preparationStaffMappingRow.mappingRowStaff
        currentSelection = currentStaffEmployeeSelection row
        selectableEmployees = selectableEmployeesForStaffDecision view row

renderEmployeeOption :: Text -> XeroEmployee -> Html
renderEmployeeOption currentSelection employee = [hsx|
    <option value={employee.xeroEmployeeId} selected={currentSelection == employee.xeroEmployeeId}>{xeroEmployeeLabel employee}</option>
|]

currentStaffEmployeeSelection :: XeroPreparationStaffRow -> Text
currentStaffEmployeeSelection row =
    fromMaybe "" $
        pendingDecisionSelection
            <|> verifiedMappingSelection
            <|> notApplicableSelection
    where
        mapping = row.preparationStaffMappingRow.mappingRowMapping
        pendingDecisionSelection = do
            decision <- row.preparationStaffDecision
            case decision.decisionKind of
                "staff_not_paid" -> Just "not_applicable"
                _                -> decision.xeroEmployeeId
        verifiedMappingSelection = do
            guard (mapping.mappingStatus == "verified")
            mapping.xeroEmployeeId
        notApplicableSelection = do
            guard (mapping.mappingStatus == "not_applicable" && isJust mapping.updatedByUserId)
            Just "not_applicable"

selectedStaffEmployeeId :: XeroPreparationStaffRow -> Maybe Text
selectedStaffEmployeeId row = do
    let selection = currentStaffEmployeeSelection row
    guard (selection /= "" && selection /= "not_applicable")
    Just selection

selectableEmployeesForStaffDecision :: XeroTimesheetPreparationView -> XeroPreparationStaffRow -> [XeroEmployee]
selectableEmployeesForStaffDecision view row =
    filter employeeAvailable view.preparationEmployees
    where
        staff = row.preparationStaffMappingRow.mappingRowStaff
        currentSelection = currentStaffEmployeeSelection row
        mappingRows = map (.preparationStaffMappingRow) view.preparationStaffRows
        selectedByOtherRows =
            view.preparationStaffRows
                |> filter (\otherRow -> otherRow.preparationStaffMappingRow.mappingRowStaff.id /= staff.id)
                |> mapMaybe selectedStaffEmployeeId
        employeeAvailable employee =
            employee.xeroEmployeeId == currentSelection
                || ( xeroEmployeeAvailableForStaff staff mappingRows employee
                        && employee.xeroEmployeeId `notElem` selectedByOtherRows
                   )

xeroEmployeeLabel :: XeroEmployee -> Text
xeroEmployeeLabel employee =
    employee.displayName

renderStaffOutcomes :: XeroTimesheetPreparationView -> Html
renderStaffOutcomes view
    | null outcomeRows = mempty
    | otherwise = [hsx|
        <section>
            <div class="d-flex align-items-center justify-content-between gap-2 mb-2">
                <h6 class="mb-0">Staff outcomes</h6>
                <span class="small app-muted">Who will be included or excluded</span>
            </div>
            <div class="table-responsive">
                <table class="table table-sm align-middle mb-0">
                    <thead>
                        <tr>
                            <th>Staff</th>
                            <th>Outcome</th>
                            <th>Reason</th>
                        </tr>
                    </thead>
                    <tbody>{forEach outcomeRows renderStaffOutcomeRow}</tbody>
                </table>
            </div>
        </section>
    |]
    where
        outcomeRows =
            view.preparationStaffRows
                |> filter (not . (.preparationStaffNeedsDecision))

renderStaffOutcomeRow :: XeroPreparationStaffRow -> Html
renderStaffOutcomeRow row = [hsx|
    <tr>
        <td>
            <div class="fw-semibold">{staffName staff}</div>
            <div class="small app-muted">{staffSecondaryLabel row}</div>
        </td>
        <td>{renderStatusBadge (staffOutcomeStatus row)}</td>
        <td class="small">{staffOutcomeReason row}</td>
    </tr>
|]
    where
        staff = row.preparationStaffMappingRow.mappingRowStaff

staffOutcomeStatus :: XeroPreparationStaffRow -> Text
staffOutcomeStatus row
    | staffMarkedNotPaidThroughXero row = "not paid"
    | staffHasVerifiedXeroEmployee row = "included"
    | otherwise = "excluded"

staffOutcomeReason :: XeroPreparationStaffRow -> Text
staffOutcomeReason row
    | staffMarkedNotPaidThroughXero row = "Persistently marked as not paid through Xero."
    | staffHasVerifiedXeroEmployee row = "Mapped to Xero employee " <> fromMaybe "" row.preparationStaffMappingRow.mappingRowMapping.xeroEmployeeName <> "."
    | otherwise = "No Xero employee is selected for this staff member."

renderStaffSelectionSubmitButton :: XeroPreparationStaffRow -> Text -> Html
renderStaffSelectionSubmitButton row currentSelection
    | staffRowHasPendingAutoMatch row = [hsx|<button class="btn btn-sm btn-primary" type="submit">Confirm match</button>|]
    | Text.null currentSelection = [hsx|<button class="btn btn-sm btn-primary" type="submit">Save</button>|]
    | otherwise = mempty

staffRowIsConfirmed :: XeroPreparationStaffRow -> Bool
staffRowIsConfirmed row =
    staffHasVerifiedXeroEmployee row || staffMarkedNotPaidThroughXero row

staffRowHasPendingAutoMatch :: XeroPreparationStaffRow -> Bool
staffRowHasPendingAutoMatch row =
    maybe False isPendingAutoMatch row.preparationStaffDecision
    where
        isPendingAutoMatch decision =
            decision.decisionKind == "staff_auto_match" && decision.decisionStatus == "pending"

staffRowNeedsAttention :: XeroPreparationStaffRow -> Bool
staffRowNeedsAttention row =
    row.preparationStaffNeedsDecision
        || maybe False ((== "pending") . (.decisionStatus)) row.preparationStaffDecision
        || Text.null (currentStaffEmployeeSelection row)

staffMappingStatus :: XeroPreparationStaffRow -> Text
staffMappingStatus row
    | staffMarkedNotPaidThroughXero row = "not_applicable"
    | staffHasVerifiedXeroEmployee row = "verified"
    | otherwise = "unmapped"

staffHasVerifiedXeroEmployee :: XeroPreparationStaffRow -> Bool
staffHasVerifiedXeroEmployee row =
    row.preparationStaffMappingRow.mappingRowMapping.mappingStatus == "verified"
        && isJust row.preparationStaffMappingRow.mappingRowMapping.xeroEmployeeId

staffMarkedNotPaidThroughXero :: XeroPreparationStaffRow -> Bool
staffMarkedNotPaidThroughXero row =
    row.preparationStaffMappingRow.mappingRowMapping.mappingStatus == "not_applicable"
        && isJust row.preparationStaffMappingRow.mappingRowMapping.updatedByUserId

renderPayItemDecisions :: XeroTimesheetPreparationView -> Html
renderPayItemDecisions view
    | null proposedRows = mempty
    | otherwise = [hsx|
        <section>
            <div class="d-flex align-items-center justify-content-between gap-2 mb-2">
                <h6 class="mb-0">Managed pay items</h6>
            </div>
            <div class={appSurfaceClasses "p-3"}>
                <div class="table-responsive mb-3">
                    <table class="table table-sm align-middle mb-0">
                        <thead>
                            <tr>
                                <th>Pay item</th>
                                <th>Value</th>
                                <th>Status</th>
                            </tr>
                        </thead>
                        <tbody>{forEach proposedRows renderPayItemCreationRow}</tbody>
                    </table>
                </div>
                <label class="form-label small fw-semibold" for="xero-preparation-submit-account-code">Account code for created pay items</label>
                <select id="xero-preparation-submit-account-code"
                        form="xero-preparation-pay-items-form"
                        name="accountCode"
                        class="form-select form-select-sm"
                        aria-label="Xero account code"
                        required={isNothing (selectedAccountCode view)}>
                    <option value="">Choose account code</option>
                    {forEach view.preparationPayItemAccountCodeOptions (renderAccountCodeOption (fromMaybe "" (selectedAccountCode view)))}
                </select>
            </div>
        </section>
    |]
    where
        proposedRows =
            view.preparationPayItemRows
                |> filter \row ->
                    row.preparationPayItemRequirement.payItemRequirementStatus == "proposed"

renderPayItemCreationRow :: XeroPreparationPayItemRow -> Html
renderPayItemCreationRow row = [hsx|
    <tr>
        <td>{requirement.payItemRequirementName}</td>
        <td>{fromMaybe "per employee ordinary rate" requirement.payItemRequirementValue}</td>
        <td>{renderStatusBadge "will be created"}</td>
    </tr>
|]
    where
        requirement = row.preparationPayItemRequirement

renderAccountCodeOption :: Text -> XeroPayItemAccountCodeOption -> Html
renderAccountCodeOption currentSelection option = [hsx|
    <option value={option.accountCodeOptionValue} selected={currentSelection == option.accountCodeOptionValue}>{option.accountCodeOptionLabel}</option>
|]

selectedAccountCode :: XeroTimesheetPreparationView -> Maybe Text
selectedAccountCode view = do
    selection <- view.preparationPayItemAccountCodeSelection
    guard (selection.selectionStatus == "verified")
    Text.strip <$> selection.accountCode

renderReadiness :: XeroTimesheetReadinessView -> Html
renderReadiness readiness = [hsx|
    <section>
        <div class="d-flex align-items-center justify-content-between gap-2 mb-2">
            <h6 class="mb-0">Readiness validation</h6>
            {renderStatusBadge (if readiness.timesheetReadinessReady then "ready" else "blocked")}
        </div>
        {renderIssues "Blockers" readiness.timesheetReadinessBlockers}
        {renderIssues "Warnings" readiness.timesheetReadinessWarnings}
    </section>
|]

renderReviewReadiness :: XeroTimesheetPreparationView -> Html
renderReviewReadiness view
    | null actionableBlockers = mempty
    | otherwise = [hsx|
        <section>
            <h6 class="mb-2">Needs attention</h6>
            {renderIssues "Blockers" actionableBlockers}
        </section>
    |]
    where
        actionableBlockers = filter reviewActionableBlocker view.preparationReadiness.timesheetReadinessBlockers

reviewActionableBlocker :: XeroTimesheetIssueView -> Bool
reviewActionableBlocker issue =
    issue.timesheetIssueCode /= "managed_pay_item_not_ready"

renderIssues :: Text -> [XeroTimesheetIssueView] -> Html
renderIssues title [] = [hsx|<div class="small app-muted">{title}: none</div>|]
renderIssues title issues = [hsx|
    <div class="small mb-2">
        <div class="fw-semibold mb-1">{title}</div>
        <div class="d-flex flex-wrap gap-2">{forEach issues renderIssue}</div>
    </div>
|]

renderIssue :: XeroTimesheetIssueView -> Html
renderIssue issue = [hsx|
    <span class={classes [("badge text-wrap text-start lh-base", True), ("text-bg-danger", issue.timesheetIssueSeverity == "blocker"), ("text-bg-warning", issue.timesheetIssueSeverity /= "blocker")]}>
        {issue.timesheetIssueMessage}
    </span>
|]

renderPreview :: XeroTimesheetPreparationView -> Html
renderPreview view
    | null view.preparationPreviewRows = mempty
    | otherwise = [hsx|
        <section>
            <h6 class="mb-2">Preview</h6>
            <div class="table-responsive">
                <table class="table table-sm align-middle mb-0">
                    <thead>
                        <tr>
                            <th>Employee</th>
                            <th>Action</th>
                            <th class="text-end">Units</th>
                            <th>Earnings lines</th>
                        </tr>
                    </thead>
                    <tbody>{forEach view.preparationPreviewRows renderPreviewRow}</tbody>
                </table>
            </div>
        </section>
    |]

renderPreviewRow :: XeroTimesheetPreviewRowView -> Html
renderPreviewRow row = [hsx|
    <tr>
        <td>
            <div class="fw-semibold">{row.previewRowEmployeeName}</div>
            <div class="small app-muted">{row.previewRowXeroEmployeeId}</div>
        </td>
        <td>{renderPreviewOperation row}</td>
        <td class="text-end">{formatUnits row.previewRowTotalUnits}</td>
        <td>{Text.intercalate ", " (map lineSummary row.previewRowLines)}</td>
    </tr>
|]

renderPreviewOperation :: XeroTimesheetPreviewRowView -> Html
renderPreviewOperation row
    | row.previewRowOperation == "update" = [hsx|
        <div>
            <span class="badge text-bg-info">Update existing draft</span>
            {renderPreviewXeroTimesheetId row.previewRowXeroTimesheetId}
        </div>
    |]
    | otherwise = [hsx|<span class="badge text-bg-success">Create new draft</span>|]

renderPreviewXeroTimesheetId :: Maybe Text -> Html
renderPreviewXeroTimesheetId Nothing = mempty
renderPreviewXeroTimesheetId (Just timesheetId) = [hsx|<div class="small app-muted">{timesheetId}</div>|]

lineSummary :: XeroTimesheetPreviewLineView -> Text
lineSummary line =
    line.previewLineViewEarningsRateName <> " (" <> formatUnits line.previewLineViewTotalUnits <> ")"

renderFooterActions :: XeroTimesheetPreparationView -> Html
renderFooterActions view = [hsx|
    <div class="d-flex flex-column flex-md-row justify-content-end gap-2 border-top pt-3">
        {renderRefreshForm view}
        {renderSubmitForm view}
    </div>
|]

renderRefreshForm :: XeroTimesheetPreparationView -> Html
renderRefreshForm view =
    renderXeroPreparationOverlayForm
        (appShellActionByMarker @RefreshXeroTimesheetPreparationOverlay)
        (pathTo (RefreshXeroTimesheetPreparationAction view.preparationRun.id))
        []
        [hsx|<button type="submit" class="btn btn-outline-secondary">Refresh checks</button>|]

renderSubmitForm :: XeroTimesheetPreparationView -> Html
renderSubmitForm view =
    renderXeroPreparationOverlayForm
        (appShellActionByMarker @SubmitXeroTimesheetPreparationOverlay)
        (pathTo (SubmitXeroTimesheetPreparationAction view.preparationRun.id))
        [("id", "xero-preparation-submit-form")]
        [hsx|
            <button type="submit"
                    class="btn btn-primary"
                    disabled={not view.preparationCanSubmit}>
                Submit to Xero
            </button>
        |]

renderStatusBadge :: Text -> Html
renderStatusBadge status = renderAppStatusBadge (statusTone status) (statusLabel status)

statusLabel :: Text -> Text
statusLabel "ready_for_preview" = "ready"
statusLabel value               = Text.replace "_" " " value

statusTone :: Text -> AppStatusTone
statusTone "ready"             = AppStatusSuccess
statusTone "ready_for_preview" = AppStatusSuccess
statusTone "previewed"         = AppStatusInfo
statusTone "submitted"         = AppStatusSuccess
statusTone "included"          = AppStatusSuccess
statusTone "not paid"          = AppStatusInfo
statusTone "needs_approval"    = AppStatusWarning
statusTone "needs_reconnect"   = AppStatusWarning
statusTone "blocked"           = AppStatusDanger
statusTone "failed"            = AppStatusDanger
statusTone "excluded"          = AppStatusDanger
statusTone _                   = AppStatusNeutral

staffName :: Staff -> Text
staffName staff = Text.strip (staff.firstName <> " " <> staff.lastName)

staffSecondaryLabel :: XeroPreparationStaffRow -> Text
staffSecondaryLabel row =
    maybe "" (.email) row.preparationStaffMappingRow.mappingRowUser

formatUnits :: Scientific -> Text
formatUnits value = cs (formatScientific Fixed (Just 2) value)

formatMoney :: Scientific -> Text
formatMoney value = "$" <> cs (formatScientific Fixed (Just 2) value)
