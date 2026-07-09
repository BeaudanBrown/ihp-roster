{-# LANGUAGE LambdaCase          #-}
{-# LANGUAGE NoImplicitPrelude   #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE OverloadedStrings   #-}

module Application.Helper.FrontendContract.IR
    ( ContractDiagnostic (..)
    , FieldIR (..)
    , FieldPresence (..)
    , FrontendContractIR (..)
    , GlobalIR (..)
    , GlobalPrimitiveIR (..)
    , AppShellActionIR (..)
    , InteractionModifierVariantIR (..)
    , InteractionSourceRefIR (..)
    , SchemaIR (..)
    , SurfaceIR (..)
    , HtmxActionOptionIR (..)
    , SurfaceInteractionPolicyIR (..)
    , SurfacePrimitiveIR (..)
    , UnionCaseIR (..)
    , WireIR (..)
    , checkedFrontendContractIR
    , validateFrontendContractIR
    ) where

import qualified Data.List as List
import qualified Data.Set as Set
import qualified Data.Text as Text
import IHP.Prelude

data FrontendContractIR = FrontendContractIR
    { contractGlobals  :: ![GlobalIR]
    , contractSurfaces :: ![SurfaceIR]
    }
    deriving (Eq, Show)

data GlobalIR = GlobalIR
    { globalMarker     :: !Text
    , globalName       :: !Text
    , globalPrimitives :: ![GlobalPrimitiveIR]
    }
    deriving (Eq, Show)

data SurfaceIR = SurfaceIR
    { surfaceMarker              :: !Text
    , surfaceName                :: !Text
    , surfacePrimitives          :: ![SurfacePrimitiveIR]
    , surfaceInteractionSessions :: ![Text]
    , surfaceInteractionLayers   :: ![Text]
    , surfaceInteractionEffects  :: ![(Text, [Text])]
    , surfaceInteractionPolicies :: ![SurfaceInteractionPolicyIR]
    , surfaceSourceRefs          :: ![InteractionSourceRefIR]
    , surfaceDropzoneRefs        :: ![(Text, Text, Text)]
    , surfaceActivationRefs      :: ![(Text, Text, Maybe Text, Text)]
    , surfaceDomTokens           :: ![Text]
    , surfaceOverlayLanes        :: ![Text]
    , surfaceLiveFragments       :: ![Text]
    , surfaceContainedSurfaces   :: ![(Text, [Text])]
    }
    deriving (Eq, Show)

data SurfaceInteractionPolicyIR = SurfaceInteractionPolicyIR
    { interactionPolicySession    :: !(Maybe Text)
    , interactionPolicyResolution :: !Text
    }
    deriving (Eq, Show)

data InteractionSourceRefIR = InteractionSourceRefIR
    { interactionSourceRefName                :: !Text
    , interactionSourceRefSession             :: !Text
    , interactionSourceRefIntent              :: !Text
    , interactionSourceRefSourceField         :: !Text
    , interactionSourceRefCompatibleDropzones :: ![Text]
    , interactionSourceRefVariants            :: ![InteractionModifierVariantIR]
    }
    deriving (Eq, Show)

data InteractionModifierVariantIR = InteractionModifierVariantIR
    { interactionModifierSemantic :: !Text
    , interactionModifierIntent   :: !Text
    , interactionModifierEffects  :: ![(Text, [Text])]
    }
    deriving (Eq, Show)

data GlobalPrimitiveIR
    = GlobalSchemaIR !SchemaIR
    | GlobalEventIR !Text !Text ![FieldIR]
    | GlobalDomIdIR !Text !Text
    | GlobalDomAttrIR !Text !Text
    | GlobalDomValueIR !Text !Text
    | GlobalFieldNameIR !Text !Text
    | GlobalDomTokenIR !Text !Text
    | GlobalAppShellActionIR !AppShellActionIR
    deriving (Eq, Show)

data AppShellActionIR = AppShellActionIR
    { appShellActionMarker  :: !Text
    , appShellActionName    :: !Text
    , appShellActionFields  :: ![FieldIR]
    , appShellActionOptions :: ![HtmxActionOptionIR]
    }
    deriving (Eq, Show)

data HtmxActionOptionIR
    = HtmxActionMethodIR !Text
    | HtmxActionTriggerIR !Text
    | HtmxActionIncludeIR !Text
    | HtmxActionSyncIR !Text
    | HtmxActionIndicatorIR !Text
    | HtmxActionConfirmIR !Text
    | HtmxActionSelectIR !Text
    | HtmxActionTargetIR !Text
    | HtmxActionSwapIR !Text
    | HtmxActionPushUrlIR !Bool
    | HtmxActionCustomHtmxIR !Text !Text
    deriving (Eq, Show)

data SurfacePrimitiveIR
    = SurfaceSchemaIR !SchemaIR
    | SurfaceScopeIR !Text !Text ![FieldIR]
    | SurfaceFragmentIR !Text !Text ![FieldIR]
    | SurfaceActionIR !Text !Text ![FieldIR] ![HtmxActionOptionIR]
    | SurfaceIntentIR !Text !Text ![FieldIR]
    | SurfaceMountStateIR !Text !Text ![FieldIR]
    | SurfaceDtoIR !Text !Text ![FieldIR]
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
    | WireSurfaceWireFragmentIR
    deriving (Eq, Show)

data ContractDiagnostic = ContractDiagnostic
    { diagnosticCode    :: !Text
    , diagnosticMessage :: !Text
    }
    deriving (Eq, Show)

checkedFrontendContractIR :: FrontendContractIR -> Either [ContractDiagnostic] FrontendContractIR
checkedFrontendContractIR contract =
    case validateFrontendContractIR contract of
        []          -> Right contract
        diagnostics -> Left diagnostics

validateFrontendContractIR :: FrontendContractIR -> [ContractDiagnostic]
validateFrontendContractIR contract =
    duplicateDiagnostics "global-name-collision" "global" [(globalName global, globalMarker global) | global <- contract.contractGlobals]
        <> duplicateDiagnostics "surface-name-collision" "surface" [(surfaceName surface, surfaceMarker surface) | surface <- contract.contractSurfaces]
        <> duplicateDiagnostics "schema-name-collision" "schema" schemaNames
        <> duplicateDiagnostics "global-primitive-collision" "global primitive" globalPrimitiveNames
        <> concatMap validateGlobal contract.contractGlobals
        <> concatMap validateSurface contract.contractSurfaces
        <> unresolvedReferenceDiagnostics declaredRefs referencedRefs
    where
        schemaNames = concatMap globalSchemas contract.contractGlobals <> concatMap surfaceSchemas contract.contractSurfaces
        declaredRefs = Set.fromList (fmap fst schemaNames <> fmap fst surfaceDtos)
        referencedRefs = concatMap globalRefs contract.contractGlobals <> concatMap surfaceRefs contract.contractSurfaces
        surfaceDtos = concatMap surfaceDtoNames contract.contractSurfaces
        globalPrimitiveNames = concatMap globalNamedPrimitives contract.contractGlobals

validateGlobal :: GlobalIR -> [ContractDiagnostic]
validateGlobal global =
    concatMap validateGlobalPrimitive global.globalPrimitives

validateSurface :: SurfaceIR -> [ContractDiagnostic]
validateSurface surface =
    duplicateDiagnostics ("surface-primitive-collision:" <> surface.surfaceName) ("surface primitive in " <> surface.surfaceName) (surfacePrimitiveNames surface)
        <> concatMap validateSurfacePrimitive surface.surfacePrimitives

validateGlobalPrimitive :: GlobalPrimitiveIR -> [ContractDiagnostic]
validateGlobalPrimitive = \case
    GlobalSchemaIR schema -> validateSchema schema
    GlobalEventIR _ _ fields -> validateFieldNames fields
    GlobalDomIdIR _ _ -> []
    GlobalDomAttrIR _ _ -> []
    GlobalDomValueIR _ _ -> []
    GlobalFieldNameIR _ _ -> []
    GlobalDomTokenIR _ _ -> []
    GlobalAppShellActionIR action -> validateFieldNames action.appShellActionFields

validateSurfacePrimitive :: SurfacePrimitiveIR -> [ContractDiagnostic]
validateSurfacePrimitive = \case
    SurfaceSchemaIR schema -> validateSchema schema
    SurfaceScopeIR _ _ fields -> validateFieldNames fields
    SurfaceFragmentIR _ _ fields -> validateFieldNames fields
    SurfaceActionIR _ _ fields _ -> validateFieldNames fields
    SurfaceIntentIR _ _ fields -> validateFieldNames fields
    SurfaceMountStateIR _ _ fields -> validateFieldNames fields
    SurfaceDtoIR _ _ fields -> validateFieldNames fields

validateSchema :: SchemaIR -> [ContractDiagnostic]
validateSchema = \case
    RecordIR _ _ fields -> validateFieldNames fields
    EnumIR _ _ values -> duplicateDiagnostics "enum-value-collision" "enum value" [(value, value) | value <- values]
    LiteralEnumIR _ _ values -> duplicateDiagnostics "literal-enum-value-collision" "literal enum value" [(value, marker) | (marker, value) <- values]
    TaggedUnionIR _ _ _ cases ->
        duplicateDiagnostics "union-case-collision" "union case" [(unionCaseTag c, unionCaseMarker c) | c <- cases]
            <> concatMap (validateFieldNames . unionCaseFields) cases

validateFieldNames :: [FieldIR] -> [ContractDiagnostic]
validateFieldNames fields =
    duplicateDiagnostics "field-name-collision" "field" [(field.fieldName, field.fieldMarker) | field <- fields]

duplicateDiagnostics :: Text -> Text -> [(Text, Text)] -> [ContractDiagnostic]
duplicateDiagnostics code label entries =
    entries
        |> List.sortOn fst
        |> List.groupBy (\a b -> fst a == fst b)
        |> mapMaybe toDiagnostic
    where
        toDiagnostic group =
            case group of
                [] -> Nothing
                ((name, _) : _) ->
                    let markers = List.nub (fmap snd group)
                     in if length markers > 1 || length group > 1
                            then Just ContractDiagnostic
                                { diagnosticCode = code
                                , diagnosticMessage = "Duplicate " <> label <> " name " <> name <> " from " <> Text.intercalate ", " markers
                                }
                            else Nothing

unresolvedReferenceDiagnostics :: Set.Set Text -> [Text] -> [ContractDiagnostic]
unresolvedReferenceDiagnostics declared refs =
    refs
        |> List.nub
        |> filter (not . (`Set.member` declared))
        |> fmap (\name -> ContractDiagnostic "unresolved-ref" ("Unresolved frontend contract ref " <> name))

globalSchemas :: GlobalIR -> [(Text, Text)]
globalSchemas global =
    [schemaNameAndMarker schema | GlobalSchemaIR schema <- global.globalPrimitives]

surfaceSchemas :: SurfaceIR -> [(Text, Text)]
surfaceSchemas surface =
    [schemaNameAndMarker schema | SurfaceSchemaIR schema <- surface.surfacePrimitives]

surfaceDtoNames :: SurfaceIR -> [(Text, Text)]
surfaceDtoNames surface =
    [(name, marker) | SurfaceDtoIR marker name _ <- surface.surfacePrimitives]

schemaNameAndMarker :: SchemaIR -> (Text, Text)
schemaNameAndMarker = \case
    RecordIR marker name _ -> (name, marker)
    EnumIR marker name _ -> (name, marker)
    LiteralEnumIR marker name _ -> (name, marker)
    TaggedUnionIR marker name _ _ -> (name, marker)

globalNamedPrimitives :: GlobalIR -> [(Text, Text)]
globalNamedPrimitives global =
    [ (name, marker)
    | primitive <- global.globalPrimitives
    , (marker, name) <- case primitive of
        GlobalSchemaIR _              -> []
        GlobalEventIR marker name _   -> [(marker, name)]
        GlobalDomIdIR marker name     -> [(marker, name)]
        GlobalDomAttrIR marker name   -> [(marker, name)]
        GlobalDomValueIR marker name  -> [(marker, name)]
        GlobalFieldNameIR marker name -> [(marker, name)]
        GlobalDomTokenIR marker name  -> [(marker, name)]
        GlobalAppShellActionIR action -> [(action.appShellActionMarker, "app-shell-action:" <> action.appShellActionName)]
    ]

surfacePrimitiveNames :: SurfaceIR -> [(Text, Text)]
surfacePrimitiveNames surface =
    [ (kind <> ":" <> name, marker)
    | primitive <- surface.surfacePrimitives
    , (kind, marker, name) <- case primitive of
        SurfaceSchemaIR _                 -> []
        SurfaceScopeIR marker name _      -> [("scope", marker, name)]
        SurfaceFragmentIR marker name _   -> [("fragment", marker, name)]
        SurfaceActionIR marker name _ _   -> [("action", marker, name)]
        SurfaceIntentIR marker name _     -> [("intent", marker, name)]
        SurfaceMountStateIR marker name _ -> [("mount-state", marker, name)]
        SurfaceDtoIR marker name _        -> [("dto", marker, name)]
    ]

globalRefs :: GlobalIR -> [Text]
globalRefs global = concatMap globalPrimitiveRefs global.globalPrimitives

surfaceRefs :: SurfaceIR -> [Text]
surfaceRefs surface = concatMap surfacePrimitiveRefs surface.surfacePrimitives

globalPrimitiveRefs :: GlobalPrimitiveIR -> [Text]
globalPrimitiveRefs = \case
    GlobalSchemaIR schema -> schemaRefs schema
    GlobalEventIR _ _ fields -> fieldRefs fields
    GlobalDomIdIR _ _ -> []
    GlobalDomAttrIR _ _ -> []
    GlobalDomValueIR _ _ -> []
    GlobalFieldNameIR _ _ -> []
    GlobalDomTokenIR _ _ -> []
    GlobalAppShellActionIR action -> fieldRefs action.appShellActionFields

surfacePrimitiveRefs :: SurfacePrimitiveIR -> [Text]
surfacePrimitiveRefs = \case
    SurfaceSchemaIR schema -> schemaRefs schema
    SurfaceScopeIR _ _ fields -> fieldRefs fields
    SurfaceFragmentIR _ _ fields -> fieldRefs fields
    SurfaceActionIR _ _ fields _ -> fieldRefs fields
    SurfaceIntentIR _ _ fields -> fieldRefs fields
    SurfaceMountStateIR _ _ fields -> fieldRefs fields
    SurfaceDtoIR _ _ fields -> fieldRefs fields

schemaRefs :: SchemaIR -> [Text]
schemaRefs = \case
    RecordIR _ _ fields -> fieldRefs fields
    EnumIR _ _ _ -> []
    LiteralEnumIR _ _ _ -> []
    TaggedUnionIR _ _ _ cases -> concatMap (fieldRefs . unionCaseFields) cases

fieldRefs :: [FieldIR] -> [Text]
fieldRefs fields = concatMap (wireRefs . fieldWire) fields

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
    WireSurfaceWireFragmentIR -> []
