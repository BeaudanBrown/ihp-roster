module Web.RosterTemplates.Mutations where

import Application.Helper.FrontendContract.Surface.Roster.Resource (rosterTemplateLibraryResource)
import Application.Helper.SurfaceResource (LiveMutationResult (..),
                                           liveMutationResult)
import Application.RosterTemplates
import Web.Controller.Prelude
import Web.SurfaceInvalidation (withDurableLiveMutationOutcome)

softDeleteRosterTemplateMutation ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    RosterTemplateActor ->
    Id RosterTemplate ->
    Id RosterGroup ->
    Text ->
    IO (Either RosterTemplateError (LiveMutationResult ()))
softDeleteRosterTemplateMutation actor templateId expectedRosterGroupId reason = do
    outcome <- withDurableLiveMutationOutcome publicationFor do
        maybeSaved <- fetchRosterTemplate actor templateId
        deleted <- case maybeSaved of
            Just saved | saved.snapshotTemplate.rosterGroupId == unpackId expectedRosterGroupId ->
                softDeleteRosterTemplateInCurrentTransaction actor templateId reason
            Just _ -> pure (Left RosterTemplateScopeMismatch)
            Nothing -> pure (Left RosterTemplateNotFound)
        pure $
            case (deleted, maybeSaved) of
                (Right (), Just saved) ->
                    Right $
                        Just $
                            liveMutationResult ()
                                [rosterTemplateLibraryResource saved.snapshotTemplate.rosterGroupId]
                (Left failure, _) -> Left failure
                (Right (), Nothing) -> Right Nothing
    pure (outcome >>= maybe (Left RosterTemplateNotFound) Right)
  where
    publicationFor = either (const Nothing) (fmap (\result -> ("roster.template.delete", result.liveMutationTouchedResources)))
