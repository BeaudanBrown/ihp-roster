{-# LANGUAGE TypeApplications #-}

module Web.View.RosterWeeks.StaffSelfServicePanel
    ( renderRosterStaffSelfServicePanelFragment
    , renderRosterStaffSelfServiceLeaveFormFragment
    , renderRosterStaffSelfServiceLeaveFormFragmentForRoster
    , renderRosterStaffSelfServiceLeaveFormFragmentWithSwap
    , rosterStaffSelfServiceLeaveFormFragmentId
    , rosterStaffSelfServicePanelFragmentId
    , rosterStaffSelfServiceTimesheetSurfaceId
    ) where

import qualified Application.Helper.FrontendContract.Surface.Roster as RosterSurface
import qualified Application.Helper.FrontendContract.Surface.Roster.Action as RosterAction
import Application.Helper.FrontendContract.Surface.Runtime (FrontendSurfaceActionRoute (..),
                                                            SurfaceImpl,
                                                            renderFrontendSurfaceActionForm,
                                                            renderFrontendSurfaceMount)
import qualified Application.Helper.FrontendContract.Surface.Timesheets as Surface
import Application.Helper.FrontendContract.Surface.Values
import Application.Helper.Url (appendQueryParams)
import Data.Time.Calendar (diffDays)
import Web.RosterWeeks.Types (RosterStaffSelfServicePanel (..))
import Web.Timesheets.FrontendSurface (TimesheetWeekScopeValue (..),
                                       TimesheetsMountStateValue (..),
                                       timesheetsDaySurfaceImpl)
import Web.View.LeaveRequests.New (LeaveRequestFieldNames (..),
                                   renderLeaveRequestFormFieldsWithNames)
import Web.View.Prelude
import Web.View.Timesheets.Index (TimesheetDayRenderModel (..),
                                  renderDaySection)

rosterStaffSelfServicePanelFragmentId :: Text
rosterStaffSelfServicePanelFragmentId = "roster-staff-self-service-panel-fragment"

rosterStaffSelfServiceLeaveFormFragmentId :: Text
rosterStaffSelfServiceLeaveFormFragmentId =
    surfaceFragmentTargetId @RosterSurface.RosterSurface @RosterSurface.RosterStaffSelfServiceLeaveFormFragment noSurfaceFields

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
        (RosterAction.createRosterSelfServiceLeaveRequestAction fields)
        FrontendSurfaceActionRoute
            { actionRouteUrl = rosterCreateLeaveRequestPath
            , actionRouteCustomHtmx = []
            , actionRouteStandardUrl = Just rosterCreateLeaveRequestPath
            , actionRouteExtraAttrs =
                [ ("id", "roster-staff-self-service-leave-form")

                ]
            }
        [hsx|
            <input type="hidden" name="responseContext" value="roster"/>
            {renderRosterScopeFields maybeRosterScope}
            {renderLeaveRequestFormFieldsWithNames fieldNames leaveRequest}
            <div class="d-grid mt-4 app-form-width">
                <button type="submit" class="btn btn-primary">Add unavailable time</button>
            </div>
        |]
  where
    fields =
        RosterAction.createRosterSelfServiceLeaveRequestActionFields
            leaveRequest.startDate
            leaveRequest.endDate
            (fromMaybe "" leaveRequest.notes)
    fieldNames =
        LeaveRequestFieldNames
            { leaveRequestStartDateFieldName = surfaceFieldNameFrom @RosterSurface.StartDate fields
            , leaveRequestEndDateFieldName = surfaceFieldNameFrom @RosterSurface.EndDate fields
            , leaveRequestNotesFieldName = surfaceFieldNameFrom @RosterSurface.Notes fields
            }

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
