{-# LANGUAGE TypeApplications #-}

module Web.View.RosterWeeks.StaffSelfServicePanel
    ( renderRosterStaffSelfServicePanelFragment
    , rosterStaffSelfServicePanelFragmentId
    , rosterStaffSelfServiceTimesheetSurfaceId
    ) where

import Application.Helper.FrontendContract.Surface.Runtime (SurfaceImpl,
                                                            renderFrontendSurfaceMount)
import qualified Application.Helper.FrontendContract.Surface.Timesheets as Surface
import Data.Time.Calendar (diffDays)
import Web.LeaveRequests.SelfService (renderSelfServiceLeaveFormMount)
import Web.RosterWeeks.Types (RosterStaffSelfServicePanel (..))
import Web.Timesheets.FrontendSurface (TimesheetWeekScopeValue (..),
                                       TimesheetsMountStateValue (..),
                                       timesheetsDaySurfaceImpl)
import Web.View.Prelude
import Web.View.Timesheets.Index (TimesheetDayRenderModel (..),
                                  renderDaySection)

rosterStaffSelfServicePanelFragmentId :: Text
rosterStaffSelfServicePanelFragmentId = "roster-staff-self-service-panel-fragment"

rosterStaffSelfServiceTimesheetSurfaceId :: Text
rosterStaffSelfServiceTimesheetSurfaceId = "roster-staff-self-service-timesheet-live-surface"

renderRosterStaffSelfServicePanelFragment :: (?context :: ControllerContext) => Maybe RosterStaffSelfServicePanel -> Html
renderRosterStaffSelfServicePanelFragment Nothing = mempty
renderRosterStaffSelfServicePanelFragment (Just panel)
    | currentUserIsManager = mempty
    | currentUserIsSupportAdmin = mempty
    | otherwise = [hsx|
        <div id={rosterStaffSelfServicePanelFragmentId}
             class="col-12 col-xl-4 col-xxl-3 roster-layout-side roster-staff-self-service-panel">
            <div class="roster-staff-self-service-stack">
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
                        <div class="roster-staff-panel-header">
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
    |]

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
        , dayWeekOffset = panel.quickToolsTimesheetWeekOffset
        , dayWeekStartDate = panel.quickToolsTimesheetWeekStartDate
        , dayShowApproved = True
        , dayShowAllStaff = False
        , dayShowSuggestions = False
        , dayStaffFilterId = Nothing
        , dayOffset = operationalDayOffset
        }

timesheetSurface :: (?context :: ControllerContext) => RosterStaffSelfServicePanel -> SurfaceImpl Surface.TimesheetsSurface
timesheetSurface panel =
    let scope = TimesheetWeekScopeValue
            { timesheetWeekVenueId = unpackId panel.quickToolsVenueId
            , timesheetWeekWeekOffset = panel.quickToolsTimesheetWeekOffset
            }
        mountState = TimesheetsMountStateValue
            { timesheetsMountShowApproved = True
            , timesheetsMountShowAllStaff = False
            , timesheetsMountShowSuggestions = False
            , timesheetsMountStaffFilterId = Nothing
            }
     in timesheetsDaySurfaceImpl scope mountState (quickToolsTimesheetDayOffset panel)

quickToolsTimesheetDayOffset :: RosterStaffSelfServicePanel -> Int
quickToolsTimesheetDayOffset panel =
    fromInteger (diffDays panel.quickToolsOperationalDay panel.quickToolsTimesheetWeekStartDate)
