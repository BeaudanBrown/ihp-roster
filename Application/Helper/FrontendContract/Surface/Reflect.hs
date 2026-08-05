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
    ) where

import Application.Helper.FrontendContract.ClosedScalar (closedScalarSourceModule)
import Application.Helper.FrontendContract.Naming (FrontendSurfaceNameContext (..),
                                                   deriveFrontendSurfaceName,
                                                   deriveSurfaceBrowserAttributeName)
import Application.Helper.FrontendContract.Surface.ContractIR
import Application.Helper.FrontendContract.Surface.DSL
import qualified Data.List as List
import Data.Typeable (tyConName, typeRep, typeRepTyCon)
import IHP.Prelude

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
    | ReflectedSession !InteractionSessionIR
    | ReflectedSourceRef !InteractionSourceRefIR
    | ReflectedDropzoneRef !InteractionDropzoneRefIR
    | ReflectedActivationRef !InteractionActivationRefIR
    | ReflectedBrowserRole !BrowserAttributeIR
    | ReflectedBrowserState !BrowserAttributeIR
    | ReflectedBrowserClosedState !BrowserClosedStateIR
    | ReflectedLinkedHighlight !LinkedHighlightIR
    | ReflectedCompleteSetSort !CompleteSetSortIR
    | ReflectedTabSet !TabSetIR
    | ReflectedLayer !Text
    | ReflectedPolicy !ConflictPolicyIR
    | ReflectedLoadPolicy !Text
    | ReflectedOverlayLane !Text
    | ReflectedClientEvent !Text ![FieldIR]
    | ReflectedDomToken !Text
    | ReflectedBrowserDomToken !Text
    | ReflectedDto !BrowserReachabilityIR !Text ![FieldIR]

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

instance Typeable marker => ReflectPrimitive ('BrowserRole marker) where
    reflectPrimitive = ReflectedBrowserRole (reflectedBrowserAttribute @marker BrowserRoleName)

instance Typeable marker => ReflectPrimitive ('BrowserState marker) where
    reflectPrimitive = ReflectedBrowserState (reflectedBrowserAttribute @marker BrowserStateName)

instance (Typeable marker, ReflectMarkerList values) => ReflectPrimitive ('BrowserClosedState marker values) where
    reflectPrimitive = ReflectedBrowserClosedState BrowserClosedStateIR
        { browserClosedStateMarker = typeMarker @marker
        , browserClosedStateAttribute = reflectedBrowserAttribute @marker BrowserStateName
        , browserClosedStateValues = reflectMarkerList @values BrowserStateValueName
        }

instance
    ( Typeable marker
    , Typeable sourceRole
    , Typeable memberRole
    , ReflectLinkedHighlightActivationList activations
    , ReflectLinkedHighlightEffectList effects
    ) => ReflectPrimitive ('LinkedHighlight marker sourceRole memberRole activations effects) where
    reflectPrimitive = ReflectedLinkedHighlight LinkedHighlightIR
        { linkedHighlightMarker = typeMarker @marker
        , linkedHighlightName = protocolName @marker DomTokenName
        , linkedHighlightSourceRole = reflectedBrowserAttribute @sourceRole BrowserRoleName
        , linkedHighlightMemberRole = reflectedBrowserAttribute @memberRole BrowserRoleName
        , linkedHighlightActivations = reflectLinkedHighlightActivationList @activations
        , linkedHighlightEffects = reflectLinkedHighlightEffectList @effects
        }

instance
    ( Typeable marker
    , Typeable rootRole
    , Typeable rowRole
    , Typeable controlRole
    , Typeable rowDto
    , ReflectCompleteSetSortKeyList keys
    , Typeable defaultKey
    , ReflectCompleteSetSortDirection defaultDirection
    ) => ReflectPrimitive ('CompleteSetSort marker rootRole rowRole controlRole rowDto keys defaultKey defaultDirection) where
    reflectPrimitive = ReflectedCompleteSetSort CompleteSetSortIR
        { completeSetSortMarker = typeMarker @marker
        , completeSetSortName = protocolName @marker DomTokenName
        , completeSetSortRootRole = reflectedBrowserAttribute @rootRole BrowserRoleName
        , completeSetSortRowRole = reflectedBrowserAttribute @rowRole BrowserRoleName
        , completeSetSortControlRole = reflectedBrowserAttribute @controlRole BrowserRoleName
        , completeSetSortRowDtoMarker = typeMarker @rowDto
        , completeSetSortKeys = reflectCompleteSetSortKeyList @keys
        , completeSetSortDefaultKey = protocolName @defaultKey SortKeyName
        , completeSetSortDefaultDirection = reflectCompleteSetSortDirection @defaultDirection
        }

instance
    ( Typeable marker
    , Typeable tabRole
    , ReflectMarkerList keys
    , Typeable defaultKey
    ) => ReflectPrimitive ('TabSet marker tabRole keys defaultKey) where
    reflectPrimitive = ReflectedTabSet TabSetIR
        { tabSetMarker = typeMarker @marker
        , tabSetName = protocolName @marker DomTokenName
        , tabSetRole = reflectedBrowserAttribute @tabRole BrowserRoleName
        , tabSetKeys = reflectMarkerList @keys TabKeyName
        , tabSetDefaultKey = protocolName @defaultKey TabKeyName
        }

instance (Typeable marker, ReflectInteractionSessionOptionList options) => ReflectPrimitive ('Session marker options) where
    reflectPrimitive =
        let reflectedOptions = reflectInteractionSessionOptionList @options
         in ReflectedSession InteractionSessionIR
                { sessionMarker = typeMarker @marker
                , sessionName = protocolName @marker SessionName
                , sessionLayers = reflectedOptions.reflectedSessionLayers
                , sessionEffects = reflectedOptions.reflectedSessionEffects
                }

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

instance (ReflectBrowserReachability reachability, Typeable marker, ReflectFieldList fields) => ReflectPrimitive ('SurfaceDto reachability marker fields) where
    reflectPrimitive = ReflectedDto (reflectBrowserReachability @reachability) (typeMarker @marker) (reflectFieldList @fields)

class ReflectBrowserReachability (reachability :: BrowserReachability) where
    reflectBrowserReachability :: BrowserReachabilityIR

instance ReflectBrowserReachability 'BrowserUnreachable where reflectBrowserReachability = BrowserUnreachableIR
instance ReflectBrowserReachability 'BrowserTypeOnly where reflectBrowserReachability = BrowserTypeOnlyIR
instance ReflectBrowserReachability 'BrowserGuard where reflectBrowserReachability = BrowserGuardIR
instance ReflectBrowserReachability 'BrowserInbound where reflectBrowserReachability = BrowserInboundIR
instance ReflectBrowserReachability 'BrowserOutbound where reflectBrowserReachability = BrowserOutboundIR
instance ReflectBrowserReachability 'BrowserBidirectional where reflectBrowserReachability = BrowserBidirectionalIR

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
instance Typeable value => ReflectWire ('WireClosed value) where
    reflectWire = WireClosedIR (typeMarker @value) (closedScalarSourceModule @value) (typeMarker @value)
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
    reflectScopeOption = reflectAuthPolicy @policy (reflectMarkerList @fields FieldName)

class ReflectAuthPolicy (policy :: AuthPolicy) where
    reflectAuthPolicy :: [Text] -> ScopeAuthIR

instance ReflectAuthPolicy 'CurrentVenue where
    reflectAuthPolicy [venueId] = AuthorizeCurrentVenueIR venueId
    reflectAuthPolicy fields    = InvalidAuthorizeIR CurrentVenuePolicyIR fields

instance ReflectAuthPolicy 'CurrentVenueUser where
    reflectAuthPolicy [venueId, userId] = AuthorizeCurrentVenueUserIR venueId userId
    reflectAuthPolicy fields = InvalidAuthorizeIR CurrentVenueUserPolicyIR fields

instance ReflectAuthPolicy 'CurrentVenueStaff where
    reflectAuthPolicy [venueId, staffId] = AuthorizeCurrentVenueStaffIR venueId staffId
    reflectAuthPolicy fields = InvalidAuthorizeIR CurrentVenueStaffPolicyIR fields

instance ReflectAuthPolicy 'CurrentVenueRosterGroup where
    reflectAuthPolicy [venueId, rosterGroupId] = AuthorizeCurrentVenueRosterGroupIR venueId rosterGroupId
    reflectAuthPolicy fields = InvalidAuthorizeIR CurrentVenueRosterGroupPolicyIR fields

instance ReflectAuthPolicy 'CurrentVenueAdmin where
    reflectAuthPolicy [venueId] = AuthorizeCurrentVenueAdminIR venueId
    reflectAuthPolicy fields = InvalidAuthorizeIR CurrentVenueAdminPolicyIR fields

instance ReflectAuthPolicy 'CurrentVenueManager where
    reflectAuthPolicy [venueId] = AuthorizeCurrentVenueManagerIR venueId
    reflectAuthPolicy fields = InvalidAuthorizeIR CurrentVenueManagerPolicyIR fields

instance ReflectAuthPolicy 'CurrentVenueOwner where
    reflectAuthPolicy [venueId] = AuthorizeCurrentVenueOwnerIR venueId
    reflectAuthPolicy fields = InvalidAuthorizeIR CurrentVenueOwnerPolicyIR fields

instance ReflectAuthPolicy 'CurrentVenueAdminRosterGroup where
    reflectAuthPolicy [venueId, rosterGroupId] = AuthorizeCurrentVenueAdminRosterGroupIR venueId rosterGroupId
    reflectAuthPolicy fields = InvalidAuthorizeIR CurrentVenueAdminRosterGroupPolicyIR fields

instance ReflectAuthPolicy 'SupportSuperAdmin where
    reflectAuthPolicy [] = AuthorizeSupportSuperAdminIR
    reflectAuthPolicy fields = InvalidAuthorizeIR SupportSuperAdminPolicyIR fields

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

class ReflectInteractionEffect (effect :: InteractionEffect) where
    reflectInteractionEffect :: InteractionEffectIR

instance Typeable layer => ReflectInteractionEffect ('CloneShadowEffect 'StandardCloneShadow layer) where
    reflectInteractionEffect = cloneShadowEffectIR (protocolName @layer LayerName)

instance Typeable layer => ReflectInteractionEffect ('CloneShadowEffect 'CopyCloneShadow layer) where
    reflectInteractionEffect = cloneShadowCopyEffectIR (protocolName @layer LayerName)

instance ReflectInteractionEffect 'DropzoneHighlightEffect where
    reflectInteractionEffect = dropzoneHighlightEffectIR

class ReflectLinkedHighlightActivationList (activations :: [LinkedHighlightActivation]) where
    reflectLinkedHighlightActivationList :: [LinkedHighlightActivationIR]

instance ReflectLinkedHighlightActivationList '[] where
    reflectLinkedHighlightActivationList = []

instance (ReflectLinkedHighlightActivation activation, ReflectLinkedHighlightActivationList rest) => ReflectLinkedHighlightActivationList (activation ': rest) where
    reflectLinkedHighlightActivationList = reflectLinkedHighlightActivation @activation : reflectLinkedHighlightActivationList @rest

class ReflectLinkedHighlightActivation (activation :: LinkedHighlightActivation) where
    reflectLinkedHighlightActivation :: LinkedHighlightActivationIR

instance ReflectLinkedHighlightActivation 'ActivateOnHover where
    reflectLinkedHighlightActivation = LinkedHighlightHoverActivationIR

instance ReflectLinkedHighlightActivation 'ActivateOnFocus where
    reflectLinkedHighlightActivation = LinkedHighlightFocusActivationIR

instance ReflectLinkedHighlightActivation 'ActivateOnKeyboard where
    reflectLinkedHighlightActivation = LinkedHighlightKeyboardActivationIR

instance Typeable pinRole => ReflectLinkedHighlightActivation ('ActivateWithPin pinRole) where
    reflectLinkedHighlightActivation = LinkedHighlightPinActivationIR (reflectedBrowserAttribute @pinRole BrowserRoleName)

class ReflectLinkedHighlightEffectList (effects :: [LinkedHighlightEffect]) where
    reflectLinkedHighlightEffectList :: [LinkedHighlightEffectIR]

instance ReflectLinkedHighlightEffectList '[] where
    reflectLinkedHighlightEffectList = []

instance (ReflectLinkedHighlightEffect effect, ReflectLinkedHighlightEffectList rest) => ReflectLinkedHighlightEffectList (effect ': rest) where
    reflectLinkedHighlightEffectList = reflectLinkedHighlightEffect @effect : reflectLinkedHighlightEffectList @rest

class ReflectLinkedHighlightEffect (effect :: LinkedHighlightEffect) where
    reflectLinkedHighlightEffect :: LinkedHighlightEffectIR

instance ReflectLinkedHighlightEffect 'HighlightMatchingSource where
    reflectLinkedHighlightEffect = LinkedHighlightMatchingSourceEffectIR

instance ReflectLinkedHighlightEffect 'HighlightMatchingMember where
    reflectLinkedHighlightEffect = LinkedHighlightMatchingMemberEffectIR

instance Typeable state => ReflectLinkedHighlightEffect ('HighlightOrderedMemberBounds state) where
    reflectLinkedHighlightEffect = LinkedHighlightOrderedMemberBoundsEffectIR (reflectedBrowserAttribute @state BrowserStateName)

data ReflectedInteractionSessionOptions = ReflectedInteractionSessionOptions
    { reflectedSessionLayers  :: ![Text]
    , reflectedSessionEffects :: ![InteractionEffectIR]
    }

class ReflectInteractionSessionOptionList (options :: [InteractionSessionOption]) where
    reflectInteractionSessionOptionList :: ReflectedInteractionSessionOptions

instance ReflectInteractionSessionOptionList '[] where
    reflectInteractionSessionOptionList = ReflectedInteractionSessionOptions [] []

instance (Typeable layer, ReflectInteractionSessionOptionList rest) => ReflectInteractionSessionOptionList ('Layer layer ': rest) where
    reflectInteractionSessionOptionList =
        let reflectedRest = reflectInteractionSessionOptionList @rest
         in reflectedRest { reflectedSessionLayers = protocolName @layer LayerName : reflectedRest.reflectedSessionLayers }

instance (ReflectInteractionEffect effect, ReflectInteractionSessionOptionList rest) => ReflectInteractionSessionOptionList ('Effect effect ': rest) where
    reflectInteractionSessionOptionList =
        let reflectedRest = reflectInteractionSessionOptionList @rest
         in reflectedRest { reflectedSessionEffects = reflectInteractionEffect @effect : reflectedRest.reflectedSessionEffects }

class ReflectCompleteSetSortKeyList (keys :: [CompleteSetSortKeySpec]) where
    reflectCompleteSetSortKeyList :: [CompleteSetSortKeyIR]

instance ReflectCompleteSetSortKeyList '[] where
    reflectCompleteSetSortKeyList = []

instance (ReflectCompleteSetSortKey key, ReflectCompleteSetSortKeyList rest) => ReflectCompleteSetSortKeyList (key ': rest) where
    reflectCompleteSetSortKeyList = reflectCompleteSetSortKey @key : reflectCompleteSetSortKeyList @rest

class ReflectCompleteSetSortKey (key :: CompleteSetSortKeySpec) where
    reflectCompleteSetSortKey :: CompleteSetSortKeyIR

instance (Typeable marker, ReflectCompleteSetSortComparatorList comparators) => ReflectCompleteSetSortKey ('SortKey marker comparators) where
    reflectCompleteSetSortKey = CompleteSetSortKeyIR
        { completeSetSortKeyMarker = typeMarker @marker
        , completeSetSortKeyName = protocolName @marker SortKeyName
        , completeSetSortKeyComparators = reflectCompleteSetSortComparatorList @comparators
        }

class ReflectCompleteSetSortComparatorList (comparators :: [CompleteSetSortComparator]) where
    reflectCompleteSetSortComparatorList :: [CompleteSetSortComparatorIR]

instance ReflectCompleteSetSortComparatorList '[] where
    reflectCompleteSetSortComparatorList = []

instance (ReflectCompleteSetSortComparator comparator, ReflectCompleteSetSortComparatorList rest) => ReflectCompleteSetSortComparatorList (comparator ': rest) where
    reflectCompleteSetSortComparatorList = reflectCompleteSetSortComparator @comparator : reflectCompleteSetSortComparatorList @rest

class ReflectCompleteSetSortComparator (comparator :: CompleteSetSortComparator) where
    reflectCompleteSetSortComparator :: CompleteSetSortComparatorIR

instance
    ( Typeable field
    , ReflectCompleteSetSortValueType valueType
    , ReflectCompleteSetSortComparatorDirection direction
    ) => ReflectCompleteSetSortComparator ('SortComparator field valueType direction) where
    reflectCompleteSetSortComparator = CompleteSetSortComparatorIR
        { completeSetSortComparatorFieldMarker = typeMarker @field
        , completeSetSortComparatorField = protocolName @field FieldName
        , completeSetSortComparatorValueType = reflectCompleteSetSortValueType @valueType
        , completeSetSortComparatorDirection = reflectCompleteSetSortComparatorDirection @direction
        }

class ReflectCompleteSetSortValueType (valueType :: CompleteSetSortValueType) where
    reflectCompleteSetSortValueType :: CompleteSetSortValueTypeIR

instance ReflectCompleteSetSortValueType 'SortText where reflectCompleteSetSortValueType = CompleteSetSortTextIR
instance ReflectCompleteSetSortValueType 'SortInteger where reflectCompleteSetSortValueType = CompleteSetSortIntegerIR
instance ReflectCompleteSetSortValueType 'SortOpaque where reflectCompleteSetSortValueType = CompleteSetSortOpaqueIR

class ReflectCompleteSetSortComparatorDirection (direction :: CompleteSetSortComparatorDirection) where
    reflectCompleteSetSortComparatorDirection :: CompleteSetSortComparatorDirectionIR

instance ReflectCompleteSetSortComparatorDirection 'FollowSortDirection where reflectCompleteSetSortComparatorDirection = CompleteSetSortSelectedDirectionIR
instance ReflectCompleteSetSortComparatorDirection 'AlwaysAscending where reflectCompleteSetSortComparatorDirection = CompleteSetSortAscendingComparatorIR

class ReflectCompleteSetSortDirection (direction :: CompleteSetSortDirection) where
    reflectCompleteSetSortDirection :: CompleteSetSortDirectionIR

instance ReflectCompleteSetSortDirection 'SortAscending where reflectCompleteSetSortDirection = CompleteSetSortAscendingIR
instance ReflectCompleteSetSortDirection 'SortDescending where reflectCompleteSetSortDirection = CompleteSetSortDescendingIR

class ReflectInteractionEffectList (effects :: [InteractionEffect]) where
    reflectInteractionEffectList :: [InteractionEffectIR]

instance ReflectInteractionEffectList '[] where
    reflectInteractionEffectList = []

instance (ReflectInteractionEffect effect, ReflectInteractionEffectList rest) => ReflectInteractionEffectList (effect ': rest) where
    reflectInteractionEffectList = reflectInteractionEffect @effect : reflectInteractionEffectList @rest

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
instance (Typeable semantic, Typeable intent, ReflectInteractionEffectList effects) => ReflectOption ('ModifierVariant semantic intent effects) where
    reflectOption = ModifierVariantOption InteractionModifierVariantIR
        { modifierVariantSemantic = protocolName @semantic ActionName
        , modifierVariantIntent = protocolName @intent IntentName
        , modifierVariantEffects = reflectInteractionEffectList @effects
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
            ReflectedSession session -> current
                { surfaceSessions = current.surfaceSessions <> [session]
                , surfaceLayers = List.nub (current.surfaceLayers <> session.sessionLayers)
                }
            ReflectedSourceRef ref -> current { surfaceSourceRefs = current.surfaceSourceRefs <> [ref] }
            ReflectedDropzoneRef ref -> current { surfaceDropzoneRefs = current.surfaceDropzoneRefs <> [ref] }
            ReflectedActivationRef ref -> current { surfaceActivationRefs = current.surfaceActivationRefs <> [ref] }
            ReflectedBrowserRole roleAttribute -> current
                { surfaceBrowserRoles = current.surfaceBrowserRoles <> [qualifyBrowserAttribute current.surfaceName roleAttribute]
                }
            ReflectedBrowserState stateAttribute -> current
                { surfaceBrowserStates = current.surfaceBrowserStates <> [qualifyBrowserAttribute current.surfaceName stateAttribute]
                }
            ReflectedBrowserClosedState state ->
                let qualifiedState = qualifyBrowserClosedState current.surfaceName state
                 in current
                    { surfaceBrowserStates = current.surfaceBrowserStates <> [qualifiedState.browserClosedStateAttribute]
                    , surfaceBrowserClosedStates = current.surfaceBrowserClosedStates <> [qualifiedState]
                    }
            ReflectedLinkedHighlight highlight -> current
                { surfaceLinkedHighlights = current.surfaceLinkedHighlights <> [qualifyLinkedHighlight current.surfaceName highlight]
                }
            ReflectedCompleteSetSort sortDefinition -> current
                { surfaceCompleteSetSorts = current.surfaceCompleteSetSorts <> [qualifyCompleteSetSort current.surfaceName sortDefinition]
                }
            ReflectedTabSet tabSet -> current
                { surfaceTabSets = current.surfaceTabSets <> [qualifyTabSet current.surfaceName tabSet]
                }
            ReflectedLayer name -> current { surfaceLayers = current.surfaceLayers <> [name] }
            ReflectedPolicy policy -> current { surfacePolicies = current.surfacePolicies <> [policy] }
            ReflectedLoadPolicy name -> current { surfaceLoadPolicies = current.surfaceLoadPolicies <> [name] }
            ReflectedOverlayLane name -> current { surfaceOverlayLanes = current.surfaceOverlayLanes <> [name] }
            ReflectedClientEvent name fields -> current { surfaceClientEvents = current.surfaceClientEvents <> [(name, fields)] }
            ReflectedDomToken name -> current { surfaceDomTokens = current.surfaceDomTokens <> [name] }
            ReflectedBrowserDomToken name -> current
                { surfaceDomTokens = current.surfaceDomTokens <> [name]
                , surfaceBrowserDomTokens = current.surfaceBrowserDomTokens <> [name]
                }
            ReflectedDto reachability marker fields -> current
                { surfaceDtos = current.surfaceDtos <> [SurfaceDtoIR reachability (RecordIR marker marker fields)]
                }

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
    , surfaceBrowserRoles = []
    , surfaceBrowserStates = []
    , surfaceBrowserClosedStates = []
    , surfaceLinkedHighlights = []
    , surfaceCompleteSetSorts = []
    , surfaceTabSets = []
    , surfaceLayers = []
    , surfacePolicies = []
    , surfaceLoadPolicies = []
    , surfaceOverlayLanes = []
    , surfaceClientEvents = []
    , surfaceDomTokens = []
    , surfaceBrowserDomTokens = []
    , surfaceDtos = []
    }

qualifyBrowserClosedState :: Text -> BrowserClosedStateIR -> BrowserClosedStateIR
qualifyBrowserClosedState surfaceName state =
    state { browserClosedStateAttribute = qualifyBrowserAttribute surfaceName state.browserClosedStateAttribute }

qualifyTabSet :: Text -> TabSetIR -> TabSetIR
qualifyTabSet surfaceName tabSet =
    tabSet { tabSetRole = qualifyBrowserAttribute surfaceName tabSet.tabSetRole }

qualifyCompleteSetSort :: Text -> CompleteSetSortIR -> CompleteSetSortIR
qualifyCompleteSetSort surfaceName sortDefinition =
    sortDefinition
        { completeSetSortRootRole = qualifyBrowserAttribute surfaceName sortDefinition.completeSetSortRootRole
        , completeSetSortRowRole = qualifyBrowserAttribute surfaceName sortDefinition.completeSetSortRowRole
        , completeSetSortControlRole = qualifyBrowserAttribute surfaceName sortDefinition.completeSetSortControlRole
        }

qualifyLinkedHighlight :: Text -> LinkedHighlightIR -> LinkedHighlightIR
qualifyLinkedHighlight surfaceName highlight =
    highlight
        { linkedHighlightSourceRole = qualifyBrowserAttribute surfaceName highlight.linkedHighlightSourceRole
        , linkedHighlightMemberRole = qualifyBrowserAttribute surfaceName highlight.linkedHighlightMemberRole
        , linkedHighlightActivations = map qualifyActivation highlight.linkedHighlightActivations
        , linkedHighlightEffects = map qualifyEffect highlight.linkedHighlightEffects
        }
  where
    qualifyActivation = \case
        LinkedHighlightPinActivationIR roleAttribute ->
            LinkedHighlightPinActivationIR (qualifyBrowserAttribute surfaceName roleAttribute)
        activation -> activation
    qualifyEffect = \case
        LinkedHighlightOrderedMemberBoundsEffectIR stateAttribute ->
            LinkedHighlightOrderedMemberBoundsEffectIR (qualifyBrowserAttribute surfaceName stateAttribute)
        effect -> effect

qualifyBrowserAttribute :: Text -> BrowserAttributeIR -> BrowserAttributeIR
qualifyBrowserAttribute surfaceName attribute =
    attribute
        { browserAttributeDomAttribute =
            deriveSurfaceBrowserAttributeName surfaceName attribute.browserAttributeName
        }

reflectedBrowserAttribute :: forall marker. Typeable marker => FrontendSurfaceNameContext -> BrowserAttributeIR
reflectedBrowserAttribute context = BrowserAttributeIR
    { browserAttributeMarker = typeMarker @marker
    , browserAttributeName = protocolName @marker context
    , browserAttributeDomAttribute = ""
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
