{-# LANGUAGE RankNTypes #-}
module Application.Daysheet.Designer.Mutations (edit, editReferences, publish) where

import qualified Application.Daysheet.Designer as Designer
import qualified Application.Daysheet.Storage as Storage
import Application.Daysheet.References (ReferenceEdit)
import Application.Error.Types (AppResult)
import Application.Helper.FrontendContract.Surface.DaysheetDesigner.Resource
import Application.Helper.SurfaceResource
import Generated.Types
import IHP.ControllerPrelude
import Web.SurfaceInvalidation (withDurableLiveMutationOutcome)

type MutationContext = (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request)

mutate :: MutationContext => VenueMembership -> Text -> ((?modelContext :: ModelContext) => IO (AppResult a)) -> IO (LiveMutationResult (AppResult a))
mutate member label action = withDurableLiveMutationOutcome publication do
    result <- action
    pure (liveMutationResult result (case result of
        Left _ -> []
        Right _ -> [designerConfigurationResource member.venueId]))
  where
    publication result = case result.liveMutationValue of
        Left _ -> Nothing
        Right _ -> Just (label, result.liveMutationTouchedResources)

edit :: MutationContext => VenueMembership -> Integer -> Maybe Integer -> Designer.Edit -> IO (LiveMutationResult (AppResult DaysheetDefinitionDraft))
edit member base revision change = mutate member "daysheet.designer.edit" (Storage.editDraft member base revision change)

editReferences :: MutationContext => VenueMembership -> Integer -> Maybe Integer -> ReferenceEdit -> IO (LiveMutationResult (AppResult DaysheetDefinitionDraft))
editReferences member base revision change = mutate member "daysheet.designer.edit-references" (Storage.editDraftReferences member base revision change)

publish :: MutationContext => VenueMembership -> Integer -> Integer -> IO (LiveMutationResult (AppResult DaysheetDefinitionVersion))
publish member base revision = mutate member "daysheet.designer.publish" (Storage.publishDraft member base revision)
