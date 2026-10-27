module Web.Controller.RecipientGroups where

import Application.RecipientGroups (listRecipientGroups)
import Web.Controller.Prelude
import Web.RecipientGroups
import Web.View.Admin.RecipientGroups (renderRecipientGroupsFragment)

instance Controller RecipientGroupsController where
    beforeAction = bepisBeforeAction BepisAdminVenueController do
        annotateTelemetryAction
        ensureIsUser
        ensureCurrentVenue
        ensureProfileCompleted
        ensureAdminRole

    action currentAction@NewRecipientGroupAction = runBepis currentAction BepisFormAction $
        openRecipientGroup Nothing
    action currentAction@EditRecipientGroupAction { recipientGroupId } = runBepis currentAction BepisFormAction $
        openRecipientGroup (Just recipientGroupId)
    action currentAction@SaveRecipientGroupAction = runBepis currentAction BepisMutationAction saveRecipientGroupFromRequest
    action currentAction@ConfirmDeleteRecipientGroupAction { recipientGroupId } = runBepis currentAction BepisFormAction $
        confirmRecipientGroupDeletion recipientGroupId Nothing
    action currentAction@DeleteRecipientGroupAction { recipientGroupId } = runBepis currentAction BepisMutationAction $
        deleteRecipientGroupFromRequest recipientGroupId
    action currentAction@ShowadminRecipientGroupsFragmentAction = runBepis currentAction BepisFragmentAction do
        groups <- listRecipientGroups
        respondHtml (renderRecipientGroupsFragment (either (const []) (\values -> values) groups))
