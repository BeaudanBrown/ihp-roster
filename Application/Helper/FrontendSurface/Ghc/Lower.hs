module Application.Helper.FrontendSurface.Ghc.Lower
    ( lowerRawRegistry
    , lowerRawSurface
    ) where

import qualified Application.Helper.FrontendSurface.ContractIR as IR
import Application.Helper.FrontendSurface.Ghc.Raw
import qualified Application.Helper.FrontendSurface.Naming as Naming
import Control.Monad (foldM)
import qualified Data.List as List
import qualified Data.Text as Text
import IHP.Prelude

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

protocol :: Naming.FrontendSurfaceNameContext -> String -> Text
protocol context marker =
    Naming.deriveFrontendSurfaceName context (text marker)

text :: String -> Text
text = Text.pack

collectEither :: [Either [String] a] -> Either [String] [a]
collectEither values =
    case partitionEithers values of
        ([], rights) -> Right rights
        (errors, _)  -> Left (concat errors)
