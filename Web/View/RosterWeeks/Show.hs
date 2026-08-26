module Web.View.RosterWeeks.Show where

import Application.Helper.Controller (currentUserIsImpersonating)
import qualified Application.Helper.FrontendContract.Passkey.Runtime as Passkey
import Application.Helper.FrontendContract.Surface.Runtime (renderFrontendSurfaceMount)
import Application.Helper.Profiling (profileHtmlComponent)
import qualified Data.Time.Calendar as Calendar
import Web.RosterWeeks.Capabilities (buildRosterViewCapabilities)
import Web.RosterWeeks.DateRange (RosterWindowScope (..))
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

instance View NoRosterGroupView where
    html = renderNoRosterGroupShell

renderNoRosterGroupShell :: NoRosterGroupView -> Html
renderNoRosterGroupShell NoRosterGroupView { .. } =
    let emptyState = [hsx|
            <div class="app-panel roster-main-panel">
                <div class="app-panel-body" role="status">
                    <p class="mb-0">You aren't assigned to a roster group yet.</p>
                </div>
            </div>
        |]
        page = renderAppPage AppPageConfig
            { appPageTitle = "Roster"
            , appPageDescription = Nothing
            , appPageActions = mempty
            , appPageHelpTopic = Just (PageHelpTopicId "roster")
            , appPageWidthClass = ""
            , appPageBody = renderPasskeySetupPrompt noRosterGroupPasskeyStrongAuthenticationRequired noRosterGroupPasskeySetupPrompt <> emptyState
            }
     in [hsx|
        <section id={rosterWeekShellId} hx-history-elt="true">
            {page}
        </section>
    |]

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
                    [ renderPasskeySetupPrompt passkeyStrongAuthenticationRequired passkeySetupPrompt
                    , renderRosterLayout RosterGridRenderModel
                        { gridRosterWeek = rosterWeek
                        , gridRosterDays = rosterDays
                        , gridWindowScope = rosterWindowScope
                        , gridRosterGroups = rosterGroups
                        , gridCurrentRosterGroup = currentRosterGroup
                        , gridAssignmentFilters = assignmentFilters
                        , gridStaffMembers = staffMembers
                        , gridPanelStaff = panelStaff
                        , gridTemplateLibrary = templateLibrary
                        , gridTemplateLibraryUserId = templateLibraryUserId
                        , gridNotificationPanelData = showNotificationPanelData
                        , gridStaffSelfServicePanel = staffSelfServicePanel
                        , gridSlotNames = slotNames
                        , gridShiftTypes = shiftTypes
                        , gridWeekStartDate = weekStartDate
                        , gridRosterCalendarRevision = rosterCalendarRevision
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
                        , gridHighlightOwnLiveShifts = highlightOwnLiveShifts
                        , gridCurrentViewerStaffKey = currentViewerStaffKey
                        , gridPublicHolidays = publicHolidays
                        , gridPublishAttempted = False
                        , gridViewMode = rosterGridViewMode
                        , gridTimelineTodayUrl = rosterTimelineTodayUrl
                        }
                    ]
            })
        rosterSurfaceScope = RosterWeekScopeValue
            { rosterWeekVenueId = unpackId rosterWindowScope.rosterWindowVenueId
            , rosterWeekGroupId = rosterWindowScope.rosterWindowRosterGroupId
            , rosterWeekWindowStart = rosterWindowScope.rosterWindowStart
            , rosterWeekWindowEnd = rosterWindowScope.rosterWindowEnd
            , rosterWeekCalendarRevision = rosterWindowScope.rosterWindowCalendarRevision
            , rosterWeekTimelineDate = case rosterGridViewMode of
                RosterDayTimelineGridView dayOffset -> Just (Calendar.addDays (toInteger dayOffset) rosterWindowScope.rosterWindowStart)
                RosterWeekGridView                  -> Nothing
            }
        rosterSurfacePlan = rosterMountedFragmentPlanFromRenderData templateLibraryUserId rosterDays renderIndexes
        rosterSurface = rosterSurfaceImpl rosterSurfaceScope rosterSurfacePlan
        shell = [hsx|
            <section id={rosterWeekShellId}
                     hx-history-elt="true">
                {renderFrontendSurfaceMount rosterSurface page}
            </section>
        |]
     in profileHtmlComponent "render.roster.full_shell" shell

renderPasskeySetupPrompt :: (?context :: ControllerContext) => Bool -> Maybe Passkey.PasskeySetupPromptMode -> Html
renderPasskeySetupPrompt _ Nothing = mempty
renderPasskeySetupPrompt _ (Just _) | currentUserIsImpersonating = mempty
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
