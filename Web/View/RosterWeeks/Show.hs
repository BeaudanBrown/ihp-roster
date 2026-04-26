module Web.View.RosterWeeks.Show where

import Application.Helper.LiveSurface (LiveSurfaceConfig (..),
                                       liveSurfaceConfigJson, mkLiveSurface)
import Application.Helper.LiveUpdate (LiveUpdateScope (..))
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
             data-live-update-surface={liveSurfaceConfigJson . rosterWeekLiveSurface currentRosterGroup.id weekOffset <$> liveUpdateScope}>
        <div data-live-update-surface={liveSurfaceConfigJson . rosterGroupConfigLiveSurface currentRosterGroup.id weekOffset <$> liveUpdateScope}
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
