module Application.Script.GenerateFrontendSurfaceAdapters where

import Application.Helper.FrontendContract.Surface.ContractIR (ContractDiagnostic (..))
import Application.Helper.FrontendContract.Surface.Contracts (registeredFrontendSurfaceContractIR)
import Application.Helper.FrontendContract.Surface.HaskellAdapter.Generator
import Application.Helper.FrontendContract.Surface.HaskellAdapter.Registry (registeredSurfaceAdapterRegistry)
import Application.Script.Prelude (Script)
import qualified Data.Text as Text
import qualified Data.Text.IO as Text
import IHP.Prelude
import qualified System.Directory as Directory
import qualified System.Environment as Environment
import System.Exit (exitFailure)
import System.FilePath (takeDirectory, (</>))
import System.IO (stderr)

run :: Script
run = liftIO main

main :: IO ()
main = do
    args <- Environment.getArgs
    case args of
        [outputRoot] -> writeGeneratedModules outputRoot
        _ -> do
            putStrLn "usage: GenerateFrontendSurfaceAdapters <output-root>" :: IO ()
            exitFailure

writeGeneratedModules :: FilePath -> IO ()
writeGeneratedModules outputRoot =
    case generateSurfaceAdapterModules registeredFrontendSurfaceContractIR registeredSurfaceAdapterRegistry of
        Left diagnostics -> do
            forM_ diagnostics \diagnostic ->
                Text.hPutStrLn stderr
                    ( diagnostic.diagnosticCode <> ": "
                        <> diagnostic.diagnosticMessage
                    )
            exitFailure
        Right generatedModules -> do
            Directory.createDirectoryIfMissing True outputRoot
            forM_ generatedModules \generated -> do
                let outputPath = outputRoot </> generated.generatedModulePath
                Directory.createDirectoryIfMissing True (takeDirectory outputPath)
                Text.writeFile outputPath generated.generatedModuleSource
