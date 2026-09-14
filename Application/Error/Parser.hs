{-# LANGUAGE NoImplicitPrelude #-}

module Application.Error.Parser
    ( parserFailure
    ) where

import Data.Aeson.Types (Parser)
import Prelude (String, fail)

-- | The sole application-owned use of 'MonadFail.fail'. Its concrete result
-- type prevents parser rejection from becoming an IO/workflow failure.
parserFailure :: String -> Parser value
parserFailure = fail
