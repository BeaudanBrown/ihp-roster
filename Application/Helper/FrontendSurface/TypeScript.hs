module Application.Helper.FrontendSurface.TypeScript
    ( renderFrontendSurfaceContractsTypeScript
    ) where

import Application.Helper.FrontendSurface.ContractIR
import qualified Data.Char as Char
import qualified Data.List as List
import qualified Data.Text as Text
import IHP.Prelude

renderFrontendSurfaceContractsTypeScript :: SurfaceContractIR -> Text
renderFrontendSurfaceContractsTypeScript contract =
    Text.unlines $
        [ "// FrontendSurface contracts generated from Application.Helper.FrontendSurface.Registry."
        , "export type FrontendSurfaceUUID = string & { readonly __brand: \"FrontendSurfaceUUID\" };"
        , "export type FrontendSurfaceDay = string & { readonly __brand: \"FrontendSurfaceDay\" };"
        , ""
        ]
            <> brandAliasLines contract
            <> concatMap renderSurface contract.contractSurfaces
            <> renderLiveTransportTypes contract
            <> renderRegistry contract

renderSurface :: SurfaceIR -> [Text]
renderSurface surface =
    let prefix = tsTypeName surface.surfaceName
     in [ "export type " <> prefix <> "SurfaceName = " <> tsString surface.surfaceName <> ";" ]
            <> concatMap renderScope surface.surfaceScopes
            <> concatMap renderMountState surface.surfaceMountStates
            <> concatMap (renderDto "") surface.surfaceDtos
            <> concatMap renderEvent surface.surfaceClientEvents
            <> renderFragmentKey prefix surface.surfaceFragments
            <> renderActionName prefix surface.surfaceHtmxActions
            <> renderIntentName prefix surface.surfaceIntents
            <> renderVocabulary (prefix <> "SessionName") surface.surfaceSessions
            <> renderVocabulary (prefix <> "DisposableLayerName") surface.surfaceLayers
            <> renderVocabulary (prefix <> "DomToken") surface.surfaceDomTokens
            <> renderVocabulary (prefix <> "OverlayLane") surface.surfaceOverlayLanes
            <> renderManifest surface
            <> [ "" ]

renderScope :: ScopeIR -> [Text]
renderScope scope =
    [ "export type " <> tsTypeName scope.scopeName <> "Scope = " <> renderRecord (Just ("kind", scope.scopeName)) scope.scopeFields <> ";" ]

renderMountState :: MountStateIR -> [Text]
renderMountState mountState =
    [ "export type " <> mountStateTsTypeName mountState.mountStateName <> " = " <> renderRecord Nothing mountState.mountStateFields <> ";" ]

mountStateTsTypeName :: Text -> Text
mountStateTsTypeName name =
    let typeName = tsTypeName name
     in if "MountState" `Text.isSuffixOf` typeName
            then typeName
            else typeName <> "MountState"

renderDto :: Text -> (Text, [FieldIR]) -> [Text]
renderDto suffix (dtoName, fields) =
    [ "export type " <> tsTypeName dtoName <> suffix <> " = " <> renderRecord Nothing fields <> ";" ]

renderEvent :: (Text, [FieldIR]) -> [Text]
renderEvent (eventName, fields) =
    [ "export type " <> tsTypeName eventName <> "EventDetail = " <> renderRecord (Just ("kind", eventName)) fields <> ";" ]

renderFragmentKey :: Text -> [FragmentIR] -> [Text]
renderFragmentKey prefix fragments =
    case fragments of
        [] -> []
        _  -> [ "export type " <> prefix <> "FragmentKey ="
              ] <> map renderVariant fragments <> [ ";" ]
    where
        renderVariant fragment =
            "    | { kind: " <> tsString fragment.fragmentName <> "; params: " <> renderRecord Nothing fragment.fragmentParams <> " }"

renderActionName :: Text -> [HtmxActionIR] -> [Text]
renderActionName prefix actions =
    renderVocabulary (prefix <> "HtmxActionName") (map (.htmxActionName) actions)
        <> concatMap renderActionFields actions
    where
        renderActionFields action =
            [ "export type " <> tsTypeName action.htmxActionName <> "ActionFields = " <> renderRecord Nothing action.htmxActionFields <> ";" ]

renderIntentName :: Text -> [IntentIR] -> [Text]
renderIntentName prefix intents =
    renderVocabulary (prefix <> "IntentName") (map (.intentName) intents)
        <> concatMap renderIntentFields intents
    where
        renderIntentFields intent =
            [ "export type " <> tsTypeName intent.intentName <> "IntentFields = " <> renderRecord Nothing intent.intentFields <> ";" ]

renderVocabulary :: Text -> [Text] -> [Text]
renderVocabulary typeName values =
    [ "export type " <> typeName <> " = " <> renderUnion values <> ";" | not (null values) ]

renderManifest :: SurfaceIR -> [Text]
renderManifest surface =
    [ "export const " <> tsConstName surface.surfaceName <> "SurfaceManifest = " <> renderManifestObject surface <> " as const;" ]

renderRegistry :: SurfaceContractIR -> [Text]
renderRegistry contract =
    [ "export type FrontendSurfaceName = " <> renderUnion (map (.surfaceName) contract.contractSurfaces) <> ";"
    , "export const FrontendSurfaceRegistry = {"
    ]
        <> map (\surface -> "    " <> tsObjectKey surface.surfaceName <> ": " <> tsConstName surface.surfaceName <> "SurfaceManifest,") contract.contractSurfaces
        <> [ "} as const;"
           , "export function isFrontendSurfaceName(value: unknown): value is FrontendSurfaceName {"
           , "    return typeof value === \"string\" && Object.prototype.hasOwnProperty.call(FrontendSurfaceRegistry, value);"
           , "}"
           , "export function parseFrontendSurfaceName(value: unknown): FrontendSurfaceName {"
           , "    if (isFrontendSurfaceName(value)) return value;"
           , "    throw new Error(\"Invalid FrontendSurfaceName\");"
           , "}"
           , "export type FrontendSurfaceContainmentEdge = { parentSurface: FrontendSurfaceName; parentFragment: string; childSurface: FrontendSurfaceName };"
           , "export const FrontendSurfaceContainmentTopology = ["
           ]
        <> renderContainmentTopology contract
        <> [ "] as const;"
           , "export function isFrontendSurfaceContainmentEdge(value: unknown): value is FrontendSurfaceContainmentEdge {"
           , "    if (typeof value !== \"object\" || value === null) return false;"
           , "    const edge = value as Record<string, unknown>;"
           , "    return isFrontendSurfaceName(edge.parentSurface) && typeof edge.parentFragment === \"string\" && isFrontendSurfaceName(edge.childSurface);"
           , "}"
           ]

renderManifestObject :: SurfaceIR -> Text
renderManifestObject surface =
    "{ surface: " <> tsString surface.surfaceName
        <> ", scopes: " <> renderStringArray (map (.scopeName) surface.surfaceScopes)
        <> ", fragments: " <> renderStringArray (map (.fragmentName) surface.surfaceFragments)
        <> ", liveFragments: " <> renderStringArray (map (.fragmentName) (liveFragments surface))
        <> ", htmxActions: " <> renderStringArray (map (.htmxActionName) surface.surfaceHtmxActions)
        <> ", intents: " <> renderStringArray (map (.intentName) surface.surfaceIntents)
        <> ", sessions: " <> renderStringArray surface.surfaceSessions
        <> ", layers: " <> renderStringArray surface.surfaceLayers
        <> ", domTokens: " <> renderStringArray surface.surfaceDomTokens
        <> ", overlayLanes: " <> renderStringArray surface.surfaceOverlayLanes
        <> ", containedSurfaces: " <> renderContainedSurfaceMap surface
        <> " }"

renderContainmentTopology :: SurfaceContractIR -> [Text]
renderContainmentTopology contract =
    [ "    { parentSurface: " <> tsString parentSurface <> ", parentFragment: " <> tsString parentFragment <> ", childSurface: " <> tsString childSurface <> " },"
    | (parentSurface, parentFragment, childSurface) <- containmentEdges contract
    ]

renderContainedSurfaceMap :: SurfaceIR -> Text
renderContainedSurfaceMap surface =
    case fragmentEntries of
        [] -> "{}"
        _  -> "{ " <> Text.intercalate ", " fragmentEntries <> " }"
    where
        fragmentEntries =
            [ tsObjectKey fragment.fragmentName <> ": " <> renderStringArray childSurfaces
            | fragment <- surface.surfaceFragments
            , let childSurfaces = containedSurfaceNames fragment.fragmentOptions
            , not (null childSurfaces)
            ]

containmentEdges :: SurfaceContractIR -> [(Text, Text, Text)]
containmentEdges contract =
    [ (surface.surfaceName, fragment.fragmentName, childSurface)
    | surface <- contract.contractSurfaces
    , fragment <- surface.surfaceFragments
    , childSurface <- containedSurfaceNames fragment.fragmentOptions
    ]

liveFragments :: SurfaceIR -> [FragmentIR]
liveFragments surface = filter (hasLiveOption . (.fragmentOptions)) surface.surfaceFragments

hasLiveOption :: [OptionIR] -> Bool
hasLiveOption = any \case
    LiveOption -> True
    LazyOption options -> hasLiveOption options
    EffectOption _ options -> hasLiveOption options
    _ -> False

renderLiveTransportTypes :: SurfaceContractIR -> [Text]
renderLiveTransportTypes contract =
    [ "export type FrontendSurfaceLiveScope ="
    ] <> liveScopeVariants <> [ ";" ]
        <> [ "export type FrontendSurfaceLiveFragment =" ] <> liveFragmentVariants <> [ ";" ]
        <> [ "export type FrontendSurfaceLiveFragmentProtection ="
           , "    | { kind: \"none\" }"
           , "    | { kind: \"focused-field\"; activeSelector: string; fieldKeyAttr: string; fieldNameFallback: boolean; containerSelector: string | null };"
           , "export type FrontendSurfaceLiveWireFragment = { fragment: FrontendSurfaceLiveFragment; targetId: string; url: string; deferUntilBlur: boolean; protectionPolicy: FrontendSurfaceLiveFragmentProtection };"
           , "export type FrontendSurfaceLiveSubscription = { scope: FrontendSurfaceLiveScope; scopeKey: string; resyncFragments: FrontendSurfaceLiveWireFragment[] };"
           , "export function isFrontendSurfaceLiveScope(value: unknown): value is FrontendSurfaceLiveScope {"
           , "    return typeof value === \"object\" && value !== null && isFrontendSurfaceName((value as Record<string, unknown>).surface);"
           , "}"
           , "export function parseFrontendSurfaceLiveScope(value: unknown): FrontendSurfaceLiveScope {"
           , "    if (isFrontendSurfaceLiveScope(value)) return value;"
           , "    throw new Error(\"Invalid FrontendSurfaceLiveScope\");"
           , "}"
           , "export function isFrontendSurfaceLiveFragment(value: unknown): value is FrontendSurfaceLiveFragment {"
           , "    return typeof value === \"object\" && value !== null && isFrontendSurfaceName((value as Record<string, unknown>).surface);"
           , "}"
           , "export function parseFrontendSurfaceLiveFragment(value: unknown): FrontendSurfaceLiveFragment {"
           , "    if (isFrontendSurfaceLiveFragment(value)) return value;"
           , "    throw new Error(\"Invalid FrontendSurfaceLiveFragment\");"
           , "}"
           , ""
           ]
    where
        liveSurfaces = filter (not . null . liveFragments) contract.contractSurfaces
        liveScopeVariants =
            case liveSurfaces of
                [] -> ["    never"]
                _  -> concatMap renderScopeVariant liveSurfaces
        liveFragmentVariants =
            case liveSurfaces of
                [] -> ["    never"]
                _  -> concatMap renderFragmentVariant liveSurfaces
        renderScopeVariant surface =
            case surface.surfaceScopes of
                scope : _ -> ["    | { surface: " <> tsString surface.surfaceName <> "; scope: " <> tsTypeName scope.scopeName <> "Scope }"]
                [] -> []
        renderFragmentVariant surface =
            let prefix = tsTypeName surface.surfaceName
             in ["    | { surface: " <> tsString surface.surfaceName <> "; fragment: " <> prefix <> "FragmentKey }"]

containedSurfaceNames :: [OptionIR] -> [Text]
containedSurfaceNames = concatMap \case
    LazyOption options -> containedSurfaceNames options
    ContainsSurfaceOption surfaceName -> [surfaceName]
    _ -> []

renderRecord :: Maybe (Text, Text) -> [FieldIR] -> Text
renderRecord maybeKind fields =
    case recordFields of
        [] -> "Record<string, never>"
        _  -> "{ " <> Text.intercalate "; " recordFields <> " }"
    where
        kindField = maybe [] (\(_, value) -> ["kind: " <> tsString value]) maybeKind
        recordFields = kindField <> map renderField fields

renderField :: FieldIR -> Text
renderField field =
    field.fieldName <> optionalMarker field.fieldPresence <> ": " <> renderFieldType field

renderFieldType :: FieldIR -> Text
renderFieldType field =
    case field.fieldPresence of
        NullableFieldPresence -> baseType <> " | null"
        _                     -> baseType
    where
        baseType = renderWireWithBrand field.fieldBrand field.fieldWire

renderWireWithBrand :: Maybe Text -> WireIR -> Text
renderWireWithBrand maybeBrand = \case
    WireUuidIR -> fromMaybe "FrontendSurfaceUUID" maybeBrand
    WireListIR inner -> "ReadonlyArray<" <> renderWireWithBrand maybeBrand inner <> ">"
    WireOptionalIR inner -> renderWireWithBrand maybeBrand inner <> " | undefined"
    WireNullableIR inner -> renderWireWithBrand maybeBrand inner <> " | null"
    other -> renderWire other

optionalMarker :: FieldPresence -> Text
optionalMarker = \case
    OptionalFieldPresence -> "?"
    _                     -> ""

renderWire :: WireIR -> Text
renderWire = \case
    WireTextIR -> "string"
    WireIntIR -> "number"
    WireBoolIR -> "boolean"
    WireUuidIR -> "FrontendSurfaceUUID"
    WireDayIR -> "FrontendSurfaceDay"
    WireListIR inner -> "ReadonlyArray<" <> renderWire inner <> ">"
    WireOptionalIR inner -> renderWire inner <> " | undefined"
    WireNullableIR inner -> renderWire inner <> " | null"
    WireRefIR name -> tsTypeName name

brandAliasLines :: SurfaceContractIR -> [Text]
brandAliasLines contract =
    let brands = contract.contractSurfaces >>= collectSurfaceBrands
     in brands
            |> List.nub
            |> List.sort
            |> map (\brand -> "export type " <> brand <> " = FrontendSurfaceUUID & { readonly __brand: " <> tsString brand <> " };")
            |> (<> [""])

collectSurfaceBrands :: SurfaceIR -> [Text]
collectSurfaceBrands surface =
    concatMap (mapMaybe (.fieldBrand) . scopeFields) surface.surfaceScopes
        <> concatMap (mapMaybe (.fieldBrand) . mountStateFields) surface.surfaceMountStates
        <> concatMap (mapMaybe (.fieldBrand) . fragmentParams) surface.surfaceFragments
        <> concatMap (mapMaybe (.fieldBrand) . htmxActionFields) surface.surfaceHtmxActions
        <> concatMap (mapMaybe (.fieldBrand) . intentFields) surface.surfaceIntents
        <> concatMap (mapMaybe (.fieldBrand) . snd) surface.surfaceClientEvents
        <> concatMap (mapMaybe (.fieldBrand) . snd) surface.surfaceDtos

renderUnion :: [Text] -> Text
renderUnion values =
    case values of
        [] -> "never"
        _  -> Text.intercalate " | " (map tsString values)

renderStringArray :: [Text] -> Text
renderStringArray values =
    "[" <> Text.intercalate ", " (map tsString values) <> "]"

tsConstName :: Text -> Text
tsConstName name = lowerFirst (tsTypeName name)

tsTypeName :: Text -> Text
tsTypeName name =
    name
        |> splitProtocolWords
        |> map title
        |> mconcat

tsObjectKey :: Text -> Text
tsObjectKey name
    | isIdentifier name = name
    | otherwise = tsString name

tsString :: Text -> Text
tsString value =
    tshow (Text.unpack value)

splitProtocolWords :: Text -> [Text]
splitProtocolWords name =
    name
        |> Text.replace "_" "-"
        |> Text.splitOn "-"
        |> filter (not . Text.null)

title :: Text -> Text
title word =
    case Text.uncons word of
        Nothing            -> ""
        Just (first, rest) -> Text.toUpper (Text.singleton first) <> rest

lowerFirst :: Text -> Text
lowerFirst value =
    case Text.uncons value of
        Nothing            -> ""
        Just (first, rest) -> Text.toLower (Text.singleton first) <> rest

isIdentifier :: Text -> Bool
isIdentifier value =
    case Text.uncons value of
        Nothing -> False
        Just (first, rest) -> isIdentifierStart first && Text.all isIdentifierPart rest
    where
        isIdentifierStart char = char == '_' || char == '$' || Char.isAlpha char
        isIdentifierPart char = isIdentifierStart char || Char.isDigit char
