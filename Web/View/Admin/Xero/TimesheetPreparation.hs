{-# LANGUAGE TypeApplications #-}
{-# OPTIONS_GHC -Werror=incomplete-patterns #-}

module Web.View.Admin.Xero.TimesheetPreparation
    ( renderXeroTimesheetPreparationDialog
    , renderXeroTimesheetPreparationReferenceSyncWaitingDialog
    , renderXeroTimesheetPreparationReferenceSyncWaitFragment
    , renderXeroTimesheetPreparationReferenceSyncWaitFragmentError
    , renderXeroTimesheetPreparationStaffMappingsFragment
    , renderXeroTimesheetPreparationSubmittingDialog
    ) where

import Application.Helper.FrontendContract.AppShell (AccountCodeField,
                                                     ApproveXeroTimesheetPreparationPayItemsOverlay,
                                                     ConfirmXeroTimesheetPreparationSubmissionOverlay,
                                                     ContinueXeroTimesheetPreparationStaffOverlay,
                                                     PeriodKeyField,
                                                     RefreshXeroTimesheetPreparationOverlay,
                                                     RunXeroTimesheetPreparationOverlay,
                                                     RunXeroTimesheetPreparationSubmissionOverlay,
                                                     SelectXeroTimesheetPreparationPeriodOverlay,
                                                     SubmitXeroTimesheetPreparationOverlay)
import Application.Helper.FrontendContract.AppShell.Request (AppShellActionFields,
                                                             appShellActionFields,
                                                             appShellActionFor,
                                                             noAppShellActionFields)
import Application.Helper.FrontendContract.AppShell.Runtime (AppShellActionRoute (..),
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
import qualified Data.Text as Text
import Data.Time.Calendar (Day)
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

renderXeroPreparationOverlayForm :: Typeable action => AppShellActionFields action -> Text -> [(Text, Text)] -> Html -> Html
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
    | needsPayItemStep view = renderXeroTimesheetPreparationPayItemsStep view
    | view.preparationState == XeroPreparationSubmitted = renderXeroTimesheetPreparationSubmittedDialog view
    | view.preparationState == XeroPreparationFailed = renderXeroTimesheetPreparationFailureDialog view
    | otherwise = renderXeroTimesheetPreparationSummaryStep view



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
renderXeroTimesheetPreparationStaffStep view =
    renderDialogOverlay DialogOverlayConfig
        { dialogOverlayTitle = preparationDialogTitle view
        , dialogOverlayBody = [hsx|
            <div class="d-flex flex-column gap-3" data-xero-timesheet-preparation-dialog="true">
                {renderStepNotice "Step 1 of 3" "Confirm proposed staff matches or choose the right Xero employee before continuing."}
                {renderConnectionNotice view}
                {renderStaffMappings view}
                {renderXeroPreparationOverlayForm (noAppShellActionFields @ContinueXeroTimesheetPreparationStaffOverlay) (pathTo (ContinueXeroTimesheetPreparationStaffStepAction view.preparationRun.id)) [("id", "xero-preparation-staff-continue-form")] mempty}
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
                {forEach view.preparationPeriodOptions renderPreparationPeriodOption}
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
                {renderStepNotice "Step 2 of 3" "Review the managed pay items Bepis will create during final submission, and choose the Xero account code to use."}
                {renderPayItemDecisions view}
                {renderXeroPreparationOverlayForm fields (pathTo (ApproveXeroTimesheetPreparationPayItemsAction view.preparationRun.id)) [("id", "xero-preparation-pay-items-form")] mempty}
            </div>
        |]
        , dialogOverlayStartButtons = []
        , dialogOverlayButtons = closeButton : [approvePayItemsButton]
        , dialogOverlayDialogClass = "modal-xl"
        }
  where
    fields =
        appShellActionFields @ApproveXeroTimesheetPreparationPayItemsOverlay
            (surfaceOptionalField @AccountCodeField (selectedAccountCode view))
            noSurfaceFields

renderXeroTimesheetPreparationSummaryStep :: XeroTimesheetPreparationView -> Html
renderXeroTimesheetPreparationSummaryStep view =
    renderDialogOverlay DialogOverlayConfig
        { dialogOverlayTitle = preparationDialogTitle view
        , dialogOverlayBody = [hsx|
            <div class="d-flex flex-column gap-3" data-xero-timesheet-preparation-dialog="true">
                {renderStepNotice "Step 3 of 3" "Review the draft timesheets Bepis will submit to Xero."}
                {if null view.preparationReconciliationNotices then mempty else renderReconciliationReview view}
                {renderPreparationReview view}
                {renderXeroPreparationOverlayForm (noAppShellActionFields @ConfirmXeroTimesheetPreparationSubmissionOverlay) (pathTo (ConfirmXeroTimesheetPreparationSubmissionAction view.preparationRun.id)) [("id", "xero-preparation-confirm-submit-form")] mempty}
            </div>
        |]
        , dialogOverlayStartButtons = []
        , dialogOverlayButtons = closeButton : [confirmSubmitButton view | view.preparationCanSubmit]
        , dialogOverlayDialogClass = "modal-xl"
        }

renderXeroTimesheetPreparationSubmittingDialog :: XeroTimesheetPreparationView -> Html
renderXeroTimesheetPreparationSubmittingDialog view =
    renderDialogOverlay DialogOverlayConfig
        { dialogOverlayTitle = "Confirm Xero draft timesheets"
        , dialogOverlayBody = [hsx|
            <div class="d-flex flex-column gap-3" data-xero-timesheet-reconciliation-review="true">
                <div>Bepis checked Xero again immediately before submission.</div>
                {renderReconciliationReview view}
                <div class="small app-muted">After confirmation, Bepis will create new drafts, update confirmed drafts, or create the explicitly warned replacement drafts shown above.</div>
                {renderXeroPreparationOverlayForm (noAppShellActionFields @RunXeroTimesheetPreparationSubmissionOverlay) (pathTo (RunXeroTimesheetPreparationSubmissionAction view.preparationRun.id)) [("id", "xero-preparation-reviewed-submit-form")] mempty}
            </div>
        |]
        , dialogOverlayStartButtons = []
        , dialogOverlayButtons = closeButton : [reviewedSubmitButton | view.preparationReconciliationCanSubmit]
        , dialogOverlayDialogClass = "modal-lg"
        }

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
    { overlayButtonLabel = "Review Xero and continue"
    , overlayButtonClass = "btn btn-primary"
    , overlayButtonAction = OverlaySubmitFormAction "xero-preparation-confirm-submit-form"
    }

reviewedSubmitButton :: OverlayButton
reviewedSubmitButton = OverlayButton
    { overlayButtonLabel = "Confirm and submit draft timesheets"
    , overlayButtonClass = "btn btn-primary"
    , overlayButtonAction = OverlaySubmitFormAction "xero-preparation-reviewed-submit-form"
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
                        name={surfaceFieldNameFrom @AccountCodeField fields}
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
        fields =
            appShellActionFields @ApproveXeroTimesheetPreparationPayItemsOverlay
                (surfaceOptionalField @AccountCodeField (selectedAccountCode view))
                noSurfaceFields
        proposedRows =
            view.preparationPayItemRows
                |> filter \row ->
                    xeroPayItemRequirementIsProposed row.preparationPayItemRequirement.payItemRequirementStatus

renderPayItemCreationRow :: XeroPreparationPayItemRow -> Html
renderPayItemCreationRow row = [hsx|
    <tr>
        <td>{requirement.payItemRequirementName}</td>
        <td>{fromMaybe "per employee ordinary rate" requirement.payItemRequirementValue}</td>
        <td>{renderAppStatusBadge AppStatusNeutral "will be created"}</td>
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
    guard (xeroAccountCodeSelectionIsVerified selection.selectionStatus)
    Text.strip <$> selection.accountCode
