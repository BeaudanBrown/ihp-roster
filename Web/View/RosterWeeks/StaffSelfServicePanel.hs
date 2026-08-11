{-# LANGUAGE TypeApplications #-}

module Web.View.RosterWeeks.StaffSelfServicePanel
    ( renderRosterStaffSelfServicePanelFragment
    , renderRosterStaffSelfServicePanelFragmentOob
    , rosterStaffSelfServicePanelFragmentId
    , rosterStaffSelfServiceTimesheetSurfaceId
    ) where

import Application.Helper.Controller (currentUserIsUnimpersonatedSuperAdmin)
import Application.Helper.FrontendContract.Surface.Roster.SidePanel (rosterSidePanelRenderAttrs)
import Application.Helper.FrontendContract.Surface.Roster.StaffPanel (RosterSelfServicePanelTab (..),
                                                                      rosterSelfServicePanelTabAttrs)
import Application.Helper.FrontendContract.Surface.Runtime (SurfaceImpl,
                                                            renderFrontendSurfaceMount)
import qualified Application.Helper.FrontendContract.Surface.Timesheets as Surface
import Data.Time.Calendar (addDays, diffDays)
import Web.LeaveRequests.SelfService (renderSelfServiceLeaveFormMount)
import Web.RosterWeeks.Dom (rosterSelfServiceQuickToolsPaneId,
                            rosterSelfServiceQuickToolsTabId,
                            rosterSelfServiceSettingsPaneId,
                            rosterSelfServiceSettingsTabId)
import Web.RosterWeeks.Types (RosterStaffSelfServicePanel (..))
import Web.Timesheets.FrontendSurface (TimesheetWeekScopeValue (..),
                                       TimesheetsMountStateValue (..),
                                       timesheetsDaySurfaceImpl)
import Web.View.Prelude
import Web.View.RosterWeeks.SettingsPanel (renderRosterOwnLiveShiftHighlightPreferenceForm)
import Web.View.Timesheets.Index (TimesheetDayRenderModel (..),
                                  renderDaySection)

rosterStaffSelfServicePanelFragmentId :: Text
rosterStaffSelfServicePanelFragmentId = "roster-staff-self-service-panel-fragment"

rosterStaffSelfServiceTimesheetSurfaceId :: Text
rosterStaffSelfServiceTimesheetSurfaceId = "roster-staff-self-service-timesheet-live-surface"

renderRosterStaffSelfServicePanelFragment :: (?context :: ControllerContext) => Maybe RosterStaffSelfServicePanel -> Html
renderRosterStaffSelfServicePanelFragment = renderRosterStaffSelfServicePanelFragmentWithSwap Nothing

renderRosterStaffSelfServicePanelFragmentOob :: (?context :: ControllerContext) => Maybe RosterStaffSelfServicePanel -> Html
renderRosterStaffSelfServicePanelFragmentOob = renderRosterStaffSelfServicePanelFragmentWithSwap (Just "outerHTML")

renderRosterStaffSelfServicePanelFragmentWithSwap :: (?context :: ControllerContext) => Maybe Text -> Maybe RosterStaffSelfServicePanel -> Html
renderRosterStaffSelfServicePanelFragmentWithSwap _ Nothing = mempty
renderRosterStaffSelfServicePanelFragmentWithSwap maybeSwapOob (Just panel)
    | currentUserIsManager = mempty
    | currentUserIsUnimpersonatedSuperAdmin = mempty
    | otherwise =
        renderSidePanelPanelRegion rosterSidePanelRenderAttrs SidePanelRegionConfig
            { sidePanelRegionId = Just rosterStaffSelfServicePanelFragmentId
            , sidePanelRegionClass = "col-12 col-xl-4 col-xxl-3 roster-layout-side roster-staff-self-service-panel"
            , sidePanelRegionExtraAttrs = maybe [] (\swap -> [("hx-swap-oob", swap)]) maybeSwapOob
            }
            [hsx|
                <div class="app-panel app-side-panel-card app-side-panel-scroll roster-staff-panel">
                    <div class="app-panel-body">
                        {renderSidePanelTabs "Roster side panel" tabs}
                        <div class="tab-content app-side-panel-tab-content roster-staff-panel-tab-content">
                            <div class="tab-pane show active app-side-panel-pane roster-staff-panel-pane"
                                 id={rosterSelfServiceQuickToolsPaneId}
                                 role="tabpanel"
                                 aria-labelledby={rosterSelfServiceQuickToolsTabId}
                                 tabindex="0">
                                <div class="app-side-panel-scroll-body roster-staff-self-service-stack">
                                    <div class="app-panel roster-quick-tool-panel">
                                        <div class="app-panel-body p-0 roster-quick-tool-panel-body">
                                            <div id={rosterStaffSelfServiceTimesheetSurfaceId}
                                                 class="roster-quick-tool-timesheet">
                                                {renderFrontendSurfaceMount (timesheetSurface panel) (renderDaySection (timesheetDayModel panel))}
                                            </div>
                                        </div>
                                    </div>
                                    <div class="app-panel roster-quick-tool-panel">
                                        <div class="app-panel-body">
                                            <div class="app-side-panel-content-header roster-staff-panel-header">
                                                <div>
                                                    <h2 class="h5 mb-1">Unavailability</h2>
                                                    <div class="roster-staff-panel-summary">Add unavailable time</div>
                                                </div>
                                            </div>
                                            {forEach panel.quickToolsStaffMembers (\staff -> renderSelfServiceLeaveFormMount "roster" False staff panel.quickToolsLeaveRequest [])}
                                        </div>
                                    </div>
                                </div>
                            </div>
                            <div class="tab-pane app-side-panel-pane app-side-panel-settings-pane roster-staff-panel-pane roster-staff-panel-settings-pane"
                                 id={rosterSelfServiceSettingsPaneId}
                                 role="tabpanel"
                                 aria-labelledby={rosterSelfServiceSettingsTabId}
                                 tabindex="0">
                                <div class="roster-settings-stack">
                                    <section class="roster-settings-section">
                                        <div class="roster-settings-section-heading">
                                            <i class="bi bi-eye" aria-hidden="true"></i>
                                            <h2 class="h6 mb-0">Display</h2>
                                        </div>
                                        {renderRosterOwnLiveShiftHighlightPreferenceForm panel.quickToolsTimesheetWeekStartDate panel.quickToolsRosterGroupId panel.quickToolsHighlightOwnLiveShifts}
                                    </section>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>
            |]
  where
    tabs =
        [ SidePanelTabConfig rosterSelfServiceQuickToolsTabId rosterSelfServiceQuickToolsPaneId "Quick tools" "bi bi-lightning" True "roster-staff-panel-tab" (rosterSelfServicePanelTabAttrs RosterQuickToolsTab)
        , SidePanelTabConfig rosterSelfServiceSettingsTabId rosterSelfServiceSettingsPaneId "Settings" "bi bi-sliders" False "roster-staff-panel-tab" (rosterSelfServicePanelTabAttrs RosterSelfServiceSettingsTab)
        ]

timesheetDayModel :: RosterStaffSelfServicePanel -> TimesheetDayRenderModel
timesheetDayModel panel =
    let operationalDayOffset = quickToolsTimesheetDayOffset panel
     in
    TimesheetDayRenderModel
        { dayEntries = panel.quickToolsTimesheetEntries
        , daySuggestions = []
        , dayStaffMembers = panel.quickToolsStaffMembers
        , dayShiftTypes = panel.quickToolsShiftTypes
        , dayToday = panel.quickToolsOperationalDay
        , dayEditWindowDays = panel.quickToolsTimesheetEditWindowDays
        , dayWeekStartDate = panel.quickToolsTimesheetWeekStartDate
        , dayCalendarRevision = panel.quickToolsCalendarRevision
        , dayStaffFilterId = Nothing
        , dayOffset = operationalDayOffset
        }

timesheetSurface :: (?context :: ControllerContext) => RosterStaffSelfServicePanel -> SurfaceImpl Surface.TimesheetsSurface
timesheetSurface panel =
    let scope = TimesheetWeekScopeValue
            { timesheetWeekVenueId = unpackId panel.quickToolsVenueId
                , timesheetWindowStart = panel.quickToolsTimesheetWeekStartDate
            , timesheetWindowEnd = addDays 7 panel.quickToolsTimesheetWeekStartDate
            , timesheetCalendarRevision = panel.quickToolsCalendarRevision
            }
        mountState = TimesheetsMountStateValue
            { timesheetsMountStaffFilterId = Nothing }
     in timesheetsDaySurfaceImpl scope mountState (quickToolsTimesheetDayOffset panel)

quickToolsTimesheetDayOffset :: RosterStaffSelfServicePanel -> Int
quickToolsTimesheetDayOffset panel =
    fromInteger (diffDays panel.quickToolsOperationalDay panel.quickToolsTimesheetWeekStartDate)
