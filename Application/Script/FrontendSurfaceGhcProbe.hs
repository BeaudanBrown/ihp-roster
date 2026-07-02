module Application.Script.FrontendSurfaceGhcProbe where

import Prelude

import qualified Application.Helper.FrontendSurface.ContractIR as IR
import qualified Application.Helper.FrontendSurface.Naming as Naming
import Control.Monad (foldM)
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

data RawRegistry = RawRegistry
    { rawRegistryModule   :: !String
    , rawRegistryExport   :: !String
    , rawRegistrySource   :: !String
    , rawRegistryKind     :: !String
    , rawRegistryRhs      :: !RawType
    , rawRegistrySurfaces :: ![RawSurface]
    }
    deriving (Eq, Show)

data RawSurface = RawSurface
    { rawSurfaceName       :: !String
    , rawSurfaceSource     :: !String
    , rawSurfaceReference  :: !RawType
    , rawSurfaceExpanded   :: !RawType
    , rawSurfaceNormalized :: !RawType
    }
    deriving (Eq, Show)

data RawType = RawType
    { rawTypeNode   :: !String
    , rawTypePretty :: !String
    , rawTypeName   :: !(Maybe String)
    , rawTypeSource :: !(Maybe String)
    , rawTypeArgs   :: ![RawType]
    }
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

lowerRawRegistry :: RawRegistry -> Either [String] IR.SurfaceContractIR
lowerRawRegistry rawRegistry = do
    surfaces <- collectEither (map lowerRawSurface rawRegistry.rawRegistrySurfaces)
    let contract = IR.SurfaceContractIR { IR.contractSurfaces = surfaces }
    case IR.validateSurfaceContractIR contract of
        [] -> Right contract
        diagnostics -> Left (map (Text.unpack . IR.diagnosticMessage) diagnostics)

lowerRawSurface :: RawSurface -> Either [String] IR.SurfaceIR
lowerRawSurface rawSurface =
    case rawSurface.rawSurfaceNormalized of
        RawType { rawTypeName = Just "Surface", rawTypeArgs = marker : capabilities : _ } -> do
            markerName <- rawMarkerName marker
            primitives <- rawListElements "surface capabilities" capabilities
            foldM addPrimitive (emptyLoweredSurface markerName) primitives
        other -> Left ["unsupported normalized surface for " <> rawSurface.rawSurfaceName <> ": " <> other.rawTypePretty]

emptyLoweredSurface :: String -> IR.SurfaceIR
emptyLoweredSurface marker = IR.SurfaceIR
    { IR.surfaceMarker = text marker
    , IR.surfaceName = protocol Naming.SurfaceName marker
    , IR.surfaceScopes = []
    , IR.surfaceMountStates = []
    , IR.surfaceFragments = []
    , IR.surfaceHtmxActions = []
    , IR.surfaceIntents = []
    , IR.surfaceSessions = []
    , IR.surfaceLayers = []
    , IR.surfaceEffects = []
    , IR.surfacePolicies = []
    , IR.surfaceLoadPolicies = []
    , IR.surfaceOverlayLanes = []
    , IR.surfaceClientEvents = []
    , IR.surfaceDomTokens = []
    , IR.surfaceDtos = []
    }

addPrimitive :: IR.SurfaceIR -> RawType -> Either [String] IR.SurfaceIR
addPrimitive surface primitive =
    case (primitive.rawTypeName, primitive.rawTypeArgs) of
        (Just "Scope", marker : fields : _) -> do
            markerName <- rawMarkerName marker
            fieldList <- lowerFieldList fields
            Right surface { IR.surfaceScopes = IR.surfaceScopes surface <> [IR.ScopeIR
                { IR.scopeMarker = text markerName
                , IR.scopeName = protocol Naming.ScopeName markerName
                , IR.scopeFields = fieldList
                }] }
        (Just "MountState", marker : fields : _) -> do
            markerName <- rawMarkerName marker
            fieldList <- lowerFieldList fields
            Right surface { IR.surfaceMountStates = IR.surfaceMountStates surface <> [IR.MountStateIR
                { IR.mountStateMarker = text markerName
                , IR.mountStateName = protocol Naming.ScopeName markerName
                , IR.mountStateFields = fieldList
                }] }
        (Just "Fragment", marker : fields : options : _) -> do
            markerName <- rawMarkerName marker
            fieldList <- lowerFieldList fields
            optionList <- lowerOptionList options
            Right surface { IR.surfaceFragments = IR.surfaceFragments surface <> [IR.FragmentIR
                { IR.fragmentMarker = text markerName
                , IR.fragmentName = protocol Naming.FragmentName markerName
                , IR.fragmentParams = fieldList
                , IR.fragmentOptions = optionList
                }] }
        (Just "HtmxAction", marker : fields : options : _) -> do
            markerName <- rawMarkerName marker
            fieldList <- lowerFieldList fields
            optionList <- lowerOptionList options
            Right surface { IR.surfaceHtmxActions = IR.surfaceHtmxActions surface <> [IR.HtmxActionIR
                { IR.htmxActionMarker = text markerName
                , IR.htmxActionName = protocol Naming.ActionName markerName
                , IR.htmxActionFields = fieldList
                , IR.htmxActionOptions = optionList
                }] }
        (Just "Intent", marker : fields : options : _) -> do
            markerName <- rawMarkerName marker
            fieldList <- lowerFieldList fields
            optionList <- lowerOptionList options
            Right surface { IR.surfaceIntents = IR.surfaceIntents surface <> [IR.IntentIR
                { IR.intentMarker = text markerName
                , IR.intentName = protocol Naming.IntentName markerName
                , IR.intentFields = fieldList
                , IR.intentOptions = optionList
                }] }
        (Just "Session", marker : _) -> do
            markerName <- rawMarkerName marker
            Right surface { IR.surfaceSessions = IR.surfaceSessions surface <> [protocol Naming.SessionName markerName] }
        (Just "DisposableLayer", marker : _) -> do
            markerName <- rawMarkerName marker
            Right surface { IR.surfaceLayers = IR.surfaceLayers surface <> [protocol Naming.LayerName markerName] }
        (Just "InteractionEffect", marker : options : _) -> do
            markerName <- rawMarkerName marker
            optionList <- lowerOptionList options
            Right surface { IR.surfaceEffects = IR.surfaceEffects surface <> [(protocol Naming.ActionName markerName, optionList)] }
        (Just "ConflictPolicy", session : fragment : resolution : _) -> do
            policy <- IR.ConflictPolicyIR <$> lowerSessionSelector session <*> lowerFragmentSelector fragment <*> lowerConflictResolution resolution
            Right surface { IR.surfacePolicies = IR.surfacePolicies surface <> [policy] }
        (Just "LoadPolicy", marker : _) -> do
            markerName <- rawMarkerName marker
            Right surface { IR.surfaceLoadPolicies = IR.surfaceLoadPolicies surface <> [protocol Naming.FragmentName markerName] }
        (Just "OverlayLane", marker : _) -> do
            markerName <- rawMarkerName marker
            Right surface { IR.surfaceOverlayLanes = IR.surfaceOverlayLanes surface <> [protocol Naming.LayerName markerName] }
        (Just "ClientEvent", marker : fields : _) -> do
            markerName <- rawMarkerName marker
            fieldList <- lowerFieldList fields
            Right surface { IR.surfaceClientEvents = IR.surfaceClientEvents surface <> [(protocol Naming.EventName markerName, fieldList)] }
        (Just "DomToken", marker : _) -> do
            markerName <- rawMarkerName marker
            Right surface { IR.surfaceDomTokens = IR.surfaceDomTokens surface <> [protocol Naming.DomTokenName markerName] }
        (Just "Dto", marker : fields : _) -> do
            markerName <- rawMarkerName marker
            fieldList <- lowerFieldList fields
            Right surface { IR.surfaceDtos = IR.surfaceDtos surface <> [(protocol Naming.ScopeName markerName, fieldList)] }
        _ -> Left ["unsupported primitive " <> primitive.rawTypePretty]

lowerFieldList :: RawType -> Either [String] [IR.FieldIR]
lowerFieldList fields = rawListElements "field list" fields >>= collectEither . map lowerField

lowerField :: RawType -> Either [String] IR.FieldIR
lowerField field =
    case (field.rawTypeName, field.rawTypeArgs) of
        (Just "Field", marker : wire : _) -> lowerFieldWithPresence IR.RequiredField marker wire
        (Just "OptionalField", marker : wire : _) -> lowerFieldWithPresence IR.OptionalFieldPresence marker wire
        (Just "NullableField", marker : wire : _) -> lowerFieldWithPresence IR.NullableFieldPresence marker wire
        _ -> Left ["unsupported field " <> field.rawTypePretty]

lowerFieldWithPresence :: IR.FieldPresence -> RawType -> RawType -> Either [String] IR.FieldIR
lowerFieldWithPresence presence marker wire = do
    markerName <- rawMarkerName marker
    wireIR <- lowerWire wire
    Right IR.FieldIR
        { IR.fieldMarker = text markerName
        , IR.fieldName = protocol Naming.FieldName markerName
        , IR.fieldWire = wireIR
        , IR.fieldPresence = presence
        , IR.fieldBrand = text <$> brandName markerName
        }

lowerWire :: RawType -> Either [String] IR.WireIR
lowerWire wire =
    case (wire.rawTypeName, wire.rawTypeArgs) of
        (Just "WireText", _) -> Right IR.WireTextIR
        (Just "WireInt", _) -> Right IR.WireIntIR
        (Just "WireBool", _) -> Right IR.WireBoolIR
        (Just "WireUUID", _) -> Right IR.WireUuidIR
        (Just "WireDay", _) -> Right IR.WireDayIR
        (Just "WireList", inner : _) -> IR.WireListIR <$> lowerWire inner
        (Just "WireOptional", inner : _) -> IR.WireOptionalIR <$> lowerWire inner
        (Just "WireNullable", inner : _) -> IR.WireNullableIR <$> lowerWire inner
        (Just "WireRef", marker : _) -> IR.WireRefIR <$> (protocol Naming.ScopeName <$> rawMarkerName marker)
        _ -> Left ["unsupported wire type " <> wire.rawTypePretty]

lowerOptionList :: RawType -> Either [String] [IR.OptionIR]
lowerOptionList options = rawListElements "option list" options >>= collectEither . map lowerOption

lowerOption :: RawType -> Either [String] IR.OptionIR
lowerOption option =
    case (option.rawTypeName, option.rawTypeArgs) of
        (Just "Eager", _) -> Right IR.EagerOption
        (Just "Lazy", nested : _) -> IR.LazyOption <$> lowerOptionList nested
        (Just "Trigger", marker : _) -> IR.TriggerOption <$> (protocol Naming.DomTokenName <$> rawMarkerName marker)
        (Just "Placeholder", marker : _) -> IR.PlaceholderOption <$> (protocol Naming.DomTokenName <$> rawMarkerName marker)
        (Just "DependsOn", marker : _) -> IR.DependsOnOption <$> (protocol Naming.DomTokenName <$> rawMarkerName marker)
        (Just "Target", marker : _) -> IR.TargetOption <$> (protocol Naming.FragmentName <$> rawMarkerName marker)
        (Just "BackedBy", marker : _) -> IR.BackedByOption <$> (protocol Naming.ActionName <$> rawMarkerName marker)
        (Just "Layer", marker : _) -> IR.LayerOption <$> (protocol Naming.LayerName <$> rawMarkerName marker)
        (Just "SessionOption", marker : _) -> IR.SessionOptionIR <$> (protocol Naming.SessionName <$> rawMarkerName marker)
        (Just "Emits", marker : _) -> IR.EmitsOption <$> (protocol Naming.EventName <$> rawMarkerName marker)
        (Just "Contains", marker : _) -> IR.ContainsOption <$> (protocol Naming.DomTokenName <$> rawMarkerName marker)
        (Just "UsesDto", marker : _) -> IR.UsesDtoOption <$> (protocol Naming.ScopeName <$> rawMarkerName marker)
        _ -> Left ["unsupported option " <> option.rawTypePretty]

lowerSessionSelector :: RawType -> Either [String] IR.SessionSelectorIR
lowerSessionSelector selector =
    case (selector.rawTypeName, selector.rawTypeArgs) of
        (Just "AnySession", _) -> Right IR.AnySessionIR
        (Just "SessionKind", marker : _) -> IR.SessionKindIR <$> (protocol Naming.SessionName <$> rawMarkerName marker)
        _ -> Left ["unsupported session selector " <> selector.rawTypePretty]

lowerFragmentSelector :: RawType -> Either [String] IR.FragmentSelectorIR
lowerFragmentSelector selector =
    case (selector.rawTypeName, selector.rawTypeArgs) of
        (Just "AnyFragment", _) -> Right IR.AnyFragmentIR
        (Just "FragmentKind", marker : _) -> IR.FragmentKindIR <$> (protocol Naming.FragmentName <$> rawMarkerName marker)
        (Just "FragmentSubtree", marker : _) -> IR.FragmentSubtreeIR <$> (protocol Naming.FragmentName <$> rawMarkerName marker)
        _ -> Left ["unsupported fragment selector " <> selector.rawTypePretty]

lowerConflictResolution :: RawType -> Either [String] IR.ConflictResolutionIR
lowerConflictResolution resolution =
    case resolution.rawTypeName of
        Just "Apply" -> Right IR.ApplyIR
        Just "Defer" -> Right IR.DeferIR
        Just "Cancel" -> Right IR.CancelIR
        _ -> Left ["unsupported conflict resolution " <> resolution.rawTypePretty]

rawListElements :: String -> RawType -> Either [String] [RawType]
rawListElements label rawType
    | rawType.rawTypeNode == "PromotedList" = Right rawType.rawTypeArgs
    | otherwise = Left ["expected " <> label <> " as normalized PromotedList, got " <> rawType.rawTypePretty]

rawMarkerName :: RawType -> Either [String] String
rawMarkerName rawType =
    case rawType.rawTypeName of
        Just name -> Right name
        Nothing -> Left ["expected marker type, got " <> rawType.rawTypePretty]

brandName :: String -> Maybe String
brandName marker
    | "Id" `List.isSuffixOf` marker = Just marker
    | otherwise = Nothing

protocol :: Naming.FrontendSurfaceNameContext -> String -> Text.Text
protocol context marker =
    Naming.deriveFrontendSurfaceName context (text marker)

text :: String -> Text.Text
text = Text.pack

collectEither :: [Either [String] a] -> Either [String] [a]
collectEither values =
    case partitionEithers values of
        ([], rights) -> Right rights
        (errors, _)  -> Left (concat errors)

partitionEithers :: [Either left right] -> ([left], [right])
partitionEithers = foldr partition ([], [])
    where
        partition value (lefts, rights) =
            case value of
                Left left   -> (left : lefts, rights)
                Right right -> (lefts, right : rights)

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
        , "rhs" Aeson..= rawTypeToJson rawRegistry.rawRegistryRhs
        , "surfaces" Aeson..= map rawSurfaceToJson rawRegistry.rawRegistrySurfaces
        , "lowered" Aeson..= loweredToJson (lowerRawRegistry rawRegistry)
        ]

rawSurfaceToJson :: RawSurface -> Aeson.Value
rawSurfaceToJson surface =
    Aeson.object
        [ "name" Aeson..= surface.rawSurfaceName
        , "source" Aeson..= surface.rawSurfaceSource
        , "reference" Aeson..= rawTypeToJson surface.rawSurfaceReference
        , "expanded" Aeson..= rawTypeToJson surface.rawSurfaceExpanded
        , "normalized" Aeson..= rawTypeToJson surface.rawSurfaceNormalized
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

rawTypeToJson :: RawType -> Aeson.Value
rawTypeToJson rawType =
    Aeson.object
        [ "node" Aeson..= rawType.rawTypeNode
        , "pretty" Aeson..= rawType.rawTypePretty
        , "name" Aeson..= rawType.rawTypeName
        , "source" Aeson..= rawType.rawTypeSource
        , "args" Aeson..= map rawTypeToJson rawType.rawTypeArgs
        ]

renderSDoc :: SDoc -> String
renderSDoc = showSDocUnsafe
