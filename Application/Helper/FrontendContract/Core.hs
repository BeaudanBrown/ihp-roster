{-# LANGUAGE LambdaCase          #-}
{-# LANGUAGE OverloadedRecordDot #-}

-- | Canonical checked vocabulary shared by global and Surface contracts.
-- Domain-specific Surface topology remains in @Surface.ContractIR@; consumers
-- should use these types directly instead of defining a renderer-facing copy.
module Application.Helper.FrontendContract.Core
    ( BrowserReachabilityIR (..)
    , ContractDiagnostic (..)
    , FieldIR (..)
    , FieldPresence (..)
    , HtmxActionOptionIR (..)
    , HtmxMethodIR (..)
    , HtmxPushUrlIR (..)
    , HtmxSyntaxIR (..)
    , SchemaIR (..)
    , SurfaceWireField (..)
    , UnionCaseIR (..)
    , WireIR (..)
    , duplicateDiagnostics
    , fieldRefs
    , htmxMethodText
    , htmxSyntaxRawReason
    , htmxSyntaxReferences
    , htmxSyntaxText
    , schemaFields
    , schemaNameAndMarker
    , schemaRefs
    , surfaceWireFieldName
    , validateFieldNames
    , validateSchemaIR
    , wireRefs
    ) where

import qualified Data.List as List
import qualified Data.Text as Text
import IHP.Prelude

-- | Browser operations emitted for one checked schema/event declaration.
-- Global and Surface roots share this representation so projection stays a
-- decision-free renderer over checked IR.
data BrowserReachabilityIR
    = BrowserUnreachableIR
    | BrowserTypeOnlyIR
    | BrowserGuardIR
    | BrowserInboundIR
    | BrowserOutboundIR
    | BrowserBidirectionalIR
    deriving (Eq, Show)

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

-- | Closed envelope fields synthesized by the semantic Surface wire terminals.
-- These names are shared by Haskell validation/carriers and TypeScript
-- rendering; feature carrier modules never spell them independently.
data SurfaceWireField
    = SurfaceWireSurfaceField
    | SurfaceWireScopeField
    | SurfaceWireKindField
    | SurfaceWireParamsField
    deriving (Eq, Ord, Show)

surfaceWireFieldName :: SurfaceWireField -> Text
surfaceWireFieldName = \case
    SurfaceWireSurfaceField -> "surface"
    SurfaceWireScopeField -> "scope"
    SurfaceWireKindField -> "kind"
    SurfaceWireParamsField -> "params"

data WireIR
    = WireTextIR
    | WireIntIR
    | WireBoolIR
    | WireUuidIR
    | WireDayIR
    -- | Exact closed scalar schema name plus its Haskell source module/type.
    -- Browser renderers use only the schema name; generated Haskell adapters
    -- retain source identity without inspecting compiler syntax.
    | WireClosedIR !Text !Text !Text
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

data HtmxSyntaxIR
    = HtmxTypedSyntaxIR !Text ![Text]
    | HtmxRawSyntaxIR !Text !Text
    deriving (Eq, Show)

htmxSyntaxText :: HtmxSyntaxIR -> Text
htmxSyntaxText = \case
    HtmxTypedSyntaxIR value _ -> value
    HtmxRawSyntaxIR value _ -> value

htmxSyntaxReferences :: HtmxSyntaxIR -> [Text]
htmxSyntaxReferences = \case
    HtmxTypedSyntaxIR _ references -> references
    HtmxRawSyntaxIR _ _ -> []

htmxSyntaxRawReason :: HtmxSyntaxIR -> Maybe Text
htmxSyntaxRawReason = \case
    HtmxTypedSyntaxIR _ _ -> Nothing
    HtmxRawSyntaxIR _ reason -> Just reason

data HtmxActionOptionIR
    = HtmxActionMethodIR !HtmxMethodIR
    | HtmxActionTriggerIR !HtmxSyntaxIR
    | HtmxActionIncludeIR !HtmxSyntaxIR
    | HtmxActionSyncIR !HtmxSyntaxIR
    | HtmxActionIndicatorIR !HtmxSyntaxIR
    | HtmxActionConfirmIR !Text
    | HtmxActionSelectIR !HtmxSyntaxIR
    | HtmxActionTargetIR !HtmxSyntaxIR
    | HtmxActionSwapIR !HtmxSyntaxIR
    | HtmxActionPushUrlIR !HtmxPushUrlIR
    | HtmxActionCustomHtmxIR !Text !Text
    deriving (Eq, Show)

data SchemaIR
    = RecordIR !Text !Text ![FieldIR]
    | EnumIR !Text !Text ![Text]
    | ClosedScalarIR !Text !Text ![Text]
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
    ClosedScalarIR _ _ values -> duplicateDiagnostics "closed-scalar-value-collision" "closed scalar value" [(value, value) | value <- values]
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
    ClosedScalarIR marker name _ -> (name, marker)
    LiteralEnumIR marker name _ -> (name, marker)
    TaggedUnionIR marker name _ _ -> (name, marker)

schemaFields :: SchemaIR -> [FieldIR]
schemaFields = \case
    RecordIR _ _ fields -> fields
    EnumIR {} -> []
    ClosedScalarIR {} -> []
    LiteralEnumIR {} -> []
    TaggedUnionIR _ _ _ cases -> concatMap (.unionCaseFields) cases

schemaRefs :: SchemaIR -> [Text]
schemaRefs = \case
    RecordIR _ _ fields -> fieldRefs fields
    EnumIR {} -> []
    ClosedScalarIR {} -> []
    LiteralEnumIR {} -> []
    TaggedUnionIR _ _ _ cases -> concatMap (fieldRefs . (.unionCaseFields)) cases

fieldRefs :: [FieldIR] -> [Text]
fieldRefs = concatMap (wireRefs . (.fieldWire))

wireRefs :: WireIR -> [Text]
wireRefs = \case
    WireRefIR name -> [name]
    WireClosedIR name _ _ -> [name]
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
