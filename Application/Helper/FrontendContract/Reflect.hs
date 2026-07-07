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
import Application.Helper.FrontendContract.Surface.Naming (deriveDomAttributeName,
                                                           deriveEventName,
                                                           deriveFrontendSurfaceName,
                                                           deriveJsonFieldName,
                                                           nameToKebab)
import qualified Application.Helper.FrontendContract.Surface.Naming as Naming
import Data.Kind (Type)
import Data.Typeable (Proxy (..), Typeable, tyConName, typeRep, typeRepTyCon)
import GHC.TypeLits (KnownSymbol, symbolVal)
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

instance (Typeable marker, ReflectSurfacePrimitiveList primitives) => ReflectFrontendContractSpec ('Surface marker primitives) where
    reflectFrontendContractSpec = FrontendContractIR
        { contractGlobals = []
        , contractSurfaces =
            [ SurfaceIR
                { surfaceMarker = typeMarker @marker
                , surfaceName = protocolName @marker Naming.SurfaceName
                , surfacePrimitives = reflectSurfacePrimitiveList @primitives
                , surfaceInteractionSessions = []
                , surfaceInteractionLayers = []
                , surfaceInteractionEffects = []
                , surfaceInteractionPolicies = []
                , surfaceSourceRefs = []
                , surfaceDropzoneRefs = []
                , surfaceActivationRefs = []
                , surfaceDomTokens = []
                , surfaceOverlayLanes = []
                , surfaceLiveFragments = []
                , surfaceContainedSurfaces = []
                }
            ]
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

class ReflectSurfacePrimitiveList (primitives :: [SurfacePrimitive]) where
    reflectSurfacePrimitiveList :: [SurfacePrimitiveIR]

instance ReflectSurfacePrimitiveList '[] where
    reflectSurfacePrimitiveList = []

instance (ReflectSurfacePrimitive primitive, ReflectSurfacePrimitiveList rest) => ReflectSurfacePrimitiveList (primitive ': rest) where
    reflectSurfacePrimitiveList = reflectSurfacePrimitive @primitive : reflectSurfacePrimitiveList @rest

class ReflectGlobalPrimitive (primitive :: GlobalPrimitive) where
    reflectGlobalPrimitive :: GlobalPrimitiveIR

instance ReflectSchemaPrimitive schema => ReflectGlobalPrimitive ('GlobalSchema schema) where
    reflectGlobalPrimitive = GlobalSchemaIR (reflectSchemaPrimitive @schema)

instance (Typeable marker, ReflectFieldList fields) => ReflectGlobalPrimitive ('Event marker fields) where
    reflectGlobalPrimitive = GlobalEventIR (typeMarker @marker) (deriveEventName "bepis" (typeMarker @marker)) (reflectFieldList @fields)

instance Typeable marker => ReflectGlobalPrimitive ('DomId marker) where
    reflectGlobalPrimitive = GlobalDomIdIR (typeMarker @marker) (nameToKebab (typeMarker @marker))

instance Typeable marker => ReflectGlobalPrimitive ('DomAttr marker) where
    reflectGlobalPrimitive = GlobalDomAttrIR (typeMarker @marker) (deriveDomAttributeName (typeMarker @marker))

instance (Typeable marker, KnownSymbol value) => ReflectGlobalPrimitive ('DomValue marker value) where
    reflectGlobalPrimitive = GlobalDomValueIR (typeMarker @marker) (cs (symbolVal (Proxy @value)))

instance Typeable marker => ReflectGlobalPrimitive ('FieldName marker) where
    reflectGlobalPrimitive = GlobalFieldNameIR (typeMarker @marker) (deriveJsonFieldName (typeMarker @marker))

instance Typeable marker => ReflectGlobalPrimitive ('DomToken marker) where
    reflectGlobalPrimitive = GlobalDomTokenIR (typeMarker @marker) (nameToKebab (typeMarker @marker))

class ReflectSurfacePrimitive (primitive :: SurfacePrimitive) where
    reflectSurfacePrimitive :: SurfacePrimitiveIR

instance ReflectSchemaPrimitive schema => ReflectSurfacePrimitive ('SurfaceSchema schema) where
    reflectSurfacePrimitive = SurfaceSchemaIR (reflectSchemaPrimitive @schema)

instance (Typeable marker, ReflectFieldList fields) => ReflectSurfacePrimitive ('Scope marker fields) where
    reflectSurfacePrimitive = SurfaceScopeIR (typeMarker @marker) (protocolName @marker Naming.ScopeName) (reflectFieldList @fields)

instance (Typeable marker, ReflectFieldList fields) => ReflectSurfacePrimitive ('Fragment marker fields) where
    reflectSurfacePrimitive = SurfaceFragmentIR (typeMarker @marker) (protocolName @marker Naming.FragmentName) (reflectFieldList @fields)

instance (Typeable marker, ReflectFieldList fields) => ReflectSurfacePrimitive ('Action marker fields) where
    reflectSurfacePrimitive = SurfaceActionIR (typeMarker @marker) (protocolName @marker Naming.ActionName) (reflectFieldList @fields) []

instance (Typeable marker, ReflectFieldList fields) => ReflectSurfacePrimitive ('Intent marker fields) where
    reflectSurfacePrimitive = SurfaceIntentIR (typeMarker @marker) (protocolName @marker Naming.IntentName) (reflectFieldList @fields)

instance (Typeable marker, ReflectFieldList fields) => ReflectSurfacePrimitive ('MountState marker fields) where
    reflectSurfacePrimitive = SurfaceMountStateIR (typeMarker @marker) (protocolName @marker Naming.ScopeName) (reflectFieldList @fields)

instance (Typeable marker, ReflectFieldList fields) => ReflectSurfacePrimitive ('Dto marker fields) where
    reflectSurfacePrimitive = SurfaceDtoIR (typeMarker @marker) (typeName @marker) (reflectFieldList @fields)

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
instance ReflectWire 'WireSurfaceWireFragment where reflectWire = WireSurfaceWireFragmentIR

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
