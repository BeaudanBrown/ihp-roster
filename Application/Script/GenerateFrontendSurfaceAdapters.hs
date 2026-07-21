module Application.Script.GenerateFrontendSurfaceAdapters where

import Application.Helper.FrontendContract.Surface.ContractIR (ContractDiagnostic (..),
                                                               SurfaceContractIR)
import Application.Helper.FrontendContract.Surface.Contracts (registeredFrontendSurfaceContractIR)
import Application.Helper.FrontendContract.Surface.HaskellAdapter.Family (SurfaceAdapterRegistry)
import Application.Helper.FrontendContract.Surface.HaskellAdapter.Generator
import Application.Helper.FrontendContract.Surface.HaskellAdapter.Registry (registeredSurfaceAdapterRegistry)
import qualified Data.Text as Text
import qualified Data.Text.IO as Text
import IHP.Prelude
import IHP.ScriptSupport (Script)
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
writeGeneratedModules outputRoot = do
    publication <-
        stageGeneratedModules
            outputRoot
            registeredFrontendSurfaceContractIR
            registeredSurfaceAdapterRegistry
    case publication of
        Left diagnostics -> do
            forM_ diagnostics \diagnostic ->
                Text.hPutStrLn stderr
                    ( diagnostic.diagnosticCode <> ": "
                        <> diagnostic.diagnosticMessage
                    )
            exitFailure
        Right () -> pure ()

-- | Publication barrier for the complete all-kind managed set. A focused-lane
-- failure is returned before the output directory is created or any existing
-- file is touched. The shell publisher formats and validates this full staged
-- tree before changing managed repository files.
stageGeneratedModules ::
    FilePath ->
    SurfaceContractIR ->
    SurfaceAdapterRegistry ->
    IO (Either [ContractDiagnostic] ())
stageGeneratedModules outputRoot contract registry =
    case generateSurfaceAdapterModules contract registry of
        Left diagnostics -> pure (Left diagnostics)
        Right generatedModules -> do
            Directory.createDirectoryIfMissing True outputRoot
            forM_ generatedModules \generated -> do
                let outputPath = outputRoot </> generated.generatedModulePath
                Directory.createDirectoryIfMissing True (takeDirectory outputPath)
                Text.writeFile outputPath generated.generatedModuleSource
            pure (Right ())
