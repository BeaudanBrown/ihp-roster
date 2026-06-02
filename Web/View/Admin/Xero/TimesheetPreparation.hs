module Web.View.Admin.Xero.TimesheetPreparation
    ( renderXeroTimesheetPreparationDialog
    , renderXeroTimesheetPreparationErrorDialog
    , renderXeroTimesheetPreparationLoadingDialog
    , renderXeroTimesheetPreparationStaffMappingsFragment
    , renderXeroTimesheetPreparationSubmittingDialog
    ) where

import Application.Helper.View.Overlay
import Application.Helper.XeroAdminTypes
import Application.Xero.Admin.ReadModel (xeroEmployeeAvailableForStaff)
import Control.Monad (guard)
import qualified Data.List as List
import Data.Scientific (FPFormat (Fixed), Scientific, formatScientific)
import qualified Data.Text as Text
import Data.Time.Calendar (Day, diffDays)
import Web.View.Prelude

renderXeroTimesheetPreparationDialog :: XeroTimesheetPreparationView -> Html
renderXeroTimesheetPreparationDialog view
    | needsStaffStep view = renderXeroTimesheetPreparationStaffStep view
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

renderXeroTimesheetPreparationLoadingDialog :: Text -> Html
renderXeroTimesheetPreparationLoadingDialog selectedPeriodKey =
    renderDialogOverlay DialogOverlayConfig
        { dialogOverlayTitle = "Prepare Xero draft timesheets"
        , dialogOverlayBody = [hsx|
            <div class="d-flex align-items-center gap-3" data-xero-timesheet-preparation-loading="true">
                <div id="xero-timesheet-preparation-modal-loading-indicator" class="spinner-border text-primary" role="status" aria-hidden="true"></div>
                <div>
                    <div class="fw-semibold">Preparing Xero draft timesheets...</div>
                    <div class="small app-muted">Checking the connection, Xero reference data, pay runs, timesheets, mappings, and pay items.</div>
                </div>
                <form method="POST"
                      action={RunXeroTimesheetPreparationAction}
                      hx-post={pathTo RunXeroTimesheetPreparationAction}
                      hx-trigger="load"
                      hx-target={"#" <> dialogOverlayMountId}
                      hx-swap="innerHTML"
                      hx-indicator="#xero-timesheet-preparation-modal-loading-indicator">
                    <input type="hidden" name="periodKey" value={selectedPeriodKey} />
                </form>
            </div>
        |]
        , dialogOverlayStartButtons = []
        , dialogOverlayButtons = []
        , dialogOverlayDialogClass = ""
        }

renderXeroTimesheetPreparationStaffStep :: XeroTimesheetPreparationView -> Html
renderXeroTimesheetPreparationStaffStep view =
    renderDialogOverlay DialogOverlayConfig
        { dialogOverlayTitle = preparationDialogTitle view
        , dialogOverlayBody = [hsx|
            <div class="d-flex flex-column gap-3" data-xero-timesheet-preparation-dialog="true">
                {renderStepNotice "Step 1 of 3" "Confirm proposed staff matches or choose the right Xero employee before continuing."}
                {renderConnectionNotice view}
                {renderStaffMappings view}
                {renderReadiness view.preparationReadiness}
                <form id="xero-preparation-staff-continue-form"
                      method="POST"
                      action={ContinueXeroTimesheetPreparationStaffStepAction view.preparationRun.id}
                      hx-post={pathTo (ContinueXeroTimesheetPreparationStaffStepAction view.preparationRun.id)}
                      hx-target={"#" <> dialogOverlayMountId}
                      hx-swap="innerHTML">
                </form>
            </div>
        |]
        , dialogOverlayStartButtons = []
        , dialogOverlayButtons = closeButton : [continueStaffButton view]
        , dialogOverlayDialogClass = "modal-xl"
        }

renderXeroTimesheetPreparationPayItemsStep :: XeroTimesheetPreparationView -> Html
renderXeroTimesheetPreparationPayItemsStep view =
    renderDialogOverlay DialogOverlayConfig
        { dialogOverlayTitle = preparationDialogTitle view
        , dialogOverlayBody = [hsx|
            <div class="d-flex flex-column gap-3" data-xero-timesheet-preparation-dialog="true">
                {renderStepNotice "Step 2 of 3" "Review the managed pay items Bepis will create during final submission, and choose the Xero account code to use."}
                {renderPayItemDecisions view}
                <form id="xero-preparation-pay-items-form"
                      method="POST"
                      action={ApproveXeroTimesheetPreparationPayItemsAction view.preparationRun.id}
                      hx-post={pathTo (ApproveXeroTimesheetPreparationPayItemsAction view.preparationRun.id)}
                      hx-target={"#" <> dialogOverlayMountId}
                      hx-swap="innerHTML">
                </form>
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
                <form id="xero-preparation-confirm-submit-form"
                      method="POST"
                      action={ConfirmXeroTimesheetPreparationSubmissionAction view.preparationRun.id}
                      hx-post={pathTo (ConfirmXeroTimesheetPreparationSubmissionAction view.preparationRun.id)}
                      hx-target={"#" <> dialogOverlayMountId}
                      hx-swap="innerHTML">
                </form>
            </div>
        |]
        , dialogOverlayStartButtons = []
        , dialogOverlayButtons = closeButton : [confirmSubmitButton view]
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
                    <div class="fw-semibold">Creating Xero draft timesheets...</div>
                    <div class="small app-muted">Bepis is submitting each employee draft timesheet to Xero. This can take a moment.</div>
                </div>
                <form method="POST"
                      action={RunXeroTimesheetPreparationSubmissionAction view.preparationRun.id}
                      hx-post={pathTo (RunXeroTimesheetPreparationSubmissionAction view.preparationRun.id)}
                      hx-trigger="load"
                      hx-target={"#" <> dialogOverlayMountId}
                      hx-swap="innerHTML"
                      hx-indicator="#xero-timesheet-preparation-submitting-indicator">
                </form>
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
                <div class="small app-muted">Close this dialog to review employee-level submission status in the Xero panel.</div>
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
    "Pay period: "
        <> formatDateDisplay view.preparationRun.payPeriodStart
        <> " to "
        <> formatDateDisplay view.preparationRun.payPeriodEnd
        <> maybe "" (\paymentDate -> " · payment " <> formatDateDisplay paymentDate) view.preparationRun.paymentDate

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
    , overlayButtonAction = OverlaySubmitFormAction "xero-preparation-staff-continue-form"
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
    view.preparationManualStaffDecisionCount > 0
        || any staffRowNeedsAttention view.preparationStaffRows

needsPayItemStep :: XeroTimesheetPreparationView -> Bool
needsPayItemStep view = any payItemRowNeedsApproval proposedRows || (not (null proposedRows) && isNothing (selectedAccountCode view))
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

renderFinalSummaryCards :: XeroTimesheetPreparationView -> Html
renderFinalSummaryCards view = [hsx|
    <div class="row g-2">
        {renderSummaryCard "Employees" (tshow (length view.preparationReviewRows))}
        {renderSummaryCard "Approved entries" (tshow (sum (map (.reviewRowEntryCount) view.preparationReviewRows)))}
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
                No Xero-paid staff with approved entries were found for this pay period.
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
                            <th class="text-end">Approved entries</th>
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
    fromIntegral (diffDays view.preparationRun.payPeriodEnd view.preparationRun.payPeriodStart) + 1

renderFinalSubmissionCopy :: Html
renderFinalSubmissionCopy = [hsx|
    <div class="small app-muted">
        This creates Xero Payroll AU draft timesheets only. Review and approve payroll in Xero before paying staff.
    </div>
|]

renderRunSummary :: XeroTimesheetPreparationView -> Html
renderRunSummary view = [hsx|
    <div>
        <div class="fw-semibold">Pay Period</div>
        <div class="small app-muted">
            {formatDateDisplay view.preparationRun.payPeriodStart} to {formatDateDisplay view.preparationRun.payPeriodEnd}
            {renderPaymentDate view.preparationRun.paymentDate}
        </div>
    </div>
|]

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
        XeroPreparationReadyForPreview -> "All required decisions are resolved. Submit will create any missing managed pay items and then create the Xero draft timesheets."
        XeroPreparationPreviewed -> "Review the preview rows, then submit only when you are ready to create Xero draft timesheets."
        XeroPreparationSubmitted -> "The latest submission status is recorded below and in the Xero panel."
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
    renderXeroTimesheetPreparationStaffMappingsFragment False

renderXeroTimesheetPreparationStaffMappingsFragment :: Bool -> XeroTimesheetPreparationView -> Html
renderXeroTimesheetPreparationStaffMappingsFragment showMatched view
    | null view.preparationStaffRows = mempty
    | otherwise = [hsx|
        <section id="xero-preparation-staff-mappings">
            <div class="d-flex align-items-center justify-content-between gap-2 mb-2">
                <h6 class="mb-0">Staff mappings</h6>
                <div class="d-flex flex-wrap gap-2 align-items-center">
                    {renderStaffShowMatchedToggle showMatched view}
                </div>
            </div>
            <div class="table-responsive">
                <table class="table table-sm align-middle mb-0 xero-staff-mappings-table" style="table-layout: fixed;">
                    <colgroup>
                        <col style="width: 32%;" />
                        <col style="width: 28%;" />
                        <col style="width: 40%;" />
                    </colgroup>
                    <thead>
                        <tr>
                            <th>Staff</th>
                            <th>Email</th>
                            <th>Xero employee</th>
                        </tr>
                    </thead>
                    <tbody>{forEach visibleRows (renderStaffMappingRow view)}</tbody>
                </table>
            </div>
        </section>
    |]
    where
        (confirmedRows, unconfirmedRows) = List.partition staffRowIsConfirmed view.preparationStaffRows
        visibleRows = unconfirmedRows <> if showMatched then confirmedRows else []

renderStaffShowMatchedToggle :: Bool -> XeroTimesheetPreparationView -> Html
renderStaffShowMatchedToggle showMatched view = [hsx|
    <form method="GET"
          action={ShowXeroTimesheetPreparationStaffMappingsFragmentAction view.preparationRun.id}
          hx-get={pathTo (ShowXeroTimesheetPreparationStaffMappingsFragmentAction view.preparationRun.id)}
          hx-trigger="change"
          hx-target="#xero-preparation-staff-mappings"
          hx-swap="outerHTML">
        <div>
            {renderStaffShowMatchedToggleButton showMatched}
        </div>
    </form>
|]

renderStaffShowMatchedToggleButton :: Bool -> Html
renderStaffShowMatchedToggleButton showMatched =
    renderAppToggleButton $ (defaultAppToggleButtonConfig "xero-preparation-show-matched-staff-toggle" showMatched [hsx|<span class="small">Show matched</span>|])
        { appToggleInputName = Just "showMatched"
        , appToggleInputValue = "true"
        , appToggleButtonClass = "btn-sm xero-staff-mapping-show-matched-toggle"
        , appToggleRoleSwitch = True
        }

renderStaffMappingRow :: XeroTimesheetPreparationView -> XeroPreparationStaffRow -> Html
renderStaffMappingRow view row = [hsx|
    <tr class={classes [("xero-staff-mapping-row-matched", staffRowIsConfirmed row)]}
        data-xero-staff-mapping-status={staffMappingStatus row}>
        <td>
            <div class="fw-semibold text-truncate">{staffName staff}</div>
        </td>
        <td class="small text-truncate">{staffSecondaryLabel row}</td>
        <td>{renderStaffEmployeeSelectionForm view row}</td>
    </tr>
|]
    where
        staff = row.preparationStaffMappingRow.mappingRowStaff

renderStaffEmployeeSelectionForm :: XeroTimesheetPreparationView -> XeroPreparationStaffRow -> Html
renderStaffEmployeeSelectionForm view row = [hsx|
    <form method="POST"
          action={ApplyXeroTimesheetPreparationStaffDecisionAction view.preparationRun.id}
          class="d-inline-flex gap-2"
          data-disable-javascript-submission="true"
          hx-post={pathTo (ApplyXeroTimesheetPreparationStaffDecisionAction view.preparationRun.id)}
          hx-trigger="change, submit"
          hx-target={"#" <> dialogOverlayMountId}
          hx-swap="innerHTML">
        <input type="hidden" name="staffId" value={tshow staff.id} />
        <input type="hidden" name="decision" value="select_employee" />
        <select name="xeroEmployeeSelection" class="form-select form-select-sm w-auto" style="min-width: 12rem; max-width: 16rem;" aria-label={"Xero employee for " <> staffName staff}>
            <option value="" selected={Text.null currentSelection}>Choose Xero employee</option>
            {forEach selectableEmployees (renderEmployeeOption currentSelection)}
            <option value="not_applicable" selected={currentSelection == "not_applicable"}>Not paid through Xero</option>
        </select>
        {renderPendingAutoMatchConfirm row}
    </form>
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
                _ -> decision.xeroEmployeeId
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

renderPendingAutoMatchConfirm :: XeroPreparationStaffRow -> Html
renderPendingAutoMatchConfirm row
    | staffRowHasPendingAutoMatch row = [hsx|<button class="btn btn-sm btn-primary" type="submit">Confirm match</button>|]
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
                <span class="small app-muted">{tshow (length proposedRows)} will be created on submit</span>
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
        <td class="text-end">{formatUnits row.previewRowTotalUnits}</td>
        <td>{Text.intercalate ", " (map lineSummary row.previewRowLines)}</td>
    </tr>
|]

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
renderRefreshForm view = [hsx|
    <form method="POST"
          action={RefreshXeroTimesheetPreparationAction view.preparationRun.id}
          hx-post={pathTo (RefreshXeroTimesheetPreparationAction view.preparationRun.id)}
          hx-target={"#" <> dialogOverlayMountId}
          hx-swap="innerHTML">
        <button type="submit" class="btn btn-outline-secondary">Refresh checks</button>
    </form>
|]

renderSubmitForm :: XeroTimesheetPreparationView -> Html
renderSubmitForm view = [hsx|
    <form id="xero-preparation-submit-form"
          method="POST"
          action={SubmitXeroTimesheetPreparationAction view.preparationRun.id}
          hx-post={pathTo (SubmitXeroTimesheetPreparationAction view.preparationRun.id)}
          hx-target={"#" <> dialogOverlayMountId}
          hx-swap="innerHTML">
        <button type="submit"
                class="btn btn-primary"
                disabled={not view.preparationCanSubmit}
                hx-confirm="Submit draft timesheets to Xero?">
            Submit to Xero
        </button>
    </form>
|]

renderStatusBadge :: Text -> Html
renderStatusBadge status = renderAppStatusBadge (statusTone status) (statusLabel status)

statusLabel :: Text -> Text
statusLabel "ready_for_preview" = "ready"
statusLabel value = Text.replace "_" " " value

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
