module Web.View.RosterWeeks.StaffSelfServicePanel
    ( renderRosterStaffSelfServicePanelFragment
    , renderRosterStaffSelfServiceLeaveFormFragment
    , renderRosterStaffSelfServiceLeaveFormFragmentForRoster
    , renderRosterStaffSelfServiceLeaveFormFragmentWithSwap
    , rosterStaffSelfServiceLeaveFormFragmentId
    , rosterStaffSelfServicePanelFragmentId
    , rosterStaffSelfServiceTimesheetSurfaceId
    ) where

import Application.Helper.FrontendContract.Surface.Runtime (FrontendSurfaceActionRoute (..),
                                                            FrontendSurfaceMountConfig (..),
                                                            FrontendSurfaceMountedFragment (..),
                                                            SurfaceImpl (..),
                                                            renderFrontendSurfaceActionForm,
                                                            renderFrontendSurfaceMount)
import qualified Application.Helper.FrontendContract.Surface.Timesheets as Surface
import Application.Helper.Url (appendQueryParams)
import Data.Time.Calendar (diffDays)
import Web.RosterWeeks.FrontendSurface (rosterSurfaceAction)
import Web.RosterWeeks.Types (RosterStaffSelfServicePanel (..))
import Web.Timesheets.FrontendSurface (TimesheetWeekScopeValue (..),
                                       TimesheetsMountStateValue (..),
                                       timesheetsCandidateMountedFragments,
                                       timesheetsSurfaceImpl)
import Web.View.LeaveRequests.New (renderLeaveRequestFormFields)
import Web.View.Prelude
import Web.View.Timesheets.Index (TimesheetDayRenderModel (..),
                                  renderDaySection)

rosterStaffSelfServicePanelFragmentId :: Text
rosterStaffSelfServicePanelFragmentId = "roster-staff-self-service-panel-fragment"

rosterStaffSelfServiceLeaveFormFragmentId :: Text
rosterStaffSelfServiceLeaveFormFragmentId = "roster-staff-self-service-leave-form-fragment"

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
                        {renderRosterStaffSelfServiceLeaveFormFragmentForRoster panel.quickToolsRosterGroupId panel.quickToolsRosterWeekOffset panel.quickToolsLeaveRequest}
                    </div>
                </div>
            </div>
        </div>
    |]

renderRosterStaffSelfServiceLeaveFormFragment :: (?context :: ControllerContext) => LeaveRequest -> Html
renderRosterStaffSelfServiceLeaveFormFragment =
    renderRosterStaffSelfServiceLeaveFormFragmentWithSwap Nothing Nothing

renderRosterStaffSelfServiceLeaveFormFragmentForRoster :: (?context :: ControllerContext) => Id RosterGroup -> Int -> LeaveRequest -> Html
renderRosterStaffSelfServiceLeaveFormFragmentForRoster rosterGroupId weekOffset =
    renderRosterStaffSelfServiceLeaveFormFragmentWithSwap Nothing (Just (rosterGroupId, weekOffset))

renderRosterStaffSelfServiceLeaveFormFragmentWithSwap :: (?context :: ControllerContext) => Maybe Text -> Maybe (Id RosterGroup, Int) -> LeaveRequest -> Html
renderRosterStaffSelfServiceLeaveFormFragmentWithSwap maybeSwapOob maybeRosterScope leaveRequest = [hsx|
    <div id={rosterStaffSelfServiceLeaveFormFragmentId} hx-swap-oob={maybeSwapOob}>
        {renderRosterStaffSelfServiceLeaveForm maybeRosterScope leaveRequest}
    </div>
|]

renderRosterStaffSelfServiceLeaveForm :: (?context :: ControllerContext) => Maybe (Id RosterGroup, Int) -> LeaveRequest -> Html
renderRosterStaffSelfServiceLeaveForm maybeRosterScope leaveRequest =
    renderFrontendSurfaceActionForm
        (rosterSurfaceAction "create-roster-self-service-leave-request")
        FrontendSurfaceActionRoute
            { actionRouteUrl = rosterCreateLeaveRequestPath
            , actionRouteFields = []
            , actionRouteCustomHtmx = []
            , actionRouteStandardUrl = Just rosterCreateLeaveRequestPath
            , actionRouteExtraAttrs =
                [ ("id", "roster-staff-self-service-leave-form")
                , ("data-disable-javascript-submission", "true")
                ]
            }
        [hsx|
            <input type="hidden" name="responseContext" value="roster"/>
            {renderRosterScopeFields maybeRosterScope}
            {renderLeaveRequestFormFields leaveRequest}
            <div class="d-grid mt-4 app-form-width">
                <button type="submit" class="btn btn-primary">Add unavailable time</button>
            </div>
        |]

renderRosterScopeFields :: Maybe (Id RosterGroup, Int) -> Html
renderRosterScopeFields Nothing = mempty
renderRosterScopeFields (Just (rosterGroupId, weekOffset)) = [hsx|
    <input type="hidden" name="rosterGroupId" value={tshow rosterGroupId}/>
    <input type="hidden" name="weekOffset" value={tshow weekOffset}/>
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

timesheetSurface :: (?context :: ControllerContext) => RosterStaffSelfServicePanel -> SurfaceImpl Surface.TimesheetsSurface
timesheetSurface panel =
    let scope = TimesheetWeekScopeValue
            { timesheetWeekVenueId = unpackId panel.quickToolsVenueId
            , timesheetWeekWeekOffset = panel.quickToolsTimesheetWeekOffset
            }
        mountState = TimesheetsMountStateValue
            { timesheetsMountShowApproved = True
            , timesheetsMountShowAllStaff = False
            , timesheetsMountStaffFilterId = Nothing
            }
        impl = timesheetsSurfaceImpl scope mountState
        dayTargetId = "timesheet-day-section-" <> tshow (quickToolsTimesheetDayOffset panel)
        dayFragment = filter (\fragment -> fragment.mountedFragmentTargetId == dayTargetId) (timesheetsCandidateMountedFragments scope mountState)
     in impl { surfaceImplMountConfig = impl.surfaceImplMountConfig { mountFragments = dayFragment } }

quickToolsTimesheetDayOffset :: RosterStaffSelfServicePanel -> Int
quickToolsTimesheetDayOffset panel =
    fromInteger (diffDays panel.quickToolsOperationalDay panel.quickToolsTimesheetWeekStartDate)
