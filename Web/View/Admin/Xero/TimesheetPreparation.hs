module Web.View.Admin.Xero.TimesheetPreparation
    ( renderXeroTimesheetPreparationDialog
    , renderXeroTimesheetPreparationErrorDialog
    ) where

import Application.Helper.View.Overlay
import Application.Helper.XeroAdminTypes
import Data.Scientific (FPFormat (Fixed), Scientific, formatScientific)
import qualified Data.Text as Text
import Data.Time.Calendar (Day)
import Web.View.Admin.Common (formatTimestamp)
import Web.View.Prelude

renderXeroTimesheetPreparationDialog :: XeroTimesheetPreparationView -> Html
renderXeroTimesheetPreparationDialog view =
    renderDialogOverlay DialogOverlayConfig
        { dialogOverlayTitle = "Prepare Xero draft timesheets"
        , dialogOverlayBody = renderPreparationBody view
        , dialogOverlayStartButtons = []
        , dialogOverlayButtons =
            [ OverlayButton
                { overlayButtonLabel = "Close"
                , overlayButtonClass = "btn btn-outline-secondary"
                , overlayButtonAction = OverlayCloseAction
                }
            ]
        , dialogOverlayDialogClass = "modal-xl"
        }

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

renderPreparationBody :: XeroTimesheetPreparationView -> Html
renderPreparationBody view = [hsx|
    <div class="d-flex flex-column gap-3" data-xero-timesheet-preparation-dialog="true">
        {renderRunSummary view}
        {renderConnectionNotice view}
        {renderStaffDecisions view}
        {renderPayItemDecisions view}
        {renderReadiness view.preparationReadiness}
        {renderPreview view}
        {renderFooterActions view}
    </div>
|]

renderRunSummary :: XeroTimesheetPreparationView -> Html
renderRunSummary view = [hsx|
    <div class="d-flex flex-column flex-lg-row justify-content-between gap-2">
        <div>
            <div class="fw-semibold">{view.preparationPeriodOption.periodOptionPayrollCalendarName}</div>
            <div class="small app-muted">
                {formatDateDisplay view.preparationRun.payPeriodStart} to {formatDateDisplay view.preparationRun.payPeriodEnd}
                {renderPaymentDate view.preparationRun.paymentDate}
            </div>
        </div>
        <div class="text-lg-end">
            {renderStatusBadge view.preparationRun.status}
            <div class="small app-muted mt-1">Started {formatTimestamp view.preparationRun.createdAt}</div>
        </div>
    </div>
|]

renderPaymentDate :: Maybe Day -> Html
renderPaymentDate Nothing = mempty
renderPaymentDate (Just paymentDate) = [hsx|<span> · payment {formatDateDisplay paymentDate}</span>|]

renderConnectionNotice :: XeroTimesheetPreparationView -> Html
renderConnectionNotice view
    | view.preparationConnection.connectionStatus == "active" = mempty
    | otherwise = [hsx|
        <div class="alert alert-warning mb-0 d-flex flex-column flex-md-row justify-content-between gap-2 align-items-md-center">
            <div>Reconnect Xero before continuing this preparation run.</div>
            <a href={pathTo StartXeroConnectionAction} class="btn btn-sm btn-warning">Reconnect Xero</a>
        </div>
    |]

renderStaffDecisions :: XeroTimesheetPreparationView -> Html
renderStaffDecisions view
    | null actionableRows = mempty
    | otherwise = [hsx|
        <section>
            <div class="d-flex align-items-center justify-content-between gap-2 mb-2">
                <h6 class="mb-0">Staff mapping decisions</h6>
                <span class="small app-muted">{tshow (length actionableRows)} to resolve</span>
            </div>
            <div class="table-responsive">
                <table class="table table-sm align-middle mb-0">
                    <thead>
                        <tr>
                            <th>Staff</th>
                            <th>Suggested match</th>
                            <th>Manual employee</th>
                            <th class="text-end">Decision</th>
                        </tr>
                    </thead>
                    <tbody>{forEach actionableRows (renderStaffDecisionRow view)}</tbody>
                </table>
            </div>
        </section>
    |]
    where
        actionableRows =
            view.preparationStaffRows
                |> filter \row ->
                    row.preparationStaffNeedsDecision
                        || maybe False ((== "pending") . (.decisionStatus)) row.preparationStaffDecision

renderStaffDecisionRow :: XeroTimesheetPreparationView -> XeroPreparationStaffRow -> Html
renderStaffDecisionRow view row = [hsx|
    <tr>
        <td>
            <div class="fw-semibold">{staffName staff}</div>
            <div class="small app-muted">{staffSecondaryLabel row}</div>
        </td>
        <td>{renderSuggestedEmployee view row}</td>
        <td>{renderManualEmployeeForm view row}</td>
        <td class="text-end">
            <div class="d-inline-flex flex-wrap gap-2 justify-content-end">
                {renderApproveSuggestionForm view row}
                {renderStaffDecisionButton view row "not_paid" "Not paid through Xero" "btn btn-sm btn-outline-secondary"}
                {renderStaffDecisionButton view row "skip" "Skip this time" "btn btn-sm btn-outline-secondary"}
            </div>
        </td>
    </tr>
|]
    where
        staff = row.preparationStaffMappingRow.mappingRowStaff

renderSuggestedEmployee :: XeroTimesheetPreparationView -> XeroPreparationStaffRow -> Html
renderSuggestedEmployee _ row =
    case (row.preparationStaffDecision >>= (.xeroEmployeeName)) <|> ((.displayName) <$> row.preparationStaffMappingRow.mappingRowSuggestedEmployee) of
        Nothing -> [hsx|<span class="small app-muted">No confident match</span>|]
        Just name -> [hsx|<span>{name}</span>|]

renderApproveSuggestionForm :: XeroTimesheetPreparationView -> XeroPreparationStaffRow -> Html
renderApproveSuggestionForm view row =
    if hasAutoSuggestion
        then [hsx|
            <form method="POST"
                  action={ApplyXeroTimesheetPreparationStaffDecisionAction view.preparationRun.id}
                  hx-post={pathTo (ApplyXeroTimesheetPreparationStaffDecisionAction view.preparationRun.id)}
                  hx-target={"#" <> dialogOverlayMountId}
                  hx-swap="innerHTML">
                <input type="hidden" name="staffId" value={tshow staff.id} />
                <input type="hidden" name="decision" value="approve_suggestion" />
                <button type="submit" class="btn btn-sm btn-primary">Approve</button>
            </form>
        |]
        else mempty
    where
        staff = row.preparationStaffMappingRow.mappingRowStaff
        hasAutoSuggestion =
            maybe False ((== "staff_auto_match") . (.decisionKind)) row.preparationStaffDecision
                || isJust row.preparationStaffMappingRow.mappingRowSuggestedEmployee

renderManualEmployeeForm :: XeroTimesheetPreparationView -> XeroPreparationStaffRow -> Html
renderManualEmployeeForm view row = [hsx|
    <form method="POST"
          action={ApplyXeroTimesheetPreparationStaffDecisionAction view.preparationRun.id}
          class="d-flex gap-2"
          hx-post={pathTo (ApplyXeroTimesheetPreparationStaffDecisionAction view.preparationRun.id)}
          hx-target={"#" <> dialogOverlayMountId}
          hx-swap="innerHTML">
        <input type="hidden" name="staffId" value={tshow staff.id} />
        <input type="hidden" name="decision" value="manual" />
        <select name="xeroEmployeeId" class="form-select form-select-sm" aria-label="Xero employee">
            <option value="">Choose employee</option>
            {forEach view.preparationEmployees renderEmployeeOption}
        </select>
        <button type="submit" class="btn btn-sm btn-outline-primary">Save</button>
    </form>
|]
    where
        staff = row.preparationStaffMappingRow.mappingRowStaff

renderEmployeeOption :: XeroEmployee -> Html
renderEmployeeOption employee = [hsx|
    <option value={employee.xeroEmployeeId}>{employee.displayName}</option>
|]

renderStaffDecisionButton :: XeroTimesheetPreparationView -> XeroPreparationStaffRow -> Text -> Text -> Text -> Html
renderStaffDecisionButton view row decision label buttonClass = [hsx|
    <form method="POST"
          action={ApplyXeroTimesheetPreparationStaffDecisionAction view.preparationRun.id}
          hx-post={pathTo (ApplyXeroTimesheetPreparationStaffDecisionAction view.preparationRun.id)}
          hx-target={"#" <> dialogOverlayMountId}
          hx-swap="innerHTML">
        <input type="hidden" name="staffId" value={tshow staff.id} />
        <input type="hidden" name="decision" value={decision} />
        <button type="submit" class={buttonClass}>{label}</button>
    </form>
|]
    where
        staff = row.preparationStaffMappingRow.mappingRowStaff

renderPayItemDecisions :: XeroTimesheetPreparationView -> Html
renderPayItemDecisions view
    | null proposedRows = mempty
    | otherwise = [hsx|
        <section>
            <div class="d-flex align-items-center justify-content-between gap-2 mb-2">
                <h6 class="mb-0">Managed pay items</h6>
                <span class="small app-muted">{tshow (length proposedRows)} pending creation</span>
            </div>
            <div class={appSurfaceClasses "p-3"}>
                <div class="small mb-2">{Text.intercalate ", " (map requirementName proposedRows)}</div>
                <form method="POST"
                      action={ApproveXeroTimesheetPreparationPayItemsAction view.preparationRun.id}
                      class="d-flex flex-column flex-md-row gap-2"
                      hx-post={pathTo (ApproveXeroTimesheetPreparationPayItemsAction view.preparationRun.id)}
                      hx-target={"#" <> dialogOverlayMountId}
                      hx-swap="innerHTML">
                    <select name="accountCode" class="form-select form-select-sm" aria-label="Xero account code">
                        <option value="">Choose account code</option>
                        {forEach view.preparationPayItemAccountCodeOptions renderAccountCodeOption}
                    </select>
                    <button type="submit" class="btn btn-sm btn-primary">Approve creation</button>
                </form>
            </div>
        </section>
    |]
    where
        proposedRows =
            view.preparationPayItemRows
                |> filter \row ->
                    row.preparationPayItemRequirement.payItemRequirementStatus == "proposed"
        requirementName row = row.preparationPayItemRequirement.payItemRequirementName

renderAccountCodeOption :: Text -> Html
renderAccountCodeOption accountCode = [hsx|<option value={accountCode}>{accountCode}</option>|]

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
        {renderPreviewForm view}
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

renderPreviewForm :: XeroTimesheetPreparationView -> Html
renderPreviewForm view = [hsx|
    <form method="POST"
          action={PreviewXeroTimesheetPreparationAction view.preparationRun.id}
          hx-post={pathTo (PreviewXeroTimesheetPreparationAction view.preparationRun.id)}
          hx-target={"#" <> dialogOverlayMountId}
          hx-swap="innerHTML">
        <button type="submit" class="btn btn-outline-primary" disabled={not view.preparationCanPreview}>Preview</button>
    </form>
|]

renderSubmitForm :: XeroTimesheetPreparationView -> Html
renderSubmitForm view = [hsx|
    <form method="POST"
          action={SubmitXeroTimesheetPreparationAction view.preparationRun.id}
          hx-post={pathTo (SubmitXeroTimesheetPreparationAction view.preparationRun.id)}
          hx-target={"#" <> dialogOverlayMountId}
          hx-swap="innerHTML">
        <button type="submit" class="btn btn-primary" disabled={not view.preparationCanSubmit}>Submit to Xero</button>
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
statusTone "needs_approval"    = AppStatusWarning
statusTone "needs_reconnect"   = AppStatusWarning
statusTone "blocked"           = AppStatusDanger
statusTone "failed"            = AppStatusDanger
statusTone _                   = AppStatusNeutral

staffName :: Staff -> Text
staffName staff = Text.strip (staff.firstName <> " " <> staff.lastName)

staffSecondaryLabel :: XeroPreparationStaffRow -> Text
staffSecondaryLabel row =
    maybe "" (.email) row.preparationStaffMappingRow.mappingRowUser

formatUnits :: Scientific -> Text
formatUnits value = cs (formatScientific Fixed (Just 2) value)
