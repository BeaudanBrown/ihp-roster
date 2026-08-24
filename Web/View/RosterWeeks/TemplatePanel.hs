{-# OPTIONS_GHC -Werror=incomplete-patterns #-}

module Web.View.RosterWeeks.TemplatePanel
    ( renderRosterTemplateLibraryFragment
    , renderRosterTemplatePanel
    ) where

import qualified Application.Helper.FrontendContract.Surface.Roster as Surface
import qualified Application.Helper.FrontendContract.Surface.Roster.Action as RosterAction
import Application.Helper.FrontendContract.Surface.Runtime (FrontendSurfaceActionRoute (..),
                                                            renderFrontendSurfaceActionForm)
import Application.Helper.FrontendContract.Surface.Values (surfaceFieldNameFrom)
import Application.RosterTemplates
import Web.RosterWeeks.Dom (rosterTemplateApplicationPreviewFormId,
                            rosterTemplateLibraryFragmentId)
import Web.RosterWeeks.Types (RosterWindowState (..))
import Web.View.Prelude

renderRosterTemplateLibraryFragment :: (?context :: ControllerContext) => Id User -> Day -> Int -> RosterGroup -> Maybe RosterWindowState -> RosterTemplateLibrary -> Html
renderRosterTemplateLibraryFragment userId anchorDate calendarRevision rosterGroup maybeRosterWeek library = [hsx|
    <div id={rosterTemplateLibraryFragmentId userId}>
        {renderRosterTemplatePanel anchorDate calendarRevision rosterGroup maybeRosterWeek library}
    </div>
|]

renderRosterTemplatePanel :: (?context :: ControllerContext) => Day -> Int -> RosterGroup -> Maybe RosterWindowState -> RosterTemplateLibrary -> Html
renderRosterTemplatePanel anchorDate calendarRevision rosterGroup maybeRosterWeek library = [hsx|
    <section class="roster-template-panel" aria-labelledby="roster-template-panel-heading">
        <div class="app-side-panel-content-header roster-staff-panel-header">
            <h2 id="roster-template-panel-heading" class="h5 mb-0">Templates</h2>
        </div>
        {renderLiveRosterTemplateMessage maybeRosterWeek}
        {renderTemplateScaleSection "Week templates" Week anchorDate calendarRevision rosterGroup maybeRosterWeek library.libraryTemplates}
    </section>
|]

renderLiveRosterTemplateMessage :: Maybe RosterWindowState -> Html
renderLiveRosterTemplateMessage (Just rosterWeek)
    | rosterWeek.windowIsPublished = [hsx|
        <div class="alert alert-info small" role="status">Templates cannot be applied to a Published roster. Return this window to Draft to apply one.</div>
    |]
renderLiveRosterTemplateMessage _ = mempty

renderTemplateScaleSection :: (?context :: ControllerContext) => Text -> RosterTemplateScaleEnum -> Day -> Int -> RosterGroup -> Maybe RosterWindowState -> [RosterTemplate] -> Html
renderTemplateScaleSection heading scale anchorDate calendarRevision rosterGroup maybeRosterWeek templates = [hsx|
    <section class="roster-template-scale-section mt-3" aria-label={heading}>
        <h3 class="h6 text-muted">{heading}</h3>
        {renderTemplateCards anchorDate calendarRevision rosterGroup maybeRosterWeek matchingTemplates}
    </section>
|]
  where
    matchingTemplates = filter ((== scale) . (.scale)) templates

renderTemplateCards :: (?context :: ControllerContext) => Day -> Int -> RosterGroup -> Maybe RosterWindowState -> [RosterTemplate] -> Html
renderTemplateCards _ _ _ _ [] = [hsx|<p class="small text-muted">No saved templates.</p>|]
renderTemplateCards anchorDate calendarRevision rosterGroup maybeRosterWeek templates = forEach templates (renderTemplateCard anchorDate calendarRevision rosterGroup maybeRosterWeek)

renderTemplateCard :: (?context :: ControllerContext) => Day -> Int -> RosterGroup -> Maybe RosterWindowState -> RosterTemplate -> Html
renderTemplateCard anchorDate calendarRevision rosterGroup maybeRosterWeek template = cardHtml
  where
    cardHtml = [hsx|
        <article class="roster-template-card border rounded-3 mb-2">
            <div class="d-flex align-items-stretch">
                {applyButton}
                <div class="d-flex align-items-center gap-1 pe-2 roster-template-card-actions">
                    <form method="POST" action={ConfirmDeleteRosterTemplateAction template.id rosterGroup.id}>
                        <input type="hidden" name="anchorDate" value={tshow anchorDate} />
                        <button class="btn btn-sm btn-outline-danger app-icon-button" type="submit" title={"Delete " <> template.name} aria-label={"Delete " <> template.name}>
                            <i class="bi bi-trash" aria-hidden="true"></i>
                        </button>
                    </form>
                </div>
            </div>
            {previewForm}
        </article>
    |]
    applicationAvailable = maybe False (not . (.windowIsPublished)) maybeRosterWeek
    applyButton = [hsx|
        <button class="btn text-start flex-grow-1 p-3 roster-template-card-apply"
                type="submit"
                form={previewFormId}
                disabled={not applicationAvailable}
                aria-label={"Apply " <> template.name}>
            <strong class="d-block">{template.name}</strong>
            <span class="small text-muted">Week snapshot</span>
        </button>
    |]
    previewForm
        | not applicationAvailable = mempty
        | otherwise = renderFrontendSurfaceActionForm (RosterAction.previewRosterTemplateApplicationAction previewFields) previewRoute [hsx|
        <input type="hidden" name={surfaceFieldNameFrom @Surface.TemplateId previewFields} value={tshow template.id} />
        <input type="hidden" name={surfaceFieldNameFrom @Surface.AnchorDate previewFields} value={tshow anchorDate} />
        <input type="hidden" name={surfaceFieldNameFrom @Surface.RosterCalendarRevision previewFields} value={tshow calendarRevision} />
    |]
    previewFormId = rosterTemplateApplicationPreviewFormId template.id
    previewFields = RosterAction.previewRosterTemplateApplicationActionFields (unpackId template.id) anchorDate calendarRevision Nothing Nothing
    previewRoute = FrontendSurfaceActionRoute
        { actionRouteUrl = pathTo PreviewRosterTemplateApplicationAction { rosterGroupId = rosterGroup.id }
        , actionRouteCustomHtmx = []
        , actionRouteStandardUrl = Just (pathTo PreviewRosterTemplateApplicationAction { rosterGroupId = rosterGroup.id })
        , actionRouteExtraAttrs = [("id", previewFormId), ("class", "d-none")]
        }
