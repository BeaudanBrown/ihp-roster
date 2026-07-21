{-# LANGUAGE AllowAmbiguousTypes  #-}
{-# LANGUAGE ConstraintKinds      #-}
{-# LANGUAGE DataKinds            #-}
{-# LANGUAGE FlexibleContexts     #-}
{-# LANGUAGE FlexibleInstances    #-}
{-# LANGUAGE GADTs                #-}
{-# LANGUAGE LambdaCase           #-}
{-# LANGUAGE PolyKinds            #-}
{-# LANGUAGE RoleAnnotations      #-}
{-# LANGUAGE ScopedTypeVariables  #-}
{-# LANGUAGE TypeApplications     #-}
{-# LANGUAGE TypeFamilies         #-}
{-# LANGUAGE TypeOperators        #-}
{-# LANGUAGE UndecidableInstances #-}

module Application.Helper.FrontendContract.Surface.Values
    ( AssertBrowserReachableSurfaceDto
    , FindMountTarget
    , KnownMountTarget
    , KnownSurfaceFieldLookup
    , KnownSurfaceFieldValues
    , KnownSurfaceWireValue (..)
    , LookupSurfaceField
    , RequireBrowserClosedStateValue
    , RequireCompleteSetSortKey
    , RequireSurfaceField
    , RequireSurfaceTabKey
    , SurfaceActionFieldSpecs
    , SurfaceActionFields
    , SurfaceActionPrimitive
    , SurfaceActivationRefPrimitive
    , SurfaceBrowserRolePrimitive
    , SurfaceBrowserStatePrimitive
    , SurfaceBrowserClosedStatePrimitive
    , SurfaceCompleteSetSortPrimitive
    , SurfaceCompleteSetSortRowDto
    , SurfaceCompleteSetSortRowFieldSpecs
    , SurfaceLinkedHighlightPrimitive
    , SurfaceTabSetPrimitive
    , SurfaceFieldBundle
    , SurfaceFieldBundleOf
    , SurfaceFieldBundleSpecs
    , SurfaceFieldLookup (..)
    , SurfaceFieldValue
    , SurfaceFieldValues
    , SurfaceFields
    , SurfaceFragmentFieldSpecs
    , SurfaceFragmentOptionSpecs
    , SurfaceFragmentTargetFieldSpecs
    , SurfaceDomTokenPrimitive
    , SurfaceDropzoneRefPrimitive
    , SurfaceDtoFieldSpecs
    , SurfaceDtoPrimitive
    , SurfaceFragmentPrimitive
    , SurfaceIntentFieldSpecs
    , SurfaceIntentFields
    , SurfaceIntentPrimitive
    , SurfaceMountStateFieldSpecs
    , SurfaceResourceFieldSpecs
    , SurfaceResourceSpec
    , SurfaceScopeFieldSpecs
    , SurfaceScopePrimitive
    , SurfaceSourceRefPrimitive
    , SurfaceWireValue
    , noSurfaceActionFields
    , noSurfaceFields
    , noSurfaceIntentFields
    , surfaceActionFields
    , surfaceActionNameValue
    , surfaceField
    , surfaceFieldNameFrom
    , surfaceFieldsJson
    , surfaceFieldsText
    , surfaceFieldValue
    , surfaceNullableField
    , surfaceOptionalField
    , parseSurfaceFieldValues
    , prependRequiredSurfaceField
    , prependOptionalSurfaceField
    , prependNullableSurfaceField
    , surfaceActivationRefValue
    , surfaceBrowserRoleValue
    , surfaceBrowserStateValue
    , surfaceBrowserClosedStateValue
    , surfaceBrowserClosedStateLiteral
    , surfaceCompleteSetSortValue
    , surfaceLinkedHighlightValue
    , surfaceTabSetValue
    , surfaceDomTokenValue
    , surfaceDropzoneRefValue
    , surfaceFragmentFieldName
    , surfaceFragmentNameValue
    , surfaceFragmentTargetId
    , surfaceFragmentValue
    , surfaceIntentFields
    , surfaceIntentNameValue
    , surfaceNameValue
    , surfaceResourceValue
    , surfaceScopeFieldName
    , surfaceScopeValue
    , surfaceSourceRefValue
    , (&:)
    ) where

import qualified Application.Helper.FrontendContract.Naming as Naming
import Application.Helper.FrontendContract.Surface.ContractIR
import Application.Helper.FrontendContract.Surface.Diagnostics
import Application.Helper.FrontendContract.Surface.DSL
import Application.Helper.FrontendContract.Surface.Reflect
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as Aeson.Key
import qualified Data.Aeson.KeyMap as Aeson.KeyMap
import qualified Data.Aeson.Types as Aeson.Types
import qualified Data.ByteString.Lazy as LBS
import Data.Foldable (toList)
import Data.Kind (Constraint, Type)
import qualified Data.Text as Text
import qualified Data.Text.Encoding as Text.Encoding
import Data.Time (Day, defaultTimeLocale, formatTime, parseTimeM)
import Data.Typeable (Typeable)
import qualified Data.UUID as UUID
import GHC.TypeLits (ErrorMessage (..), TypeError)
import IHP.Prelude

-- | One caller-provided field whose wire is still fixed by the exact owning
-- declaration. Presence and marker stay separate long enough for focused
-- diagnostics, while the stored value remains the same typed runtime value.
data SurfaceFieldInput (presence :: SurfaceFieldPresence) (marker :: Type) (wire :: WireType) where
    RequiredSurfaceField ::
        forall marker wire.
        (Typeable marker, KnownSurfaceWireValue wire) =>
        SurfaceWireValue wire -> SurfaceFieldInput 'SurfaceRequired marker wire
    OptionalSurfaceField ::
        forall marker wire.
        (Typeable marker, KnownSurfaceWireValue wire) =>
        Maybe (SurfaceWireValue wire) -> SurfaceFieldInput 'SurfaceOptional marker wire
    NullableSurfaceField ::
        forall marker wire.
        (Typeable marker, KnownSurfaceWireValue wire) =>
        Maybe (SurfaceWireValue wire) -> SurfaceFieldInput 'SurfaceNullable marker wire

-- | Exact, declaration-ordered values for one Surface field list. The expected
-- declaration remains the sole index, preserving declaration-driven inference.
-- Constructor constraints replace generic promoted-list errors with compact
-- missing, extra, order, presence, and wire diagnostics.
data SurfaceFields (fields :: [FieldSpec]) where
    NoSurfaceFields ::
        AssertSurfaceFieldsEnd fields =>
        SurfaceFields fields
    (:&) ::
        AssertSurfaceFieldHead presence marker (SurfaceFieldInputWire fields fallback) fields =>
        SurfaceFieldInput presence marker (SurfaceFieldInputWire fields fallback) ->
        SurfaceFields (SurfaceFieldsTail fields) ->
        SurfaceFields fields

infixr 5 :&

-- | Complete an exact declaration without exposing its raw data constructor.
noSurfaceFields ::
    AssertSurfaceFieldsEnd fields =>
    SurfaceFields fields
noSurfaceFields = NoSurfaceFields

-- | Add one declaration-directed field without exposing a pattern that can
-- destructure and re-index a completed field bundle.
(&:) ::
    forall presence marker fields fallback.
    AssertSurfaceFieldHead presence marker (SurfaceFieldInputWire fields fallback) fields =>
    SurfaceFieldInput presence marker (SurfaceFieldInputWire fields fallback) ->
    SurfaceFields (SurfaceFieldsTail fields) ->
    SurfaceFields fields
(&:) field rest = (:&) @presence @marker @fields @fallback field rest

infixr 5 &:

-- | Internal first-field-plus-tail representation for one nominal operation.
-- Unlike 'SurfaceFields', its first input may carry an existential wire from a
-- parser; the closed head assertion still proves that it is the declared field.
data BoundSurfaceFields (fields :: [FieldSpec]) where
    NoBoundSurfaceFields ::
        AssertSurfaceFieldsEnd fields =>
        BoundSurfaceFields fields
    BoundSurfaceField ::
        AssertSurfaceFieldHead presence marker wire fields =>
        SurfaceFieldInput presence marker wire ->
        SurfaceFields (SurfaceFieldsTail fields) ->
        BoundSurfaceFields fields

-- | Nominal, operation-indexed request bundles exposed by generated adapters.
-- The declaration-shaped values remain private, while the owning Surface and
-- operation marker stay generative at the generated builder/metadata/parser
-- seam even when two declarations normalize to the same field list.
newtype SurfaceActionFields (spec :: SurfaceSpec) (marker :: Type) =
    SurfaceActionFields (BoundSurfaceFields (SurfaceActionFieldSpecs spec marker))

type role SurfaceActionFields nominal nominal

newtype SurfaceIntentFields (spec :: SurfaceSpec) (marker :: Type) =
    SurfaceIntentFields (BoundSurfaceFields (SurfaceIntentFieldSpecs spec marker))

type role SurfaceIntentFields nominal nominal

type family SurfaceFieldBundleSpecs (bundle :: Type) :: [FieldSpec] where
    SurfaceFieldBundleSpecs (SurfaceFields fields) = fields
    SurfaceFieldBundleSpecs (SurfaceActionFields spec marker) = SurfaceActionFieldSpecs spec marker
    SurfaceFieldBundleSpecs (SurfaceIntentFields spec marker) = SurfaceIntentFieldSpecs spec marker

-- | Read-only common interface for raw declaration fields and nominal generated
-- request bundles. Construction of the nominal wrappers remains explicit in
-- generated builders; consumers can still use marker-indexed lookup,
-- serialization, and form-name access without discarding operation identity or
-- gaining access to the wrapped raw bundle.
class SurfaceFieldBundle bundle where
    surfaceFieldBundleJsonPairs :: bundle -> [Aeson.Types.Pair]
    surfaceFieldBundleTextValue :: bundle -> [(Text, Text)]

instance SurfaceFieldBundle (SurfaceFields fields) where
    surfaceFieldBundleJsonPairs = surfaceFieldJsonPairs
    surfaceFieldBundleTextValue = surfaceFieldsTextValue

instance SurfaceFieldBundle (SurfaceActionFields spec marker) where
    surfaceFieldBundleJsonPairs (SurfaceActionFields fields) = boundSurfaceFieldJsonPairs fields
    surfaceFieldBundleTextValue (SurfaceActionFields fields) = boundSurfaceFieldsTextValue fields

instance SurfaceFieldBundle (SurfaceIntentFields spec marker) where
    surfaceFieldBundleJsonPairs (SurfaceIntentFields fields) = boundSurfaceFieldJsonPairs fields
    surfaceFieldBundleTextValue (SurfaceIntentFields fields) = boundSurfaceFieldsTextValue fields

type SurfaceFieldBundleOf fields bundle =
    ( SurfaceFieldBundle bundle
    , SurfaceFieldBundleSpecs bundle ~ fields
    )

noSurfaceActionFields ::
    forall spec operation.
    AssertSurfaceFieldsEnd (SurfaceActionFieldSpecs spec operation) =>
    SurfaceActionFields spec operation
noSurfaceActionFields = SurfaceActionFields NoBoundSurfaceFields

surfaceActionFields ::
    forall spec operation presence fieldMarker fallback.
    AssertSurfaceFieldHead
        presence
        fieldMarker
        (SurfaceFieldInputWire (SurfaceActionFieldSpecs spec operation) fallback)
        (SurfaceActionFieldSpecs spec operation) =>
    SurfaceFieldInput
        presence
        fieldMarker
        (SurfaceFieldInputWire (SurfaceActionFieldSpecs spec operation) fallback) ->
    SurfaceFields (SurfaceFieldsTail (SurfaceActionFieldSpecs spec operation)) ->
    SurfaceActionFields spec operation
surfaceActionFields field rest =
    SurfaceActionFields (BoundSurfaceField field rest)

noSurfaceIntentFields ::
    forall spec operation.
    AssertSurfaceFieldsEnd (SurfaceIntentFieldSpecs spec operation) =>
    SurfaceIntentFields spec operation
noSurfaceIntentFields = SurfaceIntentFields NoBoundSurfaceFields

surfaceIntentFields ::
    forall spec operation presence fieldMarker fallback.
    AssertSurfaceFieldHead
        presence
        fieldMarker
        (SurfaceFieldInputWire (SurfaceIntentFieldSpecs spec operation) fallback)
        (SurfaceIntentFieldSpecs spec operation) =>
    SurfaceFieldInput
        presence
        fieldMarker
        (SurfaceFieldInputWire (SurfaceIntentFieldSpecs spec operation) fallback) ->
    SurfaceFields (SurfaceFieldsTail (SurfaceIntentFieldSpecs spec operation)) ->
    SurfaceIntentFields spec operation
surfaceIntentFields field rest =
    SurfaceIntentFields (BoundSurfaceField field rest)

type family SurfaceWireValue (wire :: WireType) :: Type where
    SurfaceWireValue 'WireText = Text
    SurfaceWireValue 'WireInt = Int
    SurfaceWireValue 'WireBool = Bool
    SurfaceWireValue 'WireUUID = UUID.UUID
    SurfaceWireValue 'WireDay = Day
    SurfaceWireValue ('WireList inner) = [SurfaceWireValue inner]
    SurfaceWireValue ('WireOptional inner) = Maybe (SurfaceWireValue inner)
    SurfaceWireValue ('WireNullable inner) = Maybe (SurfaceWireValue inner)
    SurfaceWireValue ('WireRef dto) = Aeson.Value

-- | Declaration-ordered typed values recovered by live identity matchers.
-- Field names, presence, and wire types remain indexed by the owning Surface
-- declaration; feature code receives values, never raw JSON identity.
type family SurfaceFieldValues (fields :: [FieldSpec]) :: Type where
    SurfaceFieldValues '[] = ()
    SurfaceFieldValues (('Field marker wire) ': rest) = (SurfaceWireValue wire, SurfaceFieldValues rest)
    SurfaceFieldValues (('OptionalField marker wire) ': rest) = (Maybe (SurfaceWireValue wire), SurfaceFieldValues rest)
    SurfaceFieldValues (('NullableField marker wire) ': rest) = (Maybe (SurfaceWireValue wire), SurfaceFieldValues rest)

-- | Presence and wire information for one marker inside an exact field bundle.
-- Looking up a marker not owned by the bundle is a compile-time error.
data SurfaceFieldLookup
    = SurfaceFieldRequired WireType
    | SurfaceFieldOptional WireType
    | SurfaceFieldNullable WireType

-- | Resolve a field marker against the complete declaration carried by
-- 'SurfaceFields'. Callers cannot ask for a marker absent from that declaration.
type family LookupSurfaceField (marker :: Type) (fields :: [FieldSpec]) :: SurfaceFieldLookup where
    LookupSurfaceField marker (('Field marker wire) ': rest) = 'SurfaceFieldRequired wire
    LookupSurfaceField marker (('OptionalField marker wire) ': rest) = 'SurfaceFieldOptional wire
    LookupSurfaceField marker (('NullableField marker wire) ': rest) = 'SurfaceFieldNullable wire
    LookupSurfaceField marker (field ': rest) = LookupSurfaceField marker rest
    LookupSurfaceField marker '[] = TypeError
        ( 'Text "FrontendSurface field bundle does not declare marker "
            ':<>: 'ShowType marker
        )

-- | The Haskell value returned by a marker-indexed field lookup. Required
-- fields return their declared wire value; optional and nullable fields retain
-- their distinct @Maybe@ boundary.
type family SurfaceFieldValue (marker :: Type) (fields :: [FieldSpec]) :: Type where
    SurfaceFieldValue marker fields = SurfaceFieldLookupValue (LookupSurfaceField marker fields)

type family SurfaceFieldLookupValue (lookup :: SurfaceFieldLookup) :: Type where
    SurfaceFieldLookupValue ('SurfaceFieldRequired wire) = SurfaceWireValue wire
    SurfaceFieldLookupValue ('SurfaceFieldOptional wire) = Maybe (SurfaceWireValue wire)
    SurfaceFieldLookupValue ('SurfaceFieldNullable wire) = Maybe (SurfaceWireValue wire)

class KnownSurfaceWireValue (wire :: WireType) where
    surfaceWireJson :: SurfaceWireValue wire -> Aeson.Value
    surfaceWireText :: SurfaceWireValue wire -> Text
    parseSurfaceWireValue :: Aeson.Value -> Aeson.Types.Parser (SurfaceWireValue wire)

instance KnownSurfaceWireValue 'WireText where
    surfaceWireJson = Aeson.String
    surfaceWireText = id
    parseSurfaceWireValue = Aeson.withText "Surface WireText" pure

instance KnownSurfaceWireValue 'WireInt where
    surfaceWireJson = Aeson.toJSON
    surfaceWireText = tshow
    parseSurfaceWireValue = Aeson.parseJSON

instance KnownSurfaceWireValue 'WireBool where
    surfaceWireJson = Aeson.Bool
    surfaceWireText value = if value then "true" else "false"
    parseSurfaceWireValue = Aeson.parseJSON

instance KnownSurfaceWireValue 'WireUUID where
    surfaceWireJson = Aeson.String . UUID.toText
    surfaceWireText = UUID.toText
    parseSurfaceWireValue = Aeson.withText "Surface WireUUID" \value ->
        maybe (fail "Surface UUID field is malformed") pure (UUID.fromText value)

instance KnownSurfaceWireValue 'WireDay where
    surfaceWireJson = Aeson.String . surfaceWireText @'WireDay
    surfaceWireText = cs . formatTime defaultTimeLocale "%F"
    parseSurfaceWireValue = Aeson.withText "Surface WireDay" \value ->
        maybe (fail "Surface day field is malformed") pure (parseTimeM True defaultTimeLocale "%F" (cs value))

instance KnownSurfaceWireValue inner => KnownSurfaceWireValue ('WireList inner) where
    surfaceWireJson = Aeson.toJSON . fmap (surfaceWireJson @inner)
    surfaceWireText = jsonText . surfaceWireJson @('WireList inner)
    parseSurfaceWireValue = Aeson.withArray "Surface WireList" (mapM (parseSurfaceWireValue @inner) . toList)

instance KnownSurfaceWireValue inner => KnownSurfaceWireValue ('WireOptional inner) where
    surfaceWireJson = maybe Aeson.Null (surfaceWireJson @inner)
    surfaceWireText = maybe "" (surfaceWireText @inner)
    parseSurfaceWireValue Aeson.Null = pure Nothing
    parseSurfaceWireValue value      = Just <$> parseSurfaceWireValue @inner value

instance KnownSurfaceWireValue inner => KnownSurfaceWireValue ('WireNullable inner) where
    surfaceWireJson = maybe Aeson.Null (surfaceWireJson @inner)
    surfaceWireText = maybe "" (surfaceWireText @inner)
    parseSurfaceWireValue Aeson.Null = pure Nothing
    parseSurfaceWireValue value      = Just <$> parseSurfaceWireValue @inner value

instance KnownSurfaceWireValue ('WireRef dto) where
    surfaceWireJson = id
    surfaceWireText = jsonText
    parseSurfaceWireValue = pure

class KnownSurfaceFieldLookup (lookup :: SurfaceFieldLookup) where
    parseSurfaceFieldLookup :: Text -> Aeson.Object -> Aeson.Types.Parser (SurfaceFieldLookupValue lookup)

instance KnownSurfaceWireValue wire => KnownSurfaceFieldLookup ('SurfaceFieldRequired wire) where
    parseSurfaceFieldLookup fieldName object = do
        value <- requiredNamedFieldValue fieldName object
        parseSurfaceWireValue @wire value

instance KnownSurfaceWireValue wire => KnownSurfaceFieldLookup ('SurfaceFieldOptional wire) where
    parseSurfaceFieldLookup fieldName object =
        case Aeson.KeyMap.lookup (Aeson.Key.fromText fieldName) object of
            Nothing    -> pure Nothing
            Just value -> Just <$> parseSurfaceWireValue @wire value

instance KnownSurfaceWireValue wire => KnownSurfaceFieldLookup ('SurfaceFieldNullable wire) where
    parseSurfaceFieldLookup fieldName object = do
        value <- requiredNamedFieldValue fieldName object
        case value of
            Aeson.Null -> pure Nothing
            present    -> Just <$> parseSurfaceWireValue @wire present

-- | Read one declared value from a complete typed field bundle. The marker must
-- occur in the bundle at compile time; runtime parsing can only fail if the
-- internal 'SurfaceFields' serialization invariant is broken.
surfaceFieldValue ::
    forall marker bundle.
    ( SurfaceFieldBundle bundle
    , Typeable marker
    , KnownSurfaceFieldLookup (LookupSurfaceField marker (SurfaceFieldBundleSpecs bundle))
    ) =>
    bundle -> SurfaceFieldValue marker (SurfaceFieldBundleSpecs bundle)
surfaceFieldValue fields =
    case Aeson.Types.parseEither parser (surfaceFieldsJson fields) of
        Right value -> value
        Left message -> error ("Typed Surface field lookup invariant failed: " <> cs message)
  where
    parser =
        Aeson.withObject
            "SurfaceFields"
            ( parseSurfaceFieldLookup
                @(LookupSurfaceField marker (SurfaceFieldBundleSpecs bundle))
                (surfaceFieldName @marker)
            )

-- | Canonical form/input name for a marker proven to belong to this complete
-- bundle. Unlike the removed owner-only accessors, obtaining a name requires
-- constructing every field in the declaration first.
surfaceFieldNameFrom ::
    forall marker bundle.
    ( SurfaceFieldBundle bundle
    , Typeable marker
    , KnownSurfaceFieldLookup (LookupSurfaceField marker (SurfaceFieldBundleSpecs bundle))
    ) =>
    bundle -> Text
surfaceFieldNameFrom _ = surfaceFieldName @marker

requiredNamedFieldValue :: Text -> Aeson.Object -> Aeson.Types.Parser Aeson.Value
requiredNamedFieldValue fieldName object =
    maybe
        (fail ("Missing Surface field: " <> cs fieldName))
        pure
        (Aeson.KeyMap.lookup (Aeson.Key.fromText fieldName) object)

surfaceField ::
    forall marker wire value.
    ( Typeable marker
    , KnownSurfaceWireValue wire
    , AssertSurfaceFieldValue 'SurfaceRequired marker wire value
    , value ~ SurfaceWireValue wire
    ) =>
    value -> SurfaceFieldInput 'SurfaceRequired marker wire
surfaceField = RequiredSurfaceField

surfaceOptionalField ::
    forall marker wire value.
    ( Typeable marker
    , KnownSurfaceWireValue wire
    , AssertSurfaceFieldValue 'SurfaceOptional marker wire (Maybe value)
    , value ~ SurfaceWireValue wire
    ) =>
    Maybe value -> SurfaceFieldInput 'SurfaceOptional marker wire
surfaceOptionalField = OptionalSurfaceField

surfaceNullableField ::
    forall marker wire value.
    ( Typeable marker
    , KnownSurfaceWireValue wire
    , AssertSurfaceFieldValue 'SurfaceNullable marker wire (Maybe value)
    , value ~ SurfaceWireValue wire
    ) =>
    Maybe value -> SurfaceFieldInput 'SurfaceNullable marker wire
surfaceNullableField = NullableSurfaceField

-- | Parser-facing exact cons helpers. Unlike the authoring smart constructors,
-- these already know the declaration head and therefore do not need to recover
-- a caller-provided value shape for diagnostics.
prependRequiredSurfaceField ::
    forall marker wire rest.
    (Typeable marker, KnownSurfaceWireValue wire) =>
    SurfaceWireValue wire -> SurfaceFields rest -> SurfaceFields (('Field marker wire) ': rest)
prependRequiredSurfaceField value rest =
    RequiredSurfaceField @marker @wire value :& rest

prependOptionalSurfaceField ::
    forall marker wire rest.
    (Typeable marker, KnownSurfaceWireValue wire) =>
    Maybe (SurfaceWireValue wire) -> SurfaceFields rest -> SurfaceFields (('OptionalField marker wire) ': rest)
prependOptionalSurfaceField value rest =
    OptionalSurfaceField @marker @wire value :& rest

prependNullableSurfaceField ::
    forall marker wire rest.
    (Typeable marker, KnownSurfaceWireValue wire) =>
    Maybe (SurfaceWireValue wire) -> SurfaceFields rest -> SurfaceFields (('NullableField marker wire) ': rest)
prependNullableSurfaceField value rest =
    NullableSurfaceField @marker @wire value :& rest

class KnownSurfaceFieldValues (fields :: [FieldSpec]) where
    surfaceFieldValueNames :: [Text]
    parseSurfaceFieldValuesObject :: Aeson.Object -> Aeson.Types.Parser (SurfaceFieldValues fields)

instance KnownSurfaceFieldValues '[] where
    surfaceFieldValueNames = []
    parseSurfaceFieldValuesObject _ = pure ()

instance
    ( Typeable marker
    , KnownSurfaceWireValue wire
    , KnownSurfaceFieldValues rest
    ) => KnownSurfaceFieldValues (('Field marker wire) ': rest) where
    surfaceFieldValueNames = surfaceFieldName @marker : surfaceFieldValueNames @rest
    parseSurfaceFieldValuesObject object = do
        value <- requiredFieldValue @marker object
        parsed <- parseSurfaceWireValue @wire value
        rest <- parseSurfaceFieldValuesObject @rest object
        pure (parsed, rest)

instance
    ( Typeable marker
    , KnownSurfaceWireValue wire
    , KnownSurfaceFieldValues rest
    ) => KnownSurfaceFieldValues (('OptionalField marker wire) ': rest) where
    surfaceFieldValueNames = surfaceFieldName @marker : surfaceFieldValueNames @rest
    parseSurfaceFieldValuesObject object = do
        parsed <- case Aeson.KeyMap.lookup (Aeson.Key.fromText (surfaceFieldName @marker)) object of
            Nothing    -> pure Nothing
            Just value -> Just <$> parseSurfaceWireValue @wire value
        rest <- parseSurfaceFieldValuesObject @rest object
        pure (parsed, rest)

instance
    ( Typeable marker
    , KnownSurfaceWireValue wire
    , KnownSurfaceFieldValues rest
    ) => KnownSurfaceFieldValues (('NullableField marker wire) ': rest) where
    surfaceFieldValueNames = surfaceFieldName @marker : surfaceFieldValueNames @rest
    parseSurfaceFieldValuesObject object = do
        value <- requiredFieldValue @marker object
        parsed <- case value of
            Aeson.Null -> pure Nothing
            present    -> Just <$> parseSurfaceWireValue @wire present
        rest <- parseSurfaceFieldValuesObject @rest object
        pure (parsed, rest)

parseSurfaceFieldValues :: forall fields. KnownSurfaceFieldValues fields => Aeson.Value -> Aeson.Types.Parser (SurfaceFieldValues fields)
parseSurfaceFieldValues value = do
    object <- case value of
        Aeson.Object object -> pure object
        Aeson.Null | null (surfaceFieldValueNames @fields) -> pure mempty
        _ -> fail "Surface field values must be an object"
    let allowed = fmap Aeson.Key.fromText (surfaceFieldValueNames @fields)
    let unknown = filter (`notElem` allowed) (Aeson.KeyMap.keys object)
    unless (null unknown) do
        fail (cs ("Surface field values contain unknown fields: " <> tshow unknown))
    parseSurfaceFieldValuesObject @fields object

requiredFieldValue :: forall marker. Typeable marker => Aeson.Object -> Aeson.Types.Parser Aeson.Value
requiredFieldValue object =
    maybe
        (fail ("Missing Surface field: " <> cs (surfaceFieldName @marker)))
        pure
        (Aeson.KeyMap.lookup (Aeson.Key.fromText (surfaceFieldName @marker)) object)

surfaceFieldsJson :: SurfaceFieldBundle bundle => bundle -> Aeson.Value
surfaceFieldsJson = Aeson.object . surfaceFieldBundleJsonPairs

surfaceFieldsText :: SurfaceFieldBundle bundle => bundle -> [(Text, Text)]
surfaceFieldsText = surfaceFieldBundleTextValue

surfaceFieldsTextValue :: SurfaceFields fields -> [(Text, Text)]
surfaceFieldsTextValue = \case
    NoSurfaceFields -> []
    field :& rest -> surfaceFieldInputText field <> surfaceFieldsTextValue rest

boundSurfaceFieldsTextValue :: BoundSurfaceFields fields -> [(Text, Text)]
boundSurfaceFieldsTextValue = \case
    NoBoundSurfaceFields -> []
    BoundSurfaceField field rest -> surfaceFieldInputText field <> surfaceFieldsTextValue rest

surfaceFieldInputText :: SurfaceFieldInput presence marker wire -> [(Text, Text)]
surfaceFieldInputText = \case
    RequiredSurfaceField @marker @wire value ->
        [(surfaceFieldName @marker, surfaceWireText @wire value)]
    OptionalSurfaceField @marker @wire (Just value) ->
        [(surfaceFieldName @marker, surfaceWireText @wire value)]
    OptionalSurfaceField Nothing -> []
    NullableSurfaceField @marker @wire value ->
        [(surfaceFieldName @marker, maybe "" (surfaceWireText @wire) value)]

surfaceFieldJsonPairs :: SurfaceFields fields -> [Aeson.Types.Pair]
surfaceFieldJsonPairs = \case
    NoSurfaceFields -> []
    field :& rest -> surfaceFieldInputJsonPairs field <> surfaceFieldJsonPairs rest

boundSurfaceFieldJsonPairs :: BoundSurfaceFields fields -> [Aeson.Types.Pair]
boundSurfaceFieldJsonPairs = \case
    NoBoundSurfaceFields -> []
    BoundSurfaceField field rest -> surfaceFieldInputJsonPairs field <> surfaceFieldJsonPairs rest

surfaceFieldInputJsonPairs :: SurfaceFieldInput presence marker wire -> [Aeson.Types.Pair]
surfaceFieldInputJsonPairs = \case
    RequiredSurfaceField @marker @wire value ->
        [Aeson.Key.fromText (surfaceFieldName @marker) Aeson..= surfaceWireJson @wire value]
    OptionalSurfaceField @marker @wire (Just value) ->
        [Aeson.Key.fromText (surfaceFieldName @marker) Aeson..= surfaceWireJson @wire value]
    OptionalSurfaceField Nothing -> []
    NullableSurfaceField @marker @wire value ->
        [Aeson.Key.fromText (surfaceFieldName @marker) Aeson..= maybe Aeson.Null (surfaceWireJson @wire) value]

surfaceFieldName :: forall marker. Typeable marker => Text
surfaceFieldName = Naming.deriveFrontendSurfaceTypeName @marker Naming.FieldName

jsonText :: Aeson.Value -> Text
jsonText = Text.Encoding.decodeUtf8 . LBS.toStrict . Aeson.encode

type family SurfacePrimitives (spec :: SurfaceSpec) :: [SurfacePrimitive] where
    SurfacePrimitives ('Surface name primitives) = primitives

type SurfaceScopePrimitive spec marker = FindSurfaceScope spec marker (SurfacePrimitives spec)
type SurfaceFragmentPrimitive spec marker = FindSurfaceFragment spec marker (SurfacePrimitives spec)
type SurfaceActionPrimitive spec marker = FindSurfaceAction spec marker (SurfacePrimitives spec)
type SurfaceIntentPrimitive spec marker = FindSurfaceIntent spec marker (SurfacePrimitives spec)
type SurfaceActivationRefPrimitive spec marker = FindSurfaceActivationRef spec marker (SurfacePrimitives spec)
type SurfaceBrowserRolePrimitive spec marker = FindSurfaceBrowserRole spec marker (SurfacePrimitives spec)
type SurfaceBrowserStatePrimitive spec marker = FindSurfaceBrowserState spec marker (SurfacePrimitives spec)
type SurfaceBrowserClosedStatePrimitive spec marker = FindSurfaceBrowserClosedState spec marker (SurfacePrimitives spec)
type SurfaceCompleteSetSortPrimitive spec marker = FindSurfaceCompleteSetSort spec marker (SurfacePrimitives spec)
type SurfaceLinkedHighlightPrimitive spec marker = FindSurfaceLinkedHighlight spec marker (SurfacePrimitives spec)
type SurfaceDomTokenPrimitive spec marker = FindSurfaceDomToken spec marker (SurfacePrimitives spec)
type SurfaceDtoPrimitive spec marker = FindSurfaceDto spec marker (SurfacePrimitives spec)
type SurfaceTabSetPrimitive spec marker = FindSurfaceTabSet spec marker (SurfacePrimitives spec)
type SurfaceSourceRefPrimitive spec marker = FindSurfaceSourceRef spec marker (SurfacePrimitives spec)
type SurfaceDropzoneRefPrimitive spec marker = FindSurfaceDropzoneRef spec marker (SurfacePrimitives spec)
type SurfaceResourceSpec spec marker = RequireSurfaceResource spec marker (FindSurfaceResource marker (SurfacePrimitives spec))

type SurfaceScopeFieldSpecs spec marker = PrimitiveFieldSpecs (SurfaceScopePrimitive spec marker)
type SurfaceFragmentFieldSpecs spec marker = PrimitiveFieldSpecs (SurfaceFragmentPrimitive spec marker)
type SurfaceFragmentOptionSpecs spec marker = FragmentOptionSpecs (SurfaceFragmentPrimitive spec marker)
type SurfaceFragmentTargetFieldSpecs spec marker = MountTargetFieldSpecs (FindMountTarget (SurfaceFragmentOptionSpecs spec marker))
type SurfaceActionFieldSpecs spec marker = PrimitiveFieldSpecs (SurfaceActionPrimitive spec marker)
type SurfaceIntentFieldSpecs spec marker = PrimitiveFieldSpecs (SurfaceIntentPrimitive spec marker)
type SurfaceResourceFieldSpecs spec marker = ResourceFieldSpecs (SurfaceResourceSpec spec marker)
type SurfaceDtoFieldSpecs spec marker = PrimitiveFieldSpecs (SurfaceDtoPrimitive spec marker)
type SurfaceCompleteSetSortRowDto spec marker = CompleteSetSortRowDto (SurfaceCompleteSetSortPrimitive spec marker)
type SurfaceCompleteSetSortRowFieldSpecs spec marker = SurfaceDtoFieldSpecs spec (SurfaceCompleteSetSortRowDto spec marker)
type SurfaceMountStateFieldSpecs spec = FindMountStateFields (SurfacePrimitives spec)

type family PrimitiveFieldSpecs (primitive :: SurfacePrimitive) :: [FieldSpec] where
    PrimitiveFieldSpecs ('Scope marker fields options) = fields
    PrimitiveFieldSpecs ('Fragment marker fields options) = fields
    PrimitiveFieldSpecs ('Action marker fields options) = fields
    PrimitiveFieldSpecs ('Intent marker fields options) = fields
    PrimitiveFieldSpecs ('MountState marker fields) = fields
    PrimitiveFieldSpecs ('SurfaceDto reachability marker fields) = fields

type family FragmentOptionSpecs (primitive :: SurfacePrimitive) :: [PrimitiveOption] where
    FragmentOptionSpecs ('Fragment marker fields options) = options

type family FindMountTarget (options :: [PrimitiveOption]) :: PrimitiveOption where
    FindMountTarget (('MountTarget marker fields) ': rest) = 'MountTarget marker fields
    FindMountTarget (option ': rest) = FindMountTarget rest
    FindMountTarget '[] = TypeError
        ( 'Text "FrontendSurface fragment does not declare a MountTarget"
        )

type family MountTargetFieldSpecs (target :: PrimitiveOption) :: [FieldSpec] where
    MountTargetFieldSpecs ('MountTarget marker fields) = fields

class KnownMountTarget (target :: PrimitiveOption) where
    mountTargetName :: Text

instance Typeable marker => KnownMountTarget ('MountTarget marker fields) where
    mountTargetName = Naming.deriveFrontendSurfaceTypeName @marker Naming.DomTokenName

type family ResourceFieldSpecs (resource :: ResourceSpec) :: [FieldSpec] where
    ResourceFieldSpecs ('Resource marker fields) = fields

type family FindMountStateFields (primitives :: [SurfacePrimitive]) :: [FieldSpec] where
    FindMountStateFields '[] = '[]
    FindMountStateFields (('MountState marker fields) ': rest) = fields
    FindMountStateFields (primitive ': rest) = FindMountStateFields rest

surfaceScopeFieldName ::
    forall spec scope marker.
    ( Typeable marker
    , RequireSurfaceField scope marker (SurfaceScopeFieldSpecs spec scope)
    ) =>
    Text
surfaceScopeFieldName = surfaceFieldName @marker

surfaceFragmentFieldName ::
    forall spec fragment marker.
    ( Typeable marker
    , RequireSurfaceField fragment marker (SurfaceFragmentFieldSpecs spec fragment)
    ) =>
    Text
surfaceFragmentFieldName = surfaceFieldName @marker

type family FindSurfaceScope (spec :: SurfaceSpec) (marker :: Type) (primitives :: [SurfacePrimitive]) :: SurfacePrimitive where
    FindSurfaceScope spec marker (('Scope marker fields options) ': rest) = 'Scope marker fields options
    FindSurfaceScope spec marker (primitive ': rest) = FindSurfaceScope spec marker rest
    FindSurfaceScope spec marker '[] = SurfaceOwnershipError spec "scope" marker

type family FindSurfaceFragment (spec :: SurfaceSpec) (marker :: Type) (primitives :: [SurfacePrimitive]) :: SurfacePrimitive where
    FindSurfaceFragment spec marker (('Fragment marker fields options) ': rest) = 'Fragment marker fields options
    FindSurfaceFragment spec marker (primitive ': rest) = FindSurfaceFragment spec marker rest
    FindSurfaceFragment spec marker '[] = SurfaceOwnershipError spec "fragment" marker

type family FindSurfaceAction (spec :: SurfaceSpec) (marker :: Type) (primitives :: [SurfacePrimitive]) :: SurfacePrimitive where
    FindSurfaceAction spec marker (('Action marker fields options) ': rest) = 'Action marker fields options
    FindSurfaceAction spec marker (primitive ': rest) = FindSurfaceAction spec marker rest
    FindSurfaceAction spec marker '[] = SurfaceOwnershipError spec "action" marker

type family FindSurfaceIntent (spec :: SurfaceSpec) (marker :: Type) (primitives :: [SurfacePrimitive]) :: SurfacePrimitive where
    FindSurfaceIntent spec marker (('Intent marker fields options) ': rest) = 'Intent marker fields options
    FindSurfaceIntent spec marker (primitive ': rest) = FindSurfaceIntent spec marker rest
    FindSurfaceIntent spec marker '[] = SurfaceOwnershipError spec "intent" marker

type family FindSurfaceActivationRef (spec :: SurfaceSpec) (marker :: Type) (primitives :: [SurfacePrimitive]) :: SurfacePrimitive where
    FindSurfaceActivationRef spec marker (('ActivationRef marker options) ': rest) = 'ActivationRef marker options
    FindSurfaceActivationRef spec marker (primitive ': rest) = FindSurfaceActivationRef spec marker rest
    FindSurfaceActivationRef spec marker '[] = SurfaceOwnershipError spec "activation-ref" marker

type family FindSurfaceBrowserRole (spec :: SurfaceSpec) (marker :: Type) (primitives :: [SurfacePrimitive]) :: SurfacePrimitive where
    FindSurfaceBrowserRole spec marker (('BrowserRole marker) ': rest) = 'BrowserRole marker
    FindSurfaceBrowserRole spec marker (primitive ': rest) = FindSurfaceBrowserRole spec marker rest
    FindSurfaceBrowserRole spec marker '[] = SurfaceOwnershipError spec "browser-role" marker

type family FindSurfaceBrowserState (spec :: SurfaceSpec) (marker :: Type) (primitives :: [SurfacePrimitive]) :: SurfacePrimitive where
    FindSurfaceBrowserState spec marker (('BrowserState marker) ': rest) = 'BrowserState marker
    FindSurfaceBrowserState spec marker (primitive ': rest) = FindSurfaceBrowserState spec marker rest
    FindSurfaceBrowserState spec marker '[] = SurfaceOwnershipError spec "browser-state" marker

type family FindSurfaceBrowserClosedState (spec :: SurfaceSpec) (marker :: Type) (primitives :: [SurfacePrimitive]) :: SurfacePrimitive where
    FindSurfaceBrowserClosedState spec marker (('BrowserClosedState marker values) ': rest) = 'BrowserClosedState marker values
    FindSurfaceBrowserClosedState spec marker (primitive ': rest) = FindSurfaceBrowserClosedState spec marker rest
    FindSurfaceBrowserClosedState spec marker '[] = SurfaceOwnershipError spec "browser-closed-state" marker

type family RequireBrowserClosedStateValue (primitive :: SurfacePrimitive) (value :: Type) :: Constraint where
    RequireBrowserClosedStateValue ('BrowserClosedState marker values) value = RequireClosedStateValue marker value values

type family RequireClosedStateValue (stateMarker :: Type) (value :: Type) (values :: [Type]) :: Constraint where
    RequireClosedStateValue stateMarker value (value ': rest) = ()
    RequireClosedStateValue stateMarker value (other ': rest) = RequireClosedStateValue stateMarker value rest
    RequireClosedStateValue stateMarker value '[] = TypeError
        ( 'Text "FrontendSurface browser state "
            ':<>: 'ShowType stateMarker
            ':<>: 'Text " does not declare value "
            ':<>: 'ShowType value
        )

type family FindSurfaceCompleteSetSort (spec :: SurfaceSpec) (marker :: Type) (primitives :: [SurfacePrimitive]) :: SurfacePrimitive where
    FindSurfaceCompleteSetSort spec marker (('CompleteSetSort marker rootRole rowRole controlRole rowDto keys defaultKey defaultDirection) ': rest) = 'CompleteSetSort marker rootRole rowRole controlRole rowDto keys defaultKey defaultDirection
    FindSurfaceCompleteSetSort spec marker (primitive ': rest) = FindSurfaceCompleteSetSort spec marker rest
    FindSurfaceCompleteSetSort spec marker '[] = SurfaceOwnershipError spec "complete-set sort" marker

type family CompleteSetSortRowDto (primitive :: SurfacePrimitive) :: Type where
    CompleteSetSortRowDto ('CompleteSetSort marker rootRole rowRole controlRole rowDto keys defaultKey defaultDirection) = rowDto

type family RequireCompleteSetSortKey (primitive :: SurfacePrimitive) (key :: Type) :: Constraint where
    RequireCompleteSetSortKey ('CompleteSetSort marker rootRole rowRole controlRole rowDto keys defaultKey defaultDirection) key = RequireSortKey marker key keys

type family RequireSortKey (sortMarker :: Type) (key :: Type) (keys :: [CompleteSetSortKeySpec]) :: Constraint where
    RequireSortKey sortMarker key (('SortKey key comparators) ': rest) = ()
    RequireSortKey sortMarker key (other ': rest) = RequireSortKey sortMarker key rest
    RequireSortKey sortMarker key '[] = TypeError
        ( 'Text "FrontendSurface complete-set sort "
            ':<>: 'ShowType sortMarker
            ':<>: 'Text " does not declare key "
            ':<>: 'ShowType key
        )

type family FindSurfaceLinkedHighlight (spec :: SurfaceSpec) (marker :: Type) (primitives :: [SurfacePrimitive]) :: SurfacePrimitive where
    FindSurfaceLinkedHighlight spec marker (('LinkedHighlight marker sourceRole memberRole activations effects) ': rest) = 'LinkedHighlight marker sourceRole memberRole activations effects
    FindSurfaceLinkedHighlight spec marker (primitive ': rest) = FindSurfaceLinkedHighlight spec marker rest
    FindSurfaceLinkedHighlight spec marker '[] = SurfaceOwnershipError spec "linked-highlight" marker

type family FindSurfaceDomToken (spec :: SurfaceSpec) (marker :: Type) (primitives :: [SurfacePrimitive]) :: SurfacePrimitive where
    FindSurfaceDomToken spec marker (('DomToken marker) ': rest) = 'DomToken marker
    FindSurfaceDomToken spec marker (('BrowserDomToken marker) ': rest) = 'BrowserDomToken marker
    FindSurfaceDomToken spec marker (primitive ': rest) = FindSurfaceDomToken spec marker rest
    FindSurfaceDomToken spec marker '[] = SurfaceOwnershipError spec "DOM token" marker

type family FindSurfaceTabSet (spec :: SurfaceSpec) (marker :: Type) (primitives :: [SurfacePrimitive]) :: SurfacePrimitive where
    FindSurfaceTabSet spec marker (('TabSet marker roleMarker keys defaultKey) ': rest) = 'TabSet marker roleMarker keys defaultKey
    FindSurfaceTabSet spec marker (primitive ': rest) = FindSurfaceTabSet spec marker rest
    FindSurfaceTabSet spec marker '[] = SurfaceOwnershipError spec "tab set" marker

type family RequireSurfaceTabKey (primitive :: SurfacePrimitive) (key :: Type) :: Constraint where
    RequireSurfaceTabKey ('TabSet marker roleMarker keys defaultKey) key = RequireTabKey marker key keys

type family RequireTabKey (tabSetMarker :: Type) (key :: Type) (keys :: [Type]) :: Constraint where
    RequireTabKey tabSetMarker key (key ': rest) = ()
    RequireTabKey tabSetMarker key (other ': rest) = RequireTabKey tabSetMarker key rest
    RequireTabKey tabSetMarker key '[] = TypeError
        ( 'Text "FrontendSurface tab set "
            ':<>: 'ShowType tabSetMarker
            ':<>: 'Text " does not declare key "
            ':<>: 'ShowType key
        )

type family FindSurfaceDto (spec :: SurfaceSpec) (marker :: Type) (primitives :: [SurfacePrimitive]) :: SurfacePrimitive where
    FindSurfaceDto spec marker (('SurfaceDto reachability marker fields) ': rest) = 'SurfaceDto reachability marker fields
    FindSurfaceDto spec marker (primitive ': rest) = FindSurfaceDto spec marker rest
    FindSurfaceDto spec marker '[] = SurfaceOwnershipError spec "dto" marker

-- | Rendering a Surface DTO into browser-visible markup requires an explicit
-- non-server reachability on that exact declaration.
type family AssertBrowserReachableSurfaceDto (primitive :: SurfacePrimitive) :: Constraint where
    AssertBrowserReachableSurfaceDto ('SurfaceDto 'BrowserUnreachable marker fields) = TypeError
        ( 'Text "FrontendSurface DTO "
            ':<>: 'ShowType marker
            ':<>: 'Text " is server-only and cannot be rendered to the browser"
        )
    AssertBrowserReachableSurfaceDto ('SurfaceDto reachability marker fields) = ()


type family FindSurfaceSourceRef (spec :: SurfaceSpec) (marker :: Type) (primitives :: [SurfacePrimitive]) :: SurfacePrimitive where
    FindSurfaceSourceRef spec marker (('SourceRef marker options) ': rest) = 'SourceRef marker options
    FindSurfaceSourceRef spec marker (primitive ': rest) = FindSurfaceSourceRef spec marker rest
    FindSurfaceSourceRef spec marker '[] = SurfaceOwnershipError spec "source-ref" marker

type family FindSurfaceDropzoneRef (spec :: SurfaceSpec) (marker :: Type) (primitives :: [SurfacePrimitive]) :: SurfacePrimitive where
    FindSurfaceDropzoneRef spec marker (('DropzoneRef marker options) ': rest) = 'DropzoneRef marker options
    FindSurfaceDropzoneRef spec marker (primitive ': rest) = FindSurfaceDropzoneRef spec marker rest
    FindSurfaceDropzoneRef spec marker '[] = SurfaceOwnershipError spec "dropzone-ref" marker

type family FindSurfaceResource (marker :: Type) (primitives :: [SurfacePrimitive]) :: Maybe ResourceSpec where
    FindSurfaceResource marker '[] = 'Nothing
    FindSurfaceResource marker (('Fragment fragment fields options) ': rest) =
        FirstResource (FindResourceInOptions marker options) (FindSurfaceResource marker rest)
    FindSurfaceResource marker (primitive ': rest) = FindSurfaceResource marker rest

type family FindResourceInOptions (marker :: Type) (options :: [PrimitiveOption]) :: Maybe ResourceSpec where
    FindResourceInOptions marker '[] = 'Nothing
    FindResourceInOptions marker (('DependsOn ('Resource marker fields) sources) ': rest) = 'Just ('Resource marker fields)
    FindResourceInOptions marker (('Lazy nested) ': rest) =
        FirstResource (FindResourceInOptions marker nested) (FindResourceInOptions marker rest)
    FindResourceInOptions marker (option ': rest) = FindResourceInOptions marker rest

type family FirstResource (left :: Maybe ResourceSpec) (right :: Maybe ResourceSpec) :: Maybe ResourceSpec where
    FirstResource ('Just resource) right = 'Just resource
    FirstResource 'Nothing right = right

type family RequireSurfaceResource (spec :: SurfaceSpec) (marker :: Type) (result :: Maybe ResourceSpec) :: ResourceSpec where
    RequireSurfaceResource spec marker ('Just resource) = resource
    RequireSurfaceResource spec marker 'Nothing = SurfaceOwnershipError spec "resource" marker

surfaceNameValue :: forall spec. ReflectSurfaceSpec spec => Text
surfaceNameValue = (reflectSurfaceSpec @spec).surfaceName

surfaceScopeValue :: forall spec marker. ReflectPrimitive (SurfaceScopePrimitive spec marker) => ScopeIR
surfaceScopeValue =
    case reflectPrimitive @(SurfaceScopePrimitive spec marker) of
        ReflectedScope scope -> scope
        _ -> error "impossible: scope lookup reflected a different primitive"

surfaceFragmentNameValue :: forall spec marker. ReflectPrimitive (SurfaceFragmentPrimitive spec marker) => Text
surfaceFragmentNameValue = (surfaceFragmentValue @spec @marker).fragmentName

surfaceFragmentTargetId ::
    forall spec marker.
    KnownMountTarget (FindMountTarget (SurfaceFragmentOptionSpecs spec marker)) =>
    SurfaceFields (SurfaceFragmentTargetFieldSpecs spec marker) ->
    Text
surfaceFragmentTargetId fields =
    Text.intercalate "-" (mountTargetName @(FindMountTarget (SurfaceFragmentOptionSpecs spec marker)) : map snd (surfaceFieldsText fields))

surfaceFragmentValue :: forall spec marker. ReflectPrimitive (SurfaceFragmentPrimitive spec marker) => FragmentIR
surfaceFragmentValue =
    case reflectPrimitive @(SurfaceFragmentPrimitive spec marker) of
        ReflectedFragment fragment -> fragment
        _ -> error "impossible: fragment lookup reflected a different primitive"

surfaceActionNameValue :: forall spec marker. ReflectPrimitive (SurfaceActionPrimitive spec marker) => Text
surfaceActionNameValue =
    case reflectPrimitive @(SurfaceActionPrimitive spec marker) of
        ReflectedHtmxAction action -> action.htmxActionName
        _ -> error "impossible: action lookup reflected a different primitive"

surfaceIntentNameValue :: forall spec marker. ReflectPrimitive (SurfaceIntentPrimitive spec marker) => Text
surfaceIntentNameValue =
    case reflectPrimitive @(SurfaceIntentPrimitive spec marker) of
        ReflectedIntent intent -> intent.intentName
        _ -> error "impossible: intent lookup reflected a different primitive"

surfaceResourceValue :: forall spec marker. ReflectResource (SurfaceResourceSpec spec marker) => ResourceIR
surfaceResourceValue = reflectResource @(SurfaceResourceSpec spec marker)

surfaceActivationRefValue :: forall spec marker. ReflectPrimitive (SurfaceActivationRefPrimitive spec marker) => InteractionActivationRefIR
surfaceActivationRefValue =
    case reflectPrimitive @(SurfaceActivationRefPrimitive spec marker) of
        ReflectedActivationRef ref -> ref
        _ -> error "impossible: activation-ref lookup reflected a different primitive"

qualifySurfaceLinkedHighlight :: forall spec. ReflectSurfaceSpec spec => LinkedHighlightIR -> LinkedHighlightIR
qualifySurfaceLinkedHighlight highlight =
    highlight
        { linkedHighlightSourceRole = qualifySurfaceBrowserAttribute @spec highlight.linkedHighlightSourceRole
        , linkedHighlightMemberRole = qualifySurfaceBrowserAttribute @spec highlight.linkedHighlightMemberRole
        , linkedHighlightActivations = map qualifyActivation highlight.linkedHighlightActivations
        , linkedHighlightEffects = map qualifyEffect highlight.linkedHighlightEffects
        }
  where
    qualifyActivation = \case
        LinkedHighlightPinActivationIR roleAttribute ->
            LinkedHighlightPinActivationIR (qualifySurfaceBrowserAttribute @spec roleAttribute)
        activation -> activation
    qualifyEffect = \case
        LinkedHighlightOrderedMemberBoundsEffectIR stateAttribute ->
            LinkedHighlightOrderedMemberBoundsEffectIR (qualifySurfaceBrowserAttribute @spec stateAttribute)
        effect -> effect

qualifySurfaceBrowserAttribute :: forall spec. ReflectSurfaceSpec spec => BrowserAttributeIR -> BrowserAttributeIR
qualifySurfaceBrowserAttribute attribute =
    attribute
        { browserAttributeDomAttribute =
            Naming.deriveSurfaceBrowserAttributeName (surfaceNameValue @spec) attribute.browserAttributeName
        }

surfaceBrowserRoleValue :: forall spec marker. (ReflectSurfaceSpec spec, ReflectPrimitive (SurfaceBrowserRolePrimitive spec marker)) => BrowserAttributeIR
surfaceBrowserRoleValue =
    case reflectPrimitive @(SurfaceBrowserRolePrimitive spec marker) of
        ReflectedBrowserRole attribute -> qualifySurfaceBrowserAttribute @spec attribute
        _ -> error "impossible: browser-role lookup reflected a different primitive"

surfaceBrowserStateValue :: forall spec marker. (ReflectSurfaceSpec spec, ReflectPrimitive (SurfaceBrowserStatePrimitive spec marker)) => BrowserAttributeIR
surfaceBrowserStateValue =
    case reflectPrimitive @(SurfaceBrowserStatePrimitive spec marker) of
        ReflectedBrowserState attribute -> qualifySurfaceBrowserAttribute @spec attribute
        _ -> error "impossible: browser-state lookup reflected a different primitive"

surfaceBrowserClosedStateValue :: forall spec marker. (ReflectSurfaceSpec spec, ReflectPrimitive (SurfaceBrowserClosedStatePrimitive spec marker)) => BrowserClosedStateIR
surfaceBrowserClosedStateValue =
    case reflectPrimitive @(SurfaceBrowserClosedStatePrimitive spec marker) of
        ReflectedBrowserClosedState state ->
            state
                { browserClosedStateAttribute =
                    qualifySurfaceBrowserAttribute @spec state.browserClosedStateAttribute
                }
        _ -> error "impossible: browser-closed-state lookup reflected a different primitive"

surfaceBrowserClosedStateLiteral ::
    forall spec marker value.
    ( Typeable value
    , RequireBrowserClosedStateValue (SurfaceBrowserClosedStatePrimitive spec marker) value
    ) =>
    Text
surfaceBrowserClosedStateLiteral =
    Naming.deriveFrontendSurfaceTypeName @value Naming.BrowserStateValueName

surfaceCompleteSetSortValue :: forall spec marker. (ReflectSurfaceSpec spec, ReflectPrimitive (SurfaceCompleteSetSortPrimitive spec marker)) => CompleteSetSortIR
surfaceCompleteSetSortValue =
    case reflectPrimitive @(SurfaceCompleteSetSortPrimitive spec marker) of
        ReflectedCompleteSetSort sortDefinition ->
            sortDefinition
                { completeSetSortRootRole = qualifySurfaceBrowserAttribute @spec sortDefinition.completeSetSortRootRole
                , completeSetSortRowRole = qualifySurfaceBrowserAttribute @spec sortDefinition.completeSetSortRowRole
                , completeSetSortControlRole = qualifySurfaceBrowserAttribute @spec sortDefinition.completeSetSortControlRole
                }
        _ -> error "impossible: complete-set-sort lookup reflected a different primitive"

surfaceTabSetValue :: forall spec marker. (ReflectSurfaceSpec spec, ReflectPrimitive (SurfaceTabSetPrimitive spec marker)) => TabSetIR
surfaceTabSetValue =
    case reflectPrimitive @(SurfaceTabSetPrimitive spec marker) of
        ReflectedTabSet tabSet ->
            tabSet { tabSetRole = qualifySurfaceBrowserAttribute @spec tabSet.tabSetRole }
        _ -> error "impossible: tab-set lookup reflected a different primitive"

surfaceLinkedHighlightValue :: forall spec marker. (ReflectSurfaceSpec spec, ReflectPrimitive (SurfaceLinkedHighlightPrimitive spec marker)) => LinkedHighlightIR
surfaceLinkedHighlightValue =
    case reflectPrimitive @(SurfaceLinkedHighlightPrimitive spec marker) of
        ReflectedLinkedHighlight highlight -> qualifySurfaceLinkedHighlight @spec highlight
        _ -> error "impossible: linked-highlight lookup reflected a different primitive"

surfaceDomTokenValue :: forall spec marker. ReflectPrimitive (SurfaceDomTokenPrimitive spec marker) => Text
surfaceDomTokenValue =
    case reflectPrimitive @(SurfaceDomTokenPrimitive spec marker) of
        ReflectedDomToken token -> token
        ReflectedBrowserDomToken token -> token
        _ -> error "impossible: DOM-token lookup reflected a different primitive"

surfaceSourceRefValue :: forall spec marker. ReflectPrimitive (SurfaceSourceRefPrimitive spec marker) => InteractionSourceRefIR
surfaceSourceRefValue =
    case reflectPrimitive @(SurfaceSourceRefPrimitive spec marker) of
        ReflectedSourceRef ref -> ref
        _ -> error "impossible: source-ref lookup reflected a different primitive"

surfaceDropzoneRefValue :: forall spec marker. ReflectPrimitive (SurfaceDropzoneRefPrimitive spec marker) => InteractionDropzoneRefIR
surfaceDropzoneRefValue =
    case reflectPrimitive @(SurfaceDropzoneRefPrimitive spec marker) of
        ReflectedDropzoneRef ref -> ref
        _ -> error "impossible: dropzone-ref lookup reflected a different primitive"
