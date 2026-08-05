{-# LANGUAGE AllowAmbiguousTypes   #-}
{-# LANGUAGE DataKinds             #-}
{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE GADTs                 #-}
{-# LANGUAGE LambdaCase            #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE PolyKinds             #-}
{-# LANGUAGE ScopedTypeVariables   #-}
{-# LANGUAGE TypeApplications      #-}
{-# LANGUAGE TypeFamilies          #-}
{-# LANGUAGE TypeOperators         #-}
{-# LANGUAGE UndecidableInstances  #-}

-- | Declaration-indexed Haskell values for global record, event-detail, and
-- tagged-union wire schemas. Field names, discriminator names, case tags,
-- presence, and recursive wire types all come from the selected type-level
-- FrontendContract declaration.
module Application.Helper.FrontendContract.Wire.Carrier
    ( CarrierField
    , CarrierFields
    , CarrierFieldValues
    , ContractReference (..)
    , CustomWire (..)
    , HaskellWireSource (..)
    , SchemaIn
    , WireSourceType
    , UnionCaseParsers
    , eventValue
    , eventValueIn
    , haskellWireSource
    , noFields
    , noUnionCases
    , nullableField
    , optionalField
    , parseEvent
    , parseRecord
    , parseRecordIn
    , parseTaggedUnion
    , parseTaggedUnionIn
    , recordValue
    , recordValueIn
    , requiredField
    , semanticSurfaceFragmentKeyJson
    , semanticSurfaceScopeJson
    , parseSemanticSurfaceFragmentKeyJson
    , parseSemanticSurfaceScopeJson
    , taggedUnionValue
    , taggedUnionValueIn
    , unionCase
    , (&:)
    , (|:)
    ) where

import Application.Helper.FrontendContract.ClosedScalar (KnownClosedScalar,
                                                         closedScalarLiteral,
                                                         parseClosedScalarLiteral)
import Application.Helper.FrontendContract.DSL
import qualified Application.Helper.FrontendContract.IR as Contract
import qualified Application.Helper.FrontendContract.Naming as Naming
import Application.Helper.FrontendContract.Reflect (ReflectFrontendContractRegistry,
                                                    reflectFrontendContracts)
import Application.Helper.FrontendContract.Registry (RegisteredFrontendContracts,
                                                     registeredFrontendContractIR)
import Application.Helper.FrontendContract.Wire.Json (validateContractMarkerValueWith,
                                                      validateSurfaceFragmentKeyValue,
                                                      validateSurfaceScopeValue)
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as AesonKey
import qualified Data.Aeson.KeyMap as KeyMap
import qualified Data.Aeson.Types as AesonTypes
import Data.Foldable (toList)
import Data.Kind (Type)
import Data.Time (Day, defaultTimeLocale, formatTime, parseTimeM)
import Data.Typeable (Proxy (..), Typeable, tyConName, typeRep, typeRepTyCon)
import qualified Data.UUID as UUID
import qualified Data.Vector as Vector
import GHC.TypeLits (ErrorMessage (..), KnownSymbol, Symbol, TypeError,
                     symbolVal)
import IHP.Prelude hiding (TypeError)

-- | Canonical recursive Haskell source type selected by a declared global wire.
-- Outer field presence is represented separately by 'CarrierFieldValues', so a
-- declared optional field containing a nullable wire becomes @Maybe (Maybe a)@.
type family WireSourceType (wire :: WireType) :: Type where
    WireSourceType 'WireText = Text
    WireSourceType 'WireInt = Int
    WireSourceType 'WireBool = Bool
    WireSourceType 'WireUUID = UUID.UUID
    WireSourceType 'WireDay = Day
    WireSourceType ('WireClosed value) = value
    WireSourceType 'WireUnknown = Aeson.Value
    WireSourceType ('WireList inner) = [WireSourceType inner]
    WireSourceType ('WireOptional inner) = Maybe (WireSourceType inner)
    WireSourceType ('WireNullable inner) = Maybe (WireSourceType inner)
    WireSourceType ('WireRef marker) = ContractReferenceValue marker
    WireSourceType 'WireSurfaceScope = CustomWireSourceType 'WireSurfaceScope
    WireSourceType 'WireSurfaceFragmentKey = CustomWireSourceType 'WireSurfaceFragmentKey

-- | A schema reference has one canonical ergonomic Haskell carrier. Carrier
-- modules provide instances beside that carrier; generic parser code consumes
-- the raw validated 'Aeson.Value' directly, without an encode/decode round trip.
class ContractReference (marker :: Type) where
    type ContractReferenceValue marker :: Type
    contractReferenceJson :: ContractReferenceValue marker -> Aeson.Value
    parseContractReference :: Aeson.Value -> AesonTypes.Parser (ContractReferenceValue marker)

-- | Source and codec for closed non-reference wire terminals whose concrete
-- Haskell carriers are owned outside this generic module.
class CustomWire (wire :: WireType) where
    type CustomWireSourceType wire :: Type
    customWireJson :: CustomWireSourceType wire -> Aeson.Value
    parseCustomWire :: Aeson.Value -> AesonTypes.Parser (CustomWireSourceType wire)

-- | Runtime source-shape projection consumed by deterministic Haskell source
-- generation. Constructors deliberately preserve every recursive container and
-- distinguish optional from nullable wires.
data HaskellWireSource
    = HaskellTextSource
    | HaskellIntSource
    | HaskellBoolSource
    | HaskellUuidSource
    | HaskellDaySource
    | HaskellClosedSource !Text !Text
    | HaskellListSource !HaskellWireSource
    | HaskellMapSource !HaskellWireSource !HaskellWireSource
    | HaskellOptionalSource !HaskellWireSource
    | HaskellNullableSource !HaskellWireSource
    | HaskellRefSource !Text
    | HaskellJsonSource
    | HaskellSurfaceScopeSource
    | HaskellSurfaceFragmentKeySource
    deriving (Eq, Show)

semanticSurfaceScopeJson :: Text -> Aeson.Value -> Aeson.Value
semanticSurfaceScopeJson surfaceName scopePayload =
    Aeson.object
        [ surfaceField Aeson..= surfaceName
        , scopeField Aeson..= scopePayload
        ]
  where
    surfaceField = AesonKey.fromText (Contract.surfaceWireFieldName Contract.SurfaceWireSurfaceField)
    scopeField = AesonKey.fromText (Contract.surfaceWireFieldName Contract.SurfaceWireScopeField)

parseSemanticSurfaceScopeJson :: Aeson.Value -> AesonTypes.Parser (Text, Aeson.Value)
parseSemanticSurfaceScopeJson raw = do
    validateSurfaceScopeValue raw
    Aeson.withObject "SurfaceScope"
        (\object ->
            (,)
                <$> object Aeson..: AesonKey.fromText (Contract.surfaceWireFieldName Contract.SurfaceWireSurfaceField)
                <*> object Aeson..: AesonKey.fromText (Contract.surfaceWireFieldName Contract.SurfaceWireScopeField)
        )
        raw

semanticSurfaceFragmentKeyJson :: Text -> Text -> Aeson.Value -> Aeson.Value
semanticSurfaceFragmentKeyJson surfaceName fragmentKind fragmentParams =
    Aeson.object
        [ surfaceField Aeson..= surfaceName
        , kindField Aeson..= fragmentKind
        , paramsField Aeson..= fragmentParams
        ]
  where
    surfaceField = AesonKey.fromText (Contract.surfaceWireFieldName Contract.SurfaceWireSurfaceField)
    kindField = AesonKey.fromText (Contract.surfaceWireFieldName Contract.SurfaceWireKindField)
    paramsField = AesonKey.fromText (Contract.surfaceWireFieldName Contract.SurfaceWireParamsField)

parseSemanticSurfaceFragmentKeyJson :: Aeson.Value -> AesonTypes.Parser (Text, Text, Aeson.Value)
parseSemanticSurfaceFragmentKeyJson raw = do
    validateSurfaceFragmentKeyValue raw
    Aeson.withObject "SurfaceFragmentKey"
        (\object ->
            (,,)
                <$> object Aeson..: AesonKey.fromText (Contract.surfaceWireFieldName Contract.SurfaceWireSurfaceField)
                <*> object Aeson..: AesonKey.fromText (Contract.surfaceWireFieldName Contract.SurfaceWireKindField)
                <*> object Aeson..: AesonKey.fromText (Contract.surfaceWireFieldName Contract.SurfaceWireParamsField)
        )
        raw

haskellWireSource :: Contract.WireIR -> HaskellWireSource
haskellWireSource = \case
    Contract.WireTextIR -> HaskellTextSource
    Contract.WireIntIR -> HaskellIntSource
    Contract.WireBoolIR -> HaskellBoolSource
    Contract.WireUuidIR -> HaskellUuidSource
    Contract.WireDayIR -> HaskellDaySource
    Contract.WireClosedIR _ sourceModule sourceType -> HaskellClosedSource sourceModule sourceType
    Contract.WireListIR inner -> HaskellListSource (haskellWireSource inner)
    Contract.WireMapIR key value -> HaskellMapSource (haskellWireSource key) (haskellWireSource value)
    Contract.WireOptionalIR inner -> HaskellOptionalSource (haskellWireSource inner)
    Contract.WireNullableIR inner -> HaskellNullableSource (haskellWireSource inner)
    Contract.WireRefIR marker -> HaskellRefSource marker
    Contract.WireUnknownIR -> HaskellJsonSource
    Contract.WireSurfaceScopeIR -> HaskellSurfaceScopeSource
    Contract.WireSurfaceFragmentKeyIR -> HaskellSurfaceFragmentKeySource

-- Type-level registry lookup --------------------------------------------------

type family FirstJust (left :: Maybe kind) (right :: Maybe kind) :: Maybe kind where
    FirstJust ('Just value) right = 'Just value
    FirstJust 'Nothing right = right

type family LookupSchemaPrimitive (marker :: Type) (primitives :: [GlobalPrimitive]) :: Maybe SchemaPrimitive where
    LookupSchemaPrimitive marker '[] = 'Nothing
    LookupSchemaPrimitive marker (('GlobalSchema reachability ('Record marker fields)) ': rest) =
        'Just ('Record marker fields)
    LookupSchemaPrimitive marker (('GlobalSchema reachability ('Enum marker cases)) ': rest) =
        'Just ('Enum marker cases)
    LookupSchemaPrimitive marker (('GlobalSchema reachability ('LiteralEnum marker cases)) ': rest) =
        'Just ('LiteralEnum marker cases)
    LookupSchemaPrimitive marker (('GlobalSchema reachability ('TaggedUnion marker cases)) ': rest) =
        'Just ('TaggedUnion marker cases)
    LookupSchemaPrimitive marker (('GlobalSchema reachability ('TaggedUnionWithTag marker tag cases)) ': rest) =
        'Just ('TaggedUnionWithTag marker tag cases)
    LookupSchemaPrimitive marker (primitive ': rest) = LookupSchemaPrimitive marker rest

type family LookupSchema (contracts :: [FrontendContractSpec]) (marker :: Type) :: Maybe SchemaPrimitive where
    LookupSchema '[] marker = 'Nothing
    LookupSchema (('Global root primitives) ': rest) marker =
        FirstJust (LookupSchemaPrimitive marker primitives) (LookupSchema rest marker)

type family RequireSchema (marker :: Type) (schema :: Maybe SchemaPrimitive) :: SchemaPrimitive where
    RequireSchema marker ('Just schema) = schema
    RequireSchema marker 'Nothing =
        TypeError
            ( 'Text "Registered FrontendContract does not declare schema marker "
                ':<>: 'ShowType marker
            )

type SchemaIn contracts marker = RequireSchema marker (LookupSchema contracts marker)

type family RecordFieldSpecs (schema :: SchemaPrimitive) :: [FieldSpec] where
    RecordFieldSpecs ('Record marker fields) = fields
    RecordFieldSpecs schema =
        TypeError
            ( 'Text "FrontendContract carrier expected a Record schema, received "
                ':<>: 'ShowType schema
            )

type family TaggedCaseSpecs (schema :: SchemaPrimitive) :: [UnionCaseSpec] where
    TaggedCaseSpecs ('TaggedUnion marker cases) = cases
    TaggedCaseSpecs ('TaggedUnionWithTag marker discriminator cases) = cases
    TaggedCaseSpecs schema =
        TypeError
            ( 'Text "FrontendContract carrier expected a TaggedUnion schema, received "
                ':<>: 'ShowType schema
            )

type family LookupUnionCase (caseMarker :: Type) (cases :: [UnionCaseSpec]) :: Maybe [FieldSpec] where
    LookupUnionCase caseMarker '[] = 'Nothing
    LookupUnionCase caseMarker (('Case caseMarker fields) ': rest) = 'Just fields
    LookupUnionCase caseMarker (caseSpec ': rest) = LookupUnionCase caseMarker rest

type family RequireUnionCase (schemaMarker :: Type) (caseMarker :: Type) (fields :: Maybe [FieldSpec]) :: [FieldSpec] where
    RequireUnionCase schemaMarker caseMarker ('Just fields) = fields
    RequireUnionCase schemaMarker caseMarker 'Nothing =
        TypeError
            ( 'Text "FrontendContract schema "
                ':<>: 'ShowType schemaMarker
                ':<>: 'Text " does not declare union case marker "
                ':<>: 'ShowType caseMarker
            )

type UnionCaseFieldSpecs contracts schemaMarker caseMarker =
    RequireUnionCase schemaMarker caseMarker (LookupUnionCase caseMarker (TaggedCaseSpecs (SchemaIn contracts schemaMarker)))

type family LookupEventPrimitive (marker :: Type) (primitives :: [GlobalPrimitive]) :: Maybe [FieldSpec] where
    LookupEventPrimitive marker '[] = 'Nothing
    LookupEventPrimitive marker (('Event reachability marker fields) ': rest) = 'Just fields
    LookupEventPrimitive marker (primitive ': rest) = LookupEventPrimitive marker rest

type family LookupEvent (contracts :: [FrontendContractSpec]) (marker :: Type) :: Maybe [FieldSpec] where
    LookupEvent '[] marker = 'Nothing
    LookupEvent (('Global root primitives) ': rest) marker =
        FirstJust (LookupEventPrimitive marker primitives) (LookupEvent rest marker)

type family RequireEvent (marker :: Type) (fields :: Maybe [FieldSpec]) :: [FieldSpec] where
    RequireEvent marker ('Just fields) = fields
    RequireEvent marker 'Nothing =
        TypeError
            ( 'Text "Registered FrontendContract does not declare event marker "
                ':<>: 'ShowType marker
            )

type EventFieldSpecs contracts marker = RequireEvent marker (LookupEvent contracts marker)

-- Typed fields ---------------------------------------------------------------

data CarrierField (field :: FieldSpec) where
    RequiredCarrierField ::
        KnownWireCodec wire =>
        WireSourceType wire ->
        CarrierField ('Field marker wire)
    OptionalCarrierField ::
        KnownWireCodec wire =>
        Maybe (WireSourceType wire) ->
        CarrierField ('OptionalField marker wire)
    NullableCarrierField ::
        KnownWireCodec wire =>
        Maybe (WireSourceType wire) ->
        CarrierField ('NullableField marker wire)

data CarrierFields (fields :: [FieldSpec]) where
    NoCarrierFields :: CarrierFields '[]
    ConsCarrierField :: CarrierField field -> CarrierFields rest -> CarrierFields (field ': rest)

type family CarrierFieldValues (fields :: [FieldSpec]) :: Type where
    CarrierFieldValues '[] = ()
    CarrierFieldValues (('Field marker wire) ': rest) =
        (WireSourceType wire, CarrierFieldValues rest)
    CarrierFieldValues (('OptionalField marker wire) ': rest) =
        (Maybe (WireSourceType wire), CarrierFieldValues rest)
    CarrierFieldValues (('NullableField marker wire) ': rest) =
        (Maybe (WireSourceType wire), CarrierFieldValues rest)

requiredField :: forall marker wire. KnownWireCodec wire => WireSourceType wire -> CarrierField ('Field marker wire)
requiredField = RequiredCarrierField

optionalField :: forall marker wire. KnownWireCodec wire => Maybe (WireSourceType wire) -> CarrierField ('OptionalField marker wire)
optionalField = OptionalCarrierField

nullableField :: forall marker wire. KnownWireCodec wire => Maybe (WireSourceType wire) -> CarrierField ('NullableField marker wire)
nullableField = NullableCarrierField

noFields :: CarrierFields '[]
noFields = NoCarrierFields

(&:) :: CarrierField field -> CarrierFields rest -> CarrierFields (field ': rest)
(&:) = ConsCarrierField
infixr 5 &:

carrierFieldValues :: CarrierFields fields -> CarrierFieldValues fields
carrierFieldValues NoCarrierFields = ()
carrierFieldValues (ConsCarrierField field rest) =
    case field of
        RequiredCarrierField value -> (value, carrierFieldValues rest)
        OptionalCarrierField value -> (value, carrierFieldValues rest)
        NullableCarrierField value -> (value, carrierFieldValues rest)

class KnownCarrierFields (fields :: [FieldSpec]) where
    carrierFieldPairs :: CarrierFields fields -> [AesonTypes.Pair]
    parseCarrierFieldsObject :: Aeson.Object -> AesonTypes.Parser (CarrierFields fields)

instance KnownCarrierFields '[] where
    carrierFieldPairs NoCarrierFields = []
    parseCarrierFieldsObject _ = pure NoCarrierFields

instance
    ( Typeable marker
    , KnownWireCodec wire
    , KnownCarrierFields rest
    ) => KnownCarrierFields (('Field marker wire) ': rest) where
    carrierFieldPairs (ConsCarrierField (RequiredCarrierField value) rest) =
        (AesonKey.fromText (fieldName @marker) Aeson..= carrierWireJson @wire value)
            : carrierFieldPairs rest
    parseCarrierFieldsObject object = do
        raw <- requiredObjectField @marker object
        value <- parseCarrierWire @wire raw
        rest <- parseCarrierFieldsObject @rest object
        pure (RequiredCarrierField value &: rest)

instance
    ( Typeable marker
    , KnownWireCodec wire
    , KnownCarrierFields rest
    ) => KnownCarrierFields (('OptionalField marker wire) ': rest) where
    carrierFieldPairs (ConsCarrierField (OptionalCarrierField value) rest) =
        maybe
            id
            (\present pairs -> (AesonKey.fromText (fieldName @marker) Aeson..= carrierWireJson @wire present) : pairs)
            value
            (carrierFieldPairs rest)
    parseCarrierFieldsObject object = do
        value <-
            case KeyMap.lookup (AesonKey.fromText (fieldName @marker)) object of
                Nothing  -> pure Nothing
                Just raw -> Just <$> parseCarrierWire @wire raw
        rest <- parseCarrierFieldsObject @rest object
        pure (OptionalCarrierField value &: rest)

instance
    ( Typeable marker
    , KnownWireCodec wire
    , KnownCarrierFields rest
    ) => KnownCarrierFields (('NullableField marker wire) ': rest) where
    carrierFieldPairs (ConsCarrierField (NullableCarrierField value) rest) =
        ( AesonKey.fromText (fieldName @marker)
            Aeson..= maybe Aeson.Null (carrierWireJson @wire) value
        ) : carrierFieldPairs rest
    parseCarrierFieldsObject object = do
        raw <- requiredObjectField @marker object
        value <-
            case raw of
                Aeson.Null -> pure Nothing
                present    -> Just <$> parseCarrierWire @wire present
        rest <- parseCarrierFieldsObject @rest object
        pure (NullableCarrierField value &: rest)

requiredObjectField :: forall marker. Typeable marker => Aeson.Object -> AesonTypes.Parser Aeson.Value
requiredObjectField object =
    maybe
        (fail ("missing required field " <> cs (fieldName @marker)))
        pure
        (KeyMap.lookup (AesonKey.fromText (fieldName @marker)) object)

fieldName :: forall marker. Typeable marker => Text
fieldName = Naming.deriveFrontendSurfaceTypeName @marker Naming.FieldName

-- Wire codecs ----------------------------------------------------------------

class KnownWireCodec (wire :: WireType) where
    carrierWireJson :: WireSourceType wire -> Aeson.Value
    parseCarrierWire :: Aeson.Value -> AesonTypes.Parser (WireSourceType wire)

instance KnownWireCodec 'WireText where
    carrierWireJson = Aeson.String
    parseCarrierWire = Aeson.withText "FrontendContract WireText" pure

instance KnownWireCodec 'WireInt where
    carrierWireJson = Aeson.toJSON
    parseCarrierWire = Aeson.parseJSON

instance KnownWireCodec 'WireBool where
    carrierWireJson = Aeson.Bool
    parseCarrierWire = Aeson.parseJSON

instance KnownWireCodec 'WireUUID where
    carrierWireJson = Aeson.String . UUID.toText
    parseCarrierWire = Aeson.withText "FrontendContract WireUUID" \value ->
        maybe (fail "FrontendContract UUID field is malformed") pure (UUID.fromText value)

instance KnownWireCodec 'WireDay where
    carrierWireJson = Aeson.String . cs . formatTime defaultTimeLocale "%F"
    parseCarrierWire = Aeson.withText "FrontendContract WireDay" \value ->
        maybe
            (fail "FrontendContract day field is malformed")
            pure
            (parseTimeM True defaultTimeLocale "%F" (cs value))

instance KnownClosedScalar value => KnownWireCodec ('WireClosed value) where
    carrierWireJson = Aeson.String . closedScalarLiteral
    parseCarrierWire = Aeson.withText "FrontendContract WireClosed" \literal ->
        maybe
            (fail ("FrontendContract closed scalar has invalid literal: " <> cs literal))
            pure
            (parseClosedScalarLiteral @value literal)

instance KnownWireCodec 'WireUnknown where
    carrierWireJson = id
    parseCarrierWire = pure

instance KnownWireCodec inner => KnownWireCodec ('WireList inner) where
    carrierWireJson = Aeson.Array . Vector.fromList . fmap (carrierWireJson @inner)
    parseCarrierWire = Aeson.withArray "FrontendContract WireList" (mapM (parseCarrierWire @inner) . toList)

instance KnownWireCodec inner => KnownWireCodec ('WireOptional inner) where
    carrierWireJson = maybe Aeson.Null (carrierWireJson @inner)
    parseCarrierWire Aeson.Null = pure Nothing
    parseCarrierWire value      = Just <$> parseCarrierWire @inner value

instance KnownWireCodec inner => KnownWireCodec ('WireNullable inner) where
    carrierWireJson = maybe Aeson.Null (carrierWireJson @inner)
    parseCarrierWire Aeson.Null = pure Nothing
    parseCarrierWire value      = Just <$> parseCarrierWire @inner value

instance ContractReference marker => KnownWireCodec ('WireRef marker) where
    carrierWireJson = contractReferenceJson @marker
    parseCarrierWire = parseContractReference @marker

instance CustomWire 'WireSurfaceScope => KnownWireCodec 'WireSurfaceScope where
    carrierWireJson = customWireJson @'WireSurfaceScope
    parseCarrierWire = parseCustomWire @'WireSurfaceScope

instance CustomWire 'WireSurfaceFragmentKey => KnownWireCodec 'WireSurfaceFragmentKey where
    carrierWireJson = customWireJson @'WireSurfaceFragmentKey
    parseCarrierWire = parseCustomWire @'WireSurfaceFragmentKey

-- Record and event builders/parsers ------------------------------------------

recordValueIn ::
    forall contracts marker.
    KnownCarrierFields (RecordFieldSpecs (SchemaIn contracts marker)) =>
    CarrierFields (RecordFieldSpecs (SchemaIn contracts marker)) ->
    Aeson.Value
recordValueIn = Aeson.object . carrierFieldPairs

recordValue ::
    forall marker.
    KnownCarrierFields (RecordFieldSpecs (SchemaIn RegisteredFrontendContracts marker)) =>
    CarrierFields (RecordFieldSpecs (SchemaIn RegisteredFrontendContracts marker)) ->
    Aeson.Value
recordValue = recordValueIn @RegisteredFrontendContracts @marker

parseRecordIn ::
    forall contracts marker result.
    ( ReflectFrontendContractRegistry contracts
    , Typeable marker
    , KnownCarrierFields (RecordFieldSpecs (SchemaIn contracts marker))
    ) =>
    (CarrierFieldValues (RecordFieldSpecs (SchemaIn contracts marker)) -> AesonTypes.Parser result) ->
    Aeson.Value ->
    AesonTypes.Parser result
parseRecordIn =
    parseRecordWith @marker @(RecordFieldSpecs (SchemaIn contracts marker))
        (reflectFrontendContracts @contracts)

parseRecord ::
    forall marker result.
    ( Typeable marker
    , KnownCarrierFields (RecordFieldSpecs (SchemaIn RegisteredFrontendContracts marker))
    ) =>
    (CarrierFieldValues (RecordFieldSpecs (SchemaIn RegisteredFrontendContracts marker)) -> AesonTypes.Parser result) ->
    Aeson.Value ->
    AesonTypes.Parser result
parseRecord =
    parseRecordWith @marker @(RecordFieldSpecs (SchemaIn RegisteredFrontendContracts marker))
        registeredFrontendContractIR

parseRecordWith ::
    forall marker fields result.
    (Typeable marker, KnownCarrierFields fields) =>
    Contract.FrontendContractIR ->
    (CarrierFieldValues fields -> AesonTypes.Parser result) ->
    Aeson.Value ->
    AesonTypes.Parser result
parseRecordWith contract build raw = do
    validateContractMarkerValueWith @marker contract raw
    Aeson.withObject (cs (markerName @marker))
        (\object -> parseCarrierFieldsObject @fields object >>= build . carrierFieldValues)
        raw

eventValueIn ::
    forall contracts marker.
    KnownCarrierFields (EventFieldSpecs contracts marker) =>
    CarrierFields (EventFieldSpecs contracts marker) ->
    Aeson.Value
eventValueIn = Aeson.object . carrierFieldPairs

eventValue ::
    forall marker.
    KnownCarrierFields (EventFieldSpecs RegisteredFrontendContracts marker) =>
    CarrierFields (EventFieldSpecs RegisteredFrontendContracts marker) ->
    Aeson.Value
eventValue = eventValueIn @RegisteredFrontendContracts @marker

parseEvent ::
    forall marker result.
    ( Typeable marker
    , KnownCarrierFields (EventFieldSpecs RegisteredFrontendContracts marker)
    ) =>
    (CarrierFieldValues (EventFieldSpecs RegisteredFrontendContracts marker) -> AesonTypes.Parser result) ->
    Aeson.Value ->
    AesonTypes.Parser result
parseEvent =
    parseRecordWith @marker @(EventFieldSpecs RegisteredFrontendContracts marker)
        registeredFrontendContractIR

-- Tagged unions --------------------------------------------------------------

class KnownTaggedSchema (schema :: SchemaPrimitive) where
    taggedDiscriminator :: Text

instance KnownTaggedSchema ('TaggedUnion marker cases) where
    taggedDiscriminator = "tag"

instance KnownSymbol discriminator => KnownTaggedSchema ('TaggedUnionWithTag marker discriminator cases) where
    taggedDiscriminator = cs (symbolVal (Proxy @discriminator))

taggedUnionValueIn ::
    forall contracts schemaMarker caseMarker.
    ( Typeable caseMarker
    , KnownTaggedSchema (SchemaIn contracts schemaMarker)
    , KnownCarrierFields (UnionCaseFieldSpecs contracts schemaMarker caseMarker)
    ) =>
    CarrierFields (UnionCaseFieldSpecs contracts schemaMarker caseMarker) ->
    Aeson.Value
taggedUnionValueIn fields =
    Aeson.object
        ( (AesonKey.fromText discriminator Aeson..= caseTag @caseMarker)
            : carrierFieldPairs fields
        )
  where
    discriminator = taggedDiscriminator @(SchemaIn contracts schemaMarker)

taggedUnionValue ::
    forall schemaMarker caseMarker.
    ( Typeable caseMarker
    , KnownTaggedSchema (SchemaIn RegisteredFrontendContracts schemaMarker)
    , KnownCarrierFields (UnionCaseFieldSpecs RegisteredFrontendContracts schemaMarker caseMarker)
    ) =>
    CarrierFields (UnionCaseFieldSpecs RegisteredFrontendContracts schemaMarker caseMarker) ->
    Aeson.Value
taggedUnionValue = taggedUnionValueIn @RegisteredFrontendContracts @schemaMarker @caseMarker

data UnionCaseParsers (cases :: [UnionCaseSpec]) result where
    NoUnionCaseParsers :: UnionCaseParsers '[] result
    ConsUnionCaseParser ::
        (CarrierFieldValues fields -> AesonTypes.Parser result) ->
        UnionCaseParsers rest result ->
        UnionCaseParsers (('Case marker fields) ': rest) result

unionCase ::
    forall marker fields result.
    (CarrierFieldValues fields -> AesonTypes.Parser result) ->
    UnionCaseParsers '[ 'Case marker fields] result
unionCase build = ConsUnionCaseParser build NoUnionCaseParsers

noUnionCases :: UnionCaseParsers '[] result
noUnionCases = NoUnionCaseParsers

(|:) ::
    UnionCaseParsers '[ 'Case marker fields] result ->
    UnionCaseParsers rest result ->
    UnionCaseParsers (('Case marker fields) ': rest) result
ConsUnionCaseParser build NoUnionCaseParsers |: rest = ConsUnionCaseParser build rest
infixr 4 |:

class ParseUnionCases (cases :: [UnionCaseSpec]) where
    parseDeclaredUnionCase ::
        Text ->
        Aeson.Object ->
        UnionCaseParsers cases result ->
        AesonTypes.Parser result

instance ParseUnionCases '[] where
    parseDeclaredUnionCase tag _ NoUnionCaseParsers =
        fail ("validated FrontendContract union case is unavailable: " <> cs tag)

instance
    ( Typeable marker
    , KnownCarrierFields fields
    , ParseUnionCases rest
    ) => ParseUnionCases (('Case marker fields) ': rest) where
    parseDeclaredUnionCase tag object (ConsUnionCaseParser build rest)
        | tag == caseTag @marker =
            parseCarrierFieldsObject @fields object >>= build . carrierFieldValues
        | otherwise = parseDeclaredUnionCase @rest tag object rest

parseTaggedUnionIn ::
    forall contracts marker result.
    ( ReflectFrontendContractRegistry contracts
    , Typeable marker
    , KnownTaggedSchema (SchemaIn contracts marker)
    , ParseUnionCases (TaggedCaseSpecs (SchemaIn contracts marker))
    ) =>
    UnionCaseParsers (TaggedCaseSpecs (SchemaIn contracts marker)) result ->
    Aeson.Value ->
    AesonTypes.Parser result
parseTaggedUnionIn =
    parseTaggedUnionWith @marker @(SchemaIn contracts marker)
        (reflectFrontendContracts @contracts)

parseTaggedUnion ::
    forall marker result.
    ( Typeable marker
    , KnownTaggedSchema (SchemaIn RegisteredFrontendContracts marker)
    , ParseUnionCases (TaggedCaseSpecs (SchemaIn RegisteredFrontendContracts marker))
    ) =>
    UnionCaseParsers (TaggedCaseSpecs (SchemaIn RegisteredFrontendContracts marker)) result ->
    Aeson.Value ->
    AesonTypes.Parser result
parseTaggedUnion =
    parseTaggedUnionWith @marker @(SchemaIn RegisteredFrontendContracts marker)
        registeredFrontendContractIR

parseTaggedUnionWith ::
    forall marker schema result.
    ( Typeable marker
    , KnownTaggedSchema schema
    , ParseUnionCases (TaggedCaseSpecs schema)
    ) =>
    Contract.FrontendContractIR ->
    UnionCaseParsers (TaggedCaseSpecs schema) result ->
    Aeson.Value ->
    AesonTypes.Parser result
parseTaggedUnionWith contract parsers raw = do
    validateContractMarkerValueWith @marker contract raw
    Aeson.withObject (cs (markerName @marker))
        (\object -> do
            tag <- object Aeson..: AesonKey.fromText (taggedDiscriminator @schema)
            parseDeclaredUnionCase @(TaggedCaseSpecs schema) tag object parsers
        )
        raw

caseTag :: forall marker. Typeable marker => Text
caseTag = Naming.nameToKebab (markerName @marker)

markerName :: forall marker. Typeable marker => Text
markerName = cs (tyConName (typeRepTyCon (typeRep (Proxy @marker))))
