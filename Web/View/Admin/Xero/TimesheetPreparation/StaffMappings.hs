{-# LANGUAGE TypeApplications #-}
{-# OPTIONS_GHC -Werror=incomplete-patterns #-}

module Web.View.Admin.Xero.TimesheetPreparation.StaffMappings
    ( preparationStaffMappingsNeedAttention
    , renderStaffMappings
    , renderXeroTimesheetPreparationStaffMappingsFragment
    ) where

import Application.Helper.FrontendContract.AppShell (ApplyXeroTimesheetPreparationStaffDecisionOverlay,
                                                     StaffIdField,
                                                     XeroEmployeeSelectionField)
import Application.Helper.FrontendContract.AppShell.Request (AppShellActionFields,
                                                             appShellActionFields,
                                                             appShellActionFor)
import Application.Helper.FrontendContract.AppShell.Runtime (AppShellActionRoute (..),
                                                             RegisteredAppShellAction,
                                                             renderAppShellActionForm)
import qualified Application.Helper.FrontendContract.Surface.Admin as Surface
import qualified Application.Helper.FrontendContract.Surface.Admin.Action as AdminAction
import Application.Helper.FrontendContract.Surface.Runtime (FrontendSurfaceActionRoute (..),
                                                            renderFrontendSurfaceActionForm)
import Application.Helper.FrontendContract.Surface.Values
import Application.Helper.XeroAdminTypes
import Application.Xero.Admin.ReadModel (xeroEmployeeAvailableForStaff)
import Application.Xero.EmployeeId (XeroEmployeeSelection (..),
                                    parseXeroEmployeeId)
import Application.Xero.WorkflowState
import Control.Monad (guard)
import qualified Data.Text as Text
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

preparationStaffMappingsNeedAttention :: [XeroPreparationStaffRow] -> Bool
preparationStaffMappingsNeedAttention = any staffRowNeedsAttention

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
        visibleRows = view.preparationStaffRows

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
    | staffRowHasPendingAutoMatch row = "Suggested match — Continue to confirm"
    | staffRowIsConfirmed row = "Approved"
    | otherwise = "Selected"

renderStaffEmployeeSelectionForm :: XeroTimesheetPreparationView -> XeroPreparationStaffRow -> Html
renderStaffEmployeeSelectionForm view row =
    renderXeroPreparationOverlayForm
        fields
        (pathTo (ApplyXeroTimesheetPreparationStaffDecisionAction view.preparationRun.id))
        [ ("class", "d-inline-flex gap-2")

        ]
        [hsx|
            <input type="hidden" name={surfaceFieldNameFrom @StaffIdField fields} value={tshow staff.id} />
            <select name={surfaceFieldNameFrom @XeroEmployeeSelectionField fields} class="form-select form-select-sm w-auto xero-employee-selection" aria-label={"Xero employee for " <> staffName staff}>
                {forEach selectableEmployees (renderEmployeeOption currentSelection)}
                <option value="not_applicable" selected={Text.null currentSelection || currentSelection == "not_applicable"}>Not paid through Xero</option>
            </select>
        |]
    where
        staff = row.preparationStaffMappingRow.mappingRowStaff
        currentSelection = currentStaffEmployeeSelection row
        selectableEmployees = selectableEmployeesForStaffDecision view row
        fields =
            appShellActionFields @ApplyXeroTimesheetPreparationStaffDecisionOverlay
                (surfaceField @StaffIdField (unpackId staff.id))
                ( surfaceField @XeroEmployeeSelectionField fieldSelection
                    &: noSurfaceFields
                )
        fieldSelection
            | currentSelection == "not_applicable" || Text.null currentSelection = XeroEmployeeNotApplicable
            | otherwise = either (const XeroEmployeeNotApplicable) XeroEmployeeSelected (parseXeroEmployeeId currentSelection)

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
                StaffNotPaid       -> Just "not_applicable"
                StaffAutoMatch     -> decision.xeroEmployeeId
                StaffManualMapping -> decision.xeroEmployeeId
                StaffStepApproved  -> decision.xeroEmployeeId
                PayItemCreate      -> decision.xeroEmployeeId
                AccountCode        -> decision.xeroEmployeeId
                CalendarSelection  -> decision.xeroEmployeeId
        verifiedMappingSelection = do
            guard (xeroStaffMappingIsVerified mapping.mappingStatus)
            mapping.xeroEmployeeId
        notApplicableSelection = do
            guard (xeroStaffMappingIsNotApplicable mapping.mappingStatus && isJust mapping.updatedByUserId)
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


staffRowIsConfirmed :: XeroPreparationStaffRow -> Bool
staffRowIsConfirmed row =
    staffHasVerifiedXeroEmployee row || staffMarkedNotPaidThroughXero row

staffRowHasPendingAutoMatch :: XeroPreparationStaffRow -> Bool
staffRowHasPendingAutoMatch row =
    maybe False isPendingAutoMatch row.preparationStaffDecision
    where
        isPendingAutoMatch decision =
            xeroPreparationKindIsStaffAutoMatch decision.decisionKind && xeroPreparationDecisionIsPending decision.decisionStatus

staffRowNeedsAttention :: XeroPreparationStaffRow -> Bool
staffRowNeedsAttention row =
    row.preparationStaffNeedsDecision
        || maybe False (xeroPreparationDecisionIsPending . (.decisionStatus)) row.preparationStaffDecision
        || Text.null (currentStaffEmployeeSelection row)

staffMappingStatus :: XeroPreparationStaffRow -> Text
staffMappingStatus row
    | staffMarkedNotPaidThroughXero row = "not_applicable"
    | staffHasVerifiedXeroEmployee row = "verified"
    | otherwise = "unmapped"

staffHasVerifiedXeroEmployee :: XeroPreparationStaffRow -> Bool
staffHasVerifiedXeroEmployee row =
    xeroStaffMappingIsVerified row.preparationStaffMappingRow.mappingRowMapping.mappingStatus
        && isJust row.preparationStaffMappingRow.mappingRowMapping.xeroEmployeeId

staffMarkedNotPaidThroughXero :: XeroPreparationStaffRow -> Bool
staffMarkedNotPaidThroughXero row =
    xeroStaffMappingIsNotApplicable row.preparationStaffMappingRow.mappingRowMapping.mappingStatus
        && isJust row.preparationStaffMappingRow.mappingRowMapping.updatedByUserId

staffName :: Staff -> Text
staffName staff = Text.strip (staff.firstName <> " " <> staff.lastName)

staffSecondaryLabel :: XeroPreparationStaffRow -> Text
staffSecondaryLabel row =
    maybe "" (.email) row.preparationStaffMappingRow.mappingRowUser
