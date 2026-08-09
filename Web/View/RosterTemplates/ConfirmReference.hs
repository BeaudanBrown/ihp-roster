module Web.View.RosterTemplates.ConfirmReference where

import Application.Helper.RosterTemplateScale (rosterTemplateScaleValue)
import Application.Helper.Url (appendQueryParams)
import Data.Time.Calendar (addDays)
import Data.Time.Format (defaultTimeLocale, formatTime)
import Web.RosterWeeks.TemplateDesigner
import Web.View.Prelude

data ConfirmReferenceView = ConfirmReferenceView
    { rosterGroup       :: !RosterGroup
    , referenceWeek     :: !RosterTemplateReferenceWeek
    , weekOffset        :: !Int
    , templateName      :: !Text
    , templateScale     :: !RosterTemplateScaleEnum
    , selectedDayOffset :: !(Maybe Int)
    , confirmationToken :: !Text
    }

instance View ConfirmReferenceView where
    html ConfirmReferenceView { .. } =
        renderAppPage AppPageConfig
            { appPageTitle = "Confirm roster reference"
            , appPageDescription = Nothing
            , appPageActions = mempty
            , appPageHelpTopic = Just (PageHelpTopicId "roster")
            , appPageWidthClass = ""
            , appPageBody = [hsx|
                <div id="roster-template-reference-confirm" class="row g-4 roster-layout">
                    <div class="col-12 mx-auto">
                        <div class="app-panel roster-main-panel p-4 p-lg-5">
                            <p class="text-uppercase small fw-semibold text-success mb-2">Reference selection · read only</p>
                            <h2 class="h4">Confirm reference</h2>
                            <p>You are creating <strong>{templateName}</strong> from {referenceLabel}.</p>
                            <div class="alert alert-info">No roster data will be changed. The reference is copied once into your private template draft.</div>
                            <div class="d-flex flex-wrap justify-content-end gap-2">
                                <a class="btn btn-outline-secondary" href={backPath}>Back</a>
                                <form method="POST" action={CreateRosterTemplateFromReferenceAction rosterGroup.id}>
                                    <input type="hidden" name="anchorDate" value={tshow referenceWeek.referenceWeekStart} />
                                    <input type="hidden" name="name" value={templateName} />
                                    <input type="hidden" name="scale" value={rosterTemplateScaleValue templateScale} />
                                    <input type="hidden" name="confirmationToken" value={confirmationToken} />
                                    {forEach selectedDayOffset renderDayOffsetInput}
                                    <button class="btn btn-primary" type="submit">Open prefilled designer</button>
                                </form>
                            </div>
                        </div>
                    </div>
                </div>
            |]
            }
      where
        referenceLabel = case selectedDayOffset of
            Nothing -> "the week of " <> formatDate referenceWeek.referenceWeekStart
            Just dayOffset ->
                let date = addDays (toInteger dayOffset) referenceWeek.referenceWeekStart
                 in cs (formatTime defaultTimeLocale "%A %d %b %Y" date)
        backPath = appendQueryParams
            (pathTo ShowRosterTemplateReferenceAction { rosterGroupId = rosterGroup.id })
            [("anchorDate", tshow referenceWeek.referenceWeekStart), ("name", templateName), ("scale", rosterTemplateScaleValue templateScale)]

renderDayOffsetInput :: Int -> Html
renderDayOffsetInput dayOffset = [hsx|<input type="hidden" name="dayOffset" value={tshow dayOffset} />|]


formatDate :: Day -> Text
formatDate = cs . formatTime defaultTimeLocale "%d %b %Y"
