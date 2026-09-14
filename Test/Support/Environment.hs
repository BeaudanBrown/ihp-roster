module Test.Support.Environment
    ( withEnvironmentVariable
    , withEnvironmentVariables
    ) where

import Control.Exception (bracket)
import IHP.Prelude
import System.Environment (lookupEnv, setEnv, unsetEnv)

withEnvironmentVariable :: String -> Maybe String -> IO value -> IO value
withEnvironmentVariable name value action =
    bracket (lookupEnv name <* apply value) apply (const action)
  where
    apply Nothing        = unsetEnv name
    apply (Just current) = setEnv name current

withEnvironmentVariables :: [(String, Maybe String)] -> IO value -> IO value
withEnvironmentVariables variables action = foldr (uncurry withEnvironmentVariable) action variables
