module Web.RosterTemplates.Mutations
    ( saveRosterTemplateDraftAsNewMutation
    , saveRosterTemplateDraftMutation
    , softDeleteRosterTemplateMutation
    ) where

import Application.Helper.FrontendContract.Surface.Roster.Resource
import Application.Helper.SurfaceResource (LiveMutationResult (..), liveMutationResult)
import Application.RosterTemplates
import Data.Traversable (traverse)
import Web.Controller.Prelude
import Web.SurfaceInvalidation (invalidateTouchedResources)

saveRosterTemplateDraftMutation ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    RosterTemplateActor ->
    Id RosterTemplateDesign ->
    IO (Either RosterTemplateError RosterTemplateSave)
saveRosterTemplateDraftMutation actor designId = do
    saved <- saveRosterTemplateDraft actor designId
    traverse invalidateSave saved
  where
    invalidateSave result = do
        invalidated <- invalidateTouchedResources "roster.template.save" $
            liveMutationResult result
                [ rosterTemplateLibraryResource result.savedTemplate.rosterGroupId
                , rosterTemplateResource (unpackId result.savedTemplate.id)
                , rosterTemplateDraftResource (unpackId (rosterTemplateActorUserId actor))
                ]
        pure invalidated.liveMutationValue

saveRosterTemplateDraftAsNewMutation ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    RosterTemplateActor ->
    Id RosterTemplateDesign ->
    Text ->
    IO (Either RosterTemplateError RosterTemplateSave)
saveRosterTemplateDraftAsNewMutation actor designId requestedName = do
    saved <- saveRosterTemplateDraftAsNew actor designId requestedName
    traverse invalidateSave saved
  where
    invalidateSave result = do
        invalidated <- invalidateTouchedResources "roster.template.save_as_new" $
            liveMutationResult result
                [ rosterTemplateLibraryResource result.savedTemplate.rosterGroupId
                , rosterTemplateResource (unpackId result.savedTemplate.id)
                , rosterTemplateDraftResource (unpackId (rosterTemplateActorUserId actor))
                ]
        pure invalidated.liveMutationValue

softDeleteRosterTemplateMutation ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    RosterTemplateActor ->
    Id RosterTemplate ->
    Text ->
    IO (Either RosterTemplateError ())
softDeleteRosterTemplateMutation actor templateId reason = do
    maybeSaved <- fetchSavedRosterTemplate actor templateId
    deleted <- softDeleteRosterTemplate actor templateId reason
    case (deleted, maybeSaved) of
        (Right (), Just saved) -> do
            invalidated <- invalidateTouchedResources "roster.template.delete" $
                liveMutationResult ()
                    [ rosterTemplateLibraryResource saved.savedTemplate.rosterGroupId
                    , rosterTemplateResource (unpackId saved.savedTemplate.id)
                    ]
            pure (Right invalidated.liveMutationValue)
        (Left failure, _) -> pure (Left failure)
        (Right (), Nothing) -> pure (Right ())
