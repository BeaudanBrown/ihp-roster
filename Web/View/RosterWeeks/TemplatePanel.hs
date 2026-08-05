module Web.View.RosterWeeks.TemplatePanel
    ( renderRosterTemplateLibraryFragment
    , renderRosterTemplatePanel
    ) where

import Application.RosterTemplates
import qualified Application.Helper.FrontendContract.Surface.Interaction as SurfaceInteraction
import qualified Application.Helper.FrontendContract.Surface.Roster as Surface
import qualified Application.Helper.FrontendContract.Surface.Roster.Action as RosterAction
import Application.Helper.FrontendContract.Surface.Roster.TemplateApplication
import Application.Helper.FrontendContract.Surface.Runtime (FrontendSurfaceActionRoute (..),
                                                            renderFrontendSurfaceActionForm)
import Application.Helper.FrontendContract.Surface.Values (surfaceFieldNameFrom)
import Application.Helper.View.Overlay (dialogOverlayMountId)
import Web.RosterWeeks.Dom (rosterTemplateLibraryFragmentId)
import Web.RosterWeeks.FrontendSurface (rosterDayTemplateDragSourceRef,
                                        rosterWeekTemplateDragSourceRef)
import Web.View.Prelude

renderRosterTemplateLibraryFragment :: (?context :: ControllerContext) => Id User -> Int -> RosterGroup -> Maybe RosterWeek -> RosterTemplateLibrary -> Html
renderRosterTemplateLibraryFragment userId weekOffset rosterGroup maybeRosterWeek library = [hsx|
    <div id={rosterTemplateLibraryFragmentId userId}>
        {renderRosterTemplatePanel weekOffset rosterGroup maybeRosterWeek library}
    </div>
|]

renderRosterTemplatePanel :: (?context :: ControllerContext) => Int -> RosterGroup -> Maybe RosterWeek -> RosterTemplateLibrary -> Html
renderRosterTemplatePanel weekOffset rosterGroup maybeRosterWeek library = [hsx|
    <section class="roster-template-panel" aria-labelledby="roster-template-panel-heading">
        <div class="roster-staff-panel-header">
            <h2 id="roster-template-panel-heading" class="h5 mb-0">Templates</h2>
            <div class="d-flex gap-2">
                <button class="btn btn-sm btn-outline-secondary" type="button" hidden="hidden" {...rosterTemplateCancelAttrs}>Cancel</button>
                <a class="btn btn-sm btn-outline-primary" href={NewRosterTemplateAction rosterGroup.id}>New</a>
            </div>
        </div>
        {forEach library.libraryPrivateDraft renderPrivateDraft}
        {renderLiveRosterTemplateMessage maybeRosterWeek}
        {renderTemplateScaleSection "Day templates" Day weekOffset rosterGroup maybeRosterWeek library.libraryTemplates}
        {renderTemplateScaleSection "Week templates" Week weekOffset rosterGroup maybeRosterWeek library.libraryTemplates}
    </section>
|]

renderLiveRosterTemplateMessage :: Maybe RosterWeek -> Html
renderLiveRosterTemplateMessage (Just rosterWeek)
    | rosterWeek.isLive = [hsx|
        <div class="alert alert-info small" role="status">Templates cannot be applied to a live roster. Move this week back to draft to apply one.</div>
    |]
renderLiveRosterTemplateMessage _ = mempty

renderPrivateDraft :: (?context :: ControllerContext) => RosterTemplateDraft -> Html
renderPrivateDraft draft = [hsx|
    <div class="alert alert-light border d-flex justify-content-between align-items-center gap-2">
        <span class="small">Private draft: <strong>{draft.draftName}</strong></span>
        <a class="btn btn-sm btn-outline-primary" href={ShowRosterTemplateDesignerAction draft.draftDesign.id}>Continue</a>
    </div>
|]

renderTemplateScaleSection :: (?context :: ControllerContext) => Text -> RosterTemplateScaleEnum -> Int -> RosterGroup -> Maybe RosterWeek -> [RosterTemplate] -> Html
renderTemplateScaleSection heading scale weekOffset rosterGroup maybeRosterWeek templates = [hsx|
    <section class="roster-template-scale-section mt-3" aria-label={heading}>
        <h3 class="h6 text-muted">{heading}</h3>
        {renderTemplateCards weekOffset rosterGroup maybeRosterWeek matchingTemplates}
    </section>
|]
  where
    matchingTemplates = filter ((== scale) . (.scale)) templates

renderTemplateCards :: (?context :: ControllerContext) => Int -> RosterGroup -> Maybe RosterWeek -> [RosterTemplate] -> Html
renderTemplateCards _ _ _ [] = [hsx|<p class="small text-muted">No saved templates.</p>|]
renderTemplateCards weekOffset rosterGroup maybeRosterWeek templates = forEach templates (renderTemplateCard weekOffset rosterGroup maybeRosterWeek)

renderTemplateCard :: (?context :: ControllerContext) => Int -> RosterGroup -> Maybe RosterWeek -> RosterTemplate -> Html
renderTemplateCard weekOffset rosterGroup maybeRosterWeek template = cardHtml
  where
    cardHtml = [hsx|
        <article class="roster-template-card border rounded-3 mb-2"
                 {...rosterTemplateCardAttrs (unpackId template.id) template.name (templateScaleValue template.scale)}>
            <div class="d-flex align-items-stretch">
                {applyButton}
                <div class="d-flex align-items-center gap-1 pe-2 roster-template-card-actions">
                    <form method="POST" action={EditRosterTemplateAction template.id}>
                        <button class="btn btn-sm btn-outline-secondary app-icon-button" type="submit" title={"Edit " <> template.name} aria-label={"Edit " <> template.name}>
                            <i class="bi bi-pencil" aria-hidden="true"></i>
                        </button>
                    </form>
                    <form method="POST" action={ConfirmDeleteRosterTemplateAction template.id rosterGroup.id weekOffset}>
                        <button class="btn btn-sm btn-outline-danger app-icon-button" type="submit" title={"Delete " <> template.name} aria-label={"Delete " <> template.name}>
                            <i class="bi bi-trash" aria-hidden="true"></i>
                        </button>
                    </form>
                </div>
            </div>
            {previewForm}
        </article>
    |]
    applicationAvailable = maybe False (not . (.isLive)) maybeRosterWeek
    applyButton = (if applicationAvailable then SurfaceInteraction.withFrontendSurfaceSourceRef templateSourceRef (tshow template.id) else \html -> html) [hsx|
        <button class="btn text-start flex-grow-1 p-3 roster-template-card-apply"
                type="button"
                disabled={not applicationAvailable}
                aria-label={"Apply " <> template.name}>
            <strong class="d-block">{template.name}</strong>
            <span class="small text-muted">Version {template.currentVersion}</span>
        </button>
    |]
    previewForm
        | not applicationAvailable = mempty
        | otherwise = renderFrontendSurfaceActionForm (RosterAction.previewRosterTemplateApplicationAction previewFields) previewRoute [hsx|
        <input type="hidden" name={surfaceFieldNameFrom @SurfaceInteraction.SourceItemKey previewFields} value={tshow template.id} />
        <input type="hidden" name={surfaceFieldNameFrom @SurfaceInteraction.TargetDropzoneKey previewFields} value={initialTargetKey} {...rosterTemplateTargetInputAttrs} />
    |]
    templateSourceRef = case template.scale of
        Day  -> rosterDayTemplateDragSourceRef
        Week -> rosterWeekTemplateDragSourceRef
    initialTargetKey = case template.scale of
        Day  -> ""
        Week -> maybe "" (("week:" <>) . tshow . (.id)) maybeRosterWeek
    previewFields = RosterAction.previewRosterTemplateApplicationActionFields (tshow template.id) initialTargetKey Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing
    previewRoute = FrontendSurfaceActionRoute
        { actionRouteUrl = pathTo PreviewRosterTemplateDropAction
            { rosterGroupId = rosterGroup.id
            , weekOffset
            }
        , actionRouteCustomHtmx = []
        , actionRouteStandardUrl = Just (pathTo PreviewRosterTemplateDropAction
            { rosterGroupId = rosterGroup.id
            , weekOffset
            })
        , actionRouteExtraAttrs = rosterTemplateApplicationFormAttrs <> [("class", "d-none")]
        }

templateScaleValue :: RosterTemplateScaleEnum -> Text
templateScaleValue Day  = "day"
templateScaleValue Week = "week"
