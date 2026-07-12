module Application.Helper.FrontendContract.Surface.Architecture
    ( frontendSurfaceArchitectureContractsValue
    ) where

import Application.Helper.FrontendContract.Core (htmxMethodText)
import Application.Helper.FrontendContract.Surface.ContractIR
import Application.Helper.FrontendContract.Surface.Contracts (registeredFrontendSurfaceContractIR)
import qualified Data.Aeson as Aeson
import qualified Data.List as List
import qualified Data.Text as Text
import IHP.Prelude

-- | Deterministic architecture facts rendered from the same checked reflected
-- Surface contract used by runtime behavior and frontend contract generation.
frontendSurfaceArchitectureContractsValue :: Aeson.Value
frontendSurfaceArchitectureContractsValue = Aeson.object
    [ "evaluator" Aeson..= ("typeclass-reflection" :: Text)
    , "source" Aeson..= ("Application.Helper.FrontendContract.Surface.Contracts.registeredFrontendSurfaceContractIR" :: Text)
    , "surfaces" Aeson..= map surfaceValue registeredFrontendSurfaceContractIR.contractSurfaces
    ]

surfaceValue :: SurfaceIR -> Aeson.Value
surfaceValue surface = Aeson.object
    [ "marker" Aeson..= surface.surfaceMarker
    , "name" Aeson..= surface.surfaceName
    , "scopes" Aeson..= map scopeValue surface.surfaceScopes
    , "mountStates" Aeson..= map mountStateValue surface.surfaceMountStates
    , "fragments" Aeson..= map fragmentValue surface.surfaceFragments
    , "actions" Aeson..= map actionValue surface.surfaceHtmxActions
    , "intents" Aeson..= map intentValue surface.surfaceIntents
    , "sessions" Aeson..= surface.surfaceSessions
    , "sourceRefs" Aeson..= map (.sourceRefName) surface.surfaceSourceRefs
    , "dropzoneRefs" Aeson..= map (.dropzoneRefName) surface.surfaceDropzoneRefs
    , "activationRefs" Aeson..= map (.activationRefName) surface.surfaceActivationRefs
    , "resources" Aeson..= map resourceValue (surfaceResources surface)
    ]

scopeValue :: ScopeIR -> Aeson.Value
scopeValue scope = Aeson.object
    [ "marker" Aeson..= scope.scopeMarker
    , "name" Aeson..= scope.scopeName
    , "fields" Aeson..= map fieldValue scope.scopeFields
    , "authorization" Aeson..= map scopeAuthorizationValue scope.scopeOptions
    ]

scopeAuthorizationValue :: ScopeAuthIR -> Aeson.Value
scopeAuthorizationValue = \case
    NoAuthIR -> Aeson.object
        [ "kind" Aeson..= ("none" :: Text)
        ]
    AuthorizeIR policy fields -> Aeson.object
        [ "kind" Aeson..= ("authorize" :: Text)
        , "policy" Aeson..= policy
        , "fields" Aeson..= fields
        ]

mountStateValue :: MountStateIR -> Aeson.Value
mountStateValue mountState = Aeson.object
    [ "marker" Aeson..= mountState.mountStateMarker
    , "name" Aeson..= mountState.mountStateName
    , "fields" Aeson..= map fieldValue mountState.mountStateFields
    ]

fragmentValue :: FragmentIR -> Aeson.Value
fragmentValue fragment = Aeson.object
    [ "marker" Aeson..= fragment.fragmentMarker
    , "name" Aeson..= fragment.fragmentName
    , "params" Aeson..= map fieldValue fragment.fragmentParams
    , "live" Aeson..= hasOption isLiveOption fragment.fragmentOptions
    , "resyncOnly" Aeson..= hasOption isResyncOnlyOption fragment.fragmentOptions
    , "dependsOnFragments" Aeson..= collectOptionTexts dependsOnFragmentName fragment.fragmentOptions
    , "containsSurfaces" Aeson..= collectOptionTexts containedSurfaceName fragment.fragmentOptions
    , "resources" Aeson..= map resourceDependencyValue (optionResourceDependencies fragment.fragmentOptions)
    ]

actionValue :: HtmxActionIR -> Aeson.Value
actionValue action = Aeson.object
    [ "marker" Aeson..= action.htmxActionMarker
    , "name" Aeson..= action.htmxActionName
    , "fields" Aeson..= map fieldValue action.htmxActionFields
    , "method" Aeson..= listToMaybe (collectOptions actionMethod action.htmxActionOptions)
    , "targetFragment" Aeson..= listToMaybe (collectOptionTexts targetFragmentName action.htmxActionOptions)
    , "targetDomToken" Aeson..= listToMaybe (collectOptionTexts targetDomTokenName action.htmxActionOptions)
    , "swap" Aeson..= listToMaybe (collectOptionTexts swapName action.htmxActionOptions)
    ]

intentValue :: IntentIR -> Aeson.Value
intentValue intent = Aeson.object
    [ "marker" Aeson..= intent.intentMarker
    , "name" Aeson..= intent.intentName
    , "fields" Aeson..= map fieldValue intent.intentFields
    , "backedBy" Aeson..= listToMaybe (collectOptionTexts backedByActionName intent.intentOptions)
    , "session" Aeson..= listToMaybe (collectOptionTexts sessionName intent.intentOptions)
    ]

fieldValue :: FieldIR -> Aeson.Value
fieldValue field = Aeson.object
    [ "marker" Aeson..= field.fieldMarker
    , "name" Aeson..= field.fieldName
    , "wire" Aeson..= wireName field.fieldWire
    , "presence" Aeson..= fieldPresenceName field.fieldPresence
    , "brand" Aeson..= fieldBrandName field
    ]

fieldBrandName :: FieldIR -> Maybe Text
fieldBrandName field
    | "Id" `Text.isSuffixOf` field.fieldMarker = Just field.fieldMarker
    | otherwise = Nothing

resourceDependencyValue :: ResourceDependencyIR -> Aeson.Value
resourceDependencyValue dependency = Aeson.object
    [ "resource" Aeson..= dependency.dependencyResource.resourceName
    , "sources" Aeson..= map resourceSourceValue dependency.dependencySources
    ]

resourceValue :: ResourceIR -> Aeson.Value
resourceValue resource = Aeson.object
    [ "marker" Aeson..= resource.resourceMarker
    , "name" Aeson..= resource.resourceName
    , "fields" Aeson..= map fieldValue resource.resourceFields
    ]

resourceSourceValue :: ResourceSourceIR -> Aeson.Value
resourceSourceValue = \case
    FromScopeIR field -> Aeson.object
        [ "kind" Aeson..= ("scope" :: Text)
        , "field" Aeson..= field
        ]
    FromFragmentIR field -> Aeson.object
        [ "kind" Aeson..= ("fragment" :: Text)
        , "field" Aeson..= field
        ]

surfaceResources :: SurfaceIR -> [ResourceIR]
surfaceResources surface =
    surface.surfaceFragments
        |> concatMap (optionResourceDependencies . (.fragmentOptions))
        |> map (.dependencyResource)
        |> List.nub

hasOption :: (OptionIR -> Bool) -> [OptionIR] -> Bool
hasOption predicate = any predicate . allOptions

collectOptionTexts :: (OptionIR -> Maybe Text) -> [OptionIR] -> [Text]
collectOptionTexts project = mapMaybe project . allOptions

collectOptions :: (OptionIR -> Maybe value) -> [OptionIR] -> [value]
collectOptions project = mapMaybe project . allOptions

allOptions :: [OptionIR] -> [OptionIR]
allOptions = concatMap \option -> option : nestedOptions option
    where
        nestedOptions = \case
            LazyOption options -> allOptions options
            EffectOption _ options -> allOptions options
            ModifierVariantOption variant -> concatMap (allOptions . snd) variant.modifierVariantEffects
            _ -> []

isLiveOption :: OptionIR -> Bool
isLiveOption = \case
    LiveOption -> True
    _ -> False

isResyncOnlyOption :: OptionIR -> Bool
isResyncOnlyOption = \case
    ResyncOnlyOption -> True
    _ -> False

dependsOnFragmentName :: OptionIR -> Maybe Text
dependsOnFragmentName = \case
    DependsOnFragmentOption name -> Just name
    _ -> Nothing

containedSurfaceName :: OptionIR -> Maybe Text
containedSurfaceName = \case
    ContainsSurfaceOption name -> Just name
    _ -> Nothing

targetFragmentName :: OptionIR -> Maybe Text
targetFragmentName = \case
    TargetOption name -> Just name
    _ -> Nothing

targetDomTokenName :: OptionIR -> Maybe Text
targetDomTokenName = \case
    HtmxOption (HtmxActionTargetIR name) -> Just name
    _ -> Nothing

swapName :: OptionIR -> Maybe Text
swapName = \case
    HtmxOption (HtmxActionSwapIR name) -> Just name
    _ -> Nothing

backedByActionName :: OptionIR -> Maybe Text
backedByActionName = \case
    BackedByOption name -> Just name
    _ -> Nothing

sessionName :: OptionIR -> Maybe Text
sessionName = \case
    SessionOptionIR name -> Just name
    _ -> Nothing

actionMethod :: OptionIR -> Maybe Text
actionMethod = \case
    HtmxOption (HtmxActionMethodIR method) -> Just (htmxMethodText method)
    _ -> Nothing

fieldPresenceName :: FieldPresence -> Text
fieldPresenceName = \case
    RequiredField -> "required"
    OptionalFieldPresence -> "optional"
    NullableFieldPresence -> "nullable"

wireName :: WireIR -> Text
wireName = \case
    WireTextIR -> "text"
    WireIntIR -> "int"
    WireBoolIR -> "bool"
    WireUuidIR -> "uuid"
    WireDayIR -> "day"
    WireUnknownIR -> "unknown"
    WireListIR wire -> "list<" <> wireName wire <> ">"
    WireMapIR key value -> "map<" <> wireName key <> "," <> wireName value <> ">"
    WireOptionalIR wire -> "optional<" <> wireName wire <> ">"
    WireNullableIR wire -> "nullable<" <> wireName wire <> ">"
    WireRefIR name -> "ref<" <> name <> ">"
    WireSurfaceScopeIR -> "surface-scope"
    WireSurfaceFragmentKeyIR -> "surface-fragment-key"
    WireSurfaceWireFragmentIR -> "surface-wire-fragment"
