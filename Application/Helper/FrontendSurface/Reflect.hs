{-# LANGUAGE AllowAmbiguousTypes  #-}
{-# LANGUAGE DataKinds            #-}
{-# LANGUAGE FlexibleInstances    #-}
{-# LANGUAGE PolyKinds            #-}
{-# LANGUAGE ScopedTypeVariables  #-}
{-# LANGUAGE TypeApplications     #-}
{-# LANGUAGE TypeOperators        #-}
{-# LANGUAGE UndecidableInstances #-}

module Application.Helper.FrontendSurface.Reflect
    ( ReflectSurfaceRegistry (..)
    , ReflectSurfaceSpec (..)
    , reflectRegisteredFrontendSurfaces
    ) where

import Application.Helper.FrontendSurface.ContractIR
import Application.Helper.FrontendSurface.DSL
import Application.Helper.FrontendSurface.Naming (FrontendSurfaceNameContext (..),
                                                  deriveFrontendSurfaceName)
import Application.Helper.FrontendSurface.Registry (RegisteredFrontendSurfaces)
import qualified Data.List as List
import qualified Data.Text as Text
import Data.Typeable (Proxy (..), Typeable, tyConName, typeRep, typeRepTyCon)
import IHP.Prelude

reflectRegisteredFrontendSurfaces :: SurfaceContractIR
reflectRegisteredFrontendSurfaces =
    SurfaceContractIR { contractSurfaces = reflectSurfaceRegistry @RegisteredFrontendSurfaces }

class ReflectSurfaceRegistry (surfaces :: [SurfaceSpec]) where
    reflectSurfaceRegistry :: [SurfaceIR]

instance ReflectSurfaceRegistry '[] where
    reflectSurfaceRegistry = []

instance (ReflectSurfaceSpec surface, ReflectSurfaceRegistry rest) => ReflectSurfaceRegistry (surface ': rest) where
    reflectSurfaceRegistry = reflectSurfaceSpec @surface : reflectSurfaceRegistry @rest

class ReflectSurfaceSpec (surface :: SurfaceSpec) where
    reflectSurfaceSpec :: SurfaceIR

instance (Typeable marker, ReflectPrimitiveList primitives) => ReflectSurfaceSpec ('Surface marker primitives) where
    reflectSurfaceSpec =
        emptySurface
            { surfaceMarker = typeMarker @marker
            , surfaceName = protocolName @marker SurfaceName
            }
            |> addPrimitives (reflectPrimitiveList @primitives)

class ReflectPrimitiveList (primitives :: [SurfacePrimitive]) where
    reflectPrimitiveList :: [ReflectedPrimitive]

instance ReflectPrimitiveList '[] where
    reflectPrimitiveList = []

instance (ReflectPrimitive primitive, ReflectPrimitiveList rest) => ReflectPrimitiveList (primitive ': rest) where
    reflectPrimitiveList = reflectPrimitive @primitive : reflectPrimitiveList @rest

data ReflectedPrimitive
    = ReflectedScope !ScopeIR
    | ReflectedMountState !MountStateIR
    | ReflectedFragment !FragmentIR
    | ReflectedHtmxAction !HtmxActionIR
    | ReflectedIntent !IntentIR
    | ReflectedSessionWithOptions !Text ![OptionIR]
    | ReflectedLayer !Text
    | ReflectedEffect !Text ![OptionIR]
    | ReflectedPolicy !ConflictPolicyIR
    | ReflectedLoadPolicy !Text
    | ReflectedOverlayLane !Text
    | ReflectedClientEvent !Text ![FieldIR]
    | ReflectedDomToken !Text
    | ReflectedDto !Text ![FieldIR]

class ReflectPrimitive (primitive :: SurfacePrimitive) where
    reflectPrimitive :: ReflectedPrimitive

instance (Typeable marker, ReflectFieldList fields) => ReflectPrimitive ('Scope marker fields) where
    reflectPrimitive = ReflectedScope ScopeIR
        { scopeMarker = typeMarker @marker
        , scopeName = protocolName @marker ScopeName
        , scopeFields = reflectFieldList @fields
        }

instance (Typeable marker, ReflectFieldList fields) => ReflectPrimitive ('MountState marker fields) where
    reflectPrimitive = ReflectedMountState MountStateIR
        { mountStateMarker = typeMarker @marker
        , mountStateName = protocolName @marker ScopeName
        , mountStateFields = reflectFieldList @fields
        }

instance (Typeable marker, ReflectFieldList fields, ReflectOptionList options) => ReflectPrimitive ('Fragment marker fields options) where
    reflectPrimitive = ReflectedFragment FragmentIR
        { fragmentMarker = typeMarker @marker
        , fragmentName = protocolName @marker FragmentName
        , fragmentParams = reflectFieldList @fields
        , fragmentOptions = reflectOptionList @options
        }

instance (Typeable marker, ReflectFieldList fields, ReflectOptionList options) => ReflectPrimitive ('Action marker fields options) where
    reflectPrimitive = ReflectedHtmxAction HtmxActionIR
        { htmxActionMarker = typeMarker @marker
        , htmxActionName = protocolName @marker ActionName
        , htmxActionFields = reflectFieldList @fields
        , htmxActionOptions = reflectOptionList @options
        }

instance (Typeable marker, ReflectFieldList fields, ReflectOptionList options) => ReflectPrimitive ('Intent marker fields options) where
    reflectPrimitive = ReflectedIntent IntentIR
        { intentMarker = typeMarker @marker
        , intentName = protocolName @marker IntentName
        , intentFields = reflectFieldList @fields
        , intentOptions = reflectOptionList @options
        }

instance (Typeable marker, ReflectOptionList options) => ReflectPrimitive ('Session marker options) where
    reflectPrimitive = ReflectedSessionWithOptions (protocolName @marker SessionName) (reflectOptionList @options)

instance (ReflectSessionSelector session, ReflectFragmentSelector fragment, ReflectConflictResolution resolution) => ReflectPrimitive ('ConflictPolicy session fragment resolution) where
    reflectPrimitive = ReflectedPolicy ConflictPolicyIR
        { conflictPolicySession = reflectSessionSelector @session
        , conflictPolicyFragment = reflectFragmentSelector @fragment
        , conflictPolicyResolution = reflectConflictResolution @resolution
        }

instance (Typeable marker, ReflectFieldList fields) => ReflectPrimitive ('Event marker fields) where
    reflectPrimitive = ReflectedClientEvent (protocolName @marker EventName) (reflectFieldList @fields)

instance Typeable marker => ReflectPrimitive ('DomToken marker) where
    reflectPrimitive = ReflectedDomToken (protocolName @marker DomTokenName)

instance (Typeable marker, ReflectFieldList fields) => ReflectPrimitive ('Dto marker fields) where
    reflectPrimitive = ReflectedDto (protocolName @marker ScopeName) (reflectFieldList @fields)

class ReflectFieldList (fields :: [FieldSpec]) where
    reflectFieldList :: [FieldIR]

instance ReflectFieldList '[] where
    reflectFieldList = []

instance (ReflectField field, ReflectFieldList rest) => ReflectFieldList (field ': rest) where
    reflectFieldList = reflectField @field : reflectFieldList @rest

class ReflectField (field :: FieldSpec) where
    reflectField :: FieldIR

instance (Typeable marker, ReflectWire wire) => ReflectField ('Field marker wire) where
    reflectField = reflectedField @marker @wire RequiredField

instance (Typeable marker, ReflectWire wire) => ReflectField ('OptionalField marker wire) where
    reflectField = reflectedField @marker @wire OptionalFieldPresence

instance (Typeable marker, ReflectWire wire) => ReflectField ('NullableField marker wire) where
    reflectField = reflectedField @marker @wire NullableFieldPresence

class ReflectWire (wire :: WireType) where
    reflectWire :: WireIR

instance ReflectWire 'WireText where reflectWire = WireTextIR
instance ReflectWire 'WireInt where reflectWire = WireIntIR
instance ReflectWire 'WireBool where reflectWire = WireBoolIR
instance ReflectWire 'WireUUID where reflectWire = WireUuidIR
instance ReflectWire 'WireDay where reflectWire = WireDayIR
instance ReflectWire inner => ReflectWire ('WireList inner) where reflectWire = WireListIR (reflectWire @inner)
instance ReflectWire inner => ReflectWire ('WireOptional inner) where reflectWire = WireOptionalIR (reflectWire @inner)
instance ReflectWire inner => ReflectWire ('WireNullable inner) where reflectWire = WireNullableIR (reflectWire @inner)
instance Typeable marker => ReflectWire ('WireRef marker) where reflectWire = WireRefIR (protocolName @marker ScopeName)

class ReflectOptionList (options :: [PrimitiveOption]) where
    reflectOptionList :: [OptionIR]

instance ReflectOptionList '[] where
    reflectOptionList = []

instance (ReflectOption option, ReflectOptionList rest) => ReflectOptionList (option ': rest) where
    reflectOptionList = reflectOption @option : reflectOptionList @rest

class ReflectOption (option :: PrimitiveOption) where
    reflectOption :: OptionIR

instance ReflectOption 'Eager where reflectOption = EagerOption
instance ReflectOption 'Live where reflectOption = LiveOption
instance ReflectOptionList options => ReflectOption ('Lazy options) where reflectOption = LazyOption (reflectOptionList @options)
instance Typeable marker => ReflectOption ('Trigger marker) where reflectOption = TriggerOption (protocolName @marker DomTokenName)
instance Typeable marker => ReflectOption ('Placeholder marker) where reflectOption = PlaceholderOption (protocolName @marker DomTokenName)
instance Typeable marker => ReflectOption ('DependsOn marker) where reflectOption = DependsOnOption (protocolName @marker DomTokenName)
instance Typeable marker => ReflectOption ('Target marker) where reflectOption = TargetOption (protocolName @marker FragmentName)
instance Typeable marker => ReflectOption ('BackedBy marker) where reflectOption = BackedByOption (protocolName @marker ActionName)
instance Typeable marker => ReflectOption ('Layer marker) where reflectOption = LayerOption (protocolName @marker LayerName)
instance (Typeable marker, ReflectOptionList options) => ReflectOption ('Effect marker options) where reflectOption = EffectOption (protocolName @marker ActionName) (reflectOptionList @options)
instance Typeable marker => ReflectOption ('SessionOption marker) where reflectOption = SessionOptionIR (protocolName @marker SessionName)
instance Typeable marker => ReflectOption ('Emits marker) where reflectOption = EmitsOption (protocolName @marker EventName)
instance Typeable marker => ReflectOption ('Contains marker) where reflectOption = ContainsOption (protocolName @marker DomTokenName)
instance Typeable marker => ReflectOption ('ContainsSurface marker) where reflectOption = ContainsSurfaceOption (protocolName @marker SurfaceName)
instance Typeable marker => ReflectOption ('UsesDto marker) where reflectOption = UsesDtoOption (protocolName @marker ScopeName)

class ReflectSessionSelector (selector :: SessionSelector) where
    reflectSessionSelector :: SessionSelectorIR

instance ReflectSessionSelector 'AnySession where
    reflectSessionSelector = AnySessionIR

instance Typeable marker => ReflectSessionSelector ('SessionKind marker) where
    reflectSessionSelector = SessionKindIR (protocolName @marker SessionName)

class ReflectFragmentSelector (selector :: FragmentSelector) where
    reflectFragmentSelector :: FragmentSelectorIR

instance ReflectFragmentSelector 'AnyFragment where
    reflectFragmentSelector = AnyFragmentIR

instance Typeable marker => ReflectFragmentSelector ('FragmentKind marker) where
    reflectFragmentSelector = FragmentKindIR (protocolName @marker FragmentName)

instance Typeable marker => ReflectFragmentSelector ('FragmentSubtree marker) where
    reflectFragmentSelector = FragmentSubtreeIR (protocolName @marker FragmentName)

class ReflectConflictResolution (resolution :: ConflictResolution) where
    reflectConflictResolution :: ConflictResolutionIR

instance ReflectConflictResolution 'Apply where reflectConflictResolution = ApplyIR
instance ReflectConflictResolution 'Defer where reflectConflictResolution = DeferIR
instance ReflectConflictResolution 'Cancel where reflectConflictResolution = CancelIR

addPrimitives :: [ReflectedPrimitive] -> SurfaceIR -> SurfaceIR
addPrimitives primitives surface =
    foldl' addPrimitive surface primitives
    where
        addPrimitive current = \case
            ReflectedScope scope -> current { surfaceScopes = current.surfaceScopes <> [scope] }
            ReflectedMountState mountState -> current { surfaceMountStates = current.surfaceMountStates <> [mountState] }
            ReflectedFragment fragment -> current { surfaceFragments = current.surfaceFragments <> [fragment] }
            ReflectedHtmxAction action -> current { surfaceHtmxActions = current.surfaceHtmxActions <> [action] }
            ReflectedIntent intent -> current { surfaceIntents = current.surfaceIntents <> [intent] }
            ReflectedSessionWithOptions name options -> current { surfaceSessions = current.surfaceSessions <> [name] } |> addOptionMetadata options
            ReflectedLayer name -> current { surfaceLayers = current.surfaceLayers <> [name] }
            ReflectedEffect name options -> current { surfaceEffects = current.surfaceEffects <> [(name, options)] }
            ReflectedPolicy policy -> current { surfacePolicies = current.surfacePolicies <> [policy] }
            ReflectedLoadPolicy name -> current { surfaceLoadPolicies = current.surfaceLoadPolicies <> [name] }
            ReflectedOverlayLane name -> current { surfaceOverlayLanes = current.surfaceOverlayLanes <> [name] }
            ReflectedClientEvent name fields -> current { surfaceClientEvents = current.surfaceClientEvents <> [(name, fields)] }
            ReflectedDomToken name -> current { surfaceDomTokens = current.surfaceDomTokens <> [name] }
            ReflectedDto name fields -> current { surfaceDtos = current.surfaceDtos <> [(name, fields)] }

addOptionMetadata :: [OptionIR] -> SurfaceIR -> SurfaceIR
addOptionMetadata options surface =
    surface
        { surfaceLayers = List.nub (surface.surfaceLayers <> layersIn options)
        , surfaceEffects = List.nub (surface.surfaceEffects <> effectsIn options)
        }
    where
        layersIn = concatMap \case
            LazyOption nested -> layersIn nested
            LayerOption name -> [name]
            EffectOption _ nested -> layersIn nested
            _ -> []
        effectsIn = concatMap \case
            LazyOption nested -> effectsIn nested
            EffectOption name nested -> (name, nested) : effectsIn nested
            _ -> []

emptySurface :: SurfaceIR
emptySurface = SurfaceIR
    { surfaceMarker = ""
    , surfaceName = ""
    , surfaceScopes = []
    , surfaceMountStates = []
    , surfaceFragments = []
    , surfaceHtmxActions = []
    , surfaceIntents = []
    , surfaceSessions = []
    , surfaceLayers = []
    , surfaceEffects = []
    , surfacePolicies = []
    , surfaceLoadPolicies = []
    , surfaceOverlayLanes = []
    , surfaceClientEvents = []
    , surfaceDomTokens = []
    , surfaceDtos = []
    }

reflectedField :: forall marker wire. (Typeable marker, ReflectWire wire) => FieldPresence -> FieldIR
reflectedField presence =
    FieldIR
        { fieldMarker = marker
        , fieldName = deriveFrontendSurfaceName FieldName marker
        , fieldWire = reflectWire @wire
        , fieldPresence = presence
        , fieldBrand = brandName marker
        }
    where
        marker = typeMarker @marker

brandName :: Text -> Maybe Text
brandName marker
    | "Id" `Text.isSuffixOf` marker = Just marker
    | otherwise = Nothing

typeMarker :: forall marker. Typeable marker => Text
typeMarker = cs (tyConName (typeRepTyCon (typeRep (Proxy @marker))))

protocolName :: forall marker. Typeable marker => FrontendSurfaceNameContext -> Text
protocolName context = deriveFrontendSurfaceName context (typeMarker @marker)
