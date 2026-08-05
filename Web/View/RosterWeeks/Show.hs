module Web.View.RosterWeeks.Show where

import qualified Application.Helper.FrontendContract.Passkey.Runtime as Passkey
import Application.Helper.FrontendContract.Surface.Roster.Chrome (RosterFullscreenState (..),
                                                                  rosterFullscreenRootAttrs)
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
            , appPageActions = renderTemplateLibraryAction viewCapabilities currentRosterGroup
            , appPageHelpTopic = Just (PageHelpTopicId "roster")
            , appPageWidthClass = ""
            , appPageBody =
                mconcat
                    [ renderPasskeySetupPrompt passkeyStrongAuthenticationRequired passkeySetupPrompt
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
                        , gridRosterTimePickerStartMinute = rosterTimePickerStartMinute
                        , gridRosterTimePickerFinalSelectableMinute = rosterTimePickerFinalSelectableMinute
                        , gridRosterWagePrediction = rosterWagePrediction
                        , gridShowWageEstimates = showWageEstimates
                        , gridShowRosterWarnings = showRosterWarnings
                        , gridPublicHolidays = publicHolidays
                        , gridPublishAttempted = False
                        , gridViewMode = rosterGridViewMode
                        , gridTimelineTodayUrl = rosterTimelineTodayUrl
                        }
                    ]
            })
        rosterSurfaceScope = RosterWeekScopeValue
            { rosterWeekVenueId = currentRosterGroup.venueId
            , rosterWeekGroupId = currentRosterGroup.id
            , rosterWeekWeekOffset = weekOffset
            , rosterWeekTimelineDayOffset = case rosterGridViewMode of
                RosterDayTimelineGridView dayOffset -> Just dayOffset
                RosterWeekGridView                  -> Nothing
            }
        rosterSurfacePlan = rosterMountedFragmentPlanFromRenderData rosterDays renderIndexes
        rosterSurface = rosterSurfaceImpl rosterSurfaceScope rosterSurfacePlan
        shell = [hsx|
            <section id={rosterWeekShellId}
                     hx-history-elt="true"
                     {...rosterFullscreenRootAttrs RosterFullscreenCollapsed}>
                {renderFrontendSurfaceMount rosterSurface page}
            </section>
        |]
     in profileHtmlComponent "render.roster.full_shell" shell

renderTemplateLibraryAction :: (?context :: ControllerContext) => RosterViewCapabilities -> RosterGroup -> Html
renderTemplateLibraryAction capabilities rosterGroup
    | capabilities.canCopyRosterWeek = [hsx|
        <a id="roster-template-library-link" class="btn btn-outline-primary" href={NewRosterTemplateAction rosterGroup.id}>Templates</a>
    |]
    | otherwise = mempty

renderPasskeySetupPrompt :: (?context :: ControllerContext) => Bool -> Maybe Passkey.PasskeySetupPromptMode -> Html
renderPasskeySetupPrompt _ Nothing = mempty
renderPasskeySetupPrompt strongAuthenticationRequired (Just promptMode) = [hsx|
    <div {...Passkey.passkeySetupPromptAttrs (tshow currentUser.id) promptMode}>
        {renderPasskeySetupPromptDialog (passkeySetupModeFromPrompt strongAuthenticationRequired promptMode) (pathTo RosterWeeksAction)}
    </div>
|]

passkeySetupModeFromPrompt :: Bool -> Passkey.PasskeySetupPromptMode -> PasskeySetupMode
passkeySetupModeFromPrompt strongAuthenticationRequired Passkey.PasskeyFirstPasskey =
    if strongAuthenticationRequired
        then MandatoryFirstPasskey
        else OptionalFirstPasskey
passkeySetupModeFromPrompt _ Passkey.PasskeyAdditionalDevice = OptionalAdditionalDevice
