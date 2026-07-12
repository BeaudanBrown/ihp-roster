{-# LANGUAGE LambdaCase          #-}
{-# LANGUAGE OverloadedRecordDot #-}

-- | Canonical checked vocabulary shared by global and Surface contracts.
-- Domain-specific Surface topology remains in @Surface.ContractIR@; consumers
-- should use these types directly instead of defining a renderer-facing copy.
module Application.Helper.FrontendContract.Core
    ( ContractDiagnostic (..)
    , FieldIR (..)
    , FieldPresence (..)
    , HtmxActionOptionIR (..)
    , HtmxMethodIR (..)
    , HtmxPushUrlIR (..)
    , SchemaIR (..)
    , UnionCaseIR (..)
    , WireIR (..)
    , duplicateDiagnostics
    , fieldRefs
    , htmxMethodText
    , htmxPushUrlBool
    , schemaFields
    , schemaNameAndMarker
    , schemaRefs
    , validateFieldNames
    , validateSchemaIR
    , wireRefs
    ) where

import qualified Data.List as List
import qualified Data.Text as Text
import IHP.Prelude

-- | Shared checked representation used by both global contract declarations and
-- domain-specific Surface topology. Feature semantics remain in their own IR
-- nodes; fields, wires, schemas, diagnostics, and HTMX request metadata do not.
data FieldIR = FieldIR
    { fieldMarker   :: !Text
    , fieldName     :: !Text
    , fieldWire     :: !WireIR
    , fieldPresence :: !FieldPresence
    }
    deriving (Eq, Show)

data FieldPresence
    = RequiredField
    | OptionalFieldPresence
    | NullableFieldPresence
    deriving (Eq, Show)

data WireIR
    = WireTextIR
    | WireIntIR
    | WireBoolIR
    | WireUuidIR
    | WireDayIR
    | WireUnknownIR
    | WireListIR !WireIR
    | WireMapIR !WireIR !WireIR
    | WireOptionalIR !WireIR
    | WireNullableIR !WireIR
    | WireRefIR !Text
    | WireSurfaceScopeIR
    | WireSurfaceFragmentKeyIR
    deriving (Eq, Show)

data HtmxMethodIR
    = HtmxGetIR
    | HtmxPostIR
    | HtmxPutIR
    | HtmxPatchIR
    | HtmxDeleteIR
    deriving (Eq, Show)

data HtmxPushUrlIR
    = HtmxPushUrlTrueIR
    | HtmxPushUrlFalseIR
    deriving (Eq, Show)

htmxMethodText :: HtmxMethodIR -> Text
htmxMethodText = \case
    HtmxGetIR -> "get"
    HtmxPostIR -> "post"
    HtmxPutIR -> "put"
    HtmxPatchIR -> "patch"
    HtmxDeleteIR -> "delete"

htmxPushUrlBool :: HtmxPushUrlIR -> Bool
htmxPushUrlBool = \case
    HtmxPushUrlTrueIR -> True
    HtmxPushUrlFalseIR -> False

data HtmxActionOptionIR
    = HtmxActionMethodIR !HtmxMethodIR
    | HtmxActionTriggerIR !Text
    | HtmxActionIncludeIR !Text
    | HtmxActionSyncIR !Text
    | HtmxActionIndicatorIR !Text
    | HtmxActionConfirmIR !Text
    | HtmxActionSelectIR !Text
    | HtmxActionTargetIR !Text
    | HtmxActionSwapIR !Text
    | HtmxActionPushUrlIR !HtmxPushUrlIR
    | HtmxActionCustomHtmxIR !Text !Text
    deriving (Eq, Show)

data SchemaIR
    = RecordIR !Text !Text ![FieldIR]
    | EnumIR !Text !Text ![Text]
    | LiteralEnumIR !Text !Text ![(Text, Text)]
    | TaggedUnionIR !Text !Text !Text ![UnionCaseIR]
    deriving (Eq, Show)

data UnionCaseIR = UnionCaseIR
    { unionCaseMarker :: !Text
    , unionCaseTag    :: !Text
    , unionCaseFields :: ![FieldIR]
    }
    deriving (Eq, Show)

data ContractDiagnostic = ContractDiagnostic
    { diagnosticCode    :: !Text
    , diagnosticMessage :: !Text
    }
    deriving (Eq, Show)

validateSchemaIR :: SchemaIR -> [ContractDiagnostic]
validateSchemaIR = \case
    RecordIR _ _ fields -> validateFieldNames fields
    EnumIR _ _ values -> duplicateDiagnostics "enum-value-collision" "enum value" [(value, value) | value <- values]
    LiteralEnumIR _ _ values -> duplicateDiagnostics "literal-enum-value-collision" "literal enum value" [(value, marker) | (marker, value) <- values]
    TaggedUnionIR _ _ _ cases ->
        duplicateDiagnostics "union-case-collision" "union case" [(unionCase.unionCaseTag, unionCase.unionCaseMarker) | unionCase <- cases]
            <> concatMap (validateFieldNames . (.unionCaseFields)) cases

validateFieldNames :: [FieldIR] -> [ContractDiagnostic]
validateFieldNames fields =
    duplicateDiagnostics "field-name-collision" "field" [(field.fieldName, field.fieldMarker) | field <- fields]

duplicateDiagnostics :: Text -> Text -> [(Text, Text)] -> [ContractDiagnostic]
duplicateDiagnostics code label entries =
    entries
        |> List.sortOn fst
        |> List.groupBy (\left right -> fst left == fst right)
        |> mapMaybe toDiagnostic
  where
    toDiagnostic = \case
        [] -> Nothing
        group@((name, _) : _) ->
            let markers = List.nub (fmap snd group)
             in if length markers > 1 || length group > 1
                    then Just ContractDiagnostic
                        { diagnosticCode = code
                        , diagnosticMessage = "Duplicate " <> label <> " name " <> name <> " from " <> Text.intercalate ", " markers
                        }
                    else Nothing

schemaNameAndMarker :: SchemaIR -> (Text, Text)
schemaNameAndMarker = \case
    RecordIR marker name _ -> (name, marker)
    EnumIR marker name _ -> (name, marker)
    LiteralEnumIR marker name _ -> (name, marker)
    TaggedUnionIR marker name _ _ -> (name, marker)

schemaFields :: SchemaIR -> [FieldIR]
schemaFields = \case
    RecordIR _ _ fields -> fields
    EnumIR {} -> []
    LiteralEnumIR {} -> []
    TaggedUnionIR _ _ _ cases -> concatMap (.unionCaseFields) cases

schemaRefs :: SchemaIR -> [Text]
schemaRefs = \case
    RecordIR _ _ fields -> fieldRefs fields
    EnumIR {} -> []
    LiteralEnumIR {} -> []
    TaggedUnionIR _ _ _ cases -> concatMap (fieldRefs . (.unionCaseFields)) cases

fieldRefs :: [FieldIR] -> [Text]
fieldRefs = concatMap (wireRefs . (.fieldWire))

wireRefs :: WireIR -> [Text]
wireRefs = \case
    WireRefIR name -> [name]
    WireListIR inner -> wireRefs inner
    WireMapIR key value -> wireRefs key <> wireRefs value
    WireOptionalIR inner -> wireRefs inner
    WireNullableIR inner -> wireRefs inner
    WireTextIR -> []
    WireIntIR -> []
    WireBoolIR -> []
    WireUuidIR -> []
    WireDayIR -> []
    WireUnknownIR -> []
    WireSurfaceScopeIR -> []
    WireSurfaceFragmentKeyIR -> []
