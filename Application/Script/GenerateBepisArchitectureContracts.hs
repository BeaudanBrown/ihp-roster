module Application.Script.GenerateBepisArchitectureContracts where

import Application.Architecture.Contracts (architectureContractsJson)
import Application.Script.Prelude (Script)
import qualified Data.ByteString.Lazy as LBS
import IHP.Prelude
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
        [] -> LBS.putStr architectureContractsJson
        [outputPath] -> do
            Directory.createDirectoryIfMissing True (takeDirectory outputPath)
            LBS.writeFile outputPath architectureContractsJson
        _ -> do
            putStrLn "usage: GenerateBepisArchitectureContracts [output-path]" :: IO ()
            exitFailure
