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
import IHP.Prelude

-- | The only payload admitted to generated request lanes. The kind index on
-- 'ResolvedAdapter' retains Action/Intent identity; this payload only carries
-- the declaration-complete operation inventory needed by shared rendering.
newtype SurfaceRequestAdapterDeclaration = SurfaceRequestAdapterDeclaration
    { surfaceRequestDeclarationOperations :: SurfaceRequestAdapterOperations
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
            contract
            registry.surfaceAdapterFamilies
            declarations
            registry.surfaceActionAdapterRegistrations
    renderSurfaceActionAdapterModules adapters

generateSurfaceIntentAdapterModules ::
    SurfaceContractIR ->
    SurfaceAdapterRegistry ->
    Either [ContractDiagnostic] [GeneratedHaskellModule]
generateSurfaceIntentAdapterModules contract registry = do
    declarations <- checkedSurfaceIntentAdapterDeclarations contract
    adapters <-
        resolveGeneratedRequestAdapters
            intentRequestRenderer
            contract
            registry.surfaceAdapterFamilies
            declarations
            registry.surfaceIntentAdapterRegistrations
    renderSurfaceIntentAdapterModules adapters

resolveGeneratedRequestAdapters ::
    RequestAdapterRenderer kind ->
    SurfaceContractIR ->
    [SurfaceAdapterFamilyMetadata] ->
    [CheckedAdapterDeclaration kind payload] ->
    [SurfaceRequestAdapterRegistration kind] ->
    Either [ContractDiagnostic] [ResolvedAdapter kind SurfaceRequestAdapterDeclaration]
resolveGeneratedRequestAdapters renderer contract families declarations registrations = do
    inventory <-
        resolveSurfaceRequestAdapterRegistrations
            renderer.requestAdapterLayout
            contract
            families
            declarations
            registrations
    pure
        [ prepareResolvedAdapter
            (const (SurfaceRequestAdapterDeclaration operations))
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
    , requestAdapterBaseName           :: !(Text -> Text)
    , requestAdapterMetadataSuffix     :: !Text
    , requestAdapterFieldsType         :: !Text
    , requestAdapterBindFields         :: !Text
    , requestAdapterEmptyFields        :: !Text
    , requestAdapterMetadataImports    :: ![Text]
    , requestAdapterMetadataResultType :: !Text
    , requestAdapterMetadataBuilder    :: !Text
    , requestAdapterParser             :: !Text
    }

actionRequestRenderer :: RequestAdapterRenderer 'ActionAdapterKind
actionRequestRenderer =
    RequestAdapterRenderer
        { requestAdapterLayout = actionAdapterLayout
        , requestAdapterBaseName = requestBaseName "action"
        , requestAdapterMetadataSuffix = ""
        , requestAdapterFieldsType = "SurfaceActionFields"
        , requestAdapterBindFields = "surfaceActionFields"
        , requestAdapterEmptyFields = "noSurfaceActionFields"
        , requestAdapterMetadataImports = ["FrontendSurfaceAction", "frontendSurfaceAction"]
        , requestAdapterMetadataResultType = "FrontendSurfaceAction"
        , requestAdapterMetadataBuilder = "frontendSurfaceAction"
        , requestAdapterParser = "parseSurfaceActionParams"
        }

intentRequestRenderer :: RequestAdapterRenderer 'IntentAdapterKind
intentRequestRenderer =
    RequestAdapterRenderer
        { requestAdapterLayout = intentAdapterLayout
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
        , requestAdapterMetadataResultType = "FrontendSurfaceHtmxRequest -> FrontendSurfaceIntentForm"
        , requestAdapterMetadataBuilder = "frontendSurfaceIntentForm"
        , requestAdapterParser = "parseSurfaceIntentParams"
        }

requestGeneratedNames ::
    RequestAdapterRenderer kind ->
    CheckedAdapterDeclaration kind SurfaceRequestAdapterDeclaration ->
    [Text]
requestGeneratedNames renderer declaration =
    concat
        [ operationName operations.surfaceAdapterFieldsBuilderOperation (baseName <> "Fields")
        , operationName operations.surfaceAdapterRenderMetadataOperation (baseName <> renderer.requestAdapterMetadataSuffix)
        , operationName operations.surfaceAdapterRequestParserOperation ("parse" <> upperFirst baseName <> "Params")
        ]
  where
    operations = declaration.checkedAdapterPayload.surfaceRequestDeclarationOperations
    baseName = renderer.requestAdapterBaseName declaration.checkedAdapterDeclarationMarker
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
        { adapterRendererLanguagePragmas =
            [ "{-# LANGUAGE ImplicitParams   #-}"
            , "{-# LANGUAGE TypeApplications #-}"
            ]
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
    renderImportList
        "Application.Helper.FrontendContract.Surface.HaskellAdapter.Association"
        ["AdapterFamilySurface"]
        <> conditionalImports hasParser
            ( renderImportList
                "Application.Helper.FrontendContract.Surface.Request"
                ["SurfaceRequestFieldError", renderer.requestAdapterParser]
            )
        <> conditionalImports hasMetadata
            ( renderImportList
                "Application.Helper.FrontendContract.Surface.Request.Runtime"
                renderer.requestAdapterMetadataImports
            )
        <> renderImportList
            "Application.Helper.FrontendContract.Surface.Values"
            valueImports
        <> conditionalImports needsDay ["import Data.Time (Day)"]
        <> conditionalImports needsUuid ["import qualified Data.UUID as UUID"]
        <> ["import IHP.Prelude"]
        <> conditionalImports hasParser ["import Network.Wai (Request)"]
        <> [ "import qualified " <> sourceModule <> " as " <> alias
           | (sourceModule, alias) <- Map.toAscList aliases
           ]
  where
    operationsOf = (.surfaceRequestDeclarationOperations) . (.renderableAdapterPayload)
    builderAdapters = filter (hasGeneratedOperation (.surfaceAdapterFieldsBuilderOperation)) adapters
    emptyBuilderAdapters = filter (null . (.renderableAdapterFields)) builderAdapters
    nonEmptyBuilderAdapters = filter (not . null . (.renderableAdapterFields)) builderAdapters
    builderFields = concatMap (.renderableAdapterFields) builderAdapters
    hasMetadata = any (hasGeneratedOperation (.surfaceAdapterRenderMetadataOperation)) adapters
    hasParser = any (hasGeneratedOperation (.surfaceAdapterRequestParserOperation)) adapters
    valueImports =
        List.sort
            ( [renderer.requestAdapterFieldsType]
                <> [renderer.requestAdapterEmptyFields | not (null emptyBuilderAdapters)]
                <> (if null nonEmptyBuilderAdapters then [] else [renderer.requestAdapterBindFields, "noSurfaceFields"])
                <> ["surfaceField" | any ((== RequiredField) . (.fieldPresence) . (.resolvedAdapterFieldIR)) builderFields]
                <> ["surfaceNullableField" | any ((== NullableFieldPresence) . (.fieldPresence) . (.resolvedAdapterFieldIR)) builderFields]
                <> ["surfaceOptionalField" | any ((== OptionalFieldPresence) . (.fieldPresence) . (.resolvedAdapterFieldIR)) builderFields]
            )
            <> ["(&:)" | any ((> 1) . length . (.renderableAdapterFields)) nonEmptyBuilderAdapters]
    builderTypes = concatMap (map (.resolvedAdapterFieldType) . (.renderableAdapterFields)) builderAdapters
    needsDay = any sourceTypeContainsDay builderTypes
    needsUuid = any sourceTypeContainsUuid builderTypes
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
    operationBlocks
        [ ( operations.surfaceAdapterFieldsBuilderOperation
          , renderFieldsBuilder renderer aliases adapter
          )
        , ( operations.surfaceAdapterRenderMetadataOperation
          , renderMetadata renderer aliases adapter
          )
        , ( operations.surfaceAdapterRequestParserOperation
          , renderParser renderer aliases adapter
          )
        ]
  where
    operations = adapter.renderableAdapterPayload.surfaceRequestDeclarationOperations

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
    RenderableAdapter payload ->
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
            [] -> [name <> " =", "    " <> renderer.requestAdapterEmptyFields]
            first : rest ->
                [ name <> renderAdapterArguments adapter.renderableAdapterFields <> " ="
                , "    " <> renderer.requestAdapterBindFields
                , "        (" <> renderAdapterFieldBuilder aliases first <> ")"
                ]
                    <> renderAdapterFieldsExpression aliases rest

renderMetadata ::
    RequestAdapterRenderer kind ->
    Map.Map Text Text ->
    RenderableAdapter payload ->
    [Text]
renderMetadata renderer aliases adapter =
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
    RenderableAdapter payload ->
    [Text]
renderParser renderer aliases adapter =
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
    RenderableAdapter payload ->
    Text
requestFieldsType renderer aliases adapter =
    renderer.requestAdapterFieldsType <> " (AdapterFamilySurface "
        <> qualifyHaskellType aliases adapter.renderableAdapterHomeFamily
        <> ") "
        <> qualifyHaskellType aliases adapter.renderableAdapterHomeDeclaration

fieldsName :: RequestAdapterRenderer kind -> RenderableAdapter payload -> Text
fieldsName renderer adapter = baseName renderer adapter <> "Fields"

metadataName :: RequestAdapterRenderer kind -> RenderableAdapter payload -> Text
metadataName renderer adapter = baseName renderer adapter <> renderer.requestAdapterMetadataSuffix

parserName :: RequestAdapterRenderer kind -> RenderableAdapter payload -> Text
parserName renderer adapter = "parse" <> upperFirst (baseName renderer adapter) <> "Params"

baseName :: RequestAdapterRenderer kind -> RenderableAdapter payload -> Text
baseName renderer = renderer.requestAdapterBaseName . (.haskellTypeName) . (.renderableAdapterHomeDeclaration)

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
