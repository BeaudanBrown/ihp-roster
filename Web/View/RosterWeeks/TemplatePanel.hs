{-# OPTIONS_GHC -Werror=incomplete-patterns #-}

module Web.View.RosterWeeks.TemplatePanel
    ( renderRosterTemplateLibraryFragment
    , renderRosterTemplatePanel
    ) where

import qualified Application.Helper.FrontendContract.Surface.Roster as Surface
import qualified Application.Helper.FrontendContract.Surface.Roster.Action as RosterAction
import Application.Helper.FrontendContract.Surface.Runtime (FrontendSurfaceActionRoute (..),
                                                            defaultFrontendSurfaceActionRoute,
                                                            renderFrontendSurfaceActionForm)
import Application.Helper.FrontendContract.Surface.Values (surfaceFieldNameFrom)
import Application.RosterTemplates
import qualified Data.Map.Strict as Map
import Web.RosterWeeks.Dom (rosterTemplateApplicationPreviewFormId,
                            rosterTemplateCaptureLauncherFormId,
                            rosterTemplateCardId,
                            rosterTemplateDeletePreviewFormId,
                            rosterTemplateLibraryFragmentId)
import Web.RosterWeeks.Types (RosterWindowState (..))
import Web.View.Prelude

renderRosterTemplateLibraryFragment :: (?context :: ControllerContext) => Day -> Int -> RosterGroup -> Maybe RosterWindowState -> RosterTemplateLibrary -> Html
renderRosterTemplateLibraryFragment anchorDate calendarRevision rosterGroup maybeRosterWeek library = [hsx|
    <div id={rosterTemplateLibraryFragmentId}>
        {renderRosterTemplatePanel anchorDate calendarRevision rosterGroup maybeRosterWeek library}
    </div>
|]

renderRosterTemplatePanel :: (?context :: ControllerContext) => Day -> Int -> RosterGroup -> Maybe RosterWindowState -> RosterTemplateLibrary -> Html
renderRosterTemplatePanel anchorDate calendarRevision rosterGroup maybeRosterWeek library = [hsx|
    <section class="roster-template-panel" aria-labelledby="roster-template-panel-heading">
        <div class="app-side-panel-content-header roster-staff-panel-header">
            <h2 id="roster-template-panel-heading" class="h5 mb-0">Templates</h2>
            {renderCaptureLauncher anchorDate rosterGroup.id}
        </div>
        <div class="mt-3" aria-label="Saved Week templates">
            {renderTemplateCards anchorDate calendarRevision rosterGroup maybeRosterWeek library}
        </div>
    </section>
|]

renderCaptureLauncher :: (?context :: ControllerContext) => Day -> Id RosterGroup -> Html
renderCaptureLauncher anchorDate rosterGroupId =
    renderFrontendSurfaceActionForm (RosterAction.openRosterTemplateCaptureAction RosterAction.openRosterTemplateCaptureActionFields) route [hsx|
        <button class="btn btn-sm btn-primary" type="submit">Save current week as template</button>
    |]
  where
    actionUrl = appendQueryParams (pathTo PreviewRosterTemplateCaptureAction { rosterGroupId }) [("anchorDate", tshow anchorDate)]
    route = ((defaultFrontendSurfaceActionRoute (actionUrl))
        { actionRouteStandardUrl = Just actionUrl
        , actionRouteExtraAttrs = [("id", rosterTemplateCaptureLauncherFormId), ("class", "app-side-panel-content-header-actions")]
        })

renderTemplateCards :: (?context :: ControllerContext) => Day -> Int -> RosterGroup -> Maybe RosterWindowState -> RosterTemplateLibrary -> Html
renderTemplateCards _ _ _ _ RosterTemplateLibrary { libraryTemplates = [] } = [hsx|<p class="small text-muted">No templates are saved.</p>|]
renderTemplateCards anchorDate calendarRevision rosterGroup maybeRosterWeek library =
    forEach library.libraryTemplates (renderTemplateCard anchorDate calendarRevision rosterGroup maybeRosterWeek library.libraryShiftCounts)

renderTemplateCard :: (?context :: ControllerContext) => Day -> Int -> RosterGroup -> Maybe RosterWindowState -> Map.Map (Id RosterTemplate) Int -> RosterTemplate -> Html
renderTemplateCard anchorDate calendarRevision rosterGroup maybeRosterWeek shiftCounts template = [hsx|
    <article id={rosterTemplateCardId template.id} class="roster-template-card border rounded-3 mb-2 p-3">
        <div class="d-flex align-items-center justify-content-between gap-3">
            <div class="min-w-0">
                <strong class="d-block text-truncate">{template.name}</strong>
                <span class="small text-muted">{shiftCount} shift(s)</span>
            </div>
            <div class="d-flex align-items-center gap-2 roster-template-card-actions">
                <button class="btn btn-sm btn-outline-primary"
                        type="submit"
                        form={previewFormId}
                        disabled={not applicationAvailable}
                        title={applyTitle}
                        aria-label={"Apply " <> template.name}>Apply</button>
                {renderDeleteLauncher anchorDate rosterGroup.id template}
            </div>
        </div>
        {previewForm}
    </article>
|]
  where
    shiftCount = Map.findWithDefault 0 template.id shiftCounts
    applicationAvailable = isJust maybeRosterWeek
    applyTitle
        | applicationAvailable = "Apply " <> template.name
        | otherwise = "Apply requires a complete viewed roster window"
    previewForm
        | not applicationAvailable = mempty
        | otherwise = renderFrontendSurfaceActionForm (RosterAction.previewRosterTemplateApplicationAction previewFields) previewRoute [hsx|
            <input type="hidden" name={surfaceFieldNameFrom @Surface.TemplateId previewFields} value={tshow template.id} />
            <input type="hidden" name={surfaceFieldNameFrom @Surface.AnchorDate previewFields} value={tshow anchorDate} />
            <input type="hidden" name={surfaceFieldNameFrom @Surface.RosterCalendarRevision previewFields} value={tshow calendarRevision} />
        |]
    previewFormId = rosterTemplateApplicationPreviewFormId template.id
    previewFields = RosterAction.previewRosterTemplateApplicationActionFields (unpackId template.id) anchorDate calendarRevision Nothing Nothing
    previewRoute = ((defaultFrontendSurfaceActionRoute (pathTo PreviewRosterTemplateApplicationAction { rosterGroupId = rosterGroup.id }))
        { actionRouteStandardUrl = Just (pathTo PreviewRosterTemplateApplicationAction { rosterGroupId = rosterGroup.id })
        , actionRouteExtraAttrs = [("id", previewFormId), ("class", "d-none")]
        })

renderDeleteLauncher :: (?context :: ControllerContext) => Day -> Id RosterGroup -> RosterTemplate -> Html
renderDeleteLauncher anchorDate rosterGroupId template =
    renderFrontendSurfaceActionForm (RosterAction.openRosterTemplateDeleteAction RosterAction.openRosterTemplateDeleteActionFields) route [hsx|
        <button class="btn btn-sm btn-outline-danger app-icon-button" type="submit" title={"Delete " <> template.name} aria-label={"Delete " <> template.name}>
            <i class="bi bi-trash" aria-hidden="true"></i>
        </button>
    |]
  where
    actionUrl = appendQueryParams (pathTo (ConfirmDeleteRosterTemplateAction template.id rosterGroupId)) [("anchorDate", tshow anchorDate)]
    route = ((defaultFrontendSurfaceActionRoute (actionUrl))
        { actionRouteStandardUrl = Just actionUrl
        , actionRouteExtraAttrs = [("id", rosterTemplateDeletePreviewFormId template.id)]
        })
