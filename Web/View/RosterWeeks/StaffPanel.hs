module Web.View.RosterWeeks.StaffPanel
    ( renderRosterStaffPanelFragment
    , renderRosterStaffPanelFragmentOob
    , renderRosterStaffPanelFragmentWithSwap
    ) where

import Application.Helper.View (staffDisplayName)
import Data.List (sortBy)
import qualified Data.Text as Text
import Web.RosterWeeks.Dom (rosterStaffPanelFragmentId)
import Web.RosterWeeks.Types (RosterStaffPanelEntry (..), RosterStaffPanelScope (..))
import Web.View.Prelude

renderRosterStaffPanelFragment :: (?context :: ControllerContext) => Int -> Id RosterGroup -> Bool -> RosterStaffPanelScope -> [RosterStaffPanelEntry] -> Html
renderRosterStaffPanelFragment =
    renderRosterStaffPanelFragmentWithSwap Nothing

renderRosterStaffPanelFragmentOob :: (?context :: ControllerContext) => Int -> Id RosterGroup -> Bool -> RosterStaffPanelScope -> [RosterStaffPanelEntry] -> Html
renderRosterStaffPanelFragmentOob =
    renderRosterStaffPanelFragmentWithSwap (Just "outerHTML")

renderRosterStaffPanelFragmentWithSwap :: (?context :: ControllerContext) => Maybe Text -> Int -> Id RosterGroup -> Bool -> RosterStaffPanelScope -> [RosterStaffPanelEntry] -> Html
renderRosterStaffPanelFragmentWithSwap maybeSwapOob weekOffset currentRosterGroupId hasMultipleRosterGroups panelScope panelStaff =
    if currentUserIsManager
        then [hsx|
            <div id={rosterStaffPanelFragmentId}
                 class="col-12 col-xl-4 col-xxl-3 roster-layout-side"
                 hx-swap-oob={maybeSwapOob}>
                {renderRosterStaffPanel weekOffset currentRosterGroupId hasMultipleRosterGroups panelScope panelStaff}
            </div>
        |]
        else mempty

renderRosterStaffPanel :: Int -> Id RosterGroup -> Bool -> RosterStaffPanelScope -> [RosterStaffPanelEntry] -> Html
renderRosterStaffPanel weekOffset currentRosterGroupId hasMultipleRosterGroups panelScope panelStaff = [hsx|
    <div class="app-panel roster-staff-panel">
        <div class="app-panel-body">
            <div class="roster-staff-panel-header">
                <div>
                    <h2 class="h5 mb-0">Staff</h2>
                </div>
                <div class="d-flex flex-column align-items-end gap-2">
                    <button type="button"
                            class="btn btn-sm btn-outline-primary"
                            hx-get={appendQueryParams (pathTo NewStaffAction) [("weekOffset", tshow weekOffset), ("rosterGroupId", tshow currentRosterGroupId)]}
                            hx-target={"#" <> htmxModalMountId}
                            hx-swap="innerHTML"
                            hx-push-url="false">
                        Add trial staff
                    </button>
                    {when hasMultipleRosterGroups (renderStaffScopeToggle weekOffset currentRosterGroupId panelScope)}
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
                            <th scope="col" class="roster-staff-action-head">
                                <span class="visually-hidden">Locate shifts</span>
                            </th>
                        </tr>
                    </thead>
                    <tbody class="roster-staff-table-body">
                        {forEach renderedPanelStaff (renderRosterStaffPanelEntry panelStaffMembers weekOffset currentRosterGroupId)}
                    </tbody>
                </table>
            </div>
        </div>
    </div>
|]
    where
        panelStaffMembers = map (.staff) panelStaff
        renderedPanelStaff = sortRosterStaffPanelEntries panelStaffMembers panelStaff

sortRosterStaffPanelEntries :: [Staff] -> [RosterStaffPanelEntry] -> [RosterStaffPanelEntry]
sortRosterStaffPanelEntries panelStaffMembers =
    sortBy \left right ->
        compare (sortName left) (sortName right)
            <> compare (get #id left.staff) (get #id right.staff)
    where
        sortName entry = Text.toCaseFold (staffDisplayName panelStaffMembers entry.staff)

renderStaffScopeToggle :: (?context :: ControllerContext) => Int -> Id RosterGroup -> RosterStaffPanelScope -> Html
renderStaffScopeToggle weekOffset currentRosterGroupId panelScope = [hsx|
    <form method="GET"
          action={ShowRosterWeekStaffPanelFragmentAction weekOffset}
          class="mb-0 roster-staff-scope-toggle">
        <input type="hidden" name="rosterGroupId" value={tshow currentRosterGroupId} />
        {renderStaffScopeToggleButton weekOffset currentRosterGroupId panelScope}
    </form>
|]

renderStaffScopeToggleButton :: (?context :: ControllerContext) => Int -> Id RosterGroup -> RosterStaffPanelScope -> Html
renderStaffScopeToggleButton weekOffset currentRosterGroupId panelScope =
    renderAppToggleButton $ (defaultAppToggleButtonConfig (staffScopeToggleInputId currentRosterGroupId) (panelScope == RosterStaffPanelAllVenue) [hsx|<span class="small fw-semibold">Show all staff</span>|])
        { appToggleInputName = Just "staffScope"
        , appToggleInputValue = "all"
        , appToggleButtonClass = "btn-sm"
        , appToggleRoleSwitch = True
        , appToggleHxGet = Just (pathTo (ShowRosterWeekStaffPanelFragmentAction weekOffset))
        , appToggleHxTrigger = Just "change"
        , appToggleHxInclude = Just "closest form"
        , appToggleHxTarget = Just staffPanelTargetSelector
        , appToggleHxSwap = Just "outerHTML"
        , appToggleHxPushUrl = Just "false"
        }

staffPanelTargetSelector :: Text
staffPanelTargetSelector = "#" <> rosterStaffPanelFragmentId

staffScopeToggleInputId :: Id RosterGroup -> Text
staffScopeToggleInputId rosterGroupId = "roster-staff-scope-toggle-" <> tshow rosterGroupId

renderRosterStaffPanelEntry :: [Staff] -> Int -> Id RosterGroup -> RosterStaffPanelEntry -> Html
renderRosterStaffPanelEntry panelStaffMembers weekOffset currentRosterGroupId entry =
    let
        staffDisplayLabel = staffDisplayName panelStaffMembers entry.staff
        staffRoleLabel = humanizeStaffRole entry.userRole
     in
        [hsx|
        <tr class="roster-staff-panel-entry"
                data-roster-staff-id={tshow entry.staff.id}
                data-roster-staff-name={staffDisplayLabel}
                data-roster-staff-role={staffRoleLabel}
                data-roster-staff-assigned={tshow entry.assignedShiftCount}
                data-roster-staff-ideal={tshow entry.staff.idealShiftsPerWeek}
                role="button"
                hx-get={appendQueryParams (pathTo (EditStaffAction entry.staff.id)) [("weekOffset", tshow weekOffset), ("rosterGroupId", tshow currentRosterGroupId)]}
                hx-target={"#" <> htmxModalMountId}
                hx-swap="innerHTML"
                hx-push-url="false"
                tabindex="0">
                <th scope="row" class="roster-staff-cell roster-staff-name">
                    <div class="roster-staff-name-primary">{staffDisplayLabel}</div>
                </th>
                <td class="roster-staff-cell roster-staff-role">{staffRoleLabel}</td>
                <td class="roster-staff-cell roster-staff-shifts">{renderShiftSummary entry}</td>
                <td class="roster-staff-cell roster-staff-action">
                    <button type="button"
                            class="btn btn-sm btn-outline-secondary app-icon-button roster-staff-locate-button"
                            data-roster-staff-highlight-toggle="true"
                            aria-label={"Locate shifts for " <> staffDisplayLabel}
                            aria-pressed="false">
                        <svg aria-hidden="true" viewBox="0 0 24 24" width="16" height="16">
                            <path d="M12 5.25c-4.55 0-8.2 3.95-9.55 6.15a1.15 1.15 0 0 0 0 1.2c1.35 2.2 5 6.15 9.55 6.15s8.2-3.95 9.55-6.15a1.15 1.15 0 0 0 0-1.2c-1.35-2.2-5-6.15-9.55-6.15Zm0 11a4.25 4.25 0 1 1 0-8.5 4.25 4.25 0 0 1 0 8.5Zm0-1.75a2.5 2.5 0 1 0 0-5 2.5 2.5 0 0 0 0 5Z" fill="currentColor"></path>
                        </svg>
                    </button>
                </td>
            </tr>
        |]

humanizeStaffRole :: Text -> Text
humanizeStaffRole "venue_admin" = "Venue Admin"
humanizeStaffRole "venue_owner" = "Venue Owner"
humanizeStaffRole "manager"     = "Manager"
humanizeStaffRole "supervisor"  = "Supervisor"
humanizeStaffRole "worker"      = "Worker"
humanizeStaffRole "trial"       = "TRIAL"
humanizeStaffRole other         = Text.toTitle (Text.replace "_" " " other)

renderShiftSummary :: RosterStaffPanelEntry -> Html
renderShiftSummary entry = [hsx|
    <span class="roster-staff-shifts-actual">{tshow entry.assignedShiftCount}</span>
    <span class="roster-staff-shifts-ideal">({tshow entry.staff.idealShiftsPerWeek})</span>
|]
