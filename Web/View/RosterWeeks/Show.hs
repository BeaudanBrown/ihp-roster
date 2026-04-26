module Web.View.RosterWeeks.Show where

import Application.Helper.LiveSurface (LiveSurfaceConfig (..),
                                       liveSurfaceConfigJson, mkLiveSurface)
import Application.Helper.LiveUpdate (LiveUpdateScope (..))
import Application.Helper.View (appendQueryParams)
import Data.Maybe (isJust)
import Web.RosterWeeks.Capabilities (buildRosterViewCapabilities)
import Web.RosterWeeks.Dom
import Web.RosterWeeks.Projection (buildDeferredRosterContentFragmentRef,
                                   buildRosterStaffPanelFragmentRef)
import Web.RosterWeeks.Types
import Web.View.Prelude
import Web.View.RosterWeeks.Grid (renderRosterContentFragment)

instance View ShowView where
    html = renderRosterWeekShell

renderRosterWeekShell :: ShowView -> Html
renderRosterWeekShell ShowView { .. } =
    let page = renderAppPage (AppPageConfig
            { appPageTitle = "Roster"
            , appPageDescription = Nothing
            , appPageActions = mempty
            , appPageWidthClass = ""
            , appPageBody =
                mconcat
                    [ renderPasskeySetupPrompt passkeySetupPrompt
                    , renderRosterContentFragment rosterWeek rosterDays weekOffset rosterGroups currentRosterGroup assignmentFilters staffMembers staffOptionStates panelStaff slotNames weekStartDate allSlots slotConflicts renderIndexes viewCapabilities
                    ]
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
             data-live-update-week-offset={liveUpdateWeekOffsetText =<< liveUpdateScope}
             data-live-update-surface={liveSurfaceConfigJson . rosterWeekLiveSurface currentRosterGroup.id weekOffset <$> liveUpdateScope}>
        <div data-live-update-owner="true"
             data-live-update-feature="roster-group-config"
             data-live-updates-path="/live-updates"
             data-live-update-content-url={appendQueryParams (pathTo (ShowRosterWeekContentFragmentAction weekOffset)) [("rosterGroupId", tshow currentRosterGroup.id)]}
             data-live-update-client-enabled={isJust liveUpdateScope}
             data-live-update-client-id=""
             data-live-update-scope-kind={liveUpdateRosterGroupScopeKind <$> liveUpdateScope}
             data-live-update-venue-id={liveUpdateVenueId <$> liveUpdateScope}
             data-live-update-roster-group-id={liveUpdateRosterGroupIdText =<< liveUpdateScope}
             data-live-update-surface={liveSurfaceConfigJson . rosterGroupConfigLiveSurface currentRosterGroup.id weekOffset <$> liveUpdateScope}
             hidden="hidden"></div>
        {page}
    </section>
|]

rosterWeekLiveSurface :: (?context :: ControllerContext) => Id RosterGroup -> Int -> LiveUpdateScope -> LiveSurfaceConfig
rosterWeekLiveSurface rosterGroupId weekOffset scope =
    (mkLiveSurface
        "roster"
        scope
        [ buildDeferredRosterContentFragmentRef rosterGroupId weekOffset
        , buildRosterStaffPanelFragmentRef rosterGroupId weekOffset
        ])
        { decorateRequestsWithin = ["#" <> rosterWeekShellId] }

rosterGroupConfigLiveSurface :: (?context :: ControllerContext) => Id RosterGroup -> Int -> LiveUpdateScope -> LiveSurfaceConfig
rosterGroupConfigLiveSurface rosterGroupId weekOffset scope =
    (mkLiveSurface
        "roster-group-config"
        (rosterGroupConfigScopeFrom scope)
        [ buildDeferredRosterContentFragmentRef rosterGroupId weekOffset
        ])
        { decorateRequestsWithin = ["#" <> rosterWeekShellId] }

rosterGroupConfigScopeFrom :: LiveUpdateScope -> LiveUpdateScope
rosterGroupConfigScopeFrom RosterWeekScope { venueId, rosterGroupId } =
    RosterGroupConfigScope { venueId, rosterGroupId }
rosterGroupConfigScopeFrom scope = scope

renderPasskeySetupPrompt :: (?context :: ControllerContext) => Maybe PasskeySetupPromptMode -> Html
renderPasskeySetupPrompt Nothing = mempty
renderPasskeySetupPrompt (Just promptMode) = [hsx|
    <section class="alert alert-info d-none js-passkey-setup-prompt"
             data-user-id={tshow currentUser.id}
             data-mode={passkeyPromptModeValue promptMode}
             data-begin-url={pathTo BeginPasskeyRegistrationAction}
             data-finish-url={pathTo FinishPasskeyRegistrationAction}
             data-status-id="passkey-setup-prompt-status">
        <div class="d-flex flex-column flex-md-row gap-3 align-items-md-center justify-content-between">
            <div>
                <strong>{passkeyPromptTitle promptMode}</strong>
                <div class="small mt-1">{passkeyPromptBody promptMode}</div>
            </div>
            <div class="d-flex gap-2 flex-shrink-0">
                <button type="button" class="btn btn-primary btn-sm js-passkey-setup-button">Set up faster sign-in</button>
                <button type="button" class="btn btn-outline-secondary btn-sm js-passkey-setup-dismiss">Not now</button>
            </div>
        </div>
        <div id="passkey-setup-prompt-status" class="alert d-none mt-3 mb-0"></div>
    </section>
|]

passkeyPromptModeValue :: PasskeySetupPromptMode -> Text
passkeyPromptModeValue FirstPasskeyPrompt            = "first-passkey"
passkeyPromptModeValue AdditionalDevicePasskeyPrompt = "additional-device"

passkeyPromptTitle :: PasskeySetupPromptMode -> Text
passkeyPromptTitle FirstPasskeyPrompt = "Use your device unlock next time"
passkeyPromptTitle AdditionalDevicePasskeyPrompt = "Set up faster sign-in on this device too"

passkeyPromptBody :: PasskeySetupPromptMode -> Text
passkeyPromptBody FirstPasskeyPrompt =
    "Create a passkey so you can sign in with Face ID, Touch ID, Windows Hello or your screen lock instead of typing your password."
passkeyPromptBody AdditionalDevicePasskeyPrompt =
    "This account already has a passkey. Add one here if you want this browser to offer the same quick sign-in."

liveUpdateScopeKind :: LiveUpdateScope -> Text
liveUpdateScopeKind RosterWeekScope {}        = "roster_week"
liveUpdateScopeKind RosterGroupConfigScope {} = "roster_group_config"
liveUpdateScopeKind AdminSlotNamesScope {}    = "admin_slot_names"
liveUpdateScopeKind AdminInvitesScope {}      = "admin_invites"
liveUpdateScopeKind LeaveRequestsScope {}     = "leave_requests"
liveUpdateScopeKind TimesheetWeekScope {}     = "timesheet_week"
liveUpdateScopeKind SupportPlatformScope      = "support_platform"

liveUpdateRosterGroupScopeKind :: LiveUpdateScope -> Maybe Text
liveUpdateRosterGroupScopeKind RosterWeekScope {}        = Just "roster_group_config"
liveUpdateRosterGroupScopeKind RosterGroupConfigScope {} = Just "roster_group_config"
liveUpdateRosterGroupScopeKind AdminSlotNamesScope {}    = Nothing
liveUpdateRosterGroupScopeKind AdminInvitesScope {}      = Nothing
liveUpdateRosterGroupScopeKind LeaveRequestsScope {}     = Nothing
liveUpdateRosterGroupScopeKind TimesheetWeekScope {}     = Nothing
liveUpdateRosterGroupScopeKind SupportPlatformScope      = Nothing

liveUpdateVenueId :: LiveUpdateScope -> Text
liveUpdateVenueId RosterWeekScope { venueId }        = tshow venueId
liveUpdateVenueId RosterGroupConfigScope { venueId } = tshow venueId
liveUpdateVenueId AdminSlotNamesScope { venueId }    = tshow venueId
liveUpdateVenueId AdminInvitesScope { venueId }      = tshow venueId
liveUpdateVenueId LeaveRequestsScope { venueId }     = tshow venueId
liveUpdateVenueId TimesheetWeekScope { venueId }     = tshow venueId
liveUpdateVenueId SupportPlatformScope               = ""

liveUpdateRosterGroupIdText :: LiveUpdateScope -> Maybe Text
liveUpdateRosterGroupIdText RosterWeekScope { rosterGroupId } = Just (tshow rosterGroupId)
liveUpdateRosterGroupIdText RosterGroupConfigScope { rosterGroupId } = Just (tshow rosterGroupId)
liveUpdateRosterGroupIdText AdminSlotNamesScope { rosterGroupId } = Just (tshow rosterGroupId)
liveUpdateRosterGroupIdText AdminInvitesScope {} = Nothing
liveUpdateRosterGroupIdText LeaveRequestsScope {} = Nothing
liveUpdateRosterGroupIdText TimesheetWeekScope {} = Nothing
liveUpdateRosterGroupIdText SupportPlatformScope = Nothing

liveUpdateWeekOffsetText :: LiveUpdateScope -> Maybe Text
liveUpdateWeekOffsetText RosterWeekScope { weekOffset } = Just (tshow weekOffset)
liveUpdateWeekOffsetText RosterGroupConfigScope {} = Nothing
liveUpdateWeekOffsetText AdminSlotNamesScope {} = Nothing
liveUpdateWeekOffsetText AdminInvitesScope {} = Nothing
liveUpdateWeekOffsetText LeaveRequestsScope {} = Nothing
liveUpdateWeekOffsetText TimesheetWeekScope { weekOffset } = Just (tshow weekOffset)
liveUpdateWeekOffsetText SupportPlatformScope = Nothing
