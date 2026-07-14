{-# LANGUAGE AllowAmbiguousTypes  #-}
{-# LANGUAGE DataKinds            #-}
{-# LANGUAGE FlexibleInstances    #-}
{-# LANGUAGE PolyKinds            #-}
{-# LANGUAGE ScopedTypeVariables  #-}
{-# LANGUAGE TypeApplications     #-}
{-# LANGUAGE TypeOperators        #-}
{-# LANGUAGE UndecidableInstances #-}

module Application.Helper.FrontendContract.Reflect
    ( ReflectFrontendContractRegistry (..)
    , ReflectFrontendContractSpec (..)
    , reflectFrontendContracts
    ) where

import Application.Helper.FrontendContract.DSL
import Application.Helper.FrontendContract.IR
import Application.Helper.FrontendContract.Naming (deriveDomAttributeName,
                                                   deriveEventName,
                                                   deriveFrontendSurfaceName,
                                                   deriveJsonFieldName,
                                                   nameToKebab)
import qualified Application.Helper.FrontendContract.Naming as Naming
import Data.Typeable (tyConName, typeRep, typeRepTyCon)
import IHP.Prelude

reflectFrontendContracts :: forall contracts. ReflectFrontendContractRegistry contracts => FrontendContractIR
reflectFrontendContracts = reflectFrontendContractRegistry @contracts

class ReflectFrontendContractRegistry (contracts :: [FrontendContractSpec]) where
    reflectFrontendContractRegistry :: FrontendContractIR

instance ReflectFrontendContractRegistry '[] where
    reflectFrontendContractRegistry = FrontendContractIR [] []

instance (ReflectFrontendContractSpec contract, ReflectFrontendContractRegistry rest) => ReflectFrontendContractRegistry (contract ': rest) where
    reflectFrontendContractRegistry =
        appendContract (reflectFrontendContractSpec @contract) (reflectFrontendContractRegistry @rest)

class ReflectFrontendContractSpec (contract :: FrontendContractSpec) where
    reflectFrontendContractSpec :: FrontendContractIR

instance (Typeable marker, ReflectGlobalPrimitiveList primitives) => ReflectFrontendContractSpec ('Global marker primitives) where
    reflectFrontendContractSpec = FrontendContractIR
        { contractGlobals =
            [ GlobalIR
                { globalMarker = typeMarker @marker
                , globalName = lowerRootName @marker
                , globalPrimitives = reflectGlobalPrimitiveList @primitives
                }
            ]
        , contractSurfaces = []
        }

appendContract :: FrontendContractIR -> FrontendContractIR -> FrontendContractIR
appendContract left right = FrontendContractIR
    { contractGlobals = left.contractGlobals <> right.contractGlobals
    , contractSurfaces = left.contractSurfaces <> right.contractSurfaces
    }

class ReflectGlobalPrimitiveList (primitives :: [GlobalPrimitive]) where
    reflectGlobalPrimitiveList :: [GlobalPrimitiveIR]

instance ReflectGlobalPrimitiveList '[] where
    reflectGlobalPrimitiveList = []

instance (ReflectGlobalPrimitive primitive, ReflectGlobalPrimitiveList rest) => ReflectGlobalPrimitiveList (primitive ': rest) where
    reflectGlobalPrimitiveList = reflectGlobalPrimitive @primitive : reflectGlobalPrimitiveList @rest

class ReflectGlobalPrimitive (primitive :: GlobalPrimitive) where
    reflectGlobalPrimitive :: GlobalPrimitiveIR

instance (ReflectBrowserReachability reachability, ReflectSchemaPrimitive schema) => ReflectGlobalPrimitive ('GlobalSchema reachability schema) where
    reflectGlobalPrimitive = GlobalSchemaIR (reflectBrowserReachability @reachability) (reflectSchemaPrimitive @schema)

instance (ReflectBrowserReachability reachability, Typeable marker, ReflectFieldList fields) => ReflectGlobalPrimitive ('Event reachability marker fields) where
    reflectGlobalPrimitive = GlobalEventIR (reflectBrowserReachability @reachability) (typeMarker @marker) (deriveEventName "bepis" (typeMarker @marker)) (reflectFieldList @fields)

class ReflectBrowserReachability (reachability :: BrowserReachability) where
    reflectBrowserReachability :: BrowserReachabilityIR

instance ReflectBrowserReachability 'BrowserUnreachable where reflectBrowserReachability = BrowserUnreachableIR
instance ReflectBrowserReachability 'BrowserTypeOnly where reflectBrowserReachability = BrowserTypeOnlyIR
instance ReflectBrowserReachability 'BrowserGuard where reflectBrowserReachability = BrowserGuardIR
instance ReflectBrowserReachability 'BrowserInbound where reflectBrowserReachability = BrowserInboundIR
instance ReflectBrowserReachability 'BrowserOutbound where reflectBrowserReachability = BrowserOutboundIR
instance ReflectBrowserReachability 'BrowserBidirectional where reflectBrowserReachability = BrowserBidirectionalIR

instance Typeable marker => ReflectGlobalPrimitive ('DomId marker) where
    reflectGlobalPrimitive = GlobalDomIdIR (typeMarker @marker) (nameToKebab (typeMarker @marker))

instance Typeable marker => ReflectGlobalPrimitive ('ServerDomId marker) where
    reflectGlobalPrimitive = GlobalServerDomIdIR (typeMarker @marker) (nameToKebab (typeMarker @marker))

instance Typeable marker => ReflectGlobalPrimitive ('DomAttr marker) where
    reflectGlobalPrimitive = GlobalDomAttrIR (typeMarker @marker) (deriveDomAttributeName (typeMarker @marker))

instance Typeable marker => ReflectGlobalPrimitive ('ServerDomAttr marker) where
    reflectGlobalPrimitive = GlobalServerDomAttrIR (typeMarker @marker) (deriveDomAttributeName (typeMarker @marker))

instance (Typeable marker, KnownSymbol value) => ReflectGlobalPrimitive ('DomValue marker value) where
    reflectGlobalPrimitive = GlobalDomValueIR (typeMarker @marker) (cs (symbolVal (Proxy @value)))

instance Typeable marker => ReflectGlobalPrimitive ('FieldName marker) where
    reflectGlobalPrimitive = GlobalFieldNameIR (typeMarker @marker) (deriveJsonFieldName (typeMarker @marker))

instance Typeable marker => ReflectGlobalPrimitive ('DomToken marker) where
    reflectGlobalPrimitive = GlobalDomTokenIR (typeMarker @marker) (nameToKebab (typeMarker @marker))

instance (Typeable marker, KnownSymbol value) => ReflectGlobalPrimitive ('Constant marker value) where
    reflectGlobalPrimitive = GlobalConstantIR (typeMarker @marker) (cs (symbolVal (Proxy @value)))

instance ReflectGlobalPrimitive ('Project 'InteractionDomProjection) where
    reflectGlobalPrimitive = GlobalProjectionIR InteractionDomProjectionIR

instance (Typeable marker, ReflectFieldList fields, ReflectAppShellActionOptionList options) => ReflectGlobalPrimitive ('AppShellAction marker fields options) where
    reflectGlobalPrimitive = GlobalAppShellActionIR AppShellActionIR
        { appShellActionMarker = typeMarker @marker
        , appShellActionName = protocolName @marker Naming.ActionName
        , appShellActionFields = reflectFieldList @fields
        , appShellActionOptions = reflectAppShellActionOptionList @options
        }

class ReflectAppShellActionOptionList (options :: [AppShellActionOption]) where
    reflectAppShellActionOptionList :: [HtmxActionOptionIR]

instance ReflectAppShellActionOptionList '[] where
    reflectAppShellActionOptionList = []

instance (ReflectAppShellActionOption option, ReflectAppShellActionOptionList rest) => ReflectAppShellActionOptionList (option ': rest) where
    reflectAppShellActionOptionList = reflectAppShellActionOption @option : reflectAppShellActionOptionList @rest

class ReflectAppShellActionOption (option :: AppShellActionOption) where
    reflectAppShellActionOption :: HtmxActionOptionIR

instance ReflectAppShellHtmxMethod method => ReflectAppShellActionOption ('AppShellHtmxMethod method) where
    reflectAppShellActionOption = HtmxActionMethodIR (reflectAppShellHtmxMethod @method)

instance KnownSymbol value => ReflectAppShellActionOption ('AppShellHtmxTrigger value) where
    reflectAppShellActionOption = HtmxActionTriggerIR (HtmxTypedSyntaxIR (cs (symbolVal (Proxy @value))) [])

instance KnownSymbol value => ReflectAppShellActionOption ('AppShellHtmxInclude value) where
    reflectAppShellActionOption = HtmxActionIncludeIR (HtmxTypedSyntaxIR (cs (symbolVal (Proxy @value))) [])

instance KnownSymbol value => ReflectAppShellActionOption ('AppShellHtmxSync value) where
    reflectAppShellActionOption = HtmxActionSyncIR (HtmxTypedSyntaxIR (cs (symbolVal (Proxy @value))) [])

instance KnownSymbol value => ReflectAppShellActionOption ('AppShellHtmxIndicator value) where
    reflectAppShellActionOption = HtmxActionIndicatorIR (HtmxTypedSyntaxIR (cs (symbolVal (Proxy @value))) [])

instance KnownSymbol value => ReflectAppShellActionOption ('AppShellHtmxConfirm value) where
    reflectAppShellActionOption = HtmxActionConfirmIR (cs (symbolVal (Proxy @value)))

instance KnownSymbol value => ReflectAppShellActionOption ('AppShellHtmxSelect value) where
    reflectAppShellActionOption = HtmxActionSelectIR (HtmxTypedSyntaxIR (cs (symbolVal (Proxy @value))) [])

instance Typeable marker => ReflectAppShellActionOption ('AppShellHtmxTarget marker) where
    reflectAppShellActionOption = HtmxActionTargetIR (HtmxTypedSyntaxIR ("#" <> name) [name])
      where
        name = nameToKebab (typeMarker @marker)

instance KnownSymbol value => ReflectAppShellActionOption ('AppShellHtmxSwap value) where
    reflectAppShellActionOption = HtmxActionSwapIR (HtmxTypedSyntaxIR (cs (symbolVal (Proxy @value))) [])

instance ReflectAppShellHtmxPushUrl value => ReflectAppShellActionOption ('AppShellHtmxPushUrl value) where
    reflectAppShellActionOption = HtmxActionPushUrlIR (reflectAppShellHtmxPushUrl @value)

instance (Typeable marker, KnownSymbol reason) => ReflectAppShellActionOption ('AppShellCustomHtmx marker reason) where
    reflectAppShellActionOption = HtmxActionCustomHtmxIR (nameToKebab (typeMarker @marker)) (cs (symbolVal (Proxy @reason)))

class ReflectAppShellHtmxMethod (method :: AppShellRequestMethod) where
    reflectAppShellHtmxMethod :: HtmxMethodIR

instance ReflectAppShellHtmxMethod 'AppShellGet where reflectAppShellHtmxMethod = HtmxGetIR
instance ReflectAppShellHtmxMethod 'AppShellPost where reflectAppShellHtmxMethod = HtmxPostIR
instance ReflectAppShellHtmxMethod 'AppShellPut where reflectAppShellHtmxMethod = HtmxPutIR
instance ReflectAppShellHtmxMethod 'AppShellPatch where reflectAppShellHtmxMethod = HtmxPatchIR
instance ReflectAppShellHtmxMethod 'AppShellDelete where reflectAppShellHtmxMethod = HtmxDeleteIR

class ReflectAppShellHtmxPushUrl (value :: AppShellPushUrlValue) where
    reflectAppShellHtmxPushUrl :: HtmxPushUrlIR

instance ReflectAppShellHtmxPushUrl 'AppShellPushUrlTrue where reflectAppShellHtmxPushUrl = HtmxPushUrlTrueIR
instance ReflectAppShellHtmxPushUrl 'AppShellPushUrlFalse where reflectAppShellHtmxPushUrl = HtmxPushUrlFalseIR

class ReflectSchemaPrimitive (schema :: SchemaPrimitive) where
    reflectSchemaPrimitive :: SchemaIR

instance (Typeable marker, ReflectFieldList fields) => ReflectSchemaPrimitive ('Record marker fields) where
    reflectSchemaPrimitive = RecordIR (typeMarker @marker) (typeName @marker) (reflectFieldList @fields)

instance (Typeable marker, ReflectTypeList cases) => ReflectSchemaPrimitive ('Enum marker cases) where
    reflectSchemaPrimitive = EnumIR (typeMarker @marker) (typeName @marker) (reflectTypeListKebab @cases)

instance (Typeable marker, ReflectLiteralCaseList cases) => ReflectSchemaPrimitive ('LiteralEnum marker cases) where
    reflectSchemaPrimitive = LiteralEnumIR (typeMarker @marker) (typeName @marker) (reflectLiteralCaseList @cases)

instance (Typeable marker, ReflectUnionCaseList cases) => ReflectSchemaPrimitive ('TaggedUnion marker cases) where
    reflectSchemaPrimitive = TaggedUnionIR (typeMarker @marker) (typeName @marker) "tag" (reflectUnionCaseList @cases)

instance (Typeable marker, KnownSymbol tagField, ReflectUnionCaseList cases) => ReflectSchemaPrimitive ('TaggedUnionWithTag marker tagField cases) where
    reflectSchemaPrimitive = TaggedUnionIR (typeMarker @marker) (typeName @marker) (cs (symbolVal (Proxy @tagField))) (reflectUnionCaseList @cases)

class ReflectLiteralCaseList (cases :: [LiteralCaseSpec]) where
    reflectLiteralCaseList :: [(Text, Text)]

instance ReflectLiteralCaseList '[] where
    reflectLiteralCaseList = []

instance (Typeable marker, KnownSymbol value, ReflectLiteralCaseList rest) => ReflectLiteralCaseList ('Literal marker value ': rest) where
    reflectLiteralCaseList = (typeMarker @marker, cs (symbolVal (Proxy @value))) : reflectLiteralCaseList @rest

class ReflectUnionCaseList (cases :: [UnionCaseSpec]) where
    reflectUnionCaseList :: [UnionCaseIR]

instance ReflectUnionCaseList '[] where
    reflectUnionCaseList = []

instance (ReflectUnionCase caseSpec, ReflectUnionCaseList rest) => ReflectUnionCaseList (caseSpec ': rest) where
    reflectUnionCaseList = reflectUnionCase @caseSpec : reflectUnionCaseList @rest

class ReflectUnionCase (caseSpec :: UnionCaseSpec) where
    reflectUnionCase :: UnionCaseIR

instance (Typeable marker, ReflectFieldList fields) => ReflectUnionCase ('Case marker fields) where
    reflectUnionCase = UnionCaseIR
        { unionCaseMarker = typeMarker @marker
        , unionCaseTag = nameToKebab (typeMarker @marker)
        , unionCaseFields = reflectFieldList @fields
        }

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

reflectedField :: forall marker wire. (Typeable marker, ReflectWire wire) => FieldPresence -> FieldIR
reflectedField presence = FieldIR
    { fieldMarker = typeMarker @marker
    , fieldName = deriveJsonFieldName (typeMarker @marker)
    , fieldWire = reflectWire @wire
    , fieldPresence = presence
    }

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
instance Typeable marker => ReflectWire ('WireRef marker) where reflectWire = WireRefIR (typeName @marker)
instance ReflectWire 'WireSurfaceScope where reflectWire = WireSurfaceScopeIR
instance ReflectWire 'WireSurfaceFragmentKey where reflectWire = WireSurfaceFragmentKeyIR

class ReflectTypeList (markers :: [Type]) where
    reflectTypeListKebab :: [Text]

instance ReflectTypeList '[] where
    reflectTypeListKebab = []

instance (Typeable marker, ReflectTypeList rest) => ReflectTypeList (marker ': rest) where
    reflectTypeListKebab = nameToKebab (typeMarker @marker) : reflectTypeListKebab @rest

protocolName :: forall marker. Typeable marker => Naming.FrontendSurfaceNameContext -> Text
protocolName context = deriveFrontendSurfaceName context (typeMarker @marker)

lowerRootName :: forall marker. Typeable marker => Text
lowerRootName = deriveFrontendSurfaceName Naming.FieldName (typeMarker @marker)

typeName :: forall marker. Typeable marker => Text
typeName = typeMarker @marker

typeMarker :: forall marker. Typeable marker => Text
typeMarker = cs (tyConName (typeRepTyCon (typeRep (Proxy @marker))))
