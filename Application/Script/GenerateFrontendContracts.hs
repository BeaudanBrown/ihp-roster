module Application.Script.GenerateFrontendContracts where

import Application.Helper.FrontendContract.Contracts (renderRegisteredFrontendContracts)
import qualified Data.Text.IO as Text
import IHP.Prelude
import IHP.ScriptSupport (Script)
import qualified System.Directory as Directory
import qualified System.Environment as Environment
import System.Exit (exitFailure)
import System.FilePath (takeDirectory)
import qualified System.IO

run :: Script
run = liftIO main

main :: IO ()
main = do
    args <- Environment.getArgs
    case args of
        [] -> renderContracts Text.putStr
        [outputPath] ->
            renderContracts \source -> do
                Directory.createDirectoryIfMissing True (takeDirectory outputPath)
                Text.writeFile outputPath source
        _ -> do
            Text.hPutStrLn System.IO.stderr "usage: GenerateFrontendContracts [output-path]"
            exitFailure
  where
    renderContracts consume =
        case renderRegisteredFrontendContracts of
            Right source -> consume source
            Left diagnostics -> do
                Text.hPutStrLn System.IO.stderr "Invalid FrontendContract registry:"
                Text.hPutStr System.IO.stderr diagnostics
                exitFailure
