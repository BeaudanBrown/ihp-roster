module Application.Script.GenerateFrontendContractsGhc where

import Application.Helper.FrontendContract.Contracts (TypeScriptDeclaration (..),
                                                      TypeScriptDeclarationOrigin (..),
                                                      renderTypeScriptDeclarations)
import Application.Helper.FrontendContract.Registry (registeredFrontendContractIRForSurfaceContract)
import Application.Helper.FrontendContract.Surface.Ghc.Extract (inspectFrontendSurfaceRegistryRaw)
import Application.Helper.FrontendContract.Surface.Ghc.Lower (lowerRawRegistry)
import Application.Helper.FrontendContract.TypeScript (renderFrontendContractTypeScript)
import Application.Script.Prelude (Script)
import qualified Data.Text.IO as Text
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
        [libdir] -> frontendContractsTypeScriptFromGhc libdir >>= Text.putStr
        [libdir, outputPath] -> do
            contracts <- frontendContractsTypeScriptFromGhc libdir
            Directory.createDirectoryIfMissing True (takeDirectory outputPath)
            Text.writeFile outputPath contracts
        _ -> do
            putStrLn "usage: GenerateFrontendContractsGhc ghc-libdir [output-path]"
            exitFailure

frontendContractsTypeScriptFromGhc :: FilePath -> IO Text
frontendContractsTypeScriptFromGhc libdir = do
    buildDir <- fromMaybe "build/FrontendSurfaceGhcApi" <$> Environment.lookupEnv "FRONTEND_SURFACE_GHC_API_BUILD_DIR"
    rawResult <- inspectFrontendSurfaceRegistryRaw libdir buildDir
    rawRegistry <- case rawResult of
        Right rawRegistry -> pure rawRegistry
        Left message -> do
            putStrLn (cs ("GenerateFrontendContractsGhc: FrontendSurface GHC extraction failed: " <> message) :: Text)
            exitFailure
    contract <- case lowerRawRegistry rawRegistry of
        Right contract -> pure contract
        Left diagnostics -> do
            putStrLn "GenerateFrontendContractsGhc: FrontendSurface GHC lowering failed:"
            mapM_ (\diagnostic -> putStrLn (cs ("  " <> diagnostic) :: Text)) diagnostics
            exitFailure
    let source = either error id (renderFrontendContractTypeScript (registeredFrontendContractIRForSurfaceContract contract))
    pure (renderTypeScriptDeclarations
        [ TypeScriptDeclaration
            { name = "FrontendContractGlobals"
            , origin = HaskellSchemaGenerated
            , source = source
            }
        ])
