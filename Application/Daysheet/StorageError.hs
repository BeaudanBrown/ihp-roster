{-# LANGUAGE DeriveGeneric #-}
module Application.Daysheet.StorageError (StorageError (..)) where

import Application.Error.Domain
import GHC.Generics (Generic)
import Prelude

data StorageError
    = AccessDenied | RevisionConflict | MissingDraft | NotPublished
    | InvalidDefinitionDocument | InvalidReferenceDocument | StoredDocumentInvalid
    | ReferenceRemovalRequiresRetirement | RevisionLimit
    deriving (Eq, Show, Generic)

instance DomainError StorageError where
    appErrorProjection AccessDenied = actionRequiredErrorProjection "You do not have permission for this Daysheet action."
    appErrorProjection RevisionConflict = actionRequiredErrorProjection "This configuration changed. Reload and review your changes before saving."
    appErrorProjection MissingDraft = actionRequiredErrorProjection "There is no saved Daysheet definition draft."
    appErrorProjection NotPublished = actionRequiredErrorProjection "Publish a Daysheet definition before creating a Daysheet."
    appErrorProjection InvalidDefinitionDocument = actionRequiredErrorProjection "The Daysheet definition has invalid fields, calculations or layouts."
    appErrorProjection InvalidReferenceDocument = actionRequiredErrorProjection "Correct the reference data before publishing or capturing this Daysheet."
    appErrorProjection StoredDocumentInvalid = terminalErrorProjection "The saved Daysheet configuration could not be read. Contact support."
    appErrorProjection ReferenceRemovalRequiresRetirement = actionRequiredErrorProjection "Retire existing reference records rather than removing or restoring their identities."
    appErrorProjection RevisionLimit = terminalErrorProjection "The Daysheet configuration revision limit has been reached. Contact support."
