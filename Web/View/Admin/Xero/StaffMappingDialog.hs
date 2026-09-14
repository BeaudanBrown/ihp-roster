{-# LANGUAGE TypeApplications #-}
{-# OPTIONS_GHC -Werror=incomplete-patterns #-}

module Web.View.Admin.Xero.StaffMappingDialog
    ( renderXeroStaffMappingsDialog
    , renderXeroStaffMappingsWaitingDialog
    , renderXeroStaffMappingsWaitFragment
    ) where

import Application.Helper.FrontendContract.AppShell (ApplyXeroStaffMappingOverlay,
                                                     StaffIdField,
                                                     XeroEmployeeSelectionField)
import Application.Helper.FrontendContract.AppShell.Request (appShellActionFields,
                                                             appShellActionFor)
import Application.Helper.FrontendContract.AppShell.Runtime (AppShellActionRoute (..),
                                                             renderAppShellActionForm)
import qualified Application.Helper.FrontendContract.Surface.Admin as Surface
import Application.Helper.FrontendContract.Surface.Runtime (renderFrontendSurfaceMount)
import Application.Helper.FrontendContract.Surface.Values
import Application.Helper.XeroAdminTypes
import Application.Xero.Admin.ReadModel (xeroEmployeeAvailableForStaff)
import Application.Xero.EmployeeId (XeroEmployeeSelection (..),
                                    parseXeroEmployeeId)
import Application.Xero.WorkflowState
import qualified Data.Text as Text
import Web.Admin.FrontendSurface (AdminVenueScopeValue (..),
                                  adminXeroStaffMappingsWaitSurfaceImpl)
import Web.View.Prelude

renderXeroStaffMappingsWaitingDialog :: UUID -> Id AppJob -> Html
renderXeroStaffMappingsWaitingDialog venueId jobId =
    renderFrontendSurfaceMount
        (adminXeroStaffMappingsWaitSurfaceImpl AdminVenueScopeValue { adminVenueId = venueId, adminRosterGroupId = Nothing } jobId)
        (renderXeroStaffMappingsWaitFragment jobId)

renderXeroStaffMappingsWaitFragment :: Id AppJob -> Html
renderXeroStaffMappingsWaitFragment jobId = [hsx|
    <div id={surfaceFragmentTargetId @Surface.AdminXeroSurface @Surface.AdminXeroStaffMappingsWaitFragment fields}>
        {renderXeroStaffMappingsWaitingOverlay}
    </div>
|]
  where
    fields = surfaceField @Surface.ReferenceSyncJobId (unpackId jobId) &: noSurfaceFields

renderXeroStaffMappingsWaitingOverlay :: Html
renderXeroStaffMappingsWaitingOverlay =
    renderDialogOverlay DialogOverlayConfig
        { dialogOverlayTitle = "Staff mappings"
        , dialogOverlayBody = [hsx|
            <div class="d-flex align-items-start gap-3" data-xero-staff-mappings-waiting="true">
                <div class="spinner-border text-primary mt-1" role="status" aria-hidden="true"></div>
                <div class="d-flex flex-column gap-1">
                    <div class="fw-semibold">Refreshing Xero staff</div>
                    <div class="small app-muted">This dialog will open automatically when current Xero staff are ready.</div>
                </div>
            </div>
        |]
        , dialogOverlayStartButtons = []
        , dialogOverlayButtons = [closeButton]
        , dialogOverlayDialogClass = ""
        }

renderXeroStaffMappingsDialog :: XeroStaffMappingsView -> Html
renderXeroStaffMappingsDialog view =
    renderDialogOverlay DialogOverlayConfig
        { dialogOverlayTitle = "Staff mappings"
        , dialogOverlayBody = renderStaffMappingsBody view
        , dialogOverlayStartButtons = []
        , dialogOverlayButtons = [closeButton]
        , dialogOverlayDialogClass = "modal-lg modal-dialog-scrollable"
        }

closeButton :: OverlayButton
closeButton =
    OverlayButton
        { overlayButtonLabel = "Close"
        , overlayButtonClass = "btn btn-outline-secondary"
        , overlayButtonAction = OverlayCloseAction
        }

renderStaffMappingsBody :: XeroStaffMappingsView -> Html
renderStaffMappingsBody view
    | null view.staffMappingsRows = [hsx|<div class="alert alert-secondary mb-0">No linked active staff are available to map.</div>|]
    | otherwise = [hsx|
        <div id="xero-staff-mappings" class="table-responsive">
            <table class="table table-sm align-middle mb-0 xero-staff-mappings-table">
                <thead>
                    <tr>
                        <th>Staff</th>
                        <th>Email</th>
                        <th>Status</th>
                        <th>Xero employee</th>
                    </tr>
                </thead>
                <tbody>{forEach view.staffMappingsRows (renderStaffMappingRow view)}</tbody>
            </table>
        </div>
    |]

renderStaffMappingRow :: XeroStaffMappingsView -> XeroStaffMappingRow -> Html
renderStaffMappingRow view row = [hsx|
    <tr data-xero-staff-mapping-status={mappingStatusValue mapping.mappingStatus}>
        <td><div class="fw-semibold text-truncate">{xeroStaffDisplayName staff}</div></td>
        <td class="small text-truncate">{maybe "" (.email) row.mappingRowUser}</td>
        <td class="small">{mappingStatusLabel mapping.mappingStatus}</td>
        <td>{renderMappingSelectionForm view row}</td>
    </tr>
|]
  where
    staff = row.mappingRowStaff
    mapping = row.mappingRowMapping

renderMappingSelectionForm :: XeroStaffMappingsView -> XeroStaffMappingRow -> Html
renderMappingSelectionForm view row =
    renderAppShellActionForm
        (appShellActionFor fields)
        AppShellActionRoute
            { appShellActionRouteUrl = pathTo ApplyXeroStaffMappingAction
            , appShellActionRouteFields = []
            , appShellActionRouteCustomHtmx = []
            , appShellActionRouteStandardUrl = Nothing
            , appShellActionRouteExtraAttrs = [("class", "d-inline-flex")]
            }
        [hsx|
            <input type="hidden" name={surfaceFieldNameFrom @StaffIdField fields} value={tshow staff.id} />
            <select name={surfaceFieldNameFrom @XeroEmployeeSelectionField fields}
                    class="form-select form-select-sm xero-employee-selection"
                    aria-label={"Xero employee for " <> xeroStaffDisplayName staff}>
                <option value="unmapped" selected={Text.null currentSelection}>Unmapped</option>
                {forEach selectableEmployees (renderEmployeeOption currentSelection)}
                <option value="not_applicable" selected={currentSelection == "not_applicable"}>Not paid through Xero</option>
            </select>
        |]
  where
    staff = row.mappingRowStaff
    currentSelection = mappingSelectionValue row.mappingRowMapping
    selectableEmployees =
        filter (xeroEmployeeAvailableForStaff staff view.staffMappingsRows) view.staffMappingsEmployees
    fieldSelection
        | Text.null currentSelection = XeroEmployeeUnmapped
        | currentSelection == "not_applicable" = XeroEmployeeNotApplicable
        | otherwise = either (const XeroEmployeeNotApplicable) XeroEmployeeSelected (parseXeroEmployeeId currentSelection)
    fields =
        appShellActionFields @ApplyXeroStaffMappingOverlay
            (surfaceField @StaffIdField (unpackId staff.id))
            (surfaceField @XeroEmployeeSelectionField fieldSelection &: noSurfaceFields)

renderEmployeeOption :: Text -> XeroEmployee -> Html
renderEmployeeOption currentSelection employee = [hsx|
    <option value={employee.xeroEmployeeId} selected={currentSelection == employee.xeroEmployeeId}>{employee.displayName}</option>
|]

mappingSelectionValue :: XeroStaffMapping -> Text
mappingSelectionValue mapping
    | xeroStaffMappingIsVerified mapping.mappingStatus = fromMaybe "" mapping.xeroEmployeeId
    | xeroStaffMappingIsNotApplicable mapping.mappingStatus = "not_applicable"
    | otherwise = ""

mappingStatusLabel :: XeroStaffMappingStatusEnum -> Text
mappingStatusLabel = \case
    XeroStaffMappingStatusEnumUnmapped -> "Unmapped"
    XeroStaffMappingStatusEnumVerified -> "Verified"
    NotApplicable -> "Not paid through Xero"
    XeroStaffMappingStatusEnumStale -> "Stale — choose again"

mappingStatusValue :: XeroStaffMappingStatusEnum -> Text
mappingStatusValue = \case
    XeroStaffMappingStatusEnumUnmapped -> "unmapped"
    XeroStaffMappingStatusEnumVerified -> "verified"
    NotApplicable -> "not_applicable"
    XeroStaffMappingStatusEnumStale -> "stale"

xeroStaffDisplayName :: Staff -> Text
xeroStaffDisplayName staff = Text.strip (staff.firstName <> " " <> staff.lastName)
