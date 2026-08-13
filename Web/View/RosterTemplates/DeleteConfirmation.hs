module Web.View.RosterTemplates.DeleteConfirmation
    ( renderRosterTemplateDeleteConfirmation
    ) where

import Application.Helper.View.Overlay
import Web.View.Prelude

renderRosterTemplateDeleteConfirmation :: (?context :: ControllerContext) => RosterTemplate -> Id RosterGroup -> Day -> Html
renderRosterTemplateDeleteConfirmation template rosterGroupId anchorDate =
    renderDialogOverlay DialogOverlayConfig
        { dialogOverlayTitle = "Delete " <> template.name
        , dialogOverlayBody = [hsx|
            <p>Delete this saved template?</p>
            <p class="small text-muted">Existing rosters are unaffected. This removes the template from the shared library.</p>
            <form id={formId} method="POST" action={DeleteRosterTemplateAction template.id}>
                <input type="hidden" name="_method" value="DELETE" />
                <input type="hidden" name="rosterGroupId" value={tshow rosterGroupId} />
                <input type="hidden" name="anchorDate" value={tshow anchorDate} />
            </form>
        |]
        , dialogOverlayStartButtons = []
        , dialogOverlayButtons =
            [ OverlayButton
                { overlayButtonLabel = "Cancel"
                , overlayButtonClass = "btn btn-outline-secondary"
                , overlayButtonAction = OverlayCloseAction
                }
            , OverlayButton
                { overlayButtonLabel = "Delete template"
                , overlayButtonClass = "btn btn-danger"
                , overlayButtonAction = OverlaySubmitFormAction formId
                }
            ]
        , dialogOverlayDialogClass = ""
        }
  where
    formId = "roster-template-delete-form"
