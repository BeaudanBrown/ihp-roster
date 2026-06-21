module Main where

import Application.Helper.Frontend.Contracts (frontendContractsTypeScript)
import IHP.Prelude
import qualified Data.Text.IO as Text
import qualified System.Directory as Directory
import qualified System.Environment as Environment
import System.Exit (exitFailure)
import System.FilePath (takeDirectory)

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
