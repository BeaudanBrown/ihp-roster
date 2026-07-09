module Web.View.RosterWeeks.Show where

import Application.Helper.FrontendContract.Surface.Runtime (renderFrontendSurfaceMount)
import Application.Helper.Profiling (profileHtmlComponent)
import Web.RosterWeeks.Capabilities (buildRosterViewCapabilities)
import Web.RosterWeeks.Dom
import Web.RosterWeeks.FrontendSurface (RosterWeekScopeValue (..),
                                        rosterMountedFragmentPlanFromRenderData,
                                        rosterSurfaceImpl)
import Web.RosterWeeks.Types
import Web.View.Passkeys.SetupModal
import Web.View.Prelude
import Web.View.RosterWeeks.Grid (renderRosterLayout)

instance View ShowView where
    html = renderRosterWeekShell

renderRosterWeekShell :: ShowView -> Html
renderRosterWeekShell ShowView { .. } =
    let page = renderAppPage (AppPageConfig
            { appPageTitle = "Roster"
            , appPageDescription = Nothing
            , appPageActions = mempty
            , appPageHelpTopic = Just (PageHelpTopicId "roster")
            , appPageWidthClass = ""
            , appPageBody =
                mconcat
                    [ renderPasskeySetupPrompt passkeySetupPrompt
                    , renderRosterLayout RosterGridRenderModel
                        { gridRosterWeek = rosterWeek
                        , gridRosterDays = rosterDays
                        , gridWeekOffset = weekOffset
                        , gridRosterGroups = rosterGroups
                        , gridCurrentRosterGroup = currentRosterGroup
                        , gridAssignmentFilters = assignmentFilters
                        , gridStaffMembers = staffMembers
                        , gridPanelStaff = panelStaff
                        , gridStaffSelfServicePanel = staffSelfServicePanel
                        , gridSlotNames = slotNames
                        , gridShiftTypes = shiftTypes
                        , gridWeekStartDate = weekStartDate
                        , gridAllSlots = allSlots
                        , gridSlotConflicts = slotConflicts
                        , gridRenderIndexes = renderIndexes
                        , gridViewCapabilities = viewCapabilities
                        , gridRosterLayoutMode = rosterLayoutMode
                        , gridRosterEndTimesEnabled = rosterEndTimesEnabled
                        , gridRosterWagePrediction = rosterWagePrediction
                        , gridShowWageEstimates = showWageEstimates
                        , gridShowRosterWarnings = showRosterWarnings
                        , gridPublicHolidays = publicHolidays
                        , gridPublishAttempted = False
                        }
                    ]
            })
        rosterSurfaceScope = RosterWeekScopeValue
            { rosterWeekVenueId = currentRosterGroup.venueId
            , rosterWeekGroupId = currentRosterGroup.id
            , rosterWeekWeekOffset = weekOffset
            }
        rosterSurfacePlan = rosterMountedFragmentPlanFromRenderData rosterDays renderIndexes
        rosterSurface = rosterSurfaceImpl rosterSurfaceScope rosterSurfacePlan
        shell = [hsx|
            <section id={rosterWeekShellId}
                     hx-history-elt="true"
                     data-roster-fullscreen="false">
                {page}
            </section>
        |]
     in profileHtmlComponent "render.roster.full_shell" (renderFrontendSurfaceMount rosterSurface shell)

renderPasskeySetupPrompt :: (?context :: ControllerContext) => Maybe PasskeySetupPromptMode -> Html
renderPasskeySetupPrompt Nothing = mempty
renderPasskeySetupPrompt (Just promptMode) = [hsx|
    <div class="js-passkey-setup-prompt"
         data-user-id={tshow currentUser.id}
         data-mode={passkeyPromptModeValue promptMode}>
        {renderPasskeySetupDialog (passkeySetupModeFromPrompt promptMode) (pathTo RosterWeeksAction)}
    </div>
|]

passkeyPromptModeValue :: PasskeySetupPromptMode -> Text
passkeyPromptModeValue FirstPasskeyPrompt            = "first-passkey"
passkeyPromptModeValue AdditionalDevicePasskeyPrompt = "additional-device"

passkeySetupModeFromPrompt :: (?context :: ControllerContext) => PasskeySetupPromptMode -> PasskeySetupMode
passkeySetupModeFromPrompt FirstPasskeyPrompt =
    if currentUserIsAdmin
        then MandatoryFirstPasskey
        else OptionalFirstPasskey
passkeySetupModeFromPrompt AdditionalDevicePasskeyPrompt = OptionalAdditionalDevice
