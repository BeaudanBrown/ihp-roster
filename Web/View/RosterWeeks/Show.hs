module Web.View.RosterWeeks.Show where

import Application.Helper.LiveUpdate (LiveUpdateScope (..))
import Application.Helper.View (appendQueryParams)
import Data.Maybe (isJust)
import Web.RosterWeeks.Capabilities (buildRosterViewCapabilities)
import Web.RosterWeeks.Dom
import Web.RosterWeeks.Types
import Web.View.RosterWeeks.Grid (renderRosterContentFragment)
import Web.View.Prelude

instance View ShowView where
    html = renderRosterWeekShell

renderRosterWeekShell :: ShowView -> Html
renderRosterWeekShell ShowView { .. } =
    let page = renderAppPage (AppPageConfig
            { appPageTitle = "Roster"
            , appPageDescription = Nothing
            , appPageActions = mempty
            , appPageWidthClass = ""
            , appPageBody = renderRosterContentFragment rosterWeek rosterDays weekOffset rosterGroups currentRosterGroup assignmentFilters staffMembers staffOptionStates panelStaff slotNames weekStartDate allSlots slotConflicts renderIndexes viewCapabilities
            })
     in [hsx|
    <section id={rosterWeekShellId}
             hx-history-elt="true"
             data-live-update-owner="true"
             data-live-update-feature="roster"
             data-live-updates-path="/live-updates"
             data-live-update-content-url={appendQueryParams (pathTo (ShowRosterWeekContentFragmentAction weekOffset)) [("rosterGroupId", tshow currentRosterGroup.id)]}
             data-live-update-staff-panel-url={appendQueryParams (pathTo (ShowRosterWeekStaffPanelFragmentAction weekOffset)) [("rosterGroupId", tshow currentRosterGroup.id)]}
             data-live-update-client-enabled={isJust liveUpdateScope}
             data-live-update-client-id=""
             data-live-update-scope-kind={liveUpdateScopeKind <$> liveUpdateScope}
             data-live-update-venue-id={liveUpdateVenueId <$> liveUpdateScope}
             data-live-update-roster-group-id={liveUpdateRosterGroupIdText =<< liveUpdateScope}
             data-live-update-week-offset={liveUpdateWeekOffsetText =<< liveUpdateScope}>
        <div data-live-update-owner="true"
             data-live-update-feature="roster-group-config"
             data-live-updates-path="/live-updates"
             data-live-update-content-url={appendQueryParams (pathTo (ShowRosterWeekContentFragmentAction weekOffset)) [("rosterGroupId", tshow currentRosterGroup.id)]}
             data-live-update-client-enabled={isJust liveUpdateScope}
             data-live-update-client-id=""
             data-live-update-scope-kind={liveUpdateRosterGroupScopeKind <$> liveUpdateScope}
             data-live-update-venue-id={liveUpdateVenueId <$> liveUpdateScope}
             data-live-update-roster-group-id={liveUpdateRosterGroupIdText =<< liveUpdateScope}
             hidden="hidden"></div>
        {page}
    </section>
|]

liveUpdateScopeKind :: LiveUpdateScope -> Text
liveUpdateScopeKind RosterWeekScope {}        = "roster_week"
liveUpdateScopeKind RosterGroupConfigScope {} = "roster_group_config"
liveUpdateScopeKind AdminSlotNamesScope {}    = "admin_slot_names"
liveUpdateScopeKind AdminInvitesScope {}      = "admin_invites"
liveUpdateScopeKind LeaveRequestsScope {}     = "leave_requests"
liveUpdateScopeKind TimesheetWeekScope {}     = "timesheet_week"

liveUpdateRosterGroupScopeKind :: LiveUpdateScope -> Maybe Text
liveUpdateRosterGroupScopeKind RosterWeekScope {}        = Just "roster_group_config"
liveUpdateRosterGroupScopeKind RosterGroupConfigScope {} = Just "roster_group_config"
liveUpdateRosterGroupScopeKind AdminSlotNamesScope {}    = Nothing
liveUpdateRosterGroupScopeKind AdminInvitesScope {}      = Nothing
liveUpdateRosterGroupScopeKind LeaveRequestsScope {}     = Nothing
liveUpdateRosterGroupScopeKind TimesheetWeekScope {}     = Nothing

liveUpdateVenueId :: LiveUpdateScope -> Text
liveUpdateVenueId RosterWeekScope { venueId }        = tshow venueId
liveUpdateVenueId RosterGroupConfigScope { venueId } = tshow venueId
liveUpdateVenueId AdminSlotNamesScope { venueId }    = tshow venueId
liveUpdateVenueId AdminInvitesScope { venueId }      = tshow venueId
liveUpdateVenueId LeaveRequestsScope { venueId }     = tshow venueId
liveUpdateVenueId TimesheetWeekScope { venueId }     = tshow venueId

liveUpdateRosterGroupIdText :: LiveUpdateScope -> Maybe Text
liveUpdateRosterGroupIdText RosterWeekScope { rosterGroupId } = Just (tshow rosterGroupId)
liveUpdateRosterGroupIdText RosterGroupConfigScope { rosterGroupId } = Just (tshow rosterGroupId)
liveUpdateRosterGroupIdText AdminSlotNamesScope { rosterGroupId } = Just (tshow rosterGroupId)
liveUpdateRosterGroupIdText AdminInvitesScope {} = Nothing
liveUpdateRosterGroupIdText LeaveRequestsScope {} = Nothing
liveUpdateRosterGroupIdText TimesheetWeekScope {} = Nothing

liveUpdateWeekOffsetText :: LiveUpdateScope -> Maybe Text
liveUpdateWeekOffsetText RosterWeekScope { weekOffset } = Just (tshow weekOffset)
liveUpdateWeekOffsetText RosterGroupConfigScope {} = Nothing
liveUpdateWeekOffsetText AdminSlotNamesScope {} = Nothing
liveUpdateWeekOffsetText AdminInvitesScope {} = Nothing
liveUpdateWeekOffsetText LeaveRequestsScope {} = Nothing
liveUpdateWeekOffsetText TimesheetWeekScope { weekOffset } = Just (tshow weekOffset)
