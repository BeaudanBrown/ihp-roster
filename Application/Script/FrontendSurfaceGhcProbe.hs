module Application.Script.FrontendSurfaceGhcProbe where

import Prelude

import Control.Monad.IO.Class (liftIO)
import qualified Data.List as List
import GHC
import GHC.Core.TyCon (synTyConRhs_maybe, tyConKind)
import GHC.Driver.Flags (GeneralFlag (Opt_ForceRecomp))
import GHC.Driver.Session (gopt_set, xopt_set)
import GHC.LanguageExtensions.Type (Extension (DataKinds, TypeFamilies, TypeOperators))
import GHC.Types.Name (nameOccName, nameSrcSpan)
import GHC.Types.Name.Occurrence (occNameString)
import GHC.Types.TyThing (TyThing (ATyCon))
import GHC.Utils.Outputable hiding ((<>))
import qualified System.Environment as Environment
import System.Exit (exitFailure)

registryModuleName :: String
registryModuleName = "Application.Helper.FrontendSurface.Registry"

registryModulePath :: String
registryModulePath = "Application/Helper/FrontendSurface/Registry.hs"

registryTypeName :: String
registryTypeName = "RegisteredFrontendSurfaces"

main :: IO ()
main = do
    args <- Environment.getArgs
    case args of
        [libdir] -> inspectRegistry libdir
        _ -> do
            putStrLn "usage: FrontendSurfaceGhcProbe <ghc-libdir>"
            exitFailure

inspectRegistry :: FilePath -> IO ()
inspectRegistry libdir =
    runGhc (Just libdir) do
        dflags <- getSessionDynFlags
        let registryDynFlags =
                gopt_set
                    ( foldl xopt_set dflags
                        [ DataKinds
                        , TypeFamilies
                        , TypeOperators
                        ]
                    )
                    Opt_ForceRecomp
        _ <- setSessionDynFlags registryDynFlags
        target <- guessTarget registryModulePath Nothing Nothing
        setTargets [target]
        _ <- load LoadAllTargets
        registryModule <- findModule (mkModuleName registryModuleName) Nothing
        maybeInfo <- getModuleInfo registryModule
        case maybeInfo >>= findRegistryExport of
            Nothing -> liftIO do
                putStrLn ("frontend-surface-ghc-probe: missing export " <> registryTypeName)
                exitFailure
            Just registryName -> do
                maybeThing <- lookupName registryName
                case maybeThing of
                    Just (ATyCon tyCon) -> liftIO do
                        putStrLn ("module: " <> registryModuleName)
                        putStrLn ("export: " <> registryTypeName)
                        putStrLn ("source: " <> renderSDoc (ppr (nameSrcSpan registryName)))
                        putStrLn ("kind: " <> renderSDoc (ppr (tyConKind tyCon)))
                        putStrLn ("rhs: " <> renderSDoc (ppr (synTyConRhs_maybe tyCon)))
                    Just otherThing -> liftIO do
                        putStrLn ("frontend-surface-ghc-probe: export is not a type constructor: " <> renderSDoc (ppr otherThing))
                        exitFailure
                    Nothing -> liftIO do
                        putStrLn ("frontend-surface-ghc-probe: lookupName failed for " <> registryTypeName)
                        exitFailure

findRegistryExport :: ModuleInfo -> Maybe Name
findRegistryExport info =
    List.find ((== registryTypeName) . occNameString . nameOccName) (modInfoExports info)

renderSDoc :: SDoc -> String
renderSDoc = showSDocUnsafe
