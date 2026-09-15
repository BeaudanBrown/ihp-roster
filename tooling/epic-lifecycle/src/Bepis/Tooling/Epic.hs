module Bepis.Tooling.Epic (runEpicCommand) where

import Bepis.Tooling.Epic.Manage (manage)
import Bepis.Tooling.Epic.Orientation (EpicError (..), orient)
import Control.Exception (catch)
import System.Environment (getArgs)
import System.Exit (ExitCode (..), exitWith)
import System.IO (hPutStrLn, stderr)

runEpicCommand :: IO ()
runEpicCommand = dispatch `catch` handleError
  where
    handleError (EpicError status message) = hPutStrLn stderr ("bepis-epic-lifecycle: " <> message) >> exitWith (ExitFailure status)

dispatch :: IO ()
dispatch = do
    arguments <- getArgs
    case arguments of
        ["orient"] -> orient False
        ["orient", "--json"] -> orient True
        ["orient", help] | help `elem` ["-h", "--help"] -> putStrLn "Usage: bepis-epic-lifecycle orient [--json]"
        "manage":rest -> manage rest
        _ -> hPutStrLn stderr "Usage: bepis-epic-lifecycle orient [--json]" >> exitWith (ExitFailure 64)
