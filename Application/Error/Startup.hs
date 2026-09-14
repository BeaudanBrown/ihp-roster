{-# LANGUAGE NoImplicitPrelude #-}

module Application.Error.Startup
    ( startupInvariantFailure
    , throwStartupException
    ) where

import qualified Control.Exception as Exception
import qualified Prelude

-- | Final pure boundary for deterministic application construction diagnostics.
-- Callers must force these values before listeners start; request/workflow code
-- must return a typed outcome instead.
startupInvariantFailure :: Prelude.String -> value
startupInvariantFailure message = Prelude.error ("Bepis startup invariant failed: " Prelude.<> message)

throwStartupException :: Exception.Exception exception => exception -> value
throwStartupException = Exception.throw
