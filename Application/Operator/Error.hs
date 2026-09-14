module Application.Operator.Error
    ( ScriptError (..)
    , exitWithScriptError
    , renderScriptError
    , requireScriptResult
    , tryScriptIO
    ) where

import qualified Control.Exception as Exception
import qualified Data.Text.IO as TextIO
import IHP.Prelude
import System.Exit (exitFailure)
import System.IO (stderr)

-- | Closed operator/dev entrypoint failures. These remain CLI failures rather
-- than application-domain 'AppError's.
data ScriptError
    = InvalidScriptArgument !Text
    | InvalidScriptConfiguration !Text
    | ScriptOperationFailed !Text
    deriving (Eq, Show)

renderScriptError :: ScriptError -> Text
renderScriptError = \case
    InvalidScriptArgument message      -> "Invalid argument: " <> message
    InvalidScriptConfiguration message -> "Invalid configuration: " <> message
    ScriptOperationFailed message      -> "Operation failed: " <> message

exitWithScriptError :: ScriptError -> IO a
exitWithScriptError scriptError = do
    TextIO.hPutStrLn stderr (renderScriptError scriptError)
    exitFailure

requireScriptResult :: Either ScriptError value -> IO value
requireScriptResult = either exitWithScriptError pure

tryScriptIO :: Text -> IO value -> IO (Either ScriptError value)
tryScriptIO label action = do
    result <- Exception.try action
    pure case result of
        Left (_ :: Exception.IOException) -> Left (InvalidScriptConfiguration (label <> " failed"))
        Right value                       -> Right value
