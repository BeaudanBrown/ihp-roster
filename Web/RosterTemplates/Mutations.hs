module Web.RosterTemplates.Mutations
    ( saveRosterTemplateDraftAsNewMutation
    , saveRosterTemplateDraftMutation
    , softDeleteRosterTemplateMutation
    ) where

import Application.Helper.FrontendContract.Surface.Roster.Resource
import Application.Helper.SurfaceResource (LiveMutationResult (..),
                                           liveMutationResult)
import Application.RosterTemplates
import Web.Controller.Prelude
import Web.SurfaceInvalidation (withDurableLiveMutationOutcome)

saveRosterTemplateDraftMutation ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    RosterTemplateActor ->
    Id RosterTemplateDesign ->
    IO (Either RosterTemplateError RosterTemplateSave)
saveRosterTemplateDraftMutation actor designId =
    fmap (fmap (.liveMutationValue)) $
        withDurableLiveMutationOutcome publicationFor do
            fmap (fmap mutationResult) (saveRosterTemplateDraftInCurrentTransaction actor designId)
  where
    mutationResult result =
        liveMutationResult result
            [ rosterTemplateLibraryResource result.savedTemplate.rosterGroupId
            , rosterTemplateResource (unpackId result.savedTemplate.id)
            , rosterTemplateDraftResource (unpackId (rosterTemplateActorUserId actor))
            ]
    publicationFor = either (const Nothing) (\result -> Just ("roster.template.save", result.liveMutationTouchedResources))

saveRosterTemplateDraftAsNewMutation ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    RosterTemplateActor ->
    Id RosterTemplateDesign ->
    Text ->
    IO (Either RosterTemplateError RosterTemplateSave)
saveRosterTemplateDraftAsNewMutation actor designId requestedName =
    fmap (fmap (.liveMutationValue)) $
        withDurableLiveMutationOutcome publicationFor do
            fmap (fmap mutationResult) (saveRosterTemplateDraftAsNewInCurrentTransaction actor designId requestedName)
  where
    mutationResult result =
        liveMutationResult result
            [ rosterTemplateLibraryResource result.savedTemplate.rosterGroupId
            , rosterTemplateResource (unpackId result.savedTemplate.id)
            , rosterTemplateDraftResource (unpackId (rosterTemplateActorUserId actor))
            ]
    publicationFor = either (const Nothing) (\result -> Just ("roster.template.save_as_new", result.liveMutationTouchedResources))

softDeleteRosterTemplateMutation ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    RosterTemplateActor ->
    Id RosterTemplate ->
    Text ->
    IO (Either RosterTemplateError ())
softDeleteRosterTemplateMutation actor templateId reason = do
    outcome <- withDurableLiveMutationOutcome publicationFor do
        maybeSaved <- fetchSavedRosterTemplate actor templateId
        deleted <- softDeleteRosterTemplate actor templateId reason
        pure $
            case (deleted, maybeSaved) of
                (Right (), Just saved) ->
                    Right $
                        Just $
                            liveMutationResult ()
                                [ rosterTemplateLibraryResource saved.savedTemplate.rosterGroupId
                                , rosterTemplateResource (unpackId saved.savedTemplate.id)
                                ]
                (Left failure, _) -> Left failure
                (Right (), Nothing) -> Right Nothing
    pure (fmap (maybe () (.liveMutationValue)) outcome)
  where
    publicationFor = either (const Nothing) (fmap (\result -> ("roster.template.delete", result.liveMutationTouchedResources)))
