module Web.View.RosterTemplates.DeleteConfirmation
    ( renderRosterTemplateDeleteConfirmation
    , renderRosterTemplateDeleteError
    ) where

import qualified Application.Helper.FrontendContract.Surface.Roster.Action as RosterAction
import Application.Helper.FrontendContract.Surface.Runtime (FrontendSurfaceActionRoute (..),
                                                            defaultFrontendSurfaceActionRoute,
                                                            renderFrontendSurfaceActionForm)
import Application.Helper.View.Overlay
import Web.RosterWeeks.Dom (rosterTemplateDeleteFormId)
import Web.View.Prelude

renderRosterTemplateDeleteConfirmation :: (?context :: ControllerContext) => RosterTemplate -> Id RosterGroup -> Day -> Html
renderRosterTemplateDeleteConfirmation template rosterGroupId anchorDate =
    renderConfirmationDialog
        (defaultConfirmationDialogConfig
            ("Delete " <> template.name)
            [hsx|
                <p>Delete this saved template?</p>
                <p class="small text-muted mb-0">Existing rosters are unaffected.</p>
            |]
            rosterTemplateDeleteFormId
            deleteForm)
            { confirmationDialogApproveLabel = "Delete template"
            , confirmationDialogApproveTone = ConfirmationDanger
            , confirmationDialogLoadingLabel = "Deleting…"
            }
  where
    deleteForm = renderFrontendSurfaceActionForm (RosterAction.deleteRosterTemplateAction RosterAction.deleteRosterTemplateActionFields) route [hsx|
        <input type="hidden" name="_method" value="DELETE"/>
    |]
    actionUrl = appendQueryParams
        (pathTo (DeleteRosterTemplateAction template.id))
        [("anchorDate", tshow anchorDate), ("rosterGroupId", tshow rosterGroupId)]
    route = ((defaultFrontendSurfaceActionRoute (actionUrl))
        { actionRouteStandardUrl = Just actionUrl
        , actionRouteExtraAttrs = [("id", rosterTemplateDeleteFormId)]
        })

renderRosterTemplateDeleteError :: Text -> Html
renderRosterTemplateDeleteError message =
    renderDialogOverlay (defaultDialogOverlayConfig
            "Delete template"
            [hsx|<p class="alert alert-danger">{message}</p>|]
            [dialogOverlayCloseButton "Close"])
