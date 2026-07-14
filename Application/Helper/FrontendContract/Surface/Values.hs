{-# LANGUAGE AllowAmbiguousTypes  #-}
{-# LANGUAGE DataKinds            #-}
{-# LANGUAGE FlexibleContexts     #-}
{-# LANGUAGE FlexibleInstances    #-}
{-# LANGUAGE GADTs                #-}
{-# LANGUAGE LambdaCase           #-}
{-# LANGUAGE PolyKinds            #-}
{-# LANGUAGE ScopedTypeVariables  #-}
{-# LANGUAGE TypeApplications     #-}
{-# LANGUAGE TypeFamilies         #-}
{-# LANGUAGE TypeOperators        #-}
{-# LANGUAGE UndecidableInstances #-}

module Application.Helper.FrontendContract.Surface.Values
    ( FindMountTarget
    , KnownMountTarget
    , KnownSurfaceFieldValues
    , RequireSurfaceField
    , SurfaceActionFieldSpecs
    , SurfaceActionPrimitive
    , SurfaceActivationRefPrimitive
    , SurfaceFieldValues
    , SurfaceFields (..)
    , SurfaceFragmentFieldSpecs
    , SurfaceFragmentOptionSpecs
    , SurfaceFragmentTargetFieldSpecs
    , SurfaceDomTokenPrimitive
    , SurfaceDropzoneRefPrimitive
    , SurfaceFragmentPrimitive
    , SurfaceIntentFieldSpecs
    , SurfaceIntentPrimitive
    , SurfaceMountStateFieldSpecs
    , SurfaceResourceFieldSpecs
    , SurfaceResourceSpec
    , SurfaceScopeFieldSpecs
    , SurfaceScopePrimitive
    , SurfaceSourceRefPrimitive
    , surfaceActionFieldName
    , surfaceActionNameValue
    , surfaceField
    , surfaceFieldsJson
    , surfaceFieldsText
    , surfaceNullableField
    , surfaceOptionalField
    , parseSurfaceFieldValues
    , surfaceActionValue
    , surfaceActivationRefValue
    , surfaceDomTokenValue
    , surfaceDropzoneRefValue
    , surfaceFragmentFieldName
    , surfaceFragmentNameValue
    , surfaceFragmentTargetId
    , surfaceFragmentValue
    , surfaceIntentFieldName
    , surfaceIntentNameValue
    , surfaceIntentValue
    , surfaceNameValue
    , surfaceResourceFieldName
    , surfaceResourceValue
    , surfaceScopeFieldName
    , surfaceScopeValue
    , surfaceSourceRefValue
    ) where

import qualified Application.Helper.FrontendContract.Naming as Naming
import Application.Helper.FrontendContract.Surface.ContractIR
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

-- | Exact, declaration-ordered values for one Surface field list. Unlike the
-- legacy phantom JSON carrier, values can only be constructed with the field
-- marker, presence, and Haskell type declared by the Surface DSL.
data SurfaceField (field :: FieldSpec) where
    RequiredSurfaceField ::
        (Typeable marker, KnownSurfaceWireValue wire) =>
        SurfaceWireValue wire -> SurfaceField ('Field marker wire)
    OptionalSurfaceField ::
        (Typeable marker, KnownSurfaceWireValue wire) =>
        Maybe (SurfaceWireValue wire) -> SurfaceField ('OptionalField marker wire)
    NullableSurfaceField ::
        (Typeable marker, KnownSurfaceWireValue wire) =>
        Maybe (SurfaceWireValue wire) -> SurfaceField ('NullableField marker wire)

data SurfaceFields (fields :: [FieldSpec]) where
    NoSurfaceFields :: SurfaceFields '[]
    (:&) :: SurfaceField field -> SurfaceFields rest -> SurfaceFields (field ': rest)

infixr 5 :&

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

surfaceField ::
    forall marker wire.
    (Typeable marker, KnownSurfaceWireValue wire) =>
    SurfaceWireValue wire -> SurfaceField ('Field marker wire)
surfaceField = RequiredSurfaceField

surfaceOptionalField ::
    forall marker wire.
    (Typeable marker, KnownSurfaceWireValue wire) =>
    Maybe (SurfaceWireValue wire) -> SurfaceField ('OptionalField marker wire)
surfaceOptionalField = OptionalSurfaceField

surfaceNullableField ::
    forall marker wire.
    (Typeable marker, KnownSurfaceWireValue wire) =>
    Maybe (SurfaceWireValue wire) -> SurfaceField ('NullableField marker wire)
surfaceNullableField = NullableSurfaceField

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

surfaceFieldsJson :: SurfaceFields fields -> Aeson.Value
surfaceFieldsJson = Aeson.object . surfaceFieldJsonPairs

surfaceFieldsText :: SurfaceFields fields -> [(Text, Text)]
surfaceFieldsText = \case
    NoSurfaceFields -> []
    RequiredSurfaceField @marker @wire value :& rest ->
        (surfaceFieldName @marker, surfaceWireText @wire value) : surfaceFieldsText rest
    OptionalSurfaceField @marker @wire (Just value) :& rest ->
        (surfaceFieldName @marker, surfaceWireText @wire value) : surfaceFieldsText rest
    OptionalSurfaceField Nothing :& rest -> surfaceFieldsText rest
    NullableSurfaceField @marker @wire value :& rest ->
        (surfaceFieldName @marker, maybe "" (surfaceWireText @wire) value) : surfaceFieldsText rest

surfaceFieldJsonPairs :: SurfaceFields fields -> [Aeson.Types.Pair]
surfaceFieldJsonPairs = \case
    NoSurfaceFields -> []
    RequiredSurfaceField @marker @wire value :& rest ->
        Aeson.Key.fromText (surfaceFieldName @marker) Aeson..= surfaceWireJson @wire value : surfaceFieldJsonPairs rest
    OptionalSurfaceField @marker @wire (Just value) :& rest ->
        Aeson.Key.fromText (surfaceFieldName @marker) Aeson..= surfaceWireJson @wire value : surfaceFieldJsonPairs rest
    OptionalSurfaceField Nothing :& rest -> surfaceFieldJsonPairs rest
    NullableSurfaceField @marker @wire value :& rest ->
        Aeson.Key.fromText (surfaceFieldName @marker) Aeson..= maybe Aeson.Null (surfaceWireJson @wire) value : surfaceFieldJsonPairs rest

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
type SurfaceDomTokenPrimitive spec marker = FindSurfaceDomToken spec marker (SurfacePrimitives spec)
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
type SurfaceMountStateFieldSpecs spec = FindMountStateFields (SurfacePrimitives spec)

type family PrimitiveFieldSpecs (primitive :: SurfacePrimitive) :: [FieldSpec] where
    PrimitiveFieldSpecs ('Scope marker fields options) = fields
    PrimitiveFieldSpecs ('Fragment marker fields options) = fields
    PrimitiveFieldSpecs ('Action marker fields options) = fields
    PrimitiveFieldSpecs ('Intent marker fields options) = fields
    PrimitiveFieldSpecs ('MountState marker fields) = fields

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

type family RequireSurfaceField (owner :: Type) (marker :: Type) (fields :: [FieldSpec]) :: Constraint where
    RequireSurfaceField owner marker (('Field marker wire) ': rest) = ()
    RequireSurfaceField owner marker (('OptionalField marker wire) ': rest) = ()
    RequireSurfaceField owner marker (('NullableField marker wire) ': rest) = ()
    RequireSurfaceField owner marker (field ': rest) = RequireSurfaceField owner marker rest
    RequireSurfaceField owner marker '[] = TypeError
        ( 'Text "FrontendSurface owner "
            ':<>: 'ShowType owner
            ':<>: 'Text " does not declare field marker "
            ':<>: 'ShowType marker
        )

surfaceResourceFieldName ::
    forall spec resource marker.
    ( Typeable marker
    , RequireSurfaceField resource marker (SurfaceResourceFieldSpecs spec resource)
    ) =>
    Text
surfaceResourceFieldName = surfaceFieldName @marker

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

surfaceActionFieldName ::
    forall spec action marker.
    ( Typeable marker
    , RequireSurfaceField action marker (SurfaceActionFieldSpecs spec action)
    ) =>
    Text
surfaceActionFieldName = surfaceFieldName @marker

surfaceIntentFieldName ::
    forall spec intent marker.
    ( Typeable marker
    , RequireSurfaceField intent marker (SurfaceIntentFieldSpecs spec intent)
    ) =>
    Text
surfaceIntentFieldName = surfaceFieldName @marker

type family FindSurfaceScope (spec :: SurfaceSpec) (marker :: Type) (primitives :: [SurfacePrimitive]) :: SurfacePrimitive where
    FindSurfaceScope spec marker (('Scope marker fields options) ': rest) = 'Scope marker fields options
    FindSurfaceScope spec marker (primitive ': rest) = FindSurfaceScope spec marker rest
    FindSurfaceScope spec marker '[] = TypeError
        ( 'Text "FrontendSurface "
            ':<>: 'ShowType spec
            ':<>: 'Text " does not declare scope marker "
            ':<>: 'ShowType marker
        )

type family FindSurfaceFragment (spec :: SurfaceSpec) (marker :: Type) (primitives :: [SurfacePrimitive]) :: SurfacePrimitive where
    FindSurfaceFragment spec marker (('Fragment marker fields options) ': rest) = 'Fragment marker fields options
    FindSurfaceFragment spec marker (primitive ': rest) = FindSurfaceFragment spec marker rest
    FindSurfaceFragment spec marker '[] = TypeError
        ( 'Text "FrontendSurface "
            ':<>: 'ShowType spec
            ':<>: 'Text " does not declare fragment marker "
            ':<>: 'ShowType marker
        )

type family FindSurfaceAction (spec :: SurfaceSpec) (marker :: Type) (primitives :: [SurfacePrimitive]) :: SurfacePrimitive where
    FindSurfaceAction spec marker (('Action marker fields options) ': rest) = 'Action marker fields options
    FindSurfaceAction spec marker (primitive ': rest) = FindSurfaceAction spec marker rest
    FindSurfaceAction spec marker '[] = TypeError
        ( 'Text "FrontendSurface "
            ':<>: 'ShowType spec
            ':<>: 'Text " does not declare action marker "
            ':<>: 'ShowType marker
        )

type family FindSurfaceIntent (spec :: SurfaceSpec) (marker :: Type) (primitives :: [SurfacePrimitive]) :: SurfacePrimitive where
    FindSurfaceIntent spec marker (('Intent marker fields options) ': rest) = 'Intent marker fields options
    FindSurfaceIntent spec marker (primitive ': rest) = FindSurfaceIntent spec marker rest
    FindSurfaceIntent spec marker '[] = TypeError
        ( 'Text "FrontendSurface "
            ':<>: 'ShowType spec
            ':<>: 'Text " does not declare intent marker "
            ':<>: 'ShowType marker
        )

type family FindSurfaceActivationRef (spec :: SurfaceSpec) (marker :: Type) (primitives :: [SurfacePrimitive]) :: SurfacePrimitive where
    FindSurfaceActivationRef spec marker (('ActivationRef marker options) ': rest) = 'ActivationRef marker options
    FindSurfaceActivationRef spec marker (primitive ': rest) = FindSurfaceActivationRef spec marker rest
    FindSurfaceActivationRef spec marker '[] = TypeError
        ( 'Text "FrontendSurface "
            ':<>: 'ShowType spec
            ':<>: 'Text " does not declare activation-ref marker "
            ':<>: 'ShowType marker
        )

type family FindSurfaceDomToken (spec :: SurfaceSpec) (marker :: Type) (primitives :: [SurfacePrimitive]) :: SurfacePrimitive where
    FindSurfaceDomToken spec marker (('DomToken marker) ': rest) = 'DomToken marker
    FindSurfaceDomToken spec marker (('BrowserDomToken marker) ': rest) = 'BrowserDomToken marker
    FindSurfaceDomToken spec marker (primitive ': rest) = FindSurfaceDomToken spec marker rest
    FindSurfaceDomToken spec marker '[] = TypeError
        ( 'Text "FrontendSurface "
            ':<>: 'ShowType spec
            ':<>: 'Text " does not declare DOM token marker "
            ':<>: 'ShowType marker
        )

type family FindSurfaceSourceRef (spec :: SurfaceSpec) (marker :: Type) (primitives :: [SurfacePrimitive]) :: SurfacePrimitive where
    FindSurfaceSourceRef spec marker (('SourceRef marker options) ': rest) = 'SourceRef marker options
    FindSurfaceSourceRef spec marker (primitive ': rest) = FindSurfaceSourceRef spec marker rest
    FindSurfaceSourceRef spec marker '[] = TypeError
        ( 'Text "FrontendSurface "
            ':<>: 'ShowType spec
            ':<>: 'Text " does not declare source-ref marker "
            ':<>: 'ShowType marker
        )

type family FindSurfaceDropzoneRef (spec :: SurfaceSpec) (marker :: Type) (primitives :: [SurfacePrimitive]) :: SurfacePrimitive where
    FindSurfaceDropzoneRef spec marker (('DropzoneRef marker options) ': rest) = 'DropzoneRef marker options
    FindSurfaceDropzoneRef spec marker (primitive ': rest) = FindSurfaceDropzoneRef spec marker rest
    FindSurfaceDropzoneRef spec marker '[] = TypeError
        ( 'Text "FrontendSurface "
            ':<>: 'ShowType spec
            ':<>: 'Text " does not declare dropzone-ref marker "
            ':<>: 'ShowType marker
        )

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
    RequireSurfaceResource spec marker 'Nothing = TypeError
        ( 'Text "FrontendSurface "
            ':<>: 'ShowType spec
            ':<>: 'Text " does not declare resource marker "
            ':<>: 'ShowType marker
        )

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
surfaceActionNameValue = (surfaceActionValue @spec @marker).htmxActionName

surfaceActionValue :: forall spec marker. ReflectPrimitive (SurfaceActionPrimitive spec marker) => HtmxActionIR
surfaceActionValue =
    case reflectPrimitive @(SurfaceActionPrimitive spec marker) of
        ReflectedHtmxAction action -> action
        _ -> error "impossible: action lookup reflected a different primitive"

surfaceIntentNameValue :: forall spec marker. ReflectPrimitive (SurfaceIntentPrimitive spec marker) => Text
surfaceIntentNameValue = (surfaceIntentValue @spec @marker).intentName

surfaceIntentValue :: forall spec marker. ReflectPrimitive (SurfaceIntentPrimitive spec marker) => IntentIR
surfaceIntentValue =
    case reflectPrimitive @(SurfaceIntentPrimitive spec marker) of
        ReflectedIntent intent -> intent
        _ -> error "impossible: intent lookup reflected a different primitive"

surfaceResourceValue :: forall spec marker. ReflectResource (SurfaceResourceSpec spec marker) => ResourceIR
surfaceResourceValue = reflectResource @(SurfaceResourceSpec spec marker)

surfaceActivationRefValue :: forall spec marker. ReflectPrimitive (SurfaceActivationRefPrimitive spec marker) => InteractionActivationRefIR
surfaceActivationRefValue =
    case reflectPrimitive @(SurfaceActivationRefPrimitive spec marker) of
        ReflectedActivationRef ref -> ref
        _ -> error "impossible: activation-ref lookup reflected a different primitive"

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
