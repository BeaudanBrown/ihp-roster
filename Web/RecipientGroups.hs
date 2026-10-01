{-# OPTIONS_GHC -Werror=incomplete-patterns #-}

module Web.RecipientGroups
    ( openRecipientGroup
    , saveRecipientGroupFromRequest
    , confirmRecipientGroupDeletion
    , deleteRecipientGroupFromRequest
    , saveRecipientGroupMutation
    , deleteRecipientGroupMutation
    ) where

import Application.RecipientGroups
import Application.RecipientGroups.Validation (validateRecipientAddresses)
import qualified Application.Helper.FrontendContract.AppShell as Shell
import Application.Helper.FrontendContract.AppShell.Request (parseAppShellActionParams)
import Application.Helper.FrontendContract.Surface.Admin.Live (adminRecipientGroupsLiveScope)
import Application.Helper.FrontendContract.Surface.Admin.Resource (adminRecipientGroupsResource)
import Application.Helper.FrontendContract.Surface.Request (surfaceRequestFieldErrorsMessage)
import Application.Helper.FrontendContract.Surface.Values (surfaceFieldValue)
import Application.Helper.LiveUpdate (setActorLiveResourcesRefresh)
import Application.Helper.SurfaceResource
import Application.Helper.Url (appendQueryParams)
import Application.Helper.View (ToastOverlayPosition (ToastBottomCenter), renderDialogOverlayClearOob, renderToastOob, successToast)
import qualified Data.Set as Set
import qualified Data.Text as Text
import Web.Admin.FrontendSurface (adminRecipientGroupsFragment)
import Web.Controller.Prelude
import Web.SurfaceInvalidation (withDurableLiveMutationOutcome)
import Web.View.Admin.RecipientGroups

openRecipientGroup :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) => Maybe (Id RecipientGroup) -> IO ResponseReceived
openRecipientGroup Nothing = respondEditor (recipientGroupDraft Nothing) Nothing
openRecipientGroup (Just groupId) = fetchRecipientGroup groupId >>= \case
    Left failure -> respondEditor (recipientGroupDraft Nothing) (Just (groupError failure))
    Right group -> respondEditor (recipientGroupDraft (Just group)) Nothing

saveRecipientGroupFromRequest :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) => IO ResponseReceived
saveRecipientGroupFromRequest = do
    ensureVenueWritable
    case parseAppShellActionParams @Shell.SaveRecipientGroup of
        Left errors -> respondEditor (recipientGroupDraft Nothing) (Just (surfaceRequestFieldErrorsMessage errors))
        Right fields -> do
            let draft = RecipientGroupDraft
                    { groupId = surfaceFieldValue @Shell.RecipientGroupIdField fields
                    , nameText = surfaceFieldValue @Shell.RecipientGroupNameField fields
                    , addressesText = surfaceFieldValue @Shell.RecipientGroupAddressesField fields
                    , entryText = fromMaybe "" (surfaceFieldValue @Shell.RecipientGroupEntryField fields)
                    , revision = surfaceFieldValue @Shell.RecipientGroupRevisionField fields
                    }
            let addresses = filter (not . Text.null) (map Text.strip (Text.lines draft.addressesText))
            let adding = fromMaybe False (surfaceFieldValue @Shell.RecipientGroupAddField fields)
            -- Draft edits never write a group. Remove must remain usable while
            -- the separate entry field has an invalid, not-yet-added address.
            case surfaceFieldValue @Shell.RecipientGroupRemoveField fields of
                Just address -> respondEditor (draft { addressesText = Text.intercalate "\n" (filter (/= address) addresses) }) Nothing
                Nothing -> do
                    let pending = Text.strip draft.entryText
                    case validateRecipientAddresses (addresses <> [pending | adding || not (Text.null pending)]) of
                        Left message -> respondEditor draft (Just message)
                        Right recipients -> do
                            let normalized = draft { addressesText = Text.intercalate "\n" recipients, entryText = "" }
                            if adding then respondEditor normalized Nothing else do
                                outcome <- saveRecipientGroupMutation (Id <$> draft.groupId) RecipientGroupInput
                                    { name = draft.nameText, recipients, expectedRevision = draft.revision }
                                case outcome of
                                    Left failure -> respondEditor normalized (Just (groupError failure))
                                    Right result -> respondCommitted "Recipient group saved." result

confirmRecipientGroupDeletion :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) => Id RecipientGroup -> Maybe Text -> IO ResponseReceived
confirmRecipientGroupDeletion groupId message = fetchRecipientGroup groupId >>= \case
    Left failure -> respondEditor (recipientGroupDraft Nothing) (Just (groupError failure))
    Right group -> do
        linked <- query @PayrollReportSetting |> filterWhere (#venueId, unpackId currentVenueId)
            |> filterWhere (#recipientGroupId, Just (unpackId groupId)) |> fetchExists
        if isHtmxRequest then respondHtml (renderRecipientGroupDeleteConfirmation group linked message)
        else redirectToPath groupsPath

deleteRecipientGroupFromRequest :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) => Id RecipientGroup -> IO ResponseReceived
deleteRecipientGroupFromRequest groupId = do
    ensureVenueWritable
    case parseAppShellActionParams @Shell.DeleteRecipientGroup of
        Left errors -> confirmRecipientGroupDeletion groupId (Just (surfaceRequestFieldErrorsMessage errors))
        Right fields -> do
            outcome <- deleteRecipientGroupMutation groupId
                (surfaceFieldValue @Shell.RecipientGroupRevisionField fields)
                (fromMaybe False (surfaceFieldValue @Shell.RecipientGroupDisableScheduleField fields))
            case outcome of
                Left failure -> confirmRecipientGroupDeletion groupId (Just (groupError failure))
                Right result -> respondCommitted "Recipient group deleted." result

saveRecipientGroupMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Maybe (Id RecipientGroup) -> RecipientGroupInput -> IO (Either RecipientGroupError (LiveMutationResult RecipientGroup))
saveRecipientGroupMutation groupId input = do
    outcome <- withDurableLiveMutationOutcome (publicationFor "recipient_group.save")
        (saveRecipientGroupInCurrentTransaction groupId input)
    pure (fmap (\group -> liveMutationResult group [adminRecipientGroupsResource (unpackId currentVenueId)]) outcome)

deleteRecipientGroupMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RecipientGroup -> Int -> Bool -> IO (Either RecipientGroupError (LiveMutationResult ()))
deleteRecipientGroupMutation groupId revision confirmDisable = do
    outcome <- withDurableLiveMutationOutcome (publicationFor "recipient_group.delete")
        (deleteRecipientGroupInCurrentTransaction groupId revision confirmDisable)
    pure (fmap (\() -> liveMutationResult () [adminRecipientGroupsResource (unpackId currentVenueId)]) outcome)

publicationFor :: (?context :: ControllerContext) => Text -> Either failure value -> Maybe (Text, Set.Set SurfaceResourceValue)
publicationFor label = \case
    Left _ -> Nothing
    Right _ -> Just (label, Set.singleton (adminRecipientGroupsResource (unpackId currentVenueId)))

respondEditor :: (?context :: ControllerContext, ?request :: Request, ?respond :: Respond) => RecipientGroupDraft -> Maybe Text -> IO ResponseReceived
respondEditor draft message
    | isHtmxRequest = respondHtml (renderRecipientGroupDialog draft message)
    | otherwise = do
        mapM_ setErrorMessage message
        redirectToPath groupsPath

respondCommitted :: (?context :: ControllerContext, ?request :: Request, ?respond :: Respond) => Text -> LiveMutationResult value -> IO ResponseReceived
respondCommitted message result
    | isHtmxRequest = do
        setHeader ("HX-Reswap", "none")
        setActorLiveResourcesRefresh (adminRecipientGroupsLiveScope (unpackId currentVenueId))
            result.liveMutationTouchedResources [adminRecipientGroupsFragment]
        respondHtml (renderDialogOverlayClearOob <> renderToastOob ToastBottomCenter (successToast message))
    | otherwise = setSuccessMessage message >> redirectToPath groupsPath

groupsPath :: Text
groupsPath = appendQueryParams (pathTo AdminAction) [("showRecipientGroups", "true")] <> "#recipient-groups"

groupError :: RecipientGroupError -> Text
groupError = \case
    RecipientGroupAccessDenied -> "Recipient group access denied."
    RecipientGroupInvalid message -> message
    RecipientGroupNotFound -> "That recipient group is no longer available."
    RecipientGroupStale -> "This group changed while the dialog was open. Close and reopen it to review the current recipients."
    RecipientGroupNameConflict -> "A recipient group with that name already exists."
    RecipientGroupScheduleConfirmationRequired -> "This group is now selected for scheduled reports. Review the confirmation to disable that schedule too."
