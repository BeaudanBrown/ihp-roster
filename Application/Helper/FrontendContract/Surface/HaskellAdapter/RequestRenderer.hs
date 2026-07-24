{-# LANGUAGE OverloadedRecordDot #-}

-- | Source mechanics shared only by the focused Action and Intent renderers.
-- Kind-specific declaration selection, names, metadata functions, and output
-- lane types remain in those focused modules; this module owns their identical
-- field-builder, parser, operation-filtering, and import shapes.
module Application.Helper.FrontendContract.Surface.HaskellAdapter.RequestRenderer
    ( renderSurfaceRequestAdapterFieldsBuilder
    , renderSurfaceRequestAdapterFieldsType
    , renderSurfaceRequestAdapterImports
    , renderSurfaceRequestAdapterOperationBlocks
    , renderSurfaceRequestAdapterParser
    ) where

import Application.Helper.FrontendContract.Surface.ContractIR
import Application.Helper.FrontendContract.Surface.HaskellAdapter.Core
import Application.Helper.FrontendContract.Surface.HaskellAdapter.Family
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import IHP.Prelude

renderSurfaceRequestAdapterImports ::
    Text ->
    Text ->
    Text ->
    [Text] ->
    Text ->
    (payload -> SurfaceRequestAdapterOperations) ->
    Map.Map Text Text ->
    [RenderableAdapter payload] ->
    [Text]
renderSurfaceRequestAdapterImports requestFieldsImport bindFieldsImport emptyFieldsImport metadataImports parserImport operationsOf aliases adapters =
    renderImportList
        "Application.Helper.FrontendContract.Surface.HaskellAdapter.Association"
        ["AdapterFamilySurface"]
        <> conditionalImports hasParser
            ( renderImportList
                "Application.Helper.FrontendContract.Surface.Request"
                ["SurfaceRequestFieldError", parserImport]
            )
        <> conditionalImports hasMetadata
            ( renderImportList
                "Application.Helper.FrontendContract.Surface.Request.Runtime"
                metadataImports
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
    builderAdapters = filter (hasGeneratedOperation (.surfaceAdapterFieldsBuilderOperation)) adapters
    emptyBuilderAdapters = filter (null . (.renderableAdapterFields)) builderAdapters
    nonEmptyBuilderAdapters = filter (not . null . (.renderableAdapterFields)) builderAdapters
    builderFields = concatMap (.renderableAdapterFields) builderAdapters
    hasMetadata = any (hasGeneratedOperation (.surfaceAdapterRenderMetadataOperation)) adapters
    hasParser = any (hasGeneratedOperation (.surfaceAdapterRequestParserOperation)) adapters
    valueImports =
        List.sort
            ( [requestFieldsImport]
                <> [emptyFieldsImport | not (null emptyBuilderAdapters)]
                <> (if null nonEmptyBuilderAdapters then [] else [bindFieldsImport, "noSurfaceFields"])
                <> ["surfaceField" | any ((== RequiredField) . (.fieldPresence) . (.resolvedAdapterFieldIR)) builderFields]
                <> ["surfaceNullableField" | any ((== NullableFieldPresence) . (.fieldPresence) . (.resolvedAdapterFieldIR)) builderFields]
                <> ["surfaceOptionalField" | any ((== OptionalFieldPresence) . (.fieldPresence) . (.resolvedAdapterFieldIR)) builderFields]
            )
            <> ["(&:)" | any ((> 1) . length . (.renderableAdapterFields)) nonEmptyBuilderAdapters]
    builderTypes = concatMap (map (.resolvedAdapterFieldType) . (.renderableAdapterFields)) builderAdapters
    needsDay = any sourceTypeContainsDay builderTypes
    needsUuid = any sourceTypeContainsUuid builderTypes
    hasGeneratedOperation operation adapter =
        surfaceAdapterOperationIsGenerated (operation (operationsOf adapter.renderableAdapterPayload))
    conditionalImports True imports = imports
    conditionalImports False _      = []

renderSurfaceRequestAdapterOperationBlocks ::
    [(SurfaceAdapterOperationEligibility, [Text])] ->
    [Text]
renderSurfaceRequestAdapterOperationBlocks operations =
    operations
        |> mapMaybe generatedBlock
        |> List.intercalate [""]
  where
    generatedBlock (eligibility, block)
        | surfaceAdapterOperationIsGenerated eligibility = Just block
        | otherwise = Nothing

renderSurfaceRequestAdapterFieldsBuilder ::
    Text ->
    Text ->
    Text ->
    (RenderableAdapter payload -> Text) ->
    Map.Map Text Text ->
    RenderableAdapter payload ->
    [Text]
renderSurfaceRequestAdapterFieldsBuilder requestFieldsType bindFieldsName emptyFieldsName fieldsName aliases adapter =
    renderFieldsBuilderSignature <> renderFieldsBuilderBody
  where
    renderFieldsBuilderBody =
        case adapter.renderableAdapterFields of
            [] ->
                [ fieldsName adapter <> " ="
                , "    " <> emptyFieldsName
                ]
            first : rest ->
                [ fieldsName adapter <> renderAdapterArguments adapter.renderableAdapterFields <> " ="
                , "    " <> bindFieldsName
                , "        (" <> renderAdapterFieldBuilder aliases first <> ")"
                ]
                    <> renderAdapterFieldsExpression aliases rest
    resultType = renderSurfaceRequestAdapterFieldsType requestFieldsType aliases adapter
    renderFieldsBuilderSignature =
        case adapter.renderableAdapterFields of
            [] -> [fieldsName adapter <> " :: " <> resultType]
            fields ->
                [fieldsName adapter <> " ::"]
                    <> map ("    " <>)
                        ( map ((<> " ->") . renderHaskellSourceType . (.resolvedAdapterFieldType)) fields
                            <> [resultType]
                        )

renderSurfaceRequestAdapterParser ::
    Text ->
    (RenderableAdapter payload -> Text) ->
    Text ->
    Map.Map Text Text ->
    RenderableAdapter payload ->
    [Text]
renderSurfaceRequestAdapterParser requestFieldsType parserName genericParser aliases adapter =
    [ parserName adapter <> " ::"
    , "    (?request :: Request) =>"
    , "    Either [SurfaceRequestFieldError] (" <> fieldsType <> ")"
    , parserName adapter <> " ="
    , "    " <> genericParser
    , "        @(AdapterFamilySurface " <> qualifyHaskellType aliases adapter.renderableAdapterHomeFamily <> ")"
    , "        @" <> qualifyHaskellType aliases adapter.renderableAdapterHomeDeclaration
    ]
  where
    fieldsType = renderSurfaceRequestAdapterFieldsType requestFieldsType aliases adapter

renderSurfaceRequestAdapterFieldsType ::
    Text ->
    Map.Map Text Text ->
    RenderableAdapter payload ->
    Text
renderSurfaceRequestAdapterFieldsType requestFieldsType aliases adapter =
    requestFieldsType <> " (AdapterFamilySurface "
        <> qualifyHaskellType aliases adapter.renderableAdapterHomeFamily
        <> ") "
        <> qualifyHaskellType aliases adapter.renderableAdapterHomeDeclaration
