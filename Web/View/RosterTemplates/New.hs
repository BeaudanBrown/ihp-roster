module Web.View.RosterTemplates.New where

import Application.RosterTemplates
import Web.View.Prelude

data NewView = NewView
    { rosterGroup     :: !RosterGroup
    , templateLibrary :: !RosterTemplateLibrary
    , creationError   :: !(Maybe Text)
    }

instance View NewView where
    html NewView { .. } =
        renderAppPage AppPageConfig
            { appPageTitle = "Create roster template"
            , appPageDescription = Just "Choose the scale and whether to begin blank or from an existing roster."
            , appPageActions = mempty
            , appPageHelpTopic = Just (PageHelpTopicId "roster")
            , appPageWidthClass = ""
            , appPageBody = [hsx|
                <div id="roster-template-create" class="row g-4 roster-layout">
                    <div class="col-12 mx-auto">
                        <div class="app-panel roster-main-panel">
                            <div class="p-4 p-lg-5">
                                <p class="text-uppercase small fw-semibold text-muted mb-2">{rosterGroup.name}</p>
                                <h2 class="h4 mb-4">Create roster template</h2>
                                {forEach creationError renderCreationError}
                                <form method="POST" action={CreateRosterTemplateDraftAction rosterGroup.id}>
                                    <fieldset class="mb-4">
                                        <legend class="h6">Template scale</legend>
                                        <div class="d-flex flex-wrap gap-3">
                                            <label class="form-check">
                                                <input class="form-check-input" type="radio" name="scale" value="day" required="required" />
                                                <span class="form-check-label">Day</span>
                                            </label>
                                            <label class="form-check">
                                                <input class="form-check-input" type="radio" name="scale" value="week" required="required" />
                                                <span class="form-check-label">Week</span>
                                            </label>
                                        </div>
                                    </fieldset>
                                    <div class="mb-4">
                                        <label class="form-label" for="roster-template-name">Template name</label>
                                        <input id="roster-template-name" class="form-control" type="text" name="name" maxlength="120" required="required" />
                                    </div>
                                    <fieldset>
                                        <legend class="h6">Starting point</legend>
                                        <div class="row g-3">
                                            <div class="col-12 col-md-6">
                                                <label class="border rounded-3 p-4 h-100 d-block">
                                                    <input class="form-check-input me-2" type="radio" name="startingPoint" value="blank" required="required" />
                                                    <span class="h5 d-inline">Start from a blank design</span>
                                                    <span class="text-muted d-block mt-2">Build a Day or Week template without changing a roster.</span>
                                                </label>
                                            </div>
                                            <div class="col-12 col-md-6">
                                                <label class="border rounded-3 p-4 h-100 d-block">
                                                    <input class="form-check-input me-2" type="radio" name="startingPoint" value="reference" required="required" />
                                                    <span class="h5 d-inline">Use a roster as reference</span>
                                                    <span class="text-muted d-block mt-2">Choose an existing live or draft roster, then copy only its design into your private draft.</span>
                                                </label>
                                            </div>
                                        </div>
                                    </fieldset>
                                    <div class="d-flex justify-content-end mt-4">
                                        <button class="btn btn-primary" type="submit">Continue</button>
                                    </div>
                                </form>
                                <hr class="my-5" />
                                <section aria-labelledby="roster-template-library-heading">
                                    <div class="d-flex flex-wrap justify-content-between align-items-center gap-2 mb-3">
                                        <h2 id="roster-template-library-heading" class="h4 mb-0">Saved templates</h2>
                                    </div>
                                    {if null templateLibrary.libraryTemplates
                                        then renderEmptyLibrary
                                        else forEach templateLibrary.libraryTemplates renderSavedTemplate}
                                </section>
                            </div>
                        </div>
                    </div>
                </div>
            |]
            }

renderEmptyLibrary :: Html
renderEmptyLibrary = [hsx|<p class="text-muted mb-0">No saved templates yet.</p>|]

renderSavedTemplate :: RosterTemplate -> Html
renderSavedTemplate template = [hsx|
    <div class="d-flex flex-wrap align-items-center justify-content-between gap-3 border rounded-3 p-3 mb-2" data-roster-template-id={tshow template.id}>
        <div>
            <h3 class="h6 mb-1">{template.name}</h3>
            <span class="badge text-bg-secondary">Week snapshot</span>
        </div>
        <div class="d-flex gap-2">
            <form method="POST" action={EditRosterTemplateAction template.id}>
                <button class="btn btn-outline-primary btn-sm" type="submit">Edit</button>
            </form>
            <form method="POST" action={DeleteRosterTemplateAction template.id}>
                <input type="hidden" name="_method" value="DELETE" />
                <button class="btn btn-outline-danger btn-sm" type="submit">Delete</button>
            </form>
        </div>
    </div>
|]


renderCreationError :: Text -> Html
renderCreationError message = [hsx|
    <div class="alert alert-danger" role="alert">{message}</div>
|]
