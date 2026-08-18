{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE OverloadedRecordDot #-}

-- | One checked implementation for generated Surface Action and Intent
-- request adapters. Kind-indexed declaration selection and output layouts keep
-- the two nominal lanes distinct; shared inventory resolution, builders,
-- metadata, parsers, imports, and source rendering live behind this interface.
module Application.Helper.FrontendContract.Surface.HaskellAdapter.Request
    ( SurfaceRequestAdapterDeclaration
    , checkedSurfaceActionAdapterDeclarations
    , checkedSurfaceIntentAdapterDeclarations
    , generateSurfaceActionAdapterModules
    , generateSurfaceActionAuthorityProofModules
    , generateSurfaceIntentAuthorityProofModules
    , generateSurfaceIntentAdapterModules
    , renderSurfaceActionAdapterModules
    , renderSurfaceIntentAdapterModules
    ) where

import Application.Helper.FrontendContract.Naming (wordsFromTypeName)
import Application.Helper.FrontendContract.Surface.ContractIR
import Application.Helper.FrontendContract.Surface.HaskellAdapter.Core
import Application.Helper.FrontendContract.Surface.HaskellAdapter.Family
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import qualified Data.Text as Text
import IHP.Prelude

-- | The only payload admitted to generated request lanes. The kind index on
-- 'ResolvedAdapter' retains Action/Intent identity; this payload only carries
-- the declaration-complete operation inventory needed by shared rendering.
data SurfaceRequestAdapterDeclaration = SurfaceRequestAdapterDeclaration
    { surfaceRequestDeclarationOperations   :: !SurfaceRequestAdapterOperations
    , surfaceRequestDeclarationEvidenceMode :: !SurfaceRequestAdapterEvidenceMode
    , surfaceRequestDeclarationAction       :: !(Maybe HtmxActionIR)
    , surfaceRequestDeclarationIntent       :: !(Maybe IntentIR)
    }
    deriving (Eq, Show)

checkedSurfaceActionAdapterDeclarations ::
    SurfaceContractIR ->
    Either [ContractDiagnostic] [CheckedAdapterDeclaration 'ActionAdapterKind HtmxActionIR]
checkedSurfaceActionAdapterDeclarations contract =
    checkedRequestDeclarations
        contract
        [ checkedActionAdapterDeclaration surface action
        | surface <- contract.contractSurfaces
        , action <- surface.surfaceHtmxActions
        ]

checkedSurfaceIntentAdapterDeclarations ::
    SurfaceContractIR ->
    Either [ContractDiagnostic] [CheckedAdapterDeclaration 'IntentAdapterKind IntentIR]
checkedSurfaceIntentAdapterDeclarations contract =
    checkedRequestDeclarations
        contract
        [ checkedIntentAdapterDeclaration surface intent
        | surface <- contract.contractSurfaces
        , intent <- surface.surfaceIntents
        ]

checkedRequestDeclarations ::
    SurfaceContractIR ->
    [CheckedAdapterDeclaration kind payload] ->
    Either [ContractDiagnostic] [CheckedAdapterDeclaration kind payload]
checkedRequestDeclarations contract declarations =
    case stableDiagnostics (validateSurfaceContractIR contract) of
        []          -> Right declarations
        diagnostics -> Left diagnostics

generateSurfaceActionAdapterModules ::
    SurfaceContractIR ->
    SurfaceAdapterRegistry ->
    Either [ContractDiagnostic] [GeneratedHaskellModule]
generateSurfaceActionAdapterModules contract registry = do
    declarations <- checkedSurfaceActionAdapterDeclarations contract
    adapters <-
        resolveGeneratedRequestAdapters
            actionRequestRenderer
            (\action -> (Just action, Nothing))
            contract
            registry.surfaceAdapterFamilies
            declarations
            registry.surfaceActionAdapterRegistrations
    renderSurfaceActionAdapterModules adapters

-- | Emit verification-only aggregate proofs for operation-local Action
-- families. The script typechecks these modules in its temporary tree but never
-- publishes them into the application source set.
generateSurfaceActionAuthorityProofModules ::
    SurfaceContractIR ->
    SurfaceAdapterRegistry ->
    Either [ContractDiagnostic] [GeneratedHaskellModule]
generateSurfaceActionAuthorityProofModules contract registry = do
    declarations <- checkedSurfaceActionAdapterDeclarations contract
    inventory <-
        resolveSurfaceRequestAdapterRegistrations
            actionAdapterLayout
            contract
            registry.surfaceAdapterFamilies
            declarations
            registry.surfaceActionAdapterRegistrations
    let orderedInventory =
            [ registration
            | declaration <- declarations
            , registration <- inventory
            , registration.checkedSurfaceRequestAdapter.resolvedAdapterDeclaration.checkedAdapterIdentity
                == declaration.checkedAdapterIdentity
            ]
    pure (renderActionAuthorityProofModules orderedInventory)

generateSurfaceIntentAuthorityProofModules ::
    SurfaceContractIR ->
    SurfaceAdapterRegistry ->
    Either [ContractDiagnostic] [GeneratedHaskellModule]
generateSurfaceIntentAuthorityProofModules contract registry = do
    declarations <- checkedSurfaceIntentAdapterDeclarations contract
    inventory <-
        resolveSurfaceRequestAdapterRegistrations
            intentAdapterLayout
            contract
            registry.surfaceAdapterFamilies
            declarations
            registry.surfaceIntentAdapterRegistrations
    let orderedInventory =
            [ registration
            | declaration <- declarations
            , registration <- inventory
            , registration.checkedSurfaceRequestAdapter.resolvedAdapterDeclaration.checkedAdapterIdentity
                == declaration.checkedAdapterIdentity
            ]
    pure (renderIntentAuthorityProofModules orderedInventory)

generateSurfaceIntentAdapterModules ::
    SurfaceContractIR ->
    SurfaceAdapterRegistry ->
    Either [ContractDiagnostic] [GeneratedHaskellModule]
generateSurfaceIntentAdapterModules contract registry = do
    declarations <- checkedSurfaceIntentAdapterDeclarations contract
    adapters <-
        resolveGeneratedRequestAdapters
            intentRequestRenderer
            (\intent -> (Nothing, Just intent))
            contract
            registry.surfaceAdapterFamilies
            declarations
            registry.surfaceIntentAdapterRegistrations
    renderSurfaceIntentAdapterModules adapters

resolveGeneratedRequestAdapters ::
    RequestAdapterRenderer kind ->
    (payload -> (Maybe HtmxActionIR, Maybe IntentIR)) ->
    SurfaceContractIR ->
    [SurfaceAdapterFamilyMetadata] ->
    [CheckedAdapterDeclaration kind payload] ->
    [SurfaceRequestAdapterRegistration kind] ->
    Either [ContractDiagnostic] [ResolvedAdapter kind SurfaceRequestAdapterDeclaration]
resolveGeneratedRequestAdapters renderer actionOf contract families declarations registrations = do
    inventory <-
        resolveSurfaceRequestAdapterRegistrations
            renderer.requestAdapterLayout
            contract
            families
            declarations
            registrations
    pure
        [ prepareResolvedAdapter
            (\payload ->
                let (surfaceRequestDeclarationAction, surfaceRequestDeclarationIntent) = actionOf payload
                in SurfaceRequestAdapterDeclaration
                    { surfaceRequestDeclarationOperations = operations
                    , surfaceRequestDeclarationEvidenceMode = registration.checkedSurfaceRequestAdapterEvidenceMode
                    , surfaceRequestDeclarationAction
                    , surfaceRequestDeclarationIntent
                    }
            )
            (requestGeneratedNames renderer)
            registration.checkedSurfaceRequestAdapter
        | registration <- inventory
        , Just operations <- [registration.checkedSurfaceRequestAdapterOperations]
        ]

renderSurfaceActionAdapterModules ::
    [ResolvedAdapter 'ActionAdapterKind SurfaceRequestAdapterDeclaration] ->
    Either [ContractDiagnostic] [GeneratedHaskellModule]
renderSurfaceActionAdapterModules = renderSurfaceRequestAdapterModules actionRequestRenderer

renderSurfaceIntentAdapterModules ::
    [ResolvedAdapter 'IntentAdapterKind SurfaceRequestAdapterDeclaration] ->
    Either [ContractDiagnostic] [GeneratedHaskellModule]
renderSurfaceIntentAdapterModules = renderSurfaceRequestAdapterModules intentRequestRenderer

data RequestAdapterRenderer kind = RequestAdapterRenderer
    { requestAdapterLayout             :: !(AdapterModuleLayout kind)
    , requestAdapterLanguagePragmas    :: ![Text]
    , requestAdapterBaseName           :: !(Text -> Text)
    , requestAdapterMetadataSuffix     :: !Text
    , requestAdapterFieldsType         :: !Text
    , requestAdapterBindFields         :: !Text
    , requestAdapterEmptyFields        :: !Text
    , requestAdapterMetadataImports    :: ![Text]
    , requestAdapterOperationLocalMetadataImports :: ![Text]
    , requestAdapterMetadataResultType :: !Text
    , requestAdapterMetadataBuilder    :: !Text
    , requestAdapterParser             :: !Text
    , requestAdapterOperationPrefix    :: !Text
    , requestAdapterOperationFields    :: !Text
    , requestAdapterOperationFieldSpecs :: !Text
    , requestAdapterOperationSurface   :: !Text
    , requestAdapterOperationMarker    :: !Text
    , requestAdapterOperationEmpty     :: !Text
    , requestAdapterOperationBind      :: !Text
    , requestAdapterOperationPresent   :: !Text
    }

actionRequestRenderer :: RequestAdapterRenderer 'ActionAdapterKind
actionRequestRenderer =
    RequestAdapterRenderer
        { requestAdapterLayout = actionAdapterLayout
        , requestAdapterLanguagePragmas =
            [ "{-# LANGUAGE ImplicitParams   #-}"
            , "{-# LANGUAGE TypeApplications #-}"
            ]
        , requestAdapterBaseName = requestBaseName "action"
        , requestAdapterMetadataSuffix = ""
        , requestAdapterFieldsType = "SurfaceActionFields"
        , requestAdapterBindFields = "surfaceActionFields"
        , requestAdapterEmptyFields = "noSurfaceActionFields"
        , requestAdapterMetadataImports = ["FrontendSurfaceAction", "frontendSurfaceAction"]
        , requestAdapterOperationLocalMetadataImports = ["FrontendSurfaceAction"]
        , requestAdapterMetadataResultType = "FrontendSurfaceAction"
        , requestAdapterMetadataBuilder = "frontendSurfaceAction"
        , requestAdapterParser = "parseSurfaceActionParams"
        , requestAdapterOperationPrefix = "Action"
        , requestAdapterOperationFields = "ActionFields"
        , requestAdapterOperationFieldSpecs = "ActionFieldSpecs"
        , requestAdapterOperationSurface = "ActionSurface"
        , requestAdapterOperationMarker = "ActionMarker"
        , requestAdapterOperationEmpty = "noActionFields"
        , requestAdapterOperationBind = "actionFields"
        , requestAdapterOperationPresent = "actionParamsPresent"
        }

intentRequestRenderer :: RequestAdapterRenderer 'IntentAdapterKind
intentRequestRenderer =
    RequestAdapterRenderer
        { requestAdapterLayout = intentAdapterLayout
        , requestAdapterLanguagePragmas =
            [ "{-# LANGUAGE ImplicitParams   #-}"
            , "{-# LANGUAGE TypeApplications #-}"
            ]
        , requestAdapterBaseName = requestBaseName "intent"
        , requestAdapterMetadataSuffix = "Form"
        , requestAdapterFieldsType = "SurfaceIntentFields"
        , requestAdapterBindFields = "surfaceIntentFields"
        , requestAdapterEmptyFields = "noSurfaceIntentFields"
        , requestAdapterMetadataImports =
            [ "FrontendSurfaceHtmxRequest"
            , "FrontendSurfaceIntentForm"
            , "frontendSurfaceIntentForm"
            ]
        , requestAdapterOperationLocalMetadataImports =
            [ "FrontendSurfaceHtmxRequest"
            , "FrontendSurfaceIntentForm"
            ]
        , requestAdapterMetadataResultType = "FrontendSurfaceHtmxRequest -> FrontendSurfaceIntentForm"
        , requestAdapterMetadataBuilder = "frontendSurfaceIntentForm"
        , requestAdapterParser = "parseSurfaceIntentParams"
        , requestAdapterOperationPrefix = "Intent"
        , requestAdapterOperationFields = "IntentFields"
        , requestAdapterOperationFieldSpecs = "IntentFieldSpecs"
        , requestAdapterOperationSurface = "IntentSurface"
        , requestAdapterOperationMarker = "IntentMarker"
        , requestAdapterOperationEmpty = "noIntentFields"
        , requestAdapterOperationBind = "intentFields"
        , requestAdapterOperationPresent = "intentParamsPresent"
        }

requestGeneratedNames ::
    RequestAdapterRenderer kind ->
    CheckedAdapterDeclaration kind SurfaceRequestAdapterDeclaration ->
    [Text]
requestGeneratedNames renderer declaration =
    operationTokenExport
        <> concat
            [ operationName operations.surfaceAdapterFieldsBuilderOperation (baseName <> "Fields")
            , operationName operations.surfaceAdapterRenderMetadataOperation (baseName <> renderer.requestAdapterMetadataSuffix)
            , operationName operations.surfaceAdapterParamsPresentOperation (baseName <> "ParamsPresent")
            , operationName operations.surfaceAdapterRequestParserOperation ("parse" <> upperFirst baseName <> "Params")
            ]
  where
    payload = declaration.checkedAdapterPayload
    operations = payload.surfaceRequestDeclarationOperations
    baseName = renderer.requestAdapterBaseName declaration.checkedAdapterDeclarationMarker
    operationTokenExport =
        [ upperFirst baseName <> "Operation"
        | payload.surfaceRequestDeclarationEvidenceMode == OperationLocalRequestEvidence
        ]
    operationName eligibility name = [name | surfaceAdapterOperationIsGenerated eligibility]

renderSurfaceRequestAdapterModules ::
    RequestAdapterRenderer kind ->
    [ResolvedAdapter kind SurfaceRequestAdapterDeclaration] ->
    Either [ContractDiagnostic] [GeneratedHaskellModule]
renderSurfaceRequestAdapterModules renderer adapters =
    renderGeneratedAdapterModules
        (requestModuleRenderer renderer)
        (map (toRenderableAdapter id) adapters)

requestModuleRenderer :: RequestAdapterRenderer kind -> AdapterModuleRenderer SurfaceRequestAdapterDeclaration
requestModuleRenderer renderer =
    AdapterModuleRenderer
        { adapterRendererLanguagePragmas = \adapters ->
            if any isOperationLocalAdapter adapters
                then
                    [ "{-# LANGUAGE DataKinds         #-}"
                    , "{-# LANGUAGE ImplicitParams    #-}"
                    , "{-# LANGUAGE OverloadedStrings #-}"
                    , "{-# LANGUAGE TypeApplications  #-}"
                    , "{-# LANGUAGE TypeFamilies      #-}"
                    ]
                else renderer.requestAdapterLanguagePragmas
        , adapterRendererHeaderLines =
            [ "-- @generated by Application.Helper.FrontendContract.Surface.HaskellAdapter.Generator"
            , "-- Do not edit; run `bash ./bin/in-env frontend-surface-adapters`."
            ]
        , adapterRendererImports = renderRequestImports renderer
        , adapterRendererDeclaration = renderRequestAdapter renderer
        }

renderRequestImports ::
    RequestAdapterRenderer kind ->
    Map.Map Text Text ->
    [RenderableAdapter SurfaceRequestAdapterDeclaration] ->
    [Text]
renderRequestImports renderer aliases adapters =
    conditionalImports (hasWholeSurface || hasOperationLocal)
        ( renderImportList
            "Application.Helper.FrontendContract.Surface.HaskellAdapter.Association"
            ( ["AdapterFamilySurface"]
                <> ["AdapterSurfaceMarker" | hasOperationLocal]
            )
        )
        <> conditionalImports hasParser
            ( renderImportList
                "Application.Helper.FrontendContract.Surface.Request"
                ( ["SurfaceRequestFieldError"]
                    <> [renderer.requestAdapterParser | hasWholeSurfaceParser]
                    <> ["parse" <> renderer.requestAdapterOperationPrefix <> "Params" | hasOperationLocalParser]
                    <> [renderer.requestAdapterOperationPresent | hasOperationLocalPresence]
                )
            )
        <> conditionalImports hasMetadata
            ( renderImportList
                "Application.Helper.FrontendContract.Surface.Request.Runtime"
                ( if hasOperationLocalMetadata
                    then renderer.requestAdapterOperationLocalMetadataImports
                    else if hasWholeSurfaceMetadata then renderer.requestAdapterMetadataImports else []
                )
            )
        <> conditionalImports hasOperationLocalMetadata
            ( renderImportList
                "Application.Helper.FrontendContract.Surface.Request.Runtime.Internal"
                ( if renderer.requestAdapterOperationPrefix == "Action"
                    then ["ActionEvidence", "actionEvidence", "frontendSurfaceActionFromEvidence"]
                    else ["IntentEvidence", "intentEvidence", "frontendSurfaceIntentFormFromEvidence"]
                )
            )
        <> conditionalImports hasOperationLocal
            ["import qualified Application.Helper.FrontendContract.Surface.ContractIR as SurfaceIR"]
        <> conditionalImports hasOperationLocal
            ( renderImportList
                "Application.Helper.FrontendContract.Surface.DSL"
                ["FieldSpec (..)", "WireType (..)"]
            )
        <> renderImportList
            "Application.Helper.FrontendContract.Surface.Values"
            valueImports
        <> conditionalImports needsDay ["import Data.Time (Day)"]
        <> conditionalImports needsUuid ["import qualified Data.UUID as UUID"]
        <> ["import IHP.Prelude"]
        <> conditionalImports hasParser ["import Network.Wai (Request)"]
        <> [ "import qualified " <> sourceModule <> " as " <> alias
           | (sourceModule, alias) <- Map.toAscList usedAliases
           ]
  where
    operationsOf = (.surfaceRequestDeclarationOperations) . (.renderableAdapterPayload)
    isOperationLocal adapter =
        adapter.renderableAdapterPayload.surfaceRequestDeclarationEvidenceMode == OperationLocalRequestEvidence
    hasOperationLocal = any isOperationLocal adapters
    hasWholeSurface = not (all isOperationLocal adapters)
    builderAdapters = filter (hasGeneratedOperation (.surfaceAdapterFieldsBuilderOperation)) adapters
    emptyBuilderAdapters = filter (null . (.renderableAdapterFields)) builderAdapters
    nonEmptyBuilderAdapters = filter (not . null . (.renderableAdapterFields)) builderAdapters
    builderFields = concatMap (.renderableAdapterFields) builderAdapters
    parserAdapters = filter (hasGeneratedOperation (.surfaceAdapterRequestParserOperation)) adapters
    metadataAdapters = filter (hasGeneratedOperation (.surfaceAdapterRenderMetadataOperation)) adapters
    hasMetadata = not (null metadataAdapters)
    hasParser = not (null parserAdapters)
    hasOperationLocalParser = any isOperationLocal parserAdapters
    hasWholeSurfaceParser = not (all isOperationLocal parserAdapters)
    presentAdapters = filter (hasGeneratedOperation (.surfaceAdapterParamsPresentOperation)) adapters
    hasOperationLocalPresence = any isOperationLocal presentAdapters
    hasOperationLocalMetadata = any isOperationLocal metadataAdapters
    hasWholeSurfaceMetadata = not (all isOperationLocal metadataAdapters)
    valueImports =
        List.sort
            ( List.nub
                ( [renderer.requestAdapterFieldsType | hasWholeSurface]
                    <> (if hasOperationLocal then
                        [ renderer.requestAdapterOperationFieldSpecs
                        , renderer.requestAdapterOperationFields
                        , renderer.requestAdapterOperationMarker
                        , renderer.requestAdapterOperationSurface
                        ] else [])
                    <> [renderer.requestAdapterEmptyFields | not (null emptyBuilderAdapters) && hasWholeSurface]
                    <> [renderer.requestAdapterOperationEmpty | any (\adapter -> isOperationLocal adapter && null adapter.renderableAdapterFields) builderAdapters]
                    <> (if null nonEmptyBuilderAdapters then [] else ["noSurfaceFields"])
                    <> [renderer.requestAdapterBindFields | not (all isOperationLocal nonEmptyBuilderAdapters)]
                    <> [renderer.requestAdapterOperationBind | any isOperationLocal nonEmptyBuilderAdapters]
                    <> ["surfaceField" | any ((== RequiredField) . (.fieldPresence) . (.resolvedAdapterFieldIR)) builderFields]
                    <> ["surfaceNullableField" | any ((== NullableFieldPresence) . (.fieldPresence) . (.resolvedAdapterFieldIR)) builderFields]
                    <> ["surfaceOptionalField" | any ((== OptionalFieldPresence) . (.fieldPresence) . (.resolvedAdapterFieldIR)) builderFields]
                )
            )
            <> ["(&:)" | any ((> 1) . length . (.renderableAdapterFields)) nonEmptyBuilderAdapters]
    builderTypes = concatMap (map (.resolvedAdapterFieldType) . (.renderableAdapterFields)) builderAdapters
    needsDay = any sourceTypeContainsDay builderTypes
    needsUuid = any sourceTypeContainsUuid builderTypes
    -- Operation-local tokens name their compact owner through the nominal
    -- family association, so that family import remains required.
    usedAliases = aliases
    hasGeneratedOperation operation adapter =
        surfaceAdapterOperationIsGenerated (operation (operationsOf adapter))
    conditionalImports True imports = imports
    conditionalImports False _      = []

renderRequestAdapter ::
    RequestAdapterRenderer kind ->
    Map.Map Text Text ->
    RenderableAdapter SurfaceRequestAdapterDeclaration ->
    [Text]
renderRequestAdapter renderer aliases adapter =
    operationLocalDeclaration
        <> ["" | not (null operationLocalDeclaration) && not (null generatedOperations)]
        <> generatedOperations
  where
    payload = adapter.renderableAdapterPayload
    operations = payload.surfaceRequestDeclarationOperations
    operationLocalDeclaration =
        [ renderOperationToken renderer aliases adapter
        | payload.surfaceRequestDeclarationEvidenceMode == OperationLocalRequestEvidence
        ]
            |> concat
    generatedOperations =
        operationBlocks
            [ ( operations.surfaceAdapterFieldsBuilderOperation
              , renderFieldsBuilder renderer aliases adapter
              )
            , ( operations.surfaceAdapterRenderMetadataOperation
              , renderMetadata renderer aliases adapter
              )
            , ( operations.surfaceAdapterParamsPresentOperation
              , renderParamsPresent renderer adapter
              )
            , ( operations.surfaceAdapterRequestParserOperation
              , renderParser renderer aliases adapter
              )
            ]

operationBlocks :: [(SurfaceAdapterOperationEligibility, [Text])] -> [Text]
operationBlocks operations =
    operations
        |> mapMaybe generatedBlock
        |> List.intercalate [""]
  where
    generatedBlock (eligibility, block)
        | surfaceAdapterOperationIsGenerated eligibility = Just block
        | otherwise = Nothing

renderFieldsBuilder ::
    RequestAdapterRenderer kind ->
    Map.Map Text Text ->
    RenderableAdapter SurfaceRequestAdapterDeclaration ->
    [Text]
renderFieldsBuilder renderer aliases adapter = signature <> body
  where
    name = fieldsName renderer adapter
    resultType = requestFieldsType renderer aliases adapter
    signature =
        case adapter.renderableAdapterFields of
            [] -> [name <> " :: " <> resultType]
            fields ->
                [name <> " ::"]
                    <> map ("    " <>)
                        ( map ((<> " ->") . renderHaskellSourceType aliases . (.resolvedAdapterFieldType)) fields
                            <> [resultType]
                        )
    body =
        case adapter.renderableAdapterFields of
            [] -> [name <> " =", "    " <> emptyFieldsBuilder]
            first : rest ->
                [ name <> renderAdapterArguments adapter.renderableAdapterFields <> " ="
                , "    " <> bindFieldsBuilder
                , "        (" <> renderAdapterFieldBuilder aliases first <> ")"
                ]
                    <> renderAdapterFieldsExpression aliases rest
    operationLocal = isOperationLocalAdapter adapter
    emptyFieldsBuilder = if operationLocal then renderer.requestAdapterOperationEmpty else renderer.requestAdapterEmptyFields
    bindFieldsBuilder = if operationLocal then renderer.requestAdapterOperationBind else renderer.requestAdapterBindFields

renderMetadata ::
    RequestAdapterRenderer kind ->
    Map.Map Text Text ->
    RenderableAdapter SurfaceRequestAdapterDeclaration ->
    [Text]
renderMetadata renderer aliases adapter
    | isOperationLocalAdapter adapter = renderOperationLocalMetadata renderer adapter
    | otherwise =
        [ metadataName renderer adapter <> " :: " <> requestFieldsType renderer aliases adapter
            <> " -> " <> renderer.requestAdapterMetadataResultType
        , metadataName renderer adapter <> " ="
        , "    " <> renderer.requestAdapterMetadataBuilder
        , "        @(AdapterFamilySurface " <> qualifyHaskellType aliases adapter.renderableAdapterHomeFamily <> ")"
        , "        @" <> qualifyHaskellType aliases adapter.renderableAdapterHomeDeclaration
        ]

renderParser ::
    RequestAdapterRenderer kind ->
    Map.Map Text Text ->
    RenderableAdapter SurfaceRequestAdapterDeclaration ->
    [Text]
renderParamsPresent ::
    RequestAdapterRenderer kind ->
    RenderableAdapter SurfaceRequestAdapterDeclaration ->
    [Text]
renderParamsPresent renderer adapter =
    [ paramsPresentName renderer adapter <> " ::"
    , "    (?request :: Request) =>"
    , "    Bool"
    , paramsPresentName renderer adapter <> " ="
    , "    " <> renderer.requestAdapterOperationPresent
    , "        @" <> operationTokenName renderer adapter
    ]

renderParser renderer aliases adapter
    | isOperationLocalAdapter adapter =
        [ parserName renderer adapter <> " ::"
        , "    (?request :: Request) =>"
        , "    Either [SurfaceRequestFieldError] (" <> requestFieldsType renderer aliases adapter <> ")"
        , parserName renderer adapter <> " ="
        , "    parse" <> renderer.requestAdapterOperationPrefix <> "Params"
        , "        @" <> operationTokenName renderer adapter
        ]
    | otherwise =
        [ parserName renderer adapter <> " ::"
        , "    (?request :: Request) =>"
        , "    Either [SurfaceRequestFieldError] (" <> requestFieldsType renderer aliases adapter <> ")"
        , parserName renderer adapter <> " ="
        , "    " <> renderer.requestAdapterParser
        , "        @(AdapterFamilySurface " <> qualifyHaskellType aliases adapter.renderableAdapterHomeFamily <> ")"
        , "        @" <> qualifyHaskellType aliases adapter.renderableAdapterHomeDeclaration
        ]

requestFieldsType ::
    RequestAdapterRenderer kind ->
    Map.Map Text Text ->
    RenderableAdapter SurfaceRequestAdapterDeclaration ->
    Text
requestFieldsType renderer aliases adapter
    | isOperationLocalAdapter adapter =
        renderer.requestAdapterOperationFields <> " " <> operationTokenName renderer adapter
    | otherwise =
        renderer.requestAdapterFieldsType <> " (AdapterFamilySurface "
            <> qualifyHaskellType aliases adapter.renderableAdapterHomeFamily
            <> ") "
            <> qualifyHaskellType aliases adapter.renderableAdapterHomeDeclaration

renderOperationToken ::
    RequestAdapterRenderer kind ->
    Map.Map Text Text ->
    RenderableAdapter SurfaceRequestAdapterDeclaration ->
    [Text]
renderOperationToken renderer aliases adapter =
    [ "data " <> token
    , ""
    , "type instance " <> renderer.requestAdapterOperationSurface <> " " <> token <> " = AdapterSurfaceMarker (AdapterFamilySurface "
        <> qualifyHaskellType aliases adapter.renderableAdapterHomeFamily <> ")"
    , "type instance " <> renderer.requestAdapterOperationMarker <> " " <> token <> " = "
        <> qualifyHaskellType aliases adapter.renderableAdapterHomeDeclaration
    , "type instance " <> renderer.requestAdapterOperationFieldSpecs <> " " <> token <> " ="
    ]
        <> renderPromotedFieldList aliases adapter.renderableAdapterFields
  where
    token = operationTokenName renderer adapter

renderPromotedFieldList :: Map.Map Text Text -> [ResolvedAdapterField] -> [Text]
renderPromotedFieldList _ [] = ["    '[]"]
renderPromotedFieldList aliases (first : rest) =
    ["    '[ " <> renderPromotedField aliases first]
        <> map (("     , " <>) . renderPromotedField aliases) rest
        <> ["     ]"]

renderPromotedField :: Map.Map Text Text -> ResolvedAdapterField -> Text
renderPromotedField aliases field =
    "'" <> presenceConstructor <> " "
        <> qualifyHaskellType aliases field.resolvedAdapterFieldMarker <> " "
        <> renderPromotedWire aliases field.resolvedAdapterFieldIR.fieldWire
  where
    presenceConstructor = case field.resolvedAdapterFieldIR.fieldPresence of
        RequiredField         -> "Field"
        OptionalFieldPresence -> "OptionalField"
        NullableFieldPresence -> "NullableField"

renderPromotedWire :: Map.Map Text Text -> WireIR -> Text
renderPromotedWire aliases = \case
    WireTextIR -> "'WireText"
    WireIntIR -> "'WireInt"
    WireBoolIR -> "'WireBool"
    WireUuidIR -> "'WireUUID"
    WireDayIR -> "'WireDay"
    WireClosedIR _ sourceModule sourceType ->
        "('WireClosed " <> qualifyHaskellType aliases (HaskellTypeMetadata
            { haskellTypeModule = sourceModule
            , haskellTypeName = sourceType
            }) <> ")"
    WireListIR inner -> "('WireList " <> renderPromotedWire aliases inner <> ")"
    WireOptionalIR inner -> "('WireOptional " <> renderPromotedWire aliases inner <> ")"
    WireNullableIR inner -> "('WireNullable " <> renderPromotedWire aliases inner <> ")"
    WireRefIR marker -> "('WireRef " <> marker <> ")"
    unsupported -> error ("Operation-local Action generator received unsupported wire " <> show unsupported)

renderOperationLocalMetadata ::
    RequestAdapterRenderer kind ->
    RenderableAdapter SurfaceRequestAdapterDeclaration ->
    [Text]
renderOperationLocalMetadata renderer adapter
    | renderer.requestAdapterOperationPrefix == "Action" =
        case payload.surfaceRequestDeclarationAction of
            Nothing -> error "Operation-local Action adapter is missing checked Action metadata"
            Just action ->
                [ evidenceName <> " :: ActionEvidence " <> token
                , evidenceName <> " ="
                , "    actionEvidence (" <> renderHtmxActionIR action <> ")"
                , ""
                , metadataName renderer adapter <> " :: " <> renderer.requestAdapterOperationFields <> " " <> token
                    <> " -> " <> renderer.requestAdapterMetadataResultType
                , metadataName renderer adapter <> " ="
                , "    frontendSurfaceActionFromEvidence " <> evidenceName
                ]
    | otherwise =
        case payload.surfaceRequestDeclarationIntent of
            Nothing -> error "Operation-local Intent adapter is missing checked Intent metadata"
            Just intent ->
                [ evidenceName <> " :: IntentEvidence " <> token
                , evidenceName <> " ="
                , "    intentEvidence (" <> renderIntentIR intent <> ")"
                , ""
                , metadataName renderer adapter <> " :: " <> renderer.requestAdapterOperationFields <> " " <> token
                    <> " -> " <> renderer.requestAdapterMetadataResultType
                , metadataName renderer adapter <> " ="
                , "    frontendSurfaceIntentFormFromEvidence " <> evidenceName
                ]
  where
    payload = adapter.renderableAdapterPayload
    token = operationTokenName renderer adapter
    evidenceName = baseName renderer adapter <> "Evidence"

renderHtmxActionIR :: HtmxActionIR -> Text
renderHtmxActionIR action =
    "SurfaceIR.HtmxActionIR "
        <> renderTextLiteral action.htmxActionMarker <> " "
        <> renderTextLiteral action.htmxActionName <> " "
        <> renderList renderFieldIR action.htmxActionFields <> " "
        <> renderList renderHtmxActionOptionIR (optionHtmxActionOptions action.htmxActionOptions)

renderIntentIR :: IntentIR -> Text
renderIntentIR intent =
    "SurfaceIR.IntentIR "
        <> renderTextLiteral intent.intentMarker <> " "
        <> renderTextLiteral intent.intentName <> " "
        <> renderList renderFieldIR intent.intentFields <> " "
        <> renderList renderHtmxActionOptionIR (optionHtmxActionOptions intent.intentOptions)

renderFieldIR :: FieldIR -> Text
renderFieldIR field =
    "SurfaceIR.FieldIR "
        <> renderTextLiteral field.fieldMarker <> " "
        <> renderTextLiteral field.fieldName <> " ("
        <> renderWireIR field.fieldWire <> ") "
        <> renderFieldPresence field.fieldPresence

renderWireIR :: WireIR -> Text
renderWireIR = \case
    WireTextIR -> "SurfaceIR.WireTextIR"
    WireIntIR -> "SurfaceIR.WireIntIR"
    WireBoolIR -> "SurfaceIR.WireBoolIR"
    WireUuidIR -> "SurfaceIR.WireUuidIR"
    WireDayIR -> "SurfaceIR.WireDayIR"
    WireClosedIR schema sourceModule sourceType ->
        "SurfaceIR.WireClosedIR " <> renderTextLiteral schema <> " "
            <> renderTextLiteral sourceModule <> " " <> renderTextLiteral sourceType
    WireUnknownIR -> "SurfaceIR.WireUnknownIR"
    WireListIR inner -> "SurfaceIR.WireListIR (" <> renderWireIR inner <> ")"
    WireMapIR key value -> "SurfaceIR.WireMapIR (" <> renderWireIR key <> ") (" <> renderWireIR value <> ")"
    WireOptionalIR inner -> "SurfaceIR.WireOptionalIR (" <> renderWireIR inner <> ")"
    WireNullableIR inner -> "SurfaceIR.WireNullableIR (" <> renderWireIR inner <> ")"
    WireRefIR marker -> "SurfaceIR.WireRefIR " <> renderTextLiteral marker
    WireSurfaceScopeIR -> "SurfaceIR.WireSurfaceScopeIR"
    WireSurfaceFragmentKeyIR -> "SurfaceIR.WireSurfaceFragmentKeyIR"

renderFieldPresence :: FieldPresence -> Text
renderFieldPresence = \case
    RequiredField -> "SurfaceIR.RequiredField"
    OptionalFieldPresence -> "SurfaceIR.OptionalFieldPresence"
    NullableFieldPresence -> "SurfaceIR.NullableFieldPresence"

renderHtmxActionOptionIR :: HtmxActionOptionIR -> Text
renderHtmxActionOptionIR option =
    "SurfaceIR.HtmxOption (" <> renderHtmxOptionIR option <> ")"

renderHtmxOptionIR :: HtmxActionOptionIR -> Text
renderHtmxOptionIR = \case
    HtmxActionMethodIR method -> "SurfaceIR.HtmxActionMethodIR " <> renderHtmxMethodIR method
    HtmxActionTriggerIR syntax -> "SurfaceIR.HtmxActionTriggerIR (" <> renderHtmxSyntaxIR syntax <> ")"
    HtmxActionIncludeIR syntax -> "SurfaceIR.HtmxActionIncludeIR (" <> renderHtmxSyntaxIR syntax <> ")"
    HtmxActionSyncIR syntax -> "SurfaceIR.HtmxActionSyncIR (" <> renderHtmxSyntaxIR syntax <> ")"
    HtmxActionIndicatorIR syntax -> "SurfaceIR.HtmxActionIndicatorIR (" <> renderHtmxSyntaxIR syntax <> ")"
    HtmxActionConfirmIR value -> "SurfaceIR.HtmxActionConfirmIR " <> renderTextLiteral value
    HtmxActionSelectIR syntax -> "SurfaceIR.HtmxActionSelectIR (" <> renderHtmxSyntaxIR syntax <> ")"
    HtmxActionTargetIR syntax -> "SurfaceIR.HtmxActionTargetIR (" <> renderHtmxSyntaxIR syntax <> ")"
    HtmxActionSwapIR syntax -> "SurfaceIR.HtmxActionSwapIR (" <> renderHtmxSyntaxIR syntax <> ")"
    HtmxActionPushUrlIR value -> "SurfaceIR.HtmxActionPushUrlIR " <> renderHtmxPushUrlIR value
    HtmxActionCustomHtmxIR marker reason ->
        "SurfaceIR.HtmxActionCustomHtmxIR " <> renderTextLiteral marker <> " " <> renderTextLiteral reason

renderHtmxSyntaxIR :: HtmxSyntaxIR -> Text
renderHtmxSyntaxIR = \case
    HtmxTypedSyntaxIR value references ->
        "SurfaceIR.HtmxTypedSyntaxIR " <> renderTextLiteral value <> " " <> renderTextList references
    HtmxRawSyntaxIR value reason ->
        "SurfaceIR.HtmxRawSyntaxIR " <> renderTextLiteral value <> " " <> renderTextLiteral reason

renderHtmxMethodIR :: HtmxMethodIR -> Text
renderHtmxMethodIR = \case
    HtmxGetIR -> "SurfaceIR.HtmxGetIR"
    HtmxPostIR -> "SurfaceIR.HtmxPostIR"
    HtmxPutIR -> "SurfaceIR.HtmxPutIR"
    HtmxPatchIR -> "SurfaceIR.HtmxPatchIR"
    HtmxDeleteIR -> "SurfaceIR.HtmxDeleteIR"

renderHtmxPushUrlIR :: HtmxPushUrlIR -> Text
renderHtmxPushUrlIR = \case
    HtmxPushUrlTrueIR -> "SurfaceIR.HtmxPushUrlTrueIR"
    HtmxPushUrlFalseIR -> "SurfaceIR.HtmxPushUrlFalseIR"

renderList :: (value -> Text) -> [value] -> Text
renderList renderValue values = "[" <> Text.intercalate ", " (map renderValue values) <> "]"

renderTextList :: [Text] -> Text
renderTextList values = "[" <> Text.intercalate ", " (map renderTextLiteral values) <> "]"

renderTextLiteral :: Text -> Text
renderTextLiteral = cs . show

isOperationLocalAdapter :: RenderableAdapter SurfaceRequestAdapterDeclaration -> Bool
isOperationLocalAdapter adapter =
    adapter.renderableAdapterPayload.surfaceRequestDeclarationEvidenceMode == OperationLocalRequestEvidence

operationTokenName :: RequestAdapterRenderer kind -> RenderableAdapter payload -> Text
operationTokenName renderer adapter = upperFirst (baseName renderer adapter) <> "Operation"

fieldsName :: RequestAdapterRenderer kind -> RenderableAdapter payload -> Text
fieldsName renderer adapter = baseName renderer adapter <> "Fields"

metadataName :: RequestAdapterRenderer kind -> RenderableAdapter payload -> Text
metadataName renderer adapter = baseName renderer adapter <> renderer.requestAdapterMetadataSuffix

paramsPresentName :: RequestAdapterRenderer kind -> RenderableAdapter payload -> Text
paramsPresentName renderer adapter = baseName renderer adapter <> "ParamsPresent"

parserName :: RequestAdapterRenderer kind -> RenderableAdapter payload -> Text
parserName renderer adapter = "parse" <> upperFirst (baseName renderer adapter) <> "Params"

baseName :: RequestAdapterRenderer kind -> RenderableAdapter payload -> Text
baseName renderer = renderer.requestAdapterBaseName . (.haskellTypeName) . (.renderableAdapterHomeDeclaration)

renderActionAuthorityProofModules ::
    [CheckedSurfaceRequestAdapterRegistration 'ActionAdapterKind HtmxActionIR] ->
    [GeneratedHaskellModule]
renderActionAuthorityProofModules inventory =
    inventory
        |> filter ((== OperationLocalRequestEvidence) . (.checkedSurfaceRequestAdapterEvidenceMode))
        |> List.sortOn (proofGroupKey . (.checkedSurfaceRequestAdapter))
        |> List.groupBy
            (\left right ->
                proofGroupKey left.checkedSurfaceRequestAdapter
                    == proofGroupKey right.checkedSurfaceRequestAdapter
            )
        |> map renderActionAuthorityProofModule
  where
    proofOutputModule = (.resolvedAdapterOutputModule)
    proofGroupKey adapter =
        ( proofOutputModule adapter
        , adapter.resolvedAdapterHome.adapterHomeSurface.haskellTypeModule
        , adapter.resolvedAdapterHome.adapterHomeSurface.haskellTypeName
        )

renderActionAuthorityProofModule ::
    [CheckedSurfaceRequestAdapterRegistration 'ActionAdapterKind HtmxActionIR] ->
    GeneratedHaskellModule
renderActionAuthorityProofModule [] = GeneratedHaskellModule "" "" ""
renderActionAuthorityProofModule registrations@(first : _) =
    GeneratedHaskellModule
        { generatedModuleName = proofModuleName
        , generatedModulePath = cs (Text.replace "." "/" proofModuleName <> ".hs")
        , generatedModuleSource = Text.unlines sourceLines
        }
  where
    adapters = map (.checkedSurfaceRequestAdapter) registrations
    renderableAdapters = map (toRenderableAdapter (const ())) adapters
    aliases = sourceModuleAliases renderableAdapters
    firstAdapter = first.checkedSurfaceRequestAdapter
    generatedModuleName = firstAdapter.resolvedAdapterOutputModule
    proofModuleName = generatedModuleName <> "AuthorityProof" <> firstAdapter.resolvedAdapterHome.adapterHomeSurface.haskellTypeName
    familyType = qualifyHaskellType aliases firstAdapter.resolvedAdapterHome.adapterHomeFamily
    operationTypes = zipWith proofOperationType registrations renderableAdapters
    excludedDeclarations =
        [ renderProofOperationToken aliases renderable
        | (registration, renderable) <- zip registrations renderableAdapters
        , isNothing registration.checkedSurfaceRequestAdapterOperations
        ]
    sourceLines =
        [ "{-# LANGUAGE ConstraintKinds #-}"
        , "{-# LANGUAGE DataKinds       #-}"
        , "{-# LANGUAGE GADTs           #-}"
        , "{-# LANGUAGE TypeFamilies    #-}"
        , "{-# LANGUAGE TypeOperators   #-}"
        , ""
        , "-- @generated verification-only authority proof; never publish into app-lib."
        , "module " <> proofModuleName <> " () where"
        , ""
        ]
            <> renderImportList
                "Application.Helper.FrontendContract.Surface.HaskellAdapter.Association"
                ["AdapterFamilySurface"]
            <> renderImportList
                "Application.Helper.FrontendContract.Surface.DSL"
                ["FieldSpec (..)", "WireType (..)"]
            <> renderImportList
                "Application.Helper.FrontendContract.Surface.Values"
                ["ActionFieldSpecs", "ActionMarker", "ActionSurface", "AssertActionAuthority"]
            <> [ "import qualified " <> generatedModuleName <> " as Generated"
               , "import Data.Kind (Constraint)"
               , "import IHP.Prelude"
               ]
            <> [ "import qualified " <> sourceModule <> " as " <> alias
               | (sourceModule, alias) <- Map.toAscList aliases
               ]
            <> [""]
            <> List.intercalate [""] excludedDeclarations
            <> [ ""
               , "data AuthorityDict (constraint :: Constraint) where"
               , "    AuthorityDict :: constraint => AuthorityDict constraint"
               , ""
               , "rosterActionAuthority ::"
               , "    AuthorityDict"
               , "        (AssertActionAuthority"
               , "            (AdapterFamilySurface " <> familyType <> ")"
               ]
            <> renderPromotedTypeList operationTypes
            <> [ "        )"
               , "rosterActionAuthority = AuthorityDict"
               ]

renderIntentAuthorityProofModules ::
    [CheckedSurfaceRequestAdapterRegistration 'IntentAdapterKind IntentIR] ->
    [GeneratedHaskellModule]
renderIntentAuthorityProofModules inventory =
    inventory
        |> filter ((== OperationLocalRequestEvidence) . (.checkedSurfaceRequestAdapterEvidenceMode))
        |> List.sortOn (intentProofGroupKey . (.checkedSurfaceRequestAdapter))
        |> List.groupBy
            (\left right ->
                intentProofGroupKey left.checkedSurfaceRequestAdapter
                    == intentProofGroupKey right.checkedSurfaceRequestAdapter
            )
        |> map renderIntentAuthorityProofModule
  where
    intentProofGroupKey adapter =
        ( adapter.resolvedAdapterOutputModule
        , adapter.resolvedAdapterHome.adapterHomeSurface.haskellTypeModule
        , adapter.resolvedAdapterHome.adapterHomeSurface.haskellTypeName
        )

renderIntentAuthorityProofModule ::
    [CheckedSurfaceRequestAdapterRegistration 'IntentAdapterKind IntentIR] ->
    GeneratedHaskellModule
renderIntentAuthorityProofModule [] = GeneratedHaskellModule "" "" ""
renderIntentAuthorityProofModule registrations@(first : _) =
    GeneratedHaskellModule
        { generatedModuleName = proofModuleName
        , generatedModulePath = cs (Text.replace "." "/" proofModuleName <> ".hs")
        , generatedModuleSource = Text.unlines sourceLines
        }
  where
    adapters = map (.checkedSurfaceRequestAdapter) registrations
    renderableAdapters = map (toRenderableAdapter (const ())) adapters
    aliases = sourceModuleAliases renderableAdapters
    firstAdapter = first.checkedSurfaceRequestAdapter
    generatedModuleName = firstAdapter.resolvedAdapterOutputModule
    proofModuleName = generatedModuleName <> "AuthorityProof" <> firstAdapter.resolvedAdapterHome.adapterHomeSurface.haskellTypeName
    familyType = qualifyHaskellType aliases firstAdapter.resolvedAdapterHome.adapterHomeFamily
    operationTypes = zipWith intentProofOperationType registrations renderableAdapters
    sourceLines =
        [ "{-# LANGUAGE ConstraintKinds #-}"
        , "{-# LANGUAGE DataKinds       #-}"
        , "{-# LANGUAGE GADTs           #-}"
        , "{-# LANGUAGE TypeFamilies    #-}"
        , "{-# LANGUAGE TypeOperators   #-}"
        , ""
        , "-- @generated verification-only authority proof; never publish into app-lib."
        , "module " <> proofModuleName <> " () where"
        , ""
        ]
            <> renderImportList
                "Application.Helper.FrontendContract.Surface.HaskellAdapter.Association"
                ["AdapterFamilySurface"]
            <> renderImportList
                "Application.Helper.FrontendContract.Surface.Values"
                ["AssertIntentAuthority"]
            <> [ "import qualified " <> generatedModuleName <> " as Generated"
               , "import Data.Kind (Constraint)"
               , "import IHP.Prelude"
               ]
            <> [ "import qualified " <> sourceModule <> " as " <> alias
               | (sourceModule, alias) <- Map.toAscList aliases
               ]
            <> [ ""
               , "data AuthorityDict (constraint :: Constraint) where"
               , "    AuthorityDict :: constraint => AuthorityDict constraint"
               , ""
               , "intentAuthority ::"
               , "    AuthorityDict"
               , "        (AssertIntentAuthority"
               , "            (AdapterFamilySurface " <> familyType <> ")"
               ]
            <> renderPromotedTypeList operationTypes
            <> [ "        )"
               , "intentAuthority = AuthorityDict"
               ]

intentProofOperationType ::
    CheckedSurfaceRequestAdapterRegistration 'IntentAdapterKind IntentIR ->
    RenderableAdapter () ->
    Text
intentProofOperationType registration adapter =
    if isJust registration.checkedSurfaceRequestAdapterOperations
        then "Generated." <> proofIntentOperationTokenName adapter
        else error "Operation-local Intent proof cannot omit a generated Intent declaration"

proofIntentOperationTokenName :: RenderableAdapter payload -> Text
proofIntentOperationTokenName adapter =
    upperFirst (requestBaseName "intent" adapter.renderableAdapterHomeDeclaration.haskellTypeName)
        <> "Operation"

proofOperationType ::
    CheckedSurfaceRequestAdapterRegistration 'ActionAdapterKind HtmxActionIR ->
    RenderableAdapter () ->
    Text
proofOperationType registration adapter =
    qualifier <> proofOperationTokenName adapter
  where
    qualifier =
        if isJust registration.checkedSurfaceRequestAdapterOperations
            then "Generated."
            else ""

renderProofOperationToken :: Map.Map Text Text -> RenderableAdapter () -> [Text]
renderProofOperationToken aliases adapter =
    [ "data " <> token
    , ""
    , "type instance ActionSurface " <> token <> " = "
        <> qualifyHaskellType aliases adapter.renderableAdapterHomeSurface
    , "type instance ActionMarker " <> token <> " = "
        <> qualifyHaskellType aliases adapter.renderableAdapterHomeDeclaration
    , "type instance ActionFieldSpecs " <> token <> " ="
    ]
        <> renderPromotedFieldList aliases adapter.renderableAdapterFields
  where
    token = proofOperationTokenName adapter

proofOperationTokenName :: RenderableAdapter payload -> Text
proofOperationTokenName adapter =
    upperFirst (requestBaseName "action" adapter.renderableAdapterHomeDeclaration.haskellTypeName)
        <> "Operation"

renderPromotedTypeList :: [Text] -> [Text]
renderPromotedTypeList [] = ["            '[]"]
renderPromotedTypeList (first : rest) =
    ["            '[ " <> first]
        <> map ("             , " <>) rest
        <> ["             ]"]

requestBaseName :: Text -> Text -> Text
requestBaseName suffix typeName =
    wordsFromTypeName typeName
        |> preserveOrAddSuffix
        |> lowerCamel
        |> haskellValueIdentifier
  where
    preserveOrAddSuffix words
        | [suffix] `List.isSuffixOf` words = words
        | otherwise = words <> [suffix]
