{-# LANGUAGE AllowAmbiguousTypes  #-}
{-# LANGUAGE FlexibleContexts     #-}
{-# LANGUAGE FlexibleInstances    #-}
{-# LANGUAGE ScopedTypeVariables  #-}
{-# LANGUAGE TypeApplications     #-}
{-# LANGUAGE TypeOperators        #-}
{-# LANGUAGE UndecidableInstances #-}

module Application.Helper.Frontend.Generic
    ( FrontendNullable (..)
    , FrontendOptional (..)
    , FrontendRef (..)
    , genericFrontendCodec
    , genericFrontendCodecWith
    ) where

import Application.Helper.Frontend.Codec (FrontendCodec (..),
                                          FrontendField (..),
                                          FrontendSchema (..),
                                          FrontendVariant (..),
                                          HasFrontendCodec (..), encodeFrontend,
                                          parseFrontend)
import Application.Helper.Frontend.Options (FrontendCodecOptions (..),
                                            defaultFrontendCodecOptions)
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as AesonKey
import qualified Data.Aeson.Types as Aeson
import Data.Kind (Type)
import qualified Data.Text as Text
import qualified Data.Vector as Vector
import GHC.Generics
import IHP.Prelude hiding (from, to)

newtype FrontendNullable a = FrontendNullable { unFrontendNullable :: Maybe a }
    deriving (Eq, Show)

newtype FrontendOptional a = FrontendOptional { unFrontendOptional :: Maybe a }
    deriving (Eq, Show)

-- | Marks a field as a named schema reference instead of inlining its schema.
newtype FrontendRef a = FrontendRef { unFrontendRef :: a }
    deriving (Eq, Show)

data FieldCodec a = FieldCodec
    { fieldCodecSchema      :: !FrontendSchema
    , fieldCodecEncodeValue :: !(a -> Aeson.Value)
    , fieldCodecParseValue  :: !(Aeson.Value -> Aeson.Parser a)
    , fieldCodecEncodePair  :: !(Text -> a -> Maybe Aeson.Pair)
    , fieldCodecParseField  :: !(Text -> Aeson.Object -> Aeson.Parser a)
    }

class FrontendFieldCodec a where
    frontendFieldCodec :: FieldCodec a

plainFieldCodec :: FrontendSchema -> (a -> Aeson.Value) -> (Aeson.Value -> Aeson.Parser a) -> FieldCodec a
plainFieldCodec schema encodeValue parseValue = FieldCodec
    { fieldCodecSchema = schema
    , fieldCodecEncodeValue = encodeValue
    , fieldCodecParseValue = parseValue
    , fieldCodecEncodePair = \fieldName value -> Just (AesonKey.fromText fieldName Aeson..= encodeValue value)
    , fieldCodecParseField = \fieldName object -> parseValue =<< object Aeson..: AesonKey.fromText fieldName
    }

instance FrontendFieldCodec Text where
    frontendFieldCodec = plainFieldCodec SchemaString Aeson.toJSON (Aeson.withText "string" pure)

instance FrontendFieldCodec Int where
    frontendFieldCodec = plainFieldCodec SchemaInt Aeson.toJSON Aeson.parseJSON

instance FrontendFieldCodec Bool where
    frontendFieldCodec = plainFieldCodec SchemaBool Aeson.toJSON Aeson.parseJSON

instance {-# OVERLAPPABLE #-} HasFrontendCodec a => FrontendFieldCodec a where
    frontendFieldCodec =
        case codecName (frontendCodec @a) of
            Just refName -> plainFieldCodec
                (SchemaRef refName)
                (encodeFrontend (frontendCodec @a))
                (parseFrontend (frontendCodec @a))
            Nothing -> error "Nested frontend field codecs require the referenced codec to have a name"

instance FrontendFieldCodec a => FrontendFieldCodec [a] where
    frontendFieldCodec = FieldCodec
        { fieldCodecSchema = SchemaArray inner.fieldCodecSchema
        , fieldCodecEncodeValue = encodeArray
        , fieldCodecParseValue = parseArray
        , fieldCodecEncodePair = \fieldName value -> Just (AesonKey.fromText fieldName Aeson..= encodeArray value)
        , fieldCodecParseField = \fieldName object -> parseArray =<< object Aeson..: AesonKey.fromText fieldName
        }
        where
            inner = frontendFieldCodec @a
            encodeArray = Aeson.Array . Vector.fromList . fmap inner.fieldCodecEncodeValue
            parseArray = Aeson.withArray "array" (mapM inner.fieldCodecParseValue . Vector.toList)

instance FrontendFieldCodec a => FrontendFieldCodec (Maybe a) where
    frontendFieldCodec = FieldCodec
        { fieldCodecSchema = SchemaNullable inner.fieldCodecSchema
        , fieldCodecEncodeValue = encodeNullable
        , fieldCodecParseValue = parseNullable
        , fieldCodecEncodePair = \fieldName value -> Just (AesonKey.fromText fieldName Aeson..= encodeNullable value)
        , fieldCodecParseField = \fieldName object -> parseNullable =<< object Aeson..: AesonKey.fromText fieldName
        }
        where
            inner = frontendFieldCodec @a
            encodeNullable = maybe Aeson.Null inner.fieldCodecEncodeValue
            parseNullable = \case
                Aeson.Null -> pure Nothing
                value -> Just <$> inner.fieldCodecParseValue value

instance FrontendFieldCodec a => FrontendFieldCodec (FrontendNullable a) where
    frontendFieldCodec = FieldCodec
        { fieldCodecSchema = SchemaNullable inner.fieldCodecSchema
        , fieldCodecEncodeValue = encodeNullable
        , fieldCodecParseValue = parseNullable
        , fieldCodecEncodePair = \fieldName value -> Just (AesonKey.fromText fieldName Aeson..= encodeNullable value)
        , fieldCodecParseField = \fieldName object -> parseNullable =<< object Aeson..: AesonKey.fromText fieldName
        }
        where
            inner = frontendFieldCodec @a
            encodeNullable = maybe Aeson.Null inner.fieldCodecEncodeValue . unFrontendNullable
            parseNullable = \case
                Aeson.Null -> pure (FrontendNullable Nothing)
                value -> FrontendNullable . Just <$> inner.fieldCodecParseValue value

instance FrontendFieldCodec a => FrontendFieldCodec (FrontendOptional a) where
    frontendFieldCodec = FieldCodec
        { fieldCodecSchema = SchemaOptional inner.fieldCodecSchema
        , fieldCodecEncodeValue = maybe Aeson.Null inner.fieldCodecEncodeValue . unFrontendOptional
        , fieldCodecParseValue = \case
            Aeson.Null -> pure (FrontendOptional Nothing)
            value -> FrontendOptional . Just <$> inner.fieldCodecParseValue value
        , fieldCodecEncodePair = \fieldName value ->
            case unFrontendOptional value of
                Nothing -> Nothing
                Just innerValue -> Just (AesonKey.fromText fieldName Aeson..= inner.fieldCodecEncodeValue innerValue)
        , fieldCodecParseField = \fieldName object -> do
            maybeValue <- object Aeson..:? AesonKey.fromText fieldName
            case maybeValue of
                Nothing -> pure (FrontendOptional Nothing)
                Just value -> FrontendOptional . Just <$> inner.fieldCodecParseValue value
        }
        where
            inner = frontendFieldCodec @a

instance HasFrontendCodec a => FrontendFieldCodec (FrontendRef a) where
    frontendFieldCodec =
        case codecName (frontendCodec @a) of
            Just refName -> plainFieldCodec
                (SchemaRef refName)
                (encodeFrontend (frontendCodec @a) . unFrontendRef)
                (fmap FrontendRef . parseFrontend (frontendCodec @a))
            Nothing -> error "FrontendRef requires the referenced codec to have a name"

-- | Derive a JSON-shaped frontend codec from a narrow DTO's Generic instance.
genericFrontendCodec :: forall a. (Generic a, GFrontendRoot (Rep a)) => FrontendCodec a
genericFrontendCodec = genericFrontendCodecWith defaultFrontendCodecOptions

-- | Derive a JSON-shaped frontend codec using local naming/tag options.
genericFrontendCodecWith :: forall a. (Generic a, GFrontendRoot (Rep a)) => FrontendCodecOptions -> FrontendCodec a
genericFrontendCodecWith options = FrontendCodec
    { codecName = Just typeName
    , codecSchema = gRootSchema options typeName (Proxy @(Rep a))
    , codecEncode = gRootEncode options typeName . from
    , codecParse = fmap to . gRootParse options typeName
    }
    where
        inferredName = gRootTypeName (Proxy @(Rep a))
        typeName = fromMaybe inferredName options.frontendTypeNameOverride

class GFrontendRoot (f :: Type -> Type) where
    gRootTypeName :: Proxy f -> Text
    gRootSchema :: FrontendCodecOptions -> Text -> Proxy f -> FrontendSchema
    gRootEncode :: FrontendCodecOptions -> Text -> f p -> Aeson.Value
    gRootParse :: FrontendCodecOptions -> Text -> Aeson.Value -> Aeson.Parser (f p)

instance (Datatype datatype, GDatatype f) => GFrontendRoot (M1 D datatype f) where
    gRootTypeName _ = cs (datatypeName (undefined :: M1 D datatype f ()))
    gRootSchema options typeName _ = gDatatypeSchema options typeName (Proxy @f)
    gRootEncode options typeName (M1 value) = gDatatypeEncode options typeName value
    gRootParse options typeName value = M1 <$> gDatatypeParse options typeName value

class GDatatype (f :: Type -> Type) where
    gDatatypeSchema :: FrontendCodecOptions -> Text -> Proxy f -> FrontendSchema
    gDatatypeEncode :: FrontendCodecOptions -> Text -> f p -> Aeson.Value
    gDatatypeParse :: FrontendCodecOptions -> Text -> Aeson.Value -> Aeson.Parser (f p)

instance (Constructor constructor, GRecordFields fields) => GDatatype (M1 C constructor fields) where
    gDatatypeSchema options typeName _ = SchemaRecord typeName (gRecordFields options (Proxy @fields))
    gDatatypeEncode options _ (M1 fields) = Aeson.object (catMaybes (gRecordEncode options fields))
    gDatatypeParse options typeName = Aeson.withObject (cs typeName) \object -> M1 <$> gRecordParse options object

instance GSum (left :+: right) => GDatatype (left :+: right) where
    gDatatypeSchema options typeName _
        | gSumIsEnum (Proxy @(left :+: right)) = SchemaStringEnum typeName (gSumEnumTags options (Proxy @(left :+: right)))
        | otherwise = SchemaTaggedUnion typeName options.frontendTaggedUnionTagField (gSumVariants options (Proxy @(left :+: right)))
    gDatatypeEncode options _ value
        | gSumIsEnum (Proxy @(left :+: right)) = Aeson.String (gSumEncodeEnum options value)
        | otherwise = gSumEncodeTagged options value
    gDatatypeParse options typeName value
        | gSumIsEnum (Proxy @(left :+: right)) = Aeson.withText (cs typeName) (gSumParseEnum options) value
        | otherwise = Aeson.withObject (cs typeName) (gSumParseTagged options) value

class GRecordFields (f :: Type -> Type) where
    gRecordFields :: FrontendCodecOptions -> Proxy f -> [FrontendField]
    gRecordEncode :: FrontendCodecOptions -> f p -> [Maybe Aeson.Pair]
    gRecordParse :: FrontendCodecOptions -> Aeson.Object -> Aeson.Parser (f p)

instance GRecordFields U1 where
    gRecordFields _ _ = []
    gRecordEncode _ U1 = []
    gRecordParse _ _ = pure U1

instance (GRecordFields left, GRecordFields right) => GRecordFields (left :*: right) where
    gRecordFields options _ = gRecordFields options (Proxy @left) <> gRecordFields options (Proxy @right)
    gRecordEncode options (left :*: right) = gRecordEncode options left <> gRecordEncode options right
    gRecordParse options object = (:*:)
        <$> gRecordParse options object
        <*> gRecordParse options object

instance (Selector selector, FrontendFieldCodec value) => GRecordFields (M1 S selector (K1 i value)) where
    gRecordFields options _ = [FrontendField fieldName (fieldCodecSchema (frontendFieldCodec @value))]
        where
            fieldName = frontendFieldName options (cs (selName (undefined :: M1 S selector (K1 i value) ())))
    gRecordEncode options (M1 (K1 value)) = [fieldCodecEncodePair (frontendFieldCodec @value) fieldName value]
        where
            fieldName = frontendFieldName options (cs (selName (undefined :: M1 S selector (K1 i value) ())))
    gRecordParse options object = M1 . K1 <$> fieldCodecParseField (frontendFieldCodec @value) fieldName object
        where
            fieldName = frontendFieldName options (cs (selName (undefined :: M1 S selector (K1 i value) ())))

class GSum (f :: Type -> Type) where
    gSumIsEnum :: Proxy f -> Bool
    gSumEnumTags :: FrontendCodecOptions -> Proxy f -> [Text]
    gSumVariants :: FrontendCodecOptions -> Proxy f -> [FrontendVariant]
    gSumEncodeEnum :: FrontendCodecOptions -> f p -> Text
    gSumParseEnum :: FrontendCodecOptions -> Text -> Aeson.Parser (f p)
    gSumEncodeTagged :: FrontendCodecOptions -> f p -> Aeson.Value
    gSumParseTagged :: FrontendCodecOptions -> Aeson.Object -> Aeson.Parser (f p)

instance (GSum left, GSum right) => GSum (left :+: right) where
    gSumIsEnum _ = gSumIsEnum (Proxy @left) && gSumIsEnum (Proxy @right)
    gSumEnumTags options _ = gSumEnumTags options (Proxy @left) <> gSumEnumTags options (Proxy @right)
    gSumVariants options _ = gSumVariants options (Proxy @left) <> gSumVariants options (Proxy @right)
    gSumEncodeEnum options = \case
        L1 value -> gSumEncodeEnum options value
        R1 value -> gSumEncodeEnum options value
    gSumParseEnum options tag =
        (L1 <$> gSumParseEnum options tag) <|> (R1 <$> gSumParseEnum options tag)
    gSumEncodeTagged options = \case
        L1 value -> gSumEncodeTagged options value
        R1 value -> gSumEncodeTagged options value
    gSumParseTagged options object =
        (L1 <$> gSumParseTagged options object) <|> (R1 <$> gSumParseTagged options object)

instance (Constructor constructor, GConstructorFields fields) => GSum (M1 C constructor fields) where
    gSumIsEnum _ = gConstructorIsEnum (Proxy @fields)
    gSumEnumTags options _ = [constructorTag options (cs (conName (undefined :: M1 C constructor fields ())))]
    gSumVariants options _ =
        [ FrontendVariant
            (constructorTag options (cs (conName (undefined :: M1 C constructor fields ()))))
            (gConstructorFields options (Proxy @fields))
        ]
    gSumEncodeEnum options (M1 fields)
        | gConstructorIsEnum (Proxy @fields) = constructorTag options (cs (conName (undefined :: M1 C constructor fields ())))
        | otherwise = error "Cannot encode non-nullary constructor as frontend enum"
    gSumParseEnum options tag
        | tag == constructorTag options (cs (conName (undefined :: M1 C constructor fields ()))) && gConstructorIsEnum (Proxy @fields) = pure (M1 gConstructorNullaryValue)
        | otherwise = fail ("Unknown frontend enum tag: " <> cs tag)
    gSumEncodeTagged options (M1 fields) =
        Aeson.object $ tagPair : catMaybes (gConstructorEncode options fields)
        where
            tagPair = AesonKey.fromText options.frontendTaggedUnionTagField Aeson..= constructorTag options (cs (conName (undefined :: M1 C constructor fields ())))
    gSumParseTagged options object = do
        tag <- object Aeson..: AesonKey.fromText options.frontendTaggedUnionTagField
        if tag == constructorTag options (cs (conName (undefined :: M1 C constructor fields ())))
            then M1 <$> gConstructorParse options object
            else fail ("Unknown frontend union tag: " <> cs (tag :: Text))

class GConstructorFields (f :: Type -> Type) where
    gConstructorIsEnum :: Proxy f -> Bool
    gConstructorFields :: FrontendCodecOptions -> Proxy f -> [FrontendField]
    gConstructorEncode :: FrontendCodecOptions -> f p -> [Maybe Aeson.Pair]
    gConstructorParse :: FrontendCodecOptions -> Aeson.Object -> Aeson.Parser (f p)
    gConstructorNullaryValue :: f p

instance {-# OVERLAPPING #-} GConstructorFields U1 where
    gConstructorIsEnum _ = True
    gConstructorFields _ _ = []
    gConstructorEncode _ U1 = []
    gConstructorParse _ _ = pure U1
    gConstructorNullaryValue = U1

instance {-# OVERLAPPABLE #-} GRecordFields fields => GConstructorFields fields where
    gConstructorIsEnum _ = False
    gConstructorFields options proxy = gRecordFields options proxy
    gConstructorEncode options = gRecordEncode options
    gConstructorParse options = gRecordParse options
    gConstructorNullaryValue = error "Non-nullary frontend constructor has no nullary value"

frontendFieldName :: FrontendCodecOptions -> Text -> Text
frontendFieldName options = options.frontendFieldNameModifier

constructorTag :: FrontendCodecOptions -> Text -> Text
constructorTag options = options.frontendConstructorTagModifier
