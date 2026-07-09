module Application.Script.FrontendSurfaceGhcProbe where

import qualified Application.Helper.FrontendContract.Surface.ContractIR as IR
import Application.Helper.FrontendContract.Surface.Ghc.Extract (inspectFrontendSurfaceRegistryRaw)
import Application.Helper.FrontendContract.Surface.Ghc.Lower (lowerRawRegistry)
import Application.Helper.FrontendContract.Surface.Ghc.Raw hiding
                                                           (rawRegistryToJson)
import qualified Application.Helper.FrontendContract.Surface.Ghc.Raw as Raw
import Application.Script.Prelude (Script)
import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Lazy.Char8 as LBS
import qualified Data.List as List
import qualified Data.Text as Text
import IHP.Prelude
import qualified System.Environment as Environment
import System.Exit (exitFailure)

run :: Script
run = liftIO main

data OutputMode
    = HumanOutput
    | JsonOutput
    deriving (Eq, Show)

main :: IO ()
main = do
    args <- Environment.getArgs
    case parseArgs args of
        Just (mode, libdir) -> inspectRegistry mode libdir
        Nothing -> do
            putStrLn "usage: FrontendSurfaceGhcProbe [--json] <ghc-libdir>"
            exitFailure

parseArgs :: [String] -> Maybe (OutputMode, FilePath)
parseArgs = \case
    [libdir] -> Just (HumanOutput, libdir)
    ["--json", libdir] -> Just (JsonOutput, libdir)
    _ -> Nothing

inspectRegistry :: OutputMode -> FilePath -> IO ()
inspectRegistry mode libdir = do
    result <- inspectFrontendSurfaceRegistryRaw libdir
    case result of
        Left message -> do
            putStrLn ("frontend-surface-ghc-probe: " <> message)
            exitFailure
        Right rawRegistry -> renderRawRegistry mode rawRegistry

renderRawRegistry :: OutputMode -> RawRegistry -> IO ()
renderRawRegistry mode rawRegistry =
    case mode of
        JsonOutput -> LBS.putStrLn (Aeson.encode (rawRegistryToJson rawRegistry))
        HumanOutput -> do
            putStrLn ("module: " <> rawRegistry.rawRegistryModule)
            putStrLn ("export: " <> rawRegistry.rawRegistryExport)
            putStrLn ("source: " <> rawRegistry.rawRegistrySource)
            putStrLn ("kind: " <> rawRegistry.rawRegistryKind)
            putStrLn ("rhs: " <> rawRegistry.rawRegistryRhs.rawTypePretty)
            putStrLn ("surfaces: " <> List.intercalate ", " (map (.rawSurfaceName) rawRegistry.rawRegistrySurfaces))
            mapM_ renderSurface rawRegistry.rawRegistrySurfaces
            renderLowered (lowerRawRegistry rawRegistry)
    where
        renderSurface surface = do
            putStrLn ("surface " <> surface.rawSurfaceName <> ": " <> surface.rawSurfaceSource)
            putStrLn ("  reference: " <> surface.rawSurfaceReference.rawTypePretty)
            putStrLn ("  expanded: " <> surface.rawSurfaceExpanded.rawTypePretty)
            putStrLn ("  normalized: " <> surface.rawSurfaceNormalized.rawTypePretty)
        renderLowered = \case
            Right contract -> putStrLn ("lowered surfaces: " <> List.intercalate ", " (map (Text.unpack . IR.surfaceName) (IR.contractSurfaces contract)))
            Left diagnostics -> do
                putStrLn "lowered diagnostics:"
                mapM_ (putStrLn . ("  " <>)) diagnostics

rawRegistryToJson :: RawRegistry -> Aeson.Value
rawRegistryToJson rawRegistry =
    Aeson.object
        [ "module" Aeson..= rawRegistry.rawRegistryModule
        , "export" Aeson..= rawRegistry.rawRegistryExport
        , "source" Aeson..= rawRegistry.rawRegistrySource
        , "kind" Aeson..= rawRegistry.rawRegistryKind
        , "rhs" Aeson..= Raw.rawTypeToJson rawRegistry.rawRegistryRhs
        , "surfaces" Aeson..= map Raw.rawSurfaceToJson rawRegistry.rawRegistrySurfaces
        , "lowered" Aeson..= loweredToJson (lowerRawRegistry rawRegistry)
        ]

loweredToJson :: Either [String] IR.SurfaceContractIR -> Aeson.Value
loweredToJson = \case
    Left diagnostics -> Aeson.object
        [ "status" Aeson..= ("error" :: String)
        , "diagnostics" Aeson..= diagnostics
        ]
    Right contract -> Aeson.object
        [ "status" Aeson..= ("ok" :: String)
        , "diagnostics" Aeson..= ([] :: [String])
        , "surfaces" Aeson..= map loweredSurfaceToJson (IR.contractSurfaces contract)
        ]

loweredSurfaceToJson :: IR.SurfaceIR -> Aeson.Value
loweredSurfaceToJson surface =
    Aeson.object
        [ "name" Aeson..= IR.surfaceName surface
        , "marker" Aeson..= IR.surfaceMarker surface
        , "scopes" Aeson..= map IR.scopeName (IR.surfaceScopes surface)
        , "fragments" Aeson..= map IR.fragmentName (IR.surfaceFragments surface)
        , "htmxActions" Aeson..= map IR.htmxActionName (IR.surfaceHtmxActions surface)
        , "intents" Aeson..= map IR.intentName (IR.surfaceIntents surface)
        , "sessions" Aeson..= IR.surfaceSessions surface
        , "layers" Aeson..= IR.surfaceLayers surface
        , "domTokens" Aeson..= IR.surfaceDomTokens surface
        , "dtos" Aeson..= map fst (IR.surfaceDtos surface)
        ]
