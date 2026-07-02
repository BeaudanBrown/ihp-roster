module Application.Script.GenerateFrontendContractsGhc where

import Application.Helper.Frontend.Contracts (frontendContractsTypeScriptWithFrontendSurface)
import Application.Helper.FrontendSurface.Contracts (frontendSurfaceContractDeclarationFor)
import Application.Helper.FrontendSurface.Ghc.Extract (inspectFrontendSurfaceRegistryRaw)
import Application.Helper.FrontendSurface.Ghc.Lower (lowerRawRegistry)
import qualified Data.Text.IO as Text
import IHP.Prelude
import qualified System.Directory as Directory
import qualified System.Environment as Environment
import System.Exit (exitFailure)
import System.FilePath (takeDirectory)

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
    rawResult <- inspectFrontendSurfaceRegistryRaw libdir
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
    pure (frontendContractsTypeScriptWithFrontendSurface (frontendSurfaceContractDeclarationFor contract))
