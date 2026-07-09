module Web.View.RosterWeeks.Timeline
    ( renderRosterDayTimelineShell
    ) where

import Application.Helper.Profiling (profileHtmlComponent)
import qualified Data.Map.Strict as Map
import qualified Data.Text as Text
import qualified Data.Time.Calendar as Calendar
import Data.Time.Format (defaultTimeLocale, formatTime)
import qualified Data.UUID as UUID
import Web.RosterWeeks.Paths (rosterWeekUrl)
import Web.RosterWeeks.Types
import Web.View.Prelude

renderRosterDayTimelineShell :: RosterRenderData -> RosterDay -> Html
renderRosterDayTimelineShell RosterRenderData { rosterWeek, currentRosterGroup, weekStartDate, orderedSlotNames, allSlots } rosterDay =
    let date = Calendar.addDays (toInteger rosterDay.dayOffset) weekStartDate
        daySlots = filter (\slot -> slot.rosterDayId == unpackId rosterDay.id) allSlots
        slotsByDefinition = Map.fromListWith (<>) [ (slot.rosterWeekSlotDefinitionId, [slot]) | slot <- daySlots ]
        backUrl = rosterWeekUrl rosterWeek.weekOffset currentRosterGroup.id
        page = renderAppPage AppPageConfig
            { appPageTitle = "Roster timeline"
            , appPageDescription = Just (Text.pack (formatTime defaultTimeLocale "%A %d/%m/%Y" date))
            , appPageActions = [hsx|
                <a href={backUrl} class="btn btn-outline-secondary btn-sm">
                    <i class="bi bi-arrow-left" aria-hidden="true"></i>
                    Back to week view
                </a>
            |]
            , appPageHelpTopic = Just (PageHelpTopicId "roster")
            , appPageWidthClass = ""
            , appPageBody = [hsx|
                <section class="app-panel roster-day-timeline-shell" data-roster-day-timeline="true">
                    <header class="d-flex align-items-center justify-content-between gap-3 mb-3">
                        <div>
                            <h2 class="h5 mb-1">{Text.pack (formatTime defaultTimeLocale "%A" date)} timeline</h2>
                            <p class="text-muted mb-0">Drag-to-move timeline interactions will be added here.</p>
                        </div>
                    </header>
                    <div class="roster-day-timeline-placeholder" role="region" aria-label="Roster day timeline">
                        {forEach orderedSlotNames (renderPlaceholderLane slotsByDefinition)}
                    </div>
                </section>
            |]
            }
     in profileHtmlComponent "render.roster.day_timeline_shell" page

renderPlaceholderLane :: Map.Map UUID.UUID [RosterSlot] -> RosterWeekSlotDefinition -> Html
renderPlaceholderLane slotsByDefinition slotDefinition =
    let laneSlots = Map.findWithDefault [] (unpackId slotDefinition.id) slotsByDefinition
     in [hsx|
        <div class="roster-day-timeline-placeholder-lane">
            <div class="fw-semibold">{slotDefinition.name}</div>
            <div class="text-muted small">{length laneSlots} shifts</div>
        </div>
    |]
