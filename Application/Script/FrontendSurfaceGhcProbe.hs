module Application.Script.FrontendSurfaceGhcProbe where

import Prelude

import qualified Application.Helper.FrontendSurface.ContractIR as IR
import Application.Helper.FrontendSurface.Ghc.Lower (lowerRawRegistry)
import Application.Helper.FrontendSurface.Ghc.Raw hiding (rawRegistryToJson)
import qualified Application.Helper.FrontendSurface.Ghc.Raw as Raw
import Control.Monad.IO.Class (liftIO)
import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Lazy.Char8 as LBS
import qualified Data.List as List
import qualified Data.Text as Text
import GHC
import GHC.Core.TyCo.Rep (TyLit (..), Type (..))
import GHC.Core.TyCon (synTyConRhs_maybe, tyConKind, tyConName)
import GHC.Core.Type (coreView)
import GHC.Driver.Flags (GeneralFlag (Opt_ForceRecomp))
import GHC.Driver.Session (gopt_set, xopt_set)
import GHC.LanguageExtensions.Type (Extension (DataKinds, TypeFamilies, TypeOperators))
import GHC.Types.Name (Name, nameOccName, nameSrcSpan)
import GHC.Types.Name.Occurrence (OccName, occNameString)
import GHC.Types.TyThing (TyThing (ATyCon))
import GHC.Types.Var (varName)
import GHC.Utils.Outputable hiding (text, (<>))
import qualified System.Environment as Environment
import System.Exit (exitFailure)

registryModuleName :: String
registryModuleName = "Application.Helper.FrontendSurface.Registry"

registryModulePath :: String
registryModulePath = "Application/Helper/FrontendSurface/Registry.hs"

registryTypeName :: String
registryTypeName = "RegisteredFrontendSurfaces"

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
inspectRegistry mode libdir =
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
                        case synTyConRhs_maybe tyCon of
                            Nothing -> do
                                putStrLn ("frontend-surface-ghc-probe: export is not a type synonym: " <> registryTypeName)
                                exitFailure
                            Just rhs -> do
                                let rawRegistry = RawRegistry
                                        { rawRegistryModule = registryModuleName
                                        , rawRegistryExport = registryTypeName
                                        , rawRegistrySource = renderSDoc (ppr (nameSrcSpan registryName))
                                        , rawRegistryKind = renderSDoc (ppr (tyConKind tyCon))
                                        , rawRegistryRhs = rawTypeFromType rhs
                                        , rawRegistrySurfaces = rawSurfacesFromRegistry rhs
                                        }
                                renderRawRegistry mode rawRegistry
                    Just otherThing -> liftIO do
                        putStrLn ("frontend-surface-ghc-probe: export is not a type constructor: " <> renderSDoc (ppr otherThing))
                        exitFailure
                    Nothing -> liftIO do
                        putStrLn ("frontend-surface-ghc-probe: lookupName failed for " <> registryTypeName)
                        exitFailure

findRegistryExport :: ModuleInfo -> Maybe Name
findRegistryExport info =
    List.find ((== registryTypeName) . occNameString . nameOccName) (modInfoExports info)

rawSurfacesFromRegistry :: Type -> [RawSurface]
rawSurfacesFromRegistry rhs =
    case promotedListElements rhs of
        Nothing       -> []
        Just surfaces -> map rawSurfaceFromType surfaces

rawSurfaceFromType :: Type -> RawSurface
rawSurfaceFromType surfaceType =
    let expanded = expandTypeSynonyms surfaceType
        surfaceName = typeHeadName surfaceType
     in RawSurface
            { rawSurfaceName = maybe (renderSDoc (ppr surfaceType)) occNameString surfaceName
            , rawSurfaceSource = maybe "<unknown>" (renderSDoc . ppr . nameSrcSpan) (typeHeadNameFull surfaceType)
            , rawSurfaceReference = rawTypeFromType surfaceType
            , rawSurfaceExpanded = rawTypeFromType expanded
            , rawSurfaceNormalized = normalizeApprovedType surfaceType
            }

promotedListElements :: Type -> Maybe [Type]
promotedListElements value =
    case value of
        TyConApp tyCon args ->
            case (occNameString (nameOccName (tyConName tyCon)), args) of
                ("[]", _) -> Just []
                (":", _kind : headType : tailType : _) -> (headType :) <$> promotedListElements tailType
                _ -> Nothing
        CastTy inner _ -> promotedListElements inner
        _ -> Nothing

expandTypeSynonyms :: Type -> Type
expandTypeSynonyms value =
    case coreView value of
        Just expanded -> expandTypeSynonyms expanded
        Nothing       -> value

normalizeApprovedType :: Type -> RawType
normalizeApprovedType originalValue =
    let value = expandTypeSynonyms originalValue
     in case value of
            TyConApp tyCon args ->
                let name = occNameString (nameOccName (tyConName tyCon))
                 in case name of
                        "Concat" -> normalizeConcat value args
                        "Append" -> normalizeAppend value args
                        ":" -> normalizePromotedList value
                        "[]" -> normalizePromotedList value
                        _ -> (rawTypeFromType value)
                            { rawTypeArgs = map normalizeApprovedType args
                            }
            AppTy left right -> RawType
                { rawTypeNode = "AppTy"
                , rawTypePretty = renderSDoc (ppr value)
                , rawTypeName = Nothing
                , rawTypeSource = Nothing
                , rawTypeArgs = map normalizeApprovedType [left, right]
                }
            ForAllTy _ body -> RawType
                { rawTypeNode = "ForAllTy"
                , rawTypePretty = renderSDoc (ppr value)
                , rawTypeName = Nothing
                , rawTypeSource = Nothing
                , rawTypeArgs = [normalizeApprovedType body]
                }
            FunTy _ multiplicity argument result -> RawType
                { rawTypeNode = "FunTy"
                , rawTypePretty = renderSDoc (ppr value)
                , rawTypeName = Nothing
                , rawTypeSource = Nothing
                , rawTypeArgs = map normalizeApprovedType [multiplicity, argument, result]
                }
            CastTy inner _ -> normalizeApprovedType inner
            _ -> rawTypeFromType value

normalizeConcat :: Type -> [Type] -> RawType
normalizeConcat original args =
    case valueArgs args of
        listsType : _ ->
            case normalizedListElements listsType >>= flattenNormalizedLists of
                Just elements -> rawPromotedList ("normalized " <> renderSDoc (ppr original)) elements
                Nothing -> unsupportedConcat
        _ -> unsupportedConcat
    where
        unsupportedConcat = (rawTypeFromType original)
            { rawTypeNode = "UnsupportedTypeFamily"
            , rawTypeArgs = map normalizeApprovedType args
            }

normalizeAppend :: Type -> [Type] -> RawType
normalizeAppend original args =
    case valueArgs args of
        leftType : rightType : _ ->
            case (normalizedListElements leftType, normalizedListElements rightType) of
                (Just leftElements, Just rightElements) -> rawPromotedList ("normalized " <> renderSDoc (ppr original)) (leftElements <> rightElements)
                _ -> unsupportedAppend
        _ -> unsupportedAppend
    where
        unsupportedAppend = (rawTypeFromType original)
            { rawTypeNode = "UnsupportedTypeFamily"
            , rawTypeArgs = map normalizeApprovedType args
            }

normalizePromotedList :: Type -> RawType
normalizePromotedList value =
    case normalizedListElements value of
        Just elements -> rawPromotedList (renderSDoc (ppr value)) elements
        Nothing       -> rawTypeFromType value

normalizedListElements :: Type -> Maybe [RawType]
normalizedListElements value =
    map normalizeApprovedType <$> promotedListElements (expandTypeSynonyms value)

flattenNormalizedLists :: [RawType] -> Maybe [RawType]
flattenNormalizedLists values =
    concatMapM rawPromotedListElements values

rawPromotedListElements :: RawType -> Maybe [RawType]
rawPromotedListElements rawType
    | rawType.rawTypeNode == "PromotedList" = Just rawType.rawTypeArgs
    | otherwise = Nothing

rawPromotedList :: String -> [RawType] -> RawType
rawPromotedList pretty elements =
    RawType
        { rawTypeNode = "PromotedList"
        , rawTypePretty = pretty
        , rawTypeName = Just "[]"
        , rawTypeSource = Nothing
        , rawTypeArgs = elements
        }

valueArgs :: [Type] -> [Type]
valueArgs = dropWhile isKindArgument

isKindArgument :: Type -> Bool
isKindArgument = \case
    TyConApp tyCon _ -> occNameString (nameOccName (tyConName tyCon)) `elem` ["Type", "List", "SurfaceSpec", "SurfacePrimitive", "FieldSpec", "PrimitiveOption", "WireType"]
    _ -> False

concatMapM :: (a -> Maybe [b]) -> [a] -> Maybe [b]
concatMapM _ [] = Just []
concatMapM f (value : rest) = do
    headValues <- f value
    tailValues <- concatMapM f rest
    pure (headValues <> tailValues)

rawTypeFromType :: Type -> RawType
rawTypeFromType value =
    case value of
        TyVarTy var -> RawType
            { rawTypeNode = "TyVarTy"
            , rawTypePretty = renderSDoc (ppr value)
            , rawTypeName = Just (occNameString (nameOccName (varName var)))
            , rawTypeSource = Just (renderSDoc (ppr (nameSrcSpan (varName var))))
            , rawTypeArgs = []
            }
        AppTy left right -> RawType
            { rawTypeNode = "AppTy"
            , rawTypePretty = renderSDoc (ppr value)
            , rawTypeName = Nothing
            , rawTypeSource = Nothing
            , rawTypeArgs = [rawTypeFromType left, rawTypeFromType right]
            }
        TyConApp tyCon args -> RawType
            { rawTypeNode = "TyConApp"
            , rawTypePretty = renderSDoc (ppr value)
            , rawTypeName = Just (occNameString (nameOccName (tyConName tyCon)))
            , rawTypeSource = Just (renderSDoc (ppr (nameSrcSpan (tyConName tyCon))))
            , rawTypeArgs = map rawTypeFromType args
            }
        ForAllTy _ body -> RawType
            { rawTypeNode = "ForAllTy"
            , rawTypePretty = renderSDoc (ppr value)
            , rawTypeName = Nothing
            , rawTypeSource = Nothing
            , rawTypeArgs = [rawTypeFromType body]
            }
        FunTy _ multiplicity argument result -> RawType
            { rawTypeNode = "FunTy"
            , rawTypePretty = renderSDoc (ppr value)
            , rawTypeName = Nothing
            , rawTypeSource = Nothing
            , rawTypeArgs = map rawTypeFromType [multiplicity, argument, result]
            }
        LitTy literal -> RawType
            { rawTypeNode = "LitTy"
            , rawTypePretty = renderSDoc (ppr value)
            , rawTypeName = Just (literalName literal)
            , rawTypeSource = Nothing
            , rawTypeArgs = []
            }
        CastTy inner _ -> RawType
            { rawTypeNode = "CastTy"
            , rawTypePretty = renderSDoc (ppr value)
            , rawTypeName = Nothing
            , rawTypeSource = Nothing
            , rawTypeArgs = [rawTypeFromType inner]
            }
        CoercionTy _ -> RawType
            { rawTypeNode = "CoercionTy"
            , rawTypePretty = renderSDoc (ppr value)
            , rawTypeName = Nothing
            , rawTypeSource = Nothing
            , rawTypeArgs = []
            }

typeHeadName :: Type -> Maybe OccName
typeHeadName value = nameOccName <$> typeHeadNameFull value

typeHeadNameFull :: Type -> Maybe Name
typeHeadNameFull value =
    case value of
        TyConApp tyCon _ -> Just (tyConName tyCon)
        CastTy inner _   -> typeHeadNameFull inner
        _                -> Nothing

literalName :: TyLit -> String
literalName = \case
    NumTyLit value -> show value
    StrTyLit value -> renderSDoc (ppr value)
    CharTyLit value -> show value

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

renderSDoc :: SDoc -> String
renderSDoc = showSDocUnsafe
