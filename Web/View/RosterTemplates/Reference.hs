{-# OPTIONS_GHC -Werror=incomplete-patterns #-}

module Web.View.RosterTemplates.Reference where

import Application.Helper.FrontendContract.Surface.Runtime (renderFrontendSurfaceMount)
import Application.Helper.RosterTemplateScale (rosterTemplateScaleIsWeek,
                                               rosterTemplateScaleValue)
import Data.Time.Calendar (addDays)
import Data.Time.Format (defaultTimeLocale, formatTime)
import Web.RosterTemplates.FrontendSurface
import Web.RosterWeeks.Paths (rosterTemplateReferenceUrl)
import Web.RosterWeeks.TemplateDesigner
import Web.View.Prelude

data ReferenceView = ReferenceView
    { rosterGroup        :: !RosterGroup
    , referenceWeek      :: !RosterTemplateReferenceWeek
    , windowStart        :: !Day
    , currentWindowStart :: !Day
    , templateName       :: !Text
    , templateScale      :: !RosterTemplateScaleEnum
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
                                    <h2 class="h4 mb-0">{if rosterTemplateScaleIsWeek templateScale then ("Select a reference week" :: Text) else "Select a reference day"}</h2>
                                </div>
                                <nav class="d-flex align-items-center gap-2" aria-label="Reference week navigation">
                                    <a class="btn btn-outline-secondary" href={referenceUrl (addDays (-7) windowStart)}>Previous week</a>
                                    <a class="btn btn-outline-secondary" href={referenceUrl currentWindowStart}>This week</a>
                                    <a class="btn btn-outline-secondary" href={referenceUrl (addDays 7 windowStart)}>Next week</a>
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
        referenceUrl targetWindowStart =
            rosterTemplateReferenceUrl
                targetWindowStart
                rosterGroup.id
                templateName
                (rosterTemplateScaleValue templateScale)

renderReferenceContent :: ReferenceView -> Html
renderReferenceContent view@ReferenceView { referenceWeek = RosterTemplateReferenceWeek { .. } }
    | null referenceRosterDays = [hsx|
        <div class="alert alert-secondary mb-0">No live or draft roster exists for this window.</div>
    |]
renderReferenceContent view@ReferenceView { referenceWeek = RosterTemplateReferenceWeek { .. }, templateScale = Week }
    | map (.operationalDate) referenceRosterDays /= map (`addDays` referenceWeekStart) [0 .. 6] = [hsx|
        <div class="alert alert-secondary mb-0">This roster week is incomplete and cannot be used as a Week template reference.</div>
    |]
    | otherwise = [hsx|
        <form method="GET" action={ConfirmRosterTemplateReferenceAction view.rosterGroup.id}
              class="roster-template-reference-target roster-template-reference-week"
              {...rosterTemplateReferenceTargetAttrs}>
            {referenceHiddenFields view Nothing}
            <button type="submit" class="btn p-0 text-start w-100 roster-template-reference-button" aria-label="Use this week as template reference">
                <span class="d-block p-4">
                    <strong>Week of {formatDate referenceWeekStart}</strong>
                    <span class="d-block text-muted mt-1">{length referenceRosterSlots} shifts · {visibilityLabel referenceRosterDays}</span>
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
        let date = rosterDay.operationalDate
            label :: Text
            label = cs (formatTime defaultTimeLocale "%A" date)
            shiftCount = length (filter (\slot -> slot.rosterDayId == unpackId rosterDay.id) referenceRosterSlots)
         in [hsx|
            <div class="col-12 col-md">
                <form method="GET" action={ConfirmRosterTemplateReferenceAction view.rosterGroup.id}
                      class="roster-template-reference-target h-100"
                      {...rosterTemplateReferenceTargetAttrs}>
                    {referenceHiddenFields view (Just rosterDay.operationalDate)}
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

referenceHiddenFields :: ReferenceView -> Maybe Day -> Html
referenceHiddenFields ReferenceView { .. } maybeOperationalDate = [hsx|
    <input type="hidden" name="rosterGroupId" value={tshow rosterGroup.id} />
    <input type="hidden" name="anchorDate" value={tshow referenceWeek.referenceWeekStart} />
    <input type="hidden" name="name" value={templateName} />
    <input type="hidden" name="scale" value={rosterTemplateScaleValue templateScale} />
    {forEach maybeOperationalDate renderOperationalDateInput}
|]

renderOperationalDateInput :: Day -> Html
renderOperationalDateInput operationalDate = [hsx|<input type="hidden" name="operationalDate" value={tshow operationalDate} />|]


visibilityLabel :: [RosterDay] -> Text
visibilityLabel rosterDays
    | all ((== Published) . (.publicationState)) rosterDays = "Published roster"
    | otherwise = "Draft roster"

formatDate :: Day -> Text
formatDate = cs . formatTime defaultTimeLocale "%d %b %Y"
