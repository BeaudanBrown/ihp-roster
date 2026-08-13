module Web.RosterTemplates.Mutations where

import Application.Helper.FrontendContract.Surface.Roster.Resource (rosterTemplateLibraryResource,
                                                                      rosterTemplateResource)
import Application.Helper.SurfaceResource (LiveMutationResult (..),
                                           liveMutationResult)
import Application.RosterTemplates
import Web.Controller.Prelude
import Web.SurfaceInvalidation (withDurableLiveMutationOutcome)

softDeleteRosterTemplateMutation ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    RosterTemplateActor ->
    Id RosterTemplate ->
    Text ->
    IO (Either RosterTemplateError ())
softDeleteRosterTemplateMutation actor templateId reason = do
    outcome <- withDurableLiveMutationOutcome publicationFor do
        maybeSaved <- fetchRosterTemplate actor templateId
        deleted <- softDeleteRosterTemplateInCurrentTransaction actor templateId reason
        pure $
            case (deleted, maybeSaved) of
                (Right (), Just saved) ->
                    Right $
                        Just $
                            liveMutationResult ()
                                [ rosterTemplateLibraryResource saved.snapshotTemplate.rosterGroupId
                                , rosterTemplateResource (unpackId saved.snapshotTemplate.id)
                                ]
                (Left failure, _) -> Left failure
                (Right (), Nothing) -> Right Nothing
    pure (fmap (maybe () (.liveMutationValue)) outcome)
  where
    publicationFor = either (const Nothing) (fmap (\result -> ("roster.template.delete", result.liveMutationTouchedResources)))
