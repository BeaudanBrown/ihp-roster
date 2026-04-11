module Web.View.RosterWeeks.StaffPanel
    ( renderRosterStaffPanelFragment
    , renderRosterStaffPanelFragmentOob
    ) where

import Application.Helper.View (appendQueryParams, staffDisplayName)
import qualified Data.Text as Text
import Web.RosterWeeks.Dom (rosterStaffPanelFragmentId)
import Web.RosterWeeks.Types (RosterStaffPanelEntry (..))
import Web.View.Prelude

renderRosterStaffPanelFragment :: (?context :: ControllerContext) => Int -> Id RosterGroup -> [RosterStaffPanelEntry] -> Html
renderRosterStaffPanelFragment =
    renderRosterStaffPanelFragmentWithSwap Nothing

renderRosterStaffPanelFragmentOob :: (?context :: ControllerContext) => Int -> Id RosterGroup -> [RosterStaffPanelEntry] -> Html
renderRosterStaffPanelFragmentOob =
    renderRosterStaffPanelFragmentWithSwap (Just "outerHTML")

renderRosterStaffPanelFragmentWithSwap :: (?context :: ControllerContext) => Maybe Text -> Int -> Id RosterGroup -> [RosterStaffPanelEntry] -> Html
renderRosterStaffPanelFragmentWithSwap maybeSwapOob weekOffset currentRosterGroupId panelStaff =
    if currentUserIsManager
        then [hsx|
            <div id={rosterStaffPanelFragmentId}
                 class="col-12 col-xl-4 col-xxl-3 roster-layout-side"
                 hx-swap-oob={maybeSwapOob}>
                {renderRosterStaffPanel weekOffset currentRosterGroupId panelStaff}
            </div>
        |]
        else mempty

renderRosterStaffPanel :: Int -> Id RosterGroup -> [RosterStaffPanelEntry] -> Html
renderRosterStaffPanel weekOffset currentRosterGroupId panelStaff = [hsx|
    <div class="app-panel roster-staff-panel">
        <div class="app-panel-body">
            <div class="roster-staff-panel-header">
                <div>
                    <h2 class="h5 mb-1">Staff</h2>
                    <div class="roster-staff-panel-summary">{tshow (length panelStaff)} active staff</div>
                </div>
            </div>

            <div class="roster-staff-panel-list">
                <table class="roster-staff-table">
                    <thead class="roster-staff-table-head">
                        <tr>
                            <th scope="col" aria-sort="none">
                                <button type="button" class="roster-staff-sort-button" data-roster-staff-sort-key="name">
                                    Name
                                </button>
                            </th>
                            <th scope="col" class="roster-staff-role-head" aria-sort="none">
                                <button type="button" class="roster-staff-sort-button" data-roster-staff-sort-key="role">
                                    Role
                                </button>
                            </th>
                            <th scope="col" class="roster-staff-metric-head" aria-sort="none">
                                <button type="button" class="roster-staff-sort-button roster-staff-sort-button-metric" data-roster-staff-sort-key="shifts">
                                    Shifts
                                </button>
                            </th>
                            <th scope="col" class="roster-staff-action-head">Edit</th>
                        </tr>
                    </thead>
                    <tbody class="roster-staff-table-body">
                        {forEach panelStaff (renderRosterStaffPanelEntry panelStaffMembers weekOffset currentRosterGroupId)}
                    </tbody>
                </table>
            </div>
        </div>
    </div>
|]
    where
        panelStaffMembers = map (.staff) panelStaff

renderRosterStaffPanelEntry :: [Staff] -> Int -> Id RosterGroup -> RosterStaffPanelEntry -> Html
renderRosterStaffPanelEntry panelStaffMembers weekOffset currentRosterGroupId entry =
    let
        staffDisplayLabel = staffDisplayName panelStaffMembers entry.staff
        staffRoleLabel = humanizeStaffRole entry.userRole
     in
        [hsx|
            <tr class="roster-staff-panel-entry"
                data-roster-staff-name={staffDisplayLabel}
                data-roster-staff-role={staffRoleLabel}
                data-roster-staff-assigned={tshow entry.assignedShiftCount}
                data-roster-staff-ideal={tshow entry.staff.idealShiftsPerWeek}>
                <th scope="row" class="roster-staff-cell roster-staff-name">
                    <div class="roster-staff-name-primary">{staffDisplayLabel}</div>
                </th>
                <td class="roster-staff-cell roster-staff-role">{staffRoleLabel}</td>
                <td class="roster-staff-cell roster-staff-shifts">{renderShiftSummary entry}</td>
                <td class="roster-staff-cell roster-staff-action">
                    <button type="button"
                       class="btn btn-sm btn-outline-secondary roster-staff-edit-button"
                       hx-get={appendQueryParams (pathTo (EditStaffAction entry.staff.id)) [("weekOffset", tshow weekOffset), ("rosterGroupId", tshow currentRosterGroupId)]}
                       hx-target={"#" <> htmxModalMountId}
                       hx-swap="innerHTML"
                       hx-push-url="false">
                        Edit
                    </button>
                </td>
            </tr>
        |]

humanizeStaffRole :: Text -> Text
humanizeStaffRole "venue_admin" = "Venue Admin"
humanizeStaffRole "venue_owner" = "Venue Owner"
humanizeStaffRole "manager"     = "Manager"
humanizeStaffRole "worker"      = "Worker"
humanizeStaffRole other         = Text.toTitle (Text.replace "_" " " other)

renderShiftSummary :: RosterStaffPanelEntry -> Html
renderShiftSummary entry = [hsx|
    <span class="roster-staff-shifts-actual">{tshow entry.assignedShiftCount}</span>
    <span class="roster-staff-shifts-ideal">({tshow entry.staff.idealShiftsPerWeek})</span>
|]
