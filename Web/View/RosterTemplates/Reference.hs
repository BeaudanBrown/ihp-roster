module Web.View.RosterTemplates.Reference where

import Application.Helper.FrontendContract.Surface.Runtime (renderFrontendSurfaceMount)
import Application.Helper.Url (appendQueryParams)
import Data.Time.Calendar (addDays)
import Data.Time.Format (defaultTimeLocale, formatTime)
import Web.RosterTemplates.FrontendSurface
import Web.RosterWeeks.TemplateDesigner
import Web.View.Prelude

data ReferenceView = ReferenceView
    { rosterGroup       :: !RosterGroup
    , referenceWeek     :: !RosterTemplateReferenceWeek
    , weekOffset        :: !Int
    , currentWeekOffset :: !Int
    , templateName      :: !Text
    , templateScale     :: !RosterTemplateScaleEnum
    }

instance View ReferenceView where
    html view@ReferenceView { .. } =
        renderAppPage AppPageConfig
            { appPageTitle = "Choose roster reference"
            , appPageDescription = Just "Reference mode is read-only. Selecting a roster copies its design into a private template draft."
            , appPageActions = mempty
            , appPageHelpTopic = Just (PageHelpTopicId "roster")
            , appPageWidthClass = ""
            , appPageBody = renderFrontendSurfaceMount templateSurface [hsx|
                <div id="roster-template-reference" class="row g-4 roster-layout">
                    <div class="col-12 mx-auto">
                        <div id={rosterTemplateDesignerContentId} class="app-panel roster-main-panel">
                            <header class="d-flex flex-wrap align-items-center justify-content-between gap-3 p-4 border-bottom">
                                <div>
                                    <p class="text-uppercase small fw-semibold text-success mb-1">Reference selection · read only</p>
                                    <h2 class="h4 mb-0">{if templateScale == Day then ("Select a reference day" :: Text) else "Select a reference week"}</h2>
                                </div>
                                <nav class="d-flex align-items-center gap-2" aria-label="Reference week navigation">
                                    <a class="btn btn-outline-secondary" href={referenceUrl (weekOffset - 1)}>Previous week</a>
                                    <a class="btn btn-outline-secondary" href={referenceUrl currentWeekOffset}>This week</a>
                                    <a class="btn btn-outline-secondary" href={referenceUrl (weekOffset + 1)}>Next week</a>
                                </nav>
                            </header>
                            <div class="p-4">
                                <p class="d-md-none alert alert-info">Tap a valid outlined day or week to select it.</p>
                                {renderReferenceContent view}
                            </div>
                        </div>
                    </div>
                </div>
            |]
            }
      where
        templateSurface = rosterTemplateDesignerSurfaceImpl RosterTemplateDesignerScopeValue
            { templateDesignerVenueId = rosterGroup.venueId
            , templateDesignerRosterGroupId = unpackId rosterGroup.id
            , templateDesignerUserId = unpackId currentUser.id
            }
        referenceUrl targetOffset =
            appendQueryParams
                (pathTo ShowRosterTemplateReferenceAction { rosterGroupId = rosterGroup.id, weekOffset = targetOffset })
                [("name", templateName), ("scale", scaleValue templateScale)]

renderReferenceContent :: ReferenceView -> Html
renderReferenceContent view@ReferenceView { referenceWeek = RosterTemplateReferenceWeek { referenceRosterWeek = Nothing } } = [hsx|
    <div class="alert alert-secondary mb-0">No live or draft roster exists for this week.</div>
|]
renderReferenceContent view@ReferenceView { referenceWeek = RosterTemplateReferenceWeek { .. }, templateScale = Week } = [hsx|
    <form method="GET" action={ConfirmRosterTemplateReferenceAction view.rosterGroup.id view.weekOffset}
          class="roster-template-reference-target roster-template-reference-week"
          {...rosterTemplateReferenceTargetAttrs}>
        {referenceHiddenFields view Nothing}
        <button type="submit" class="btn p-0 text-start w-100 roster-template-reference-button" aria-label="Use this week as template reference">
            <span class="d-block p-4">
                <strong>Week of {formatDate referenceWeekStart}</strong>
                <span class="d-block text-muted mt-1">{length referenceRosterSlots} shifts · {visibilityLabel referenceRosterWeek}</span>
            </span>
        </button>
    </form>
|]
renderReferenceContent view@ReferenceView { referenceWeek = RosterTemplateReferenceWeek { .. }, templateScale = Day } = [hsx|
    <div class="row g-3">
        {forEach referenceRosterDays renderDay}
    </div>
|]
  where
    renderDay rosterDay =
        let date = addDays (toInteger rosterDay.dayOffset) referenceWeekStart
            label :: Text
            label = cs (formatTime defaultTimeLocale "%A" date)
            shiftCount = length (filter (\slot -> slot.rosterDayId == unpackId rosterDay.id) referenceRosterSlots)
         in [hsx|
            <div class="col-12 col-md">
                <form method="GET" action={ConfirmRosterTemplateReferenceAction view.rosterGroup.id view.weekOffset}
                      class="roster-template-reference-target h-100"
                      {...rosterTemplateReferenceTargetAttrs}>
                    {referenceHiddenFields view (Just rosterDay.dayOffset)}
                    <button type="submit" class="btn p-0 text-start w-100 h-100 roster-template-reference-button" aria-label={"Use " <> label <> " as template reference"}>
                        <span class="d-block p-3">
                            <strong>{label}</strong>
                            <span class="d-block text-muted">{formatDate date}</span>
                            <span class="d-block small mt-2">{shiftCount} shifts</span>
                        </span>
                    </button>
                </form>
            </div>
        |]

referenceHiddenFields :: ReferenceView -> Maybe Int -> Html
referenceHiddenFields ReferenceView { .. } maybeDayOffset = [hsx|
    <input type="hidden" name="rosterGroupId" value={tshow rosterGroup.id} />
    <input type="hidden" name="weekOffset" value={tshow weekOffset} />
    <input type="hidden" name="name" value={templateName} />
    <input type="hidden" name="scale" value={scaleValue templateScale} />
    {forEach maybeDayOffset renderDayOffsetInput}
|]

renderDayOffsetInput :: Int -> Html
renderDayOffsetInput dayOffset = [hsx|<input type="hidden" name="dayOffset" value={tshow dayOffset} />|]

scaleValue :: RosterTemplateScaleEnum -> Text
scaleValue Day  = "day"
scaleValue Week = "week"

visibilityLabel :: Maybe RosterWeek -> Text
visibilityLabel Nothing = "Unavailable"
visibilityLabel (Just rosterWeek)
    | rosterWeek.isLive = "Live roster"
    | otherwise = "Draft roster"

formatDate :: Day -> Text
formatDate = cs . formatTime defaultTimeLocale "%d %b %Y"
