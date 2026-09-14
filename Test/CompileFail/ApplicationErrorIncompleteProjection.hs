{-# OPTIONS_GHC -Werror=incomplete-patterns #-}
{-# LANGUAGE DeriveGeneric #-}

module Test.CompileFail.ApplicationErrorIncompleteProjection where

import Application.Error.Domain
import Application.Error.Types
import GHC.Generics (Generic)
import IHP.Prelude

data AddedDomainError
    = ExistingFailure
    | NewlyAddedFailure
    deriving (Generic)

-- Adding the second constructor must fail until all safe fields are projected.
instance DomainError AddedDomainError where
    appErrorProjection ExistingFailure = AppErrorProjection
        { safeMessage = "Safe fixture message"
        , severity = Blocking
        , recovery = UserFixRequired
        , retryDirective = DoNotRetry
        }
