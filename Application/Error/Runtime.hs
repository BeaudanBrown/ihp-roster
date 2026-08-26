{-# LANGUAGE NoImplicitPrelude          #-}

module Application.Error.Runtime
    ( ExternalRuntimeCategory (..)
    , externalRuntimeExceptionCategory
    , externalRuntimeInvariantFailure
    , throwExternalRuntime
    , throwExternalRuntimeMessage
    ) where

import qualified Control.Exception as Exception
import Data.Text (Text)
import qualified Data.Text as Text
import Prelude (IO, Maybe, Show (..), String)
import qualified Prelude

-- | Closed reasons that may reach the final synchronous runtime boundary.
-- Recoverable or distinguishable operation failures must use AppResult instead.
data ExternalRuntimeCategory
    = PersistedRuntimeInvariant
    | ProviderRuntimeInvariant
    | AuthorizedFrameworkInvariant
    | JobProvenanceInvariant
    | CheckedConfigurationInvariant
    deriving (Prelude.Eq, Prelude.Show)

-- Dynamic-message and pure invariant failures retain their closed category,
-- while Show deliberately excludes technical payload text.
data ExternalRuntimeBoundaryException
    = ExternalRuntimeBoundaryMessage !ExternalRuntimeCategory !Text

instance Show ExternalRuntimeBoundaryException where
    show _ = "Bepis external runtime boundary failed"

instance Exception.Exception ExternalRuntimeBoundaryException

externalRuntimeExceptionCategory :: Exception.SomeException -> Maybe ExternalRuntimeCategory
externalRuntimeExceptionCategory exception =
    externalRuntimeCategory Prelude.<$> Exception.fromException exception
  where
    externalRuntimeCategory (ExternalRuntimeBoundaryMessage category _) = category

externalRuntimeInvariantFailure :: ExternalRuntimeCategory -> String -> value
externalRuntimeInvariantFailure category message =
    Exception.throw (ExternalRuntimeBoundaryMessage category (Text.pack message))

-- Typed external exceptions retain their own closed constructor identity so
-- existing provider/transaction classifiers can catch them without unwrapping.
throwExternalRuntime :: Exception.Exception exception => exception -> IO value
throwExternalRuntime = Exception.throwIO

throwExternalRuntimeMessage :: ExternalRuntimeCategory -> Text -> IO value
throwExternalRuntimeMessage category message = Exception.throwIO (ExternalRuntimeBoundaryMessage category message)
