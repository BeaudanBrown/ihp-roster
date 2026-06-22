module Application.Script.GenerateFrontendContracts where

import Application.Helper.Frontend.Contracts (frontendContractsTypeScript)
import Application.Script.Prelude (Script)
import IHP.Prelude
import qualified Data.Text.IO as Text
import qualified System.Directory as Directory
import qualified System.Environment as Environment
import System.Exit (exitFailure)
import System.FilePath (takeDirectory)

run :: Script
run = liftIO main

main :: IO ()
main = do
    args <- Environment.getArgs
    case args of
        [] -> Text.putStr frontendContractsTypeScript
        [outputPath] -> do
            Directory.createDirectoryIfMissing True (takeDirectory outputPath)
            Text.writeFile outputPath frontendContractsTypeScript
        _ -> do
            putStrLn "usage: GenerateFrontendContracts [output-path]" :: IO ()
            exitFailure
