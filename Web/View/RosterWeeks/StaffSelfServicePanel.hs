module Web.View.RosterWeeks.StaffSelfServicePanel
    ( renderRosterStaffSelfServicePanelFragment
    , renderRosterStaffSelfServiceLeaveFormFragment
    , rosterStaffSelfServiceLeaveFormFragmentId
    , rosterStaffSelfServicePanelFragmentId
    , rosterStaffSelfServiceTimesheetLiveSurfaceId
    ) where

import Application.Helper.LiveSurface (LiveSurfaceConfig (..),
                                       liveSurfaceConfigJson,
                                       mkTypedDefinedLiveSurface)
import Application.Helper.Url (appendQueryParams)
import Data.Time.Calendar (diffDays)
import Web.RosterWeeks.Types (RosterStaffSelfServicePanel (..))
import Web.Timesheets.Projection (TimesheetProjectionRequest (..),
                                  timesheetLiveSurfaceDefinition)
import Web.View.LeaveRequests.New (renderLeaveRequestFormFields)
import Web.View.Prelude
import Web.View.Timesheets.Index (TimesheetDayRenderModel (..),
                                  renderDaySection)

rosterStaffSelfServicePanelFragmentId :: Text
rosterStaffSelfServicePanelFragmentId = "roster-staff-self-service-panel-fragment"

rosterStaffSelfServiceLeaveFormFragmentId :: Text
rosterStaffSelfServiceLeaveFormFragmentId = "roster-staff-self-service-leave-form-fragment"

rosterStaffSelfServiceTimesheetLiveSurfaceId :: Text
rosterStaffSelfServiceTimesheetLiveSurfaceId = "roster-staff-self-service-timesheet-live-surface"

renderRosterStaffSelfServicePanelFragment :: (?context :: ControllerContext) => Maybe RosterStaffSelfServicePanel -> Html
renderRosterStaffSelfServicePanelFragment Nothing = mempty
renderRosterStaffSelfServicePanelFragment (Just panel)
    | currentUserIsManager = mempty
    | currentUserIsSupportAdmin = mempty
    | otherwise = [hsx|
        <div id={rosterStaffSelfServicePanelFragmentId}
             class="col-12 col-xl-4 col-xxl-2 roster-layout-side roster-staff-self-service-panel">
            <div class="roster-staff-self-service-stack">
                <div class="app-panel roster-quick-tool-panel">
                    <div class="app-panel-body p-0">
                        <div id={rosterStaffSelfServiceTimesheetLiveSurfaceId}
                             class="roster-quick-tool-timesheet"
                             data-live-update-surface={liveSurfaceConfigJson (timesheetLiveSurface panel)}>
                            {renderDaySection (timesheetDayModel panel)}
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
                        {renderRosterStaffSelfServiceLeaveFormFragment panel.quickToolsLeaveRequest}
                    </div>
                </div>
            </div>
        </div>
    |]

renderRosterStaffSelfServiceLeaveFormFragment :: (?context :: ControllerContext) => LeaveRequest -> Html
renderRosterStaffSelfServiceLeaveFormFragment leaveRequest = [hsx|
    <div id={rosterStaffSelfServiceLeaveFormFragmentId}>
        <form id="roster-staff-self-service-leave-form"
              method="POST"
              action={rosterCreateLeaveRequestPath}
              data-disable-javascript-submission="true"
              hx-post={rosterCreateLeaveRequestPath}
              hx-target={"#" <> rosterStaffSelfServiceLeaveFormFragmentId}
              hx-swap="outerHTML"
              hx-push-url="false">
            <input type="hidden" name="responseContext" value="roster"/>
            {renderLeaveRequestFormFields leaveRequest}
            <div class="d-grid mt-4 app-form-width">
                <button type="submit" class="btn btn-primary">Add unavailable time</button>
            </div>
        </form>
    </div>
|]

rosterCreateLeaveRequestPath :: Text
rosterCreateLeaveRequestPath =
    appendQueryParams
        (pathTo CreateLeaveRequestAction)
        [("responseContext", "roster")]

timesheetDayModel :: RosterStaffSelfServicePanel -> TimesheetDayRenderModel
timesheetDayModel panel =
    let operationalDayOffset = quickToolsTimesheetDayOffset panel
     in
    TimesheetDayRenderModel
        { dayEntries = panel.quickToolsTimesheetEntries
        , dayStaffMembers = panel.quickToolsStaffMembers
        , dayShiftTypes = panel.quickToolsShiftTypes
        , dayToday = panel.quickToolsOperationalDay
        , dayEditWindowDays = panel.quickToolsTimesheetEditWindowDays
        , dayWeekOffset = panel.quickToolsTimesheetWeekOffset
        , dayWeekStartDate = panel.quickToolsTimesheetWeekStartDate
        , dayShowApproved = True
        , dayShowAllStaff = False
        , dayStaffFilterId = Nothing
        , dayOffset = operationalDayOffset
        }

timesheetLiveSurface :: (?context :: ControllerContext) => RosterStaffSelfServicePanel -> LiveSurfaceConfig
timesheetLiveSurface panel =
    mkTypedDefinedLiveSurface timesheetLiveSurfaceDefinition (timesheetProjectionRequest panel)

timesheetProjectionRequest :: RosterStaffSelfServicePanel -> TimesheetProjectionRequest
timesheetProjectionRequest panel =
    TimesheetProjectionRequest
        { projectionWeekOffset = panel.quickToolsTimesheetWeekOffset
        , projectionShowApproved = True
        , projectionShowAllStaff = False
        , projectionStaffFilterId = Nothing
        }

quickToolsTimesheetDayOffset :: RosterStaffSelfServicePanel -> Int
quickToolsTimesheetDayOffset panel =
    fromInteger (diffDays panel.quickToolsOperationalDay panel.quickToolsTimesheetWeekStartDate)
