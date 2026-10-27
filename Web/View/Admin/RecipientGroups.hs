module Web.View.Admin.RecipientGroups where

import qualified Application.Helper.FrontendContract.AppShell as Shell
import Application.Helper.FrontendContract.AppShell.Request (appShellActionFields)
import Application.Helper.FrontendContract.AppShell.Runtime
import Application.Helper.FrontendContract.Overlay.Runtime (dialogEnterSubmitAttrs)
import qualified Application.Helper.FrontendContract.Surface.Admin as Surface
import Application.Helper.FrontendContract.Surface.Runtime (renderFrontendSurfaceMount)
import Application.Helper.FrontendContract.Surface.Values
import Application.Helper.View.Overlay
import Application.Helper.Url (appendQueryParams)
import qualified Data.Text as Text
import Web.Admin.FrontendSurface (AdminVenueScopeValue (..), adminRecipientGroupsSurfaceImpl)
import Web.View.Admin.Common
import Web.View.Prelude

renderRecipientGroupsMount :: (?context :: ControllerContext) => [RecipientGroup] -> Html
renderRecipientGroupsMount groups = renderFrontendSurfaceMount
    (adminRecipientGroupsSurfaceImpl AdminVenueScopeValue { adminVenueId = currentAdminVenueScopeId, adminRosterGroupId = Nothing })
    (renderRecipientGroupsFragment groups)

renderRecipientGroupsFragment :: [RecipientGroup] -> Html
renderRecipientGroupsFragment groups = [hsx|
    <div id={surfaceFragmentTargetId @Surface.AdminRecipientGroupsSurface @Surface.AdminRecipientGroupsFragment noSurfaceFields}>
        <div class="d-flex flex-wrap justify-content-between align-items-center gap-2 mb-3">
            <p class="mb-0">Named email lists for this venue. Being a recipient grants no access to Bepis.</p>
            <button {...createAttrs}>Create recipient group</button>
        </div>
        <div class="d-grid gap-2">
            {if null groups then renderEmptyState "No recipient groups yet." else forEach groups renderGroup}
        </div>
    </div>
|]
  where
    createAttrs = appShellActionAttrs (appShellActionByMarker @Shell.OpenRecipientGroupDialog)
        ((defaultAppShellActionRoute (pathTo NewRecipientGroupAction)) { appShellActionRouteExtraAttrs = [("class", "btn btn-outline-primary")] })
    renderGroup group = [hsx|
        <div class={appSurfaceClasses "p-3"} role="group" aria-label={group.name}>
            <div class="d-flex flex-wrap justify-content-between align-items-center gap-3">
                <div><div class="fw-semibold text-break">{group.name}</div><div class="small app-muted">{length group.recipients} {if length group.recipients == 1 then "recipient" else "recipients" :: Text}</div></div>
                <div class="d-flex gap-2">
                    <button {...editAttrs}>Edit</button>
                    <button {...deleteAttrs}>Delete</button>
                </div>
            </div>
        </div>
    |]
      where
        editAttrs = appShellActionAttrs (appShellActionByMarker @Shell.OpenRecipientGroupDialog)
            ((defaultAppShellActionRoute (pathTo (EditRecipientGroupAction group.id))) { appShellActionRouteExtraAttrs = [("class", "btn btn-outline-secondary")] })
        deleteAttrs = appShellActionAttrs (appShellActionByMarker @Shell.OpenRecipientGroupDeleteDialog)
            ((defaultAppShellActionRoute (pathTo (ConfirmDeleteRecipientGroupAction group.id))) { appShellActionRouteExtraAttrs = [("class", "btn btn-outline-danger")] })

-- Private recipient inputs are only rendered to authorised users, never logged.
data RecipientGroupDraft = RecipientGroupDraft
    { groupId :: !(Maybe UUID)
    , nameText :: !Text
    , addressesText :: !Text
    , entryText :: !Text
    , revision :: !(Maybe Int)
    }

recipientGroupDraft :: Maybe RecipientGroup -> RecipientGroupDraft
recipientGroupDraft group = RecipientGroupDraft
    { groupId = unpackId . (.id) <$> group
    , nameText = maybe "" (.name) group
    , addressesText = maybe "" (Text.intercalate "\n" . (.recipients)) group
    , entryText = ""
    , revision = (.revision) <$> group
    }

renderRecipientGroupDialog :: RecipientGroupDraft -> Maybe Text -> Html
renderRecipientGroupDialog draft message = renderKeyboardDialogOverlay DialogOverlayConfig
    { dialogOverlayTitle = if isJust draft.groupId then "Edit recipient group" else "Create recipient group"
    , dialogOverlayBody = [hsx|
        {forEach message renderMessage}
        {renderAppShellActionForm (appShellActionByMarker @Shell.SaveRecipientGroup)
            ((defaultAppShellActionRoute (pathTo SaveRecipientGroupAction)) { appShellActionRouteExtraAttrs = [("id", "recipient-group-form")] }) formBody}
      |]
    , dialogOverlayStartButtons = []
    , dialogOverlayButtons = defaultOverlayButtons "recipient-group-form"
    , dialogOverlayDialogClass = "modal-lg"
    , dialogOverlayDismissalGuard = Nothing
    }
  where
    renderMessage text = [hsx|<p class="alert alert-info" role="status">{text}</p>|]
    addresses = filter (not . Text.null) (Text.lines draft.addressesText)
    fields = appShellActionFields @Shell.SaveRecipientGroup
        (surfaceField @Shell.RecipientGroupNameField draft.nameText)
        ( surfaceField @Shell.RecipientGroupAddressesField draft.addressesText
        &: surfaceOptionalField @Shell.RecipientGroupIdField draft.groupId
        &: surfaceOptionalField @Shell.RecipientGroupRevisionField draft.revision
        &: surfaceOptionalField @Shell.RecipientGroupEntryField (Just draft.entryText)
        &: surfaceOptionalField @Shell.RecipientGroupAddField Nothing
        &: surfaceOptionalField @Shell.RecipientGroupRemoveField Nothing
        &: noSurfaceFields )
    formBody = [hsx|
        <label class="form-label" for="recipient-group-name">Group name</label>
        <input id="recipient-group-name" class="form-control mb-3" name={surfaceFieldNameFrom @Shell.RecipientGroupNameField fields} value={draft.nameText} maxlength="100" autofocus={Text.null draft.nameText}/>
        <label class="form-label" for="recipient-group-entry">Email address</label>
        <div class="input-group mb-2">
            <input id="recipient-group-entry" class="form-control" type="email" autocomplete="email" name={surfaceFieldNameFrom @Shell.RecipientGroupEntryField fields} value={draft.entryText} autofocus={not (Text.null draft.nameText)}/>
            <button type="submit" class="btn btn-outline-primary" name={surfaceFieldNameFrom @Shell.RecipientGroupAddField fields} value="true" {...dialogEnterSubmitAttrs}>Add</button>
        </div>
        <p class="small app-muted">Add 1–50 email addresses. Payroll emails show the entire group in To and Reply-To.</p>
        <ul class="list-group mb-3" aria-label="Recipient addresses">{forEach addresses renderAddress}</ul>
        <input type="hidden" name={surfaceFieldNameFrom @Shell.RecipientGroupAddressesField fields} value={draft.addressesText}/>
        {forEach draft.groupId renderIdentifier}
        {forEach draft.revision renderRevision}
    |]
    renderIdentifier identifier = [hsx|<input type="hidden" name={surfaceFieldNameFrom @Shell.RecipientGroupIdField fields} value={tshow identifier}/>|]
    renderRevision revision = [hsx|<input type="hidden" name={surfaceFieldNameFrom @Shell.RecipientGroupRevisionField fields} value={tshow revision}/>|]
    renderAddress address = [hsx|
        <li class="list-group-item d-flex align-items-center justify-content-between gap-2">
            <span class="text-break">{address}</span>
            <button type="submit" class="btn btn-outline-secondary btn-sm" formnovalidate="formnovalidate" name={surfaceFieldNameFrom @Shell.RecipientGroupRemoveField fields} value={address} aria-label={"Remove " <> address}>Remove</button>
        </li>
    |]

renderRecipientGroupDeleteConfirmation :: RecipientGroup -> Bool -> Maybe Text -> Html
renderRecipientGroupDeleteConfirmation group linked message = renderConfirmationDialog
    ((defaultConfirmationDialogConfig "Delete recipient group" description "recipient-group-delete-form" form)
        { confirmationDialogApproveLabel = if linked then "Delete group and disable schedule" else "Delete group"
        , confirmationDialogApproveTone = ConfirmationDanger
        , confirmationDialogLoadingLabel = "Deleting…"
        })
  where
    description = [hsx|
        {forEach message renderMessage}
        <p>Delete <strong class="text-break">{group.name}</strong> from available recipient groups?</p>
        {linkedWarning}
        <p>Prepared manual emails keep their original recipients. Emails already being sent cannot be recalled.</p>
    |]
    renderMessage text = [hsx|<p class="alert alert-warning" role="status">{text}</p>|]
    linkedWarning = if linked then [hsx|<p class="alert alert-warning">This group is selected for scheduled reports. Deleting it also disables that schedule and stops unstarted automatic emails.</p>|] else mempty
    fields = appShellActionFields @Shell.DeleteRecipientGroup
        (surfaceField @Shell.RecipientGroupRevisionField group.revision)
        (surfaceOptionalField @Shell.RecipientGroupDisableScheduleField (Just linked) &: noSurfaceFields)
    -- IHP does not parse DELETE bodies. Carry only these non-private immutable
    -- confirmation fields in the typed URL, also used by the native fallback.
    actionUrl = appendQueryParams (pathTo (DeleteRecipientGroupAction group.id)) (surfaceFieldsText fields)
    form = renderAppShellActionForm (appShellActionByMarker @Shell.DeleteRecipientGroup)
        ((defaultAppShellActionRoute actionUrl) { appShellActionRouteExtraAttrs = [("id", "recipient-group-delete-form")] })
        [hsx|<input type="hidden" name="_method" value="DELETE"/>|]
