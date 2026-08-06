module Web.View.RosterTemplates.DraftOccupied where

import Application.Helper.RosterTemplateScale (rosterTemplateScaleValue)
import Application.RosterTemplates
import Web.View.Prelude

data DraftOccupiedView = DraftOccupiedView
    { rosterGroup              :: !RosterGroup
    , existingDraft            :: !RosterTemplateDraft
    , pendingName              :: !Text
    , pendingScale             :: !RosterTemplateScaleEnum
    , pendingStartingPoint     :: !Text
    , pendingWeekOffset        :: !(Maybe Int)
    , pendingDayOffset         :: !(Maybe Int)
    , pendingConfirmationToken :: !(Maybe Text)
    }

instance View DraftOccupiedView where
    html DraftOccupiedView { .. } =
        renderAppPage AppPageConfig
            { appPageTitle = "Template draft already in progress"
            , appPageDescription = Nothing
            , appPageActions = mempty
            , appPageHelpTopic = Just (PageHelpTopicId "roster")
            , appPageWidthClass = ""
            , appPageBody = [hsx|
                <div id="roster-template-draft-occupied" class="row g-4 roster-layout">
                    <div class="col-12 mx-auto">
                        <div class="app-panel roster-main-panel p-4 p-lg-5">
                            <h2 class="h4">A template draft is already in progress</h2>
                            <p>Your private draft <strong>{existingDraft.draftName}</strong> must be continued or discarded before another can start.</p>
                            <div class="d-flex flex-wrap gap-2">
                                <a class="btn btn-primary" href={ShowRosterTemplateDesignerAction existingDraft.draftDesign.id}>Continue draft</a>
                                <form method="POST" action={DiscardAndRestartRosterTemplateDraftAction rosterGroup.id existingDraft.draftDesign.id}>
                                    <input type="hidden" name="name" value={pendingName} />
                                    <input type="hidden" name="scale" value={rosterTemplateScaleValue pendingScale} />
                                    <input type="hidden" name="startingPoint" value={pendingStartingPoint} />
                                    <input type="hidden" name="expectedDraftRevision" value={rosterTemplateDraftRevision existingDraft} />
                                    {forEach pendingWeekOffset renderWeekOffset}
                                    {forEach pendingDayOffset renderDayOffset}
                                    {forEach pendingConfirmationToken renderConfirmationToken}
                                    <button class="btn btn-danger" type="submit">Discard and start new</button>
                                </form>
                                <a class="btn btn-outline-secondary" href={NewRosterTemplateAction rosterGroup.id}>Cancel</a>
                            </div>
                        </div>
                    </div>
                </div>
            |]
            }


renderWeekOffset :: Int -> Html
renderWeekOffset value = [hsx|<input type="hidden" name="weekOffset" value={tshow value} />|]

renderConfirmationToken :: Text -> Html
renderConfirmationToken value = [hsx|<input type="hidden" name="confirmationToken" value={value} />|]

renderDayOffset :: Int -> Html
renderDayOffset value = [hsx|<input type="hidden" name="dayOffset" value={tshow value} />|]
