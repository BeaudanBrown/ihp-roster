{-# LANGUAGE ExistentialQuantification #-}

module Application.Helper.Frontend.Codec
    ( FrontendCodec (..)
    , FrontendField (..)
    , FrontendSchema (..)
    , FrontendVariant (..)
    , SomeFrontendCodec (..)
    , arrayCodec
    , boolCodec
    , encodeFrontend
    , intCodec
    , nullableCodec
    , parseFrontend
    , refCodec
    , renderFrontendContracts
    , renderTypedConstant
    , stringCodec
    , stringEnumCodec
    ) where

import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Types as Aeson
import qualified Data.ByteString.Lazy as LBS
import qualified Data.List as List
import qualified Data.Text as Text
import qualified Data.Text.Encoding as TextEncoding
import qualified Data.Vector as Vector
import IHP.Prelude

-- | A narrow Haskell-owned frontend codec. The schema is the source for
-- TypeScript declarations, guards, and typed constants; the encode/parse
-- functions are the JSON boundary implementation for the same contract.
data FrontendCodec a = FrontendCodec
    { codecName   :: !(Maybe Text)
    , codecSchema :: !FrontendSchema
    , codecEncode :: !(a -> Aeson.Value)
    , codecParse  :: !(Aeson.Value -> Aeson.Parser a)
    }

-- | Schema shapes intentionally supported by Bepis browser contracts.
data FrontendSchema
    = SchemaString
    | SchemaInt
    | SchemaBool
    | SchemaNullable !FrontendSchema
    | SchemaOptional !FrontendSchema
    | SchemaArray !FrontendSchema
    | SchemaRef !Text
    | SchemaRecord !Text ![FrontendField]
    | SchemaStringEnum !Text ![Text]
    | SchemaTaggedUnion !Text !Text ![FrontendVariant]
    deriving (Eq, Show)

data FrontendField = FrontendField
    { fieldName   :: !Text
    , fieldSchema :: !FrontendSchema
    }
    deriving (Eq, Show)

data FrontendVariant = FrontendVariant
    { variantTag    :: !Text
    , variantFields :: ![FrontendField]
    }
    deriving (Eq, Show)

data SomeFrontendCodec = forall a. SomeFrontendCodec (FrontendCodec a)

stringCodec :: FrontendCodec Text
stringCodec = FrontendCodec Nothing SchemaString Aeson.toJSON (Aeson.withText "string" pure)

intCodec :: FrontendCodec Int
intCodec = FrontendCodec Nothing SchemaInt Aeson.toJSON Aeson.parseJSON

boolCodec :: FrontendCodec Bool
boolCodec = FrontendCodec Nothing SchemaBool Aeson.toJSON Aeson.parseJSON

arrayCodec :: FrontendCodec a -> FrontendCodec [a]
arrayCodec itemCodec =
    FrontendCodec
        { codecName = Nothing
        , codecSchema = SchemaArray itemCodec.codecSchema
        , codecEncode = Aeson.Array . Vector.fromList . fmap (codecEncode itemCodec)
        , codecParse = Aeson.withArray "array" (mapM (codecParse itemCodec) . Vector.toList)
        }

nullableCodec :: FrontendCodec a -> FrontendCodec (Maybe a)
nullableCodec innerCodec =
    FrontendCodec
        { codecName = Nothing
        , codecSchema = SchemaNullable innerCodec.codecSchema
        , codecEncode = maybe Aeson.Null (codecEncode innerCodec)
        , codecParse = \case
            Aeson.Null -> pure Nothing
            value -> Just <$> codecParse innerCodec value
        }

refCodec :: Text -> FrontendCodec Aeson.Value
refCodec name =
    FrontendCodec
        { codecName = Nothing
        , codecSchema = SchemaRef name
        , codecEncode = id
        , codecParse = pure
        }

stringEnumCodec :: Eq a => Text -> [(a, Text)] -> FrontendCodec a
stringEnumCodec name values =
    FrontendCodec
        { codecName = Just name
        , codecSchema = SchemaStringEnum name (fmap snd values)
        , codecEncode = \value -> Aeson.String (enumText value)
        , codecParse = Aeson.withText (cs name) parseEnum
        }
    where
        enumText value = fromMaybe (error ("Unknown frontend enum value for " <> cs name)) (lookup value values)
        parseEnum text = case List.find ((== text) . snd) values of
            Just (value, _) -> pure value
            Nothing         -> fail ("Unknown " <> cs name <> ": " <> cs text)

encodeFrontend :: FrontendCodec a -> a -> Aeson.Value
encodeFrontend = codecEncode

parseFrontend :: FrontendCodec a -> Aeson.Value -> Aeson.Parser a
parseFrontend = codecParse

renderFrontendContracts :: [SomeFrontendCodec] -> Either Text Text
renderFrontendContracts codecs = do
    namedSchemas <- mapM namedCodecSchema codecs
    case duplicateNames (fmap fst namedSchemas) of
        [] -> Right (Text.unlines (helperSource : concatMap renderNamed namedSchemas))
        duplicates -> Left ("Duplicate frontend codec names: " <> Text.intercalate ", " duplicates)

renderTypedConstant :: Text -> FrontendCodec a -> a -> Text
renderTypedConstant constantName codec value =
    "export const " <> constantName <> ": " <> schemaType codec.codecSchema <> " = " <> encodeJsonText (codecEncode codec value) <> ";"

namedCodecSchema :: SomeFrontendCodec -> Either Text (Text, FrontendSchema)
namedCodecSchema (SomeFrontendCodec codec) =
    case codec.codecName of
        Just name -> Right (name, codec.codecSchema)
        Nothing   -> Left "Top-level frontend codecs must have names"

renderNamed :: (Text, FrontendSchema) -> [Text]
renderNamed (name, schema) =
    [ renderTypeDeclaration name schema
    , renderGuardDeclaration name schema
    , ""
    ]

renderTypeDeclaration :: Text -> FrontendSchema -> Text
renderTypeDeclaration name = \case
    SchemaRecord _ fields ->
        Text.unlines $
            [ "export type " <> name <> " = {" ]
                <> fmap renderField fields
                <> [ "};" ]
    SchemaStringEnum _ values ->
        Text.unlines $
            [ "export type " <> name <> " =" ]
                <> renderUnionValues values
    SchemaTaggedUnion _ tagField variants ->
        Text.unlines $
            [ "export type " <> name <> " =" ]
                <> renderUnionVariants tagField variants
    schema ->
        "export type " <> name <> " = " <> schemaType schema <> ";"

renderField :: FrontendField -> Text
renderField field =
    "    " <> field.fieldName <> optionalMarker field.fieldSchema <> ": " <> schemaType (stripOptional field.fieldSchema) <> ";"

renderUnionValues :: [Text] -> [Text]
renderUnionValues values =
    case reverse values of
        [] -> [ "    never;" ]
        lastValue : reversedPrefix ->
            fmap ("    | " <>) (fmap quote (reverse reversedPrefix)) <> [ "    | " <> quote lastValue <> ";" ]

renderUnionVariants :: Text -> [FrontendVariant] -> [Text]
renderUnionVariants tagField variants =
    case reverse variants of
        [] -> [ "    never;" ]
        lastVariant : reversedPrefix ->
            fmap ("    | " <>) (fmap (renderVariantType tagField) (reverse reversedPrefix))
                <> [ "    | " <> renderVariantType tagField lastVariant <> ";" ]

renderVariantType :: Text -> FrontendVariant -> Text
renderVariantType tagField variant =
    "{ " <> Text.intercalate "; " (tagPart : fmap renderVariantField variant.variantFields) <> " }"
    where
        tagPart = tagField <> ": " <> quote variant.variantTag
        renderVariantField field = field.fieldName <> optionalMarker field.fieldSchema <> ": " <> schemaType (stripOptional field.fieldSchema)

schemaType :: FrontendSchema -> Text
schemaType = \case
    SchemaString -> "string"
    SchemaInt -> "number"
    SchemaBool -> "boolean"
    SchemaNullable inner -> schemaType inner <> " | null"
    SchemaOptional inner -> schemaType inner <> " | undefined"
    SchemaArray inner -> schemaType inner <> "[]"
    SchemaRef name -> name
    SchemaRecord name _ -> name
    SchemaStringEnum name _ -> name
    SchemaTaggedUnion name _ _ -> name

renderGuardDeclaration :: Text -> FrontendSchema -> Text
renderGuardDeclaration name schema =
    Text.unlines
        [ "export function is" <> name <> "(value: unknown): value is " <> name <> " {"
        , "    return " <> guardExpr "value" schema <> ";"
        , "}"
        ]

guardExpr :: Text -> FrontendSchema -> Text
guardExpr valueExpr = \case
    SchemaString -> "typeof " <> valueExpr <> " === \"string\""
    SchemaInt -> "typeof " <> valueExpr <> " === \"number\" && Number.isInteger(" <> valueExpr <> ")"
    SchemaBool -> "typeof " <> valueExpr <> " === \"boolean\""
    SchemaNullable inner -> valueExpr <> " === null || (" <> guardExpr valueExpr inner <> ")"
    SchemaOptional inner -> valueExpr <> " === undefined || (" <> guardExpr valueExpr inner <> ")"
    SchemaArray inner -> "Array.isArray(" <> valueExpr <> ") && " <> valueExpr <> ".every((item) => " <> guardExpr "item" inner <> ")"
    SchemaRef name -> "is" <> name <> "(" <> valueExpr <> ")"
    SchemaRecord _ fields -> recordGuard valueExpr fields
    SchemaStringEnum _ values -> Text.intercalate " || " (fmap (\value -> valueExpr <> " === " <> quote value) values)
    SchemaTaggedUnion _ tagField variants -> Text.intercalate " || " (fmap (\variant -> "(" <> variantGuard valueExpr tagField variant <> ")") variants)

recordGuard :: Text -> [FrontendField] -> Text
recordGuard valueExpr fields =
    Text.intercalate
        " && "
        ([ "isExactRecord(" <> valueExpr <> ", " <> stringArray requiredNames <> ", " <> stringArray optionalNames <> ")" ] <> fmap fieldGuard fields)
    where
        requiredNames = fmap (.fieldName) (filter (not . isOptionalSchema . (.fieldSchema)) fields)
        optionalNames = fmap (.fieldName) (filter (isOptionalSchema . (.fieldSchema)) fields)
        fieldGuard field =
            case field.fieldSchema of
                SchemaOptional inner -> "(!Object.prototype.hasOwnProperty.call(" <> valueExpr <> ", " <> quote field.fieldName <> ") || " <> guardExpr (valueExpr <> "[" <> quote field.fieldName <> "]") inner <> ")"
                schema -> guardExpr (valueExpr <> "[" <> quote field.fieldName <> "]") schema

variantGuard :: Text -> Text -> FrontendVariant -> Text
variantGuard valueExpr tagField variant =
    Text.intercalate
        " && "
        ([ "isExactRecord(" <> valueExpr <> ", " <> stringArray requiredNames <> ", " <> stringArray optionalNames <> ")"
         , valueExpr <> "[" <> quote tagField <> "] === " <> quote variant.variantTag
         ] <> fmap fieldGuard variant.variantFields)
    where
        requiredNames = tagField : fmap (.fieldName) (filter (not . isOptionalSchema . (.fieldSchema)) variant.variantFields)
        optionalNames = fmap (.fieldName) (filter (isOptionalSchema . (.fieldSchema)) variant.variantFields)
        fieldGuard field =
            case field.fieldSchema of
                SchemaOptional inner -> "(!Object.prototype.hasOwnProperty.call(" <> valueExpr <> ", " <> quote field.fieldName <> ") || " <> guardExpr (valueExpr <> "[" <> quote field.fieldName <> "]") inner <> ")"
                schema -> guardExpr (valueExpr <> "[" <> quote field.fieldName <> "]") schema

helperSource :: Text
helperSource = Text.unlines
    [ "function isExactRecord(value: unknown, requiredKeys: string[], optionalKeys: string[]): value is Record<string, unknown> {"
    , "    if (typeof value !== \"object\" || value === null || Array.isArray(value)) return false;"
    , "    const actualKeys = Object.keys(value);"
    , "    const allowedKeys = new Set([...requiredKeys, ...optionalKeys]);"
    , "    return requiredKeys.every((key) => Object.prototype.hasOwnProperty.call(value, key)) && actualKeys.every((key) => allowedKeys.has(key));"
    , "}"
    , ""
    ]

optionalMarker :: FrontendSchema -> Text
optionalMarker = \case
    SchemaOptional _ -> "?"
    _ -> ""

stripOptional :: FrontendSchema -> FrontendSchema
stripOptional = \case
    SchemaOptional inner -> inner
    schema -> schema

isOptionalSchema :: FrontendSchema -> Bool
isOptionalSchema = \case
    SchemaOptional _ -> True
    _ -> False

stringArray :: [Text] -> Text
stringArray values = "[" <> Text.intercalate ", " (fmap quote values) <> "]"

quote :: Text -> Text
quote value =
    encodeJsonText (Aeson.String value)

duplicateNames :: [Text] -> [Text]
duplicateNames names =
    names
        |> List.sort
        |> groupedDuplicates
    where
        groupedDuplicates [] = []
        groupedDuplicates (name : rest)
            | name `elem` rest = name : groupedDuplicates (dropWhile (== name) rest)
            | otherwise = groupedDuplicates rest

encodeJsonText :: Aeson.Value -> Text
encodeJsonText = TextEncoding.decodeUtf8 . LBS.toStrict . Aeson.encode
