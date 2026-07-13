{-# LANGUAGE AllowAmbiguousTypes  #-}
{-# LANGUAGE DataKinds            #-}
{-# LANGUAGE FlexibleInstances    #-}
{-# LANGUAGE PolyKinds            #-}
{-# LANGUAGE ScopedTypeVariables  #-}
{-# LANGUAGE TypeApplications     #-}
{-# LANGUAGE TypeOperators        #-}
{-# LANGUAGE UndecidableInstances #-}

module Application.Helper.FrontendContract.Surface.Reflect
    ( ReflectedPrimitive (..)
    , ReflectPrimitive (..)
    , ReflectResource (..)
    , ReflectSurfaceRegistry (..)
    , ReflectSurfaceSpec (..)
    , reflectRegisteredFrontendSurfaces
    ) where

import Application.Helper.FrontendContract.Naming (FrontendSurfaceNameContext (..),
                                                   deriveFrontendSurfaceName)
import Application.Helper.FrontendContract.Surface.ContractIR
import Application.Helper.FrontendContract.Surface.DSL
import Application.Helper.FrontendContract.Surface.Registry (RegisteredFrontendSurfaces)
import qualified Data.List as List
import Data.Typeable (tyConName, typeRep, typeRepTyCon)
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
    | ReflectedSourceRef !InteractionSourceRefIR
    | ReflectedDropzoneRef !InteractionDropzoneRefIR
    | ReflectedActivationRef !InteractionActivationRefIR
    | ReflectedLayer !Text
    | ReflectedEffect !Text ![OptionIR]
    | ReflectedPolicy !ConflictPolicyIR
    | ReflectedLoadPolicy !Text
    | ReflectedOverlayLane !Text
    | ReflectedClientEvent !Text ![FieldIR]
    | ReflectedDomToken !Text
    | ReflectedBrowserDomToken !Text
    | ReflectedDto !Text ![FieldIR]

class ReflectPrimitive (primitive :: SurfacePrimitive) where
    reflectPrimitive :: ReflectedPrimitive

instance (Typeable marker, ReflectFieldList fields, ReflectScopeOptionList options) => ReflectPrimitive ('Scope marker fields options) where
    reflectPrimitive = ReflectedScope ScopeIR
        { scopeMarker = typeMarker @marker
        , scopeName = protocolName @marker ScopeName
        , scopeFields = reflectFieldList @fields
        , scopeOptions = reflectScopeOptionList @options
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

instance (Typeable marker, ReflectOptionList options) => ReflectPrimitive ('SourceRef marker options) where
    reflectPrimitive =
        let options = reflectOptionList @options
         in ReflectedSourceRef InteractionSourceRefIR
            { sourceRefMarker = typeMarker @marker
            , sourceRefName = protocolName @marker InteractionRefName
            , sourceRefSession = requiredOption "source ref" (typeMarker @marker) "SessionOption" [name | SessionOptionIR name <- options]
            , sourceRefIntent = requiredOption "source ref" (typeMarker @marker) "Submits" [name | SubmitsOption name <- options]
            , sourceRefSourceField = requiredOption "source ref" (typeMarker @marker) "SourceField" [name | SourceFieldOption name <- options]
            , sourceRefCompatibleDropzones = [name | CompatibleDropzoneOption name <- options]
            , sourceRefVariants = [variant | ModifierVariantOption variant <- options]
            }

instance (Typeable marker, ReflectOptionList options) => ReflectPrimitive ('DropzoneRef marker options) where
    reflectPrimitive =
        let options = reflectOptionList @options
         in ReflectedDropzoneRef InteractionDropzoneRefIR
            { dropzoneRefMarker = typeMarker @marker
            , dropzoneRefName = protocolName @marker InteractionRefName
            , dropzoneRefSession = requiredOption "dropzone ref" (typeMarker @marker) "SessionOption" [name | SessionOptionIR name <- options]
            , dropzoneRefTargetField = requiredOption "dropzone ref" (typeMarker @marker) "TargetField" [name | TargetFieldOption name <- options]
            }

instance (Typeable marker, ReflectOptionList options) => ReflectPrimitive ('ActivationRef marker options) where
    reflectPrimitive =
        let options = reflectOptionList @options
         in ReflectedActivationRef InteractionActivationRefIR
            { activationRefMarker = typeMarker @marker
            , activationRefName = protocolName @marker InteractionRefName
            , activationRefIntent = requiredOption "activation ref" (typeMarker @marker) "Submits" [name | SubmitsOption name <- options]
            , activationRefValueField = optionalUniqueOption "activation ref" (typeMarker @marker) "ValueField" [name | ValueFieldOption name <- options]
            , activationRefTrigger = "click"
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

instance Typeable marker => ReflectPrimitive ('BrowserDomToken marker) where
    reflectPrimitive = ReflectedBrowserDomToken (protocolName @marker DomTokenName)

instance (Typeable marker, ReflectFieldList fields) => ReflectPrimitive ('Dto marker fields) where
    reflectPrimitive = ReflectedDto (typeMarker @marker) (reflectFieldList @fields)

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
instance Typeable marker => ReflectWire ('WireRef marker) where reflectWire = WireRefIR (typeMarker @marker)

class ReflectScopeOptionList (options :: [ScopeOption]) where
    reflectScopeOptionList :: [ScopeAuthIR]

instance ReflectScopeOptionList '[] where
    reflectScopeOptionList = []

instance (ReflectScopeOption option, ReflectScopeOptionList rest) => ReflectScopeOptionList (option ': rest) where
    reflectScopeOptionList = reflectScopeOption @option : reflectScopeOptionList @rest

class ReflectScopeOption (option :: ScopeOption) where
    reflectScopeOption :: ScopeAuthIR

instance ReflectScopeOption 'NoAuth where
    reflectScopeOption = NoAuthIR

instance (ReflectAuthPolicy policy, ReflectMarkerList fields) => ReflectScopeOption ('Authorize policy fields) where
    reflectScopeOption = AuthorizeIR (reflectAuthPolicy @policy) (reflectMarkerList @fields FieldName)

class ReflectAuthPolicy (policy :: AuthPolicy) where
    reflectAuthPolicy :: Text

instance ReflectAuthPolicy 'CurrentVenue where reflectAuthPolicy = "current-venue"
instance ReflectAuthPolicy 'CurrentVenueUser where reflectAuthPolicy = "current-venue-user"
instance ReflectAuthPolicy 'CurrentVenueStaff where reflectAuthPolicy = "current-venue-staff"
instance ReflectAuthPolicy 'CurrentVenueRosterGroup where reflectAuthPolicy = "current-venue-roster-group"
instance ReflectAuthPolicy 'CurrentVenueAdmin where reflectAuthPolicy = "current-venue-admin"
instance ReflectAuthPolicy 'CurrentVenueManager where reflectAuthPolicy = "current-venue-manager"
instance ReflectAuthPolicy 'CurrentVenueOwner where reflectAuthPolicy = "current-venue-owner"
instance ReflectAuthPolicy 'CurrentVenueAdminRosterGroup where reflectAuthPolicy = "current-venue-admin-roster-group"
instance ReflectAuthPolicy 'SupportSuperAdmin where reflectAuthPolicy = "support-super-admin"

class ReflectMarkerList (markers :: [Type]) where
    reflectMarkerList :: FrontendSurfaceNameContext -> [Text]

instance ReflectMarkerList '[] where
    reflectMarkerList _ = []

instance (Typeable marker, ReflectMarkerList rest) => ReflectMarkerList (marker ': rest) where
    reflectMarkerList context = protocolName @marker context : reflectMarkerList @rest context

class ReflectResource (resource :: ResourceSpec) where
    reflectResource :: ResourceIR

instance (Typeable marker, ReflectFieldList fields) => ReflectResource ('Resource marker fields) where
    reflectResource = ResourceIR
        { resourceMarker = typeMarker @marker
        , resourceName = protocolName @marker ScopeName
        , resourceFields = reflectFieldList @fields
        }

class ReflectDependencySourceList (sources :: [DependencySource]) where
    reflectDependencySourceList :: [ResourceSourceIR]

instance ReflectDependencySourceList '[] where
    reflectDependencySourceList = []

instance (ReflectDependencySource source, ReflectDependencySourceList rest) => ReflectDependencySourceList (source ': rest) where
    reflectDependencySourceList = reflectDependencySource @source : reflectDependencySourceList @rest

class ReflectDependencySource (source :: DependencySource) where
    reflectDependencySource :: ResourceSourceIR

instance Typeable marker => ReflectDependencySource ('FromScope marker) where
    reflectDependencySource = FromScopeIR (protocolName @marker FieldName)

instance Typeable marker => ReflectDependencySource ('FromFragment marker) where
    reflectDependencySource = FromFragmentIR (protocolName @marker FieldName)

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
instance ReflectOption 'ResyncOnly where reflectOption = ResyncOnlyOption
instance ReflectOptionList options => ReflectOption ('Lazy options) where reflectOption = LazyOption (reflectOptionList @options)
instance Typeable marker => ReflectOption ('Trigger marker) where reflectOption = TriggerOption (protocolName @marker DomTokenName)
instance Typeable marker => ReflectOption ('Placeholder marker) where reflectOption = PlaceholderOption (protocolName @marker DomTokenName)
instance (ReflectResource resource, ReflectDependencySourceList sources) => ReflectOption ('DependsOn resource sources) where
    reflectOption = DependsOnOption ResourceDependencyIR
        { dependencyResource = reflectResource @resource
        , dependencySources = reflectDependencySourceList @sources
        }
instance Typeable marker => ReflectOption ('DependsOnFragment marker) where reflectOption = DependsOnFragmentOption (protocolName @marker FragmentName)
instance (Typeable marker, ReflectFieldList fields) => ReflectOption ('MountTarget marker fields) where
    reflectOption = MountTargetOption (protocolName @marker DomTokenName) (reflectFieldList @fields)
instance Typeable marker => ReflectOption ('Target marker) where reflectOption = TargetOption (protocolName @marker FragmentName)
instance Typeable marker => ReflectOption ('BackedBy marker) where reflectOption = BackedByOption (protocolName @marker ActionName)
instance Typeable marker => ReflectOption ('Layer marker) where reflectOption = LayerOption (protocolName @marker LayerName)
instance (Typeable marker, ReflectOptionList options) => ReflectOption ('Effect marker options) where reflectOption = EffectOption (protocolName @marker ActionName) (reflectOptionList @options)
instance (Typeable semantic, Typeable intent, ReflectOptionList effects) => ReflectOption ('ModifierVariant semantic intent effects) where
    reflectOption = ModifierVariantOption InteractionModifierVariantIR
        { modifierVariantSemantic = protocolName @semantic ActionName
        , modifierVariantIntent = protocolName @intent IntentName
        , modifierVariantEffects = effectsInOptions (reflectOptionList @effects)
        }
instance Typeable marker => ReflectOption ('SessionOption marker) where reflectOption = SessionOptionIR (protocolName @marker SessionName)
instance Typeable marker => ReflectOption ('Submits marker) where reflectOption = SubmitsOption (protocolName @marker IntentName)
instance Typeable marker => ReflectOption ('SourceField marker) where reflectOption = SourceFieldOption (protocolName @marker FieldName)
instance Typeable marker => ReflectOption ('TargetField marker) where reflectOption = TargetFieldOption (protocolName @marker FieldName)
instance Typeable marker => ReflectOption ('CompatibleDropzone marker) where reflectOption = CompatibleDropzoneOption (protocolName @marker InteractionRefName)
instance Typeable marker => ReflectOption ('ValueField marker) where reflectOption = ValueFieldOption (protocolName @marker FieldName)
instance Typeable marker => ReflectOption ('Emits marker) where reflectOption = EmitsOption (protocolName @marker EventName)
instance Typeable marker => ReflectOption ('Contains marker) where reflectOption = ContainsOption (protocolName @marker DomTokenName)
instance Typeable marker => ReflectOption ('ContainsSurface marker) where reflectOption = ContainsSurfaceOption (protocolName @marker SurfaceName)
instance Typeable marker => ReflectOption ('UsesDto marker) where reflectOption = UsesDtoOption (typeMarker @marker)
instance ReflectHtmxMethod method => ReflectOption ('HtmxMethod method) where reflectOption = HtmxOption (HtmxActionMethodIR (reflectHtmxMethod @method))
instance ReflectHtmxTrigger trigger => ReflectOption ('HtmxTrigger trigger) where reflectOption = HtmxOption (HtmxActionTriggerIR (reflectHtmxTrigger @trigger))
instance ReflectHtmxSelector selector => ReflectOption ('HtmxInclude selector) where reflectOption = HtmxOption (HtmxActionIncludeIR (reflectHtmxSelector @selector))
instance ReflectHtmxSync sync => ReflectOption ('HtmxSync sync) where reflectOption = HtmxOption (HtmxActionSyncIR (reflectHtmxSync @sync))
instance ReflectHtmxSelector selector => ReflectOption ('HtmxIndicator selector) where reflectOption = HtmxOption (HtmxActionIndicatorIR (reflectHtmxSelector @selector))
instance Typeable marker => ReflectOption ('HtmxConfirm marker) where reflectOption = HtmxOption (HtmxActionConfirmIR (protocolName @marker DomTokenName))
instance ReflectHtmxSelector selector => ReflectOption ('HtmxSelect selector) where reflectOption = HtmxOption (HtmxActionSelectIR (reflectHtmxSelector @selector))
instance ReflectHtmxSelector selector => ReflectOption ('HtmxTarget selector) where reflectOption = HtmxOption (HtmxActionTargetIR (reflectHtmxSelector @selector))
instance ReflectHtmxSwap swap => ReflectOption ('HtmxSwap swap) where reflectOption = HtmxOption (HtmxActionSwapIR (reflectHtmxSwap @swap))
instance ReflectHtmxPushUrl value => ReflectOption ('HtmxPushUrl value) where reflectOption = HtmxOption (HtmxActionPushUrlIR (reflectHtmxPushUrl @value))
instance (Typeable marker, KnownSymbol reason) => ReflectOption ('CustomHtmx marker reason) where
    reflectOption = HtmxOption (HtmxActionCustomHtmxIR (protocolName @marker DomTokenName) (cs (symbolVal (Proxy @reason))))

class ReflectHtmxMethod (method :: HtmxMethod) where
    reflectHtmxMethod :: HtmxMethodIR

instance ReflectHtmxMethod 'HtmxGet where reflectHtmxMethod = HtmxGetIR
instance ReflectHtmxMethod 'HtmxPost where reflectHtmxMethod = HtmxPostIR
instance ReflectHtmxMethod 'HtmxPut where reflectHtmxMethod = HtmxPutIR
instance ReflectHtmxMethod 'HtmxPatch where reflectHtmxMethod = HtmxPatchIR
instance ReflectHtmxMethod 'HtmxDelete where reflectHtmxMethod = HtmxDeleteIR

class ReflectHtmxPushUrl (value :: HtmxPushUrl) where
    reflectHtmxPushUrl :: HtmxPushUrlIR

instance ReflectHtmxPushUrl 'HtmxPushUrlTrue where reflectHtmxPushUrl = HtmxPushUrlTrueIR
instance ReflectHtmxPushUrl 'HtmxPushUrlFalse where reflectHtmxPushUrl = HtmxPushUrlFalseIR

class ReflectHtmxSelector (selector :: HtmxSelectorSpec) where
    reflectHtmxSelector :: HtmxSyntaxIR

instance Typeable marker => ReflectHtmxSelector ('HtmxId marker) where
    reflectHtmxSelector = HtmxTypedSyntaxIR ("#" <> name) [name]
      where
        name = protocolName @marker DomTokenName

instance Typeable marker => ReflectHtmxSelector ('HtmxClass marker) where
    reflectHtmxSelector = HtmxTypedSyntaxIR ("." <> name) [name]
      where
        name = protocolName @marker DomTokenName

instance ReflectHtmxSelector selector => ReflectHtmxSelector ('HtmxClosest selector) where
    reflectHtmxSelector = mapHtmxSyntax ("closest " <>) (reflectHtmxSelector @selector)

instance ReflectHtmxSelector selector => ReflectHtmxSelector ('HtmxFind selector) where
    reflectHtmxSelector = mapHtmxSyntax ("find " <>) (reflectHtmxSelector @selector)

instance ReflectHtmxSelector 'HtmxThis where reflectHtmxSelector = HtmxTypedSyntaxIR "this" []
instance ReflectHtmxSelector 'HtmxDocument where reflectHtmxSelector = HtmxTypedSyntaxIR "document" []
instance ReflectHtmxSelector 'HtmxWindow where reflectHtmxSelector = HtmxTypedSyntaxIR "window" []
instance ReflectHtmxSelector 'HtmxBody where reflectHtmxSelector = HtmxTypedSyntaxIR "body" []
instance (KnownSymbol value, KnownSymbol reason) => ReflectHtmxSelector ('HtmxRawSelector value reason) where
    reflectHtmxSelector = HtmxRawSyntaxIR (cs (symbolVal (Proxy @value))) (cs (symbolVal (Proxy @reason)))

class ReflectHtmxTrigger (trigger :: HtmxTriggerSpec) where
    reflectHtmxTrigger :: HtmxSyntaxIR

instance ReflectHtmxTrigger 'HtmxClick where reflectHtmxTrigger = HtmxTypedSyntaxIR "click" []
instance ReflectHtmxTrigger 'HtmxChange where reflectHtmxTrigger = HtmxTypedSyntaxIR "change" []
instance ReflectHtmxTrigger 'HtmxLoad where reflectHtmxTrigger = HtmxTypedSyntaxIR "load" []
instance Typeable marker => ReflectHtmxTrigger ('HtmxCustomEvent marker) where
    reflectHtmxTrigger = HtmxTypedSyntaxIR (protocolName @marker EventName) []
instance (KnownSymbol value, KnownSymbol reason) => ReflectHtmxTrigger ('HtmxRawTrigger value reason) where
    reflectHtmxTrigger = HtmxRawSyntaxIR (cs (symbolVal (Proxy @value))) (cs (symbolVal (Proxy @reason)))

class ReflectHtmxSwap (swap :: HtmxSwapSpec) where
    reflectHtmxSwap :: HtmxSyntaxIR

instance ReflectHtmxSwap 'HtmxInnerHTML where reflectHtmxSwap = HtmxTypedSyntaxIR "innerHTML" []
instance ReflectHtmxSwap 'HtmxOuterHTML where reflectHtmxSwap = HtmxTypedSyntaxIR "outerHTML" []
instance ReflectHtmxSwap 'HtmxBeforeEnd where reflectHtmxSwap = HtmxTypedSyntaxIR "beforeend" []
instance ReflectHtmxSwap 'HtmxAfterBegin where reflectHtmxSwap = HtmxTypedSyntaxIR "afterbegin" []
instance ReflectHtmxSwap 'HtmxNoSwap where reflectHtmxSwap = HtmxTypedSyntaxIR "none" []
instance (KnownSymbol value, KnownSymbol reason) => ReflectHtmxSwap ('HtmxRawSwap value reason) where
    reflectHtmxSwap = HtmxRawSyntaxIR (cs (symbolVal (Proxy @value))) (cs (symbolVal (Proxy @reason)))

class ReflectHtmxSync (sync :: HtmxSyncSpec) where
    reflectHtmxSync :: HtmxSyntaxIR

instance (ReflectHtmxSelector selector, ReflectHtmxSyncStrategy strategy) => ReflectHtmxSync ('HtmxSyncOn selector strategy) where
    reflectHtmxSync = mapHtmxSyntax (<> ":" <> reflectHtmxSyncStrategy @strategy) (reflectHtmxSelector @selector)
instance (KnownSymbol value, KnownSymbol reason) => ReflectHtmxSync ('HtmxRawSync value reason) where
    reflectHtmxSync = HtmxRawSyntaxIR (cs (symbolVal (Proxy @value))) (cs (symbolVal (Proxy @reason)))

class ReflectHtmxSyncStrategy (strategy :: HtmxSyncStrategy) where
    reflectHtmxSyncStrategy :: Text

instance ReflectHtmxSyncStrategy 'HtmxSyncDrop where reflectHtmxSyncStrategy = "drop"
instance ReflectHtmxSyncStrategy 'HtmxSyncAbort where reflectHtmxSyncStrategy = "abort"
instance ReflectHtmxSyncStrategy 'HtmxSyncReplace where reflectHtmxSyncStrategy = "replace"
instance ReflectHtmxSyncStrategy 'HtmxSyncQueueFirst where reflectHtmxSyncStrategy = "queue first"
instance ReflectHtmxSyncStrategy 'HtmxSyncQueueAll where reflectHtmxSyncStrategy = "queue all"
instance ReflectHtmxSyncStrategy 'HtmxSyncQueueLast where reflectHtmxSyncStrategy = "queue last"

mapHtmxSyntax :: (Text -> Text) -> HtmxSyntaxIR -> HtmxSyntaxIR
mapHtmxSyntax transform = \case
    HtmxTypedSyntaxIR value references -> HtmxTypedSyntaxIR (transform value) references
    HtmxRawSyntaxIR value reason -> HtmxRawSyntaxIR (transform value) reason

requiredOption :: Text -> Text -> Text -> [Text] -> Text
requiredOption kind marker optionName values =
    case values of
        [value] -> value
        [] -> error (cs (kind <> " " <> marker <> " must declare " <> optionName))
        _ -> error (cs (kind <> " " <> marker <> " declares " <> optionName <> " more than once"))

optionalUniqueOption :: Text -> Text -> Text -> [Text] -> Maybe Text
optionalUniqueOption kind marker optionName values =
    case values of
        [] -> Nothing
        [value] -> Just value
        _ -> error (cs (kind <> " " <> marker <> " declares " <> optionName <> " more than once"))

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
            ReflectedSourceRef ref -> current { surfaceSourceRefs = current.surfaceSourceRefs <> [ref] }
            ReflectedDropzoneRef ref -> current { surfaceDropzoneRefs = current.surfaceDropzoneRefs <> [ref] }
            ReflectedActivationRef ref -> current { surfaceActivationRefs = current.surfaceActivationRefs <> [ref] }
            ReflectedLayer name -> current { surfaceLayers = current.surfaceLayers <> [name] }
            ReflectedEffect name options -> current { surfaceEffects = current.surfaceEffects <> [(name, options)] }
            ReflectedPolicy policy -> current { surfacePolicies = current.surfacePolicies <> [policy] }
            ReflectedLoadPolicy name -> current { surfaceLoadPolicies = current.surfaceLoadPolicies <> [name] }
            ReflectedOverlayLane name -> current { surfaceOverlayLanes = current.surfaceOverlayLanes <> [name] }
            ReflectedClientEvent name fields -> current { surfaceClientEvents = current.surfaceClientEvents <> [(name, fields)] }
            ReflectedDomToken name -> current { surfaceDomTokens = current.surfaceDomTokens <> [name] }
            ReflectedBrowserDomToken name -> current
                { surfaceDomTokens = current.surfaceDomTokens <> [name]
                , surfaceBrowserDomTokens = current.surfaceBrowserDomTokens <> [name]
                }
            ReflectedDto marker fields -> current { surfaceDtos = current.surfaceDtos <> [RecordIR marker marker fields] }

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
            ModifierVariantOption variant -> concatMap (layersIn . snd) variant.modifierVariantEffects
            _ -> []
        effectsIn = effectsInOptions

effectsInOptions :: [OptionIR] -> [(Text, [OptionIR])]
effectsInOptions = concatMap \case
    LazyOption nested -> effectsInOptions nested
    EffectOption name nested -> (name, nested) : effectsInOptions nested
    ModifierVariantOption variant -> variant.modifierVariantEffects <> concatMap (effectsInOptions . snd) variant.modifierVariantEffects
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
    , surfaceSourceRefs = []
    , surfaceDropzoneRefs = []
    , surfaceActivationRefs = []
    , surfaceLayers = []
    , surfaceEffects = []
    , surfacePolicies = []
    , surfaceLoadPolicies = []
    , surfaceOverlayLanes = []
    , surfaceClientEvents = []
    , surfaceDomTokens = []
    , surfaceBrowserDomTokens = []
    , surfaceDtos = []
    }

reflectedField :: forall marker wire. (Typeable marker, ReflectWire wire) => FieldPresence -> FieldIR
reflectedField presence =
    FieldIR
        { fieldMarker = marker
        , fieldName = deriveFrontendSurfaceName FieldName marker
        , fieldWire = reflectWire @wire
        , fieldPresence = presence
        }
    where
        marker = typeMarker @marker

typeMarker :: forall marker. Typeable marker => Text
typeMarker = cs (tyConName (typeRepTyCon (typeRep (Proxy @marker))))

protocolName :: forall marker. Typeable marker => FrontendSurfaceNameContext -> Text
protocolName context = deriveFrontendSurfaceName context (typeMarker @marker)
