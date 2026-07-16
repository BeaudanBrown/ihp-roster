{-# LANGUAGE LambdaCase          #-}
{-# LANGUAGE OverloadedRecordDot #-}

-- | Pure validation and canonical source rendering for private generated
-- Surface resource adapters. The checked Surface IR owns declarations and
-- wires; typed home metadata contributes only ownership and source type names.
module Application.Helper.FrontendContract.Surface.HaskellAdapter.Generator
    ( GeneratedHaskellModule (..)
    , generateSurfaceResourceAdapterModules
    ) where

import Application.Helper.FrontendContract.Naming (wordsFromTypeName)
import Application.Helper.FrontendContract.Surface.ContractIR
import Application.Helper.FrontendContract.Surface.HaskellAdapter.Family
import Application.Helper.FrontendContract.Wire.Carrier (HaskellWireSource (..),
                                                         haskellWireSource)
import qualified Data.Char as Char
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import qualified Data.Text as Text
import IHP.Prelude

-- | One repository-relative Haskell module. Callers write these values only
-- after the complete registry has validated successfully.
data GeneratedHaskellModule = GeneratedHaskellModule
    { generatedModuleName   :: !Text
    , generatedModulePath   :: !FilePath
    , generatedModuleSource :: !Text
    }
    deriving (Eq, Show)

data ResolvedResourceAdapter = ResolvedResourceAdapter
    { resolvedHome         :: !SurfaceResourceAdapterHomeMetadata
    , resolvedResource     :: !ResourceIR
    , resolvedOutputModule :: !Text
    , resolvedConstructor  :: !Text
    , resolvedMatcher      :: !Text
    , resolvedFields       :: ![ResolvedField]
    }
    deriving (Eq, Show)

data ResolvedField = ResolvedField
    { resolvedFieldIR     :: !FieldIR
    , resolvedFieldMarker :: !HaskellTypeMetadata
    , resolvedFieldType   :: !HaskellSourceType
    }
    deriving (Eq, Show)

data HaskellSourceType
    = HaskellNamedType !HaskellNamedType
    | HaskellListType !HaskellSourceType
    | HaskellMaybeType !HaskellSourceType
    deriving (Eq, Show)

data HaskellNamedType
    = HaskellTextType
    | HaskellIntType
    | HaskellBoolType
    | HaskellUuidType
    | HaskellDayType
    deriving (Eq, Show)

generateSurfaceResourceAdapterModules ::
    SurfaceContractIR ->
    SurfaceAdapterRegistry ->
    Either [ContractDiagnostic] [GeneratedHaskellModule]
generateSurfaceResourceAdapterModules contract registry =
    case stableDiagnostics allDiagnostics of
        []          -> Right (renderGeneratedModules resolvedAdapters)
        diagnostics -> Left diagnostics
  where
    contractDiagnostics = validateSurfaceContractIR contract
    familyDiagnostics = validateFamilies contract registry.surfaceAdapterFamilies
    duplicateHomeDiagnostics = validateDuplicateHomes registry.surfaceResourceAdapterHomes
    (homeDiagnostics, ownedAdapters) =
        unzip (map (resolveResourceHome contract registry) registry.surfaceResourceAdapterHomes)
    resolvedOwnedAdapters = catMaybes ownedAdapters
    resourceHomeCoverageDiagnostics = validateResourceHomeCoverage contract resolvedOwnedAdapters
    (sourceDiagnostics, resolvedAdapters) =
        unzip (map resolveResourceSourceTypes resolvedOwnedAdapters)
            |> second catMaybes
    collisionDiagnostics = validateGeneratedNameCollisions resolvedAdapters
    allDiagnostics =
        contractDiagnostics
            <> familyDiagnostics
            <> duplicateHomeDiagnostics
            <> concat homeDiagnostics
            <> resourceHomeCoverageDiagnostics
            <> concat sourceDiagnostics
            <> collisionDiagnostics

validateFamilies :: SurfaceContractIR -> [SurfaceAdapterFamilyMetadata] -> [ContractDiagnostic]
validateFamilies contract families =
    duplicateMetadataDiagnostics
        "duplicate-adapter-family"
        "adapter family"
        adapterFamilyType
        families
        <> duplicateMetadataDiagnostics
            "duplicate-surface-adapter-family"
            "Surface adapter family"
            adapterFamilySurfaceMarker
            families
        <> concatMap validateFamily families
  where
    validateFamily adapterFamily =
        validateHaskellTypeModule "adapter-family-source-module" "adapter family" adapterFamily.adapterFamilyType
            <> validateHaskellTypeModule "adapter-surface-source-module" "adapter Surface" adapterFamily.adapterFamilySurfaceMarker
            <> case surfacesWithMarker contract adapterFamily.adapterFamilySurfaceMarker.haskellTypeName of
                [_] -> []
                [] ->
                    [ diagnostic
                        "adapter-family-surface-ownership"
                        ( "Adapter family " <> renderHaskellType adapterFamily.adapterFamilyType
                            <> " associates unregistered Surface marker "
                            <> renderHaskellType adapterFamily.adapterFamilySurfaceMarker
                        )
                    ]
                _ ->
                    [ diagnostic
                        "adapter-family-surface-ownership"
                        ( "Adapter family " <> renderHaskellType adapterFamily.adapterFamilyType
                            <> " associates ambiguous Surface marker "
                            <> renderHaskellType adapterFamily.adapterFamilySurfaceMarker
                        )
                    ]

resolveResourceHome ::
    SurfaceContractIR ->
    SurfaceAdapterRegistry ->
    SurfaceResourceAdapterHomeMetadata ->
    ([ContractDiagnostic], Maybe ResolvedResourceAdapter)
resolveResourceHome contract registry home =
    case (registeredFamily, ownedSurface, ownedResources) of
        (Just adapterFamily, [_], [resource])
            | adapterFamily.adapterFamilySurfaceMarker /= home.resourceAdapterHomeSurface ->
                ( commonDiagnostics
                    <> [ diagnostic
                            "adapter-resource-home-family-mismatch"
                            ( "Resource home " <> renderHaskellType home.resourceAdapterHomeResource
                                <> " records Surface " <> renderHaskellType home.resourceAdapterHomeSurface
                                <> " but family " <> renderHaskellType home.resourceAdapterHomeFamily
                                <> " associates " <> renderHaskellType adapterFamily.adapterFamilySurfaceMarker
                            )
                       ]
                , Nothing
                )
            | fieldMarkerNames resource /= map (.haskellTypeName) home.resourceAdapterHomeFieldMarkers ->
                ( commonDiagnostics
                    <> [ diagnostic
                            "adapter-resource-home-field-metadata"
                            ( "Resource home " <> renderHaskellType home.resourceAdapterHomeResource
                                <> " field marker metadata does not match checked resource " <> resource.resourceName
                            )
                       ]
                , Nothing
                )
            | otherwise ->
                ( commonDiagnostics
                , Just ResolvedResourceAdapter
                    { resolvedHome = home
                    , resolvedResource = resource
                    , resolvedOutputModule = home.resourceAdapterHomeSurface.haskellTypeModule <> ".Generated.Resource"
                    , resolvedConstructor = resourceConstructorName home.resourceAdapterHomeResource.haskellTypeName
                    , resolvedMatcher = "match" <> upperFirst (resourceConstructorName home.resourceAdapterHomeResource.haskellTypeName)
                    , resolvedFields = zipWith unresolvedField resource.resourceFields home.resourceAdapterHomeFieldMarkers
                    }
                )
          where
            unresolvedField field marker = ResolvedField field marker (HaskellNamedType HaskellTextType)
        _ -> (commonDiagnostics <> ownershipDiagnostics, Nothing)
  where
    registeredFamily =
        find ((== home.resourceAdapterHomeFamily) . (.adapterFamilyType)) registry.surfaceAdapterFamilies
    ownedSurface = surfacesWithMarker contract home.resourceAdapterHomeSurface.haskellTypeName
    ownedResources =
        case ownedSurface of
            [surface] ->
                resourcesForSurface surface
                    |> filter ((== home.resourceAdapterHomeResource.haskellTypeName) . (.resourceMarker))
            _ -> []
    commonDiagnostics =
        validateHaskellTypeModule "adapter-family-source-module" "adapter family" home.resourceAdapterHomeFamily
            <> validateHaskellTypeModule "adapter-surface-source-module" "adapter Surface" home.resourceAdapterHomeSurface
            <> validateHaskellTypeModule "adapter-resource-source-module" "adapter resource" home.resourceAdapterHomeResource
            <> concatMap (validateHaskellTypeModule "adapter-field-source-module" "adapter field") home.resourceAdapterHomeFieldMarkers
            <> concatMap validateGeneratedImportLocality generatedImports
    generatedImports =
        ("adapter family", home.resourceAdapterHomeFamily)
            : ("resource marker", home.resourceAdapterHomeResource)
            : map (\marker -> ("field marker", marker)) home.resourceAdapterHomeFieldMarkers
    validateGeneratedImportLocality (label, importedType)
        | featureModuleOwns home.resourceAdapterHomeSurface.haskellTypeModule importedType.haskellTypeModule = []
        | otherwise =
            [ diagnostic
                "adapter-import-locality"
                ( "Resource " <> renderHaskellType home.resourceAdapterHomeResource
                    <> " would import " <> label <> " " <> renderHaskellType importedType
                    <> " outside owning feature module tree " <> home.resourceAdapterHomeSurface.haskellTypeModule
                )
            ]
    ownershipDiagnostics =
        missingFamilyDiagnostics <> missingSurfaceDiagnostics <> missingResourceDiagnostics
    missingFamilyDiagnostics =
        case registeredFamily of
            Nothing ->
                [ diagnostic
                    "unregistered-adapter-family"
                    ( "Resource home " <> renderHaskellType home.resourceAdapterHomeResource
                        <> " references unregistered adapter family " <> renderHaskellType home.resourceAdapterHomeFamily
                    )
                ]
            Just _ -> []
    missingSurfaceDiagnostics =
        case ownedSurface of
            [] ->
                [ diagnostic
                    "adapter-resource-home-ownership"
                    ( "Adapter family " <> renderHaskellType home.resourceAdapterHomeFamily
                        <> " has no checked Surface " <> renderHaskellType home.resourceAdapterHomeSurface
                        <> " for resource " <> renderHaskellType home.resourceAdapterHomeResource
                    )
                ]
            [_] -> []
            _ ->
                [ diagnostic
                    "adapter-resource-home-ownership"
                    ( "Adapter family " <> renderHaskellType home.resourceAdapterHomeFamily
                        <> " has ambiguous checked Surface " <> renderHaskellType home.resourceAdapterHomeSurface
                        <> " for resource " <> renderHaskellType home.resourceAdapterHomeResource
                    )
                ]
    missingResourceDiagnostics =
        case ownedSurface of
            [_]
                | null ownedResources ->
                    [ diagnostic
                        "adapter-resource-home-ownership"
                        ( "Adapter family " <> renderHaskellType home.resourceAdapterHomeFamily
                            <> " Surface " <> renderHaskellType home.resourceAdapterHomeSurface
                            <> " does not own resource " <> renderHaskellType home.resourceAdapterHomeResource
                        )
                    ]
                | length ownedResources > 1 ->
                    [ diagnostic
                        "adapter-resource-home-ownership"
                        ( "Adapter family " <> renderHaskellType home.resourceAdapterHomeFamily
                            <> " Surface " <> renderHaskellType home.resourceAdapterHomeSurface
                            <> " has ambiguous resource " <> renderHaskellType home.resourceAdapterHomeResource
                        )
                    ]
            _ -> []

resolveResourceSourceTypes ::
    ResolvedResourceAdapter ->
    ([ContractDiagnostic], Maybe ResolvedResourceAdapter)
resolveResourceSourceTypes adapter =
    case partitionEithers (map resolveField adapter.resolvedFields) of
        ([], fields)     -> ([], Just adapter { resolvedFields = fields })
        (diagnostics, _) -> (diagnostics, Nothing)
  where
    resolveField field =
        case sourceTypeForField field.resolvedFieldIR of
            Right sourceType -> Right field { resolvedFieldType = sourceType }
            Left unsupported ->
                Left $ diagnostic
                    "unsupported-generated-source-type"
                    ( "Resource " <> adapter.resolvedResource.resourceName
                        <> " field " <> field.resolvedFieldIR.fieldName
                        <> " has unsupported generated Haskell source type " <> unsupported
                    )

sourceTypeForField :: FieldIR -> Either Text HaskellSourceType
sourceTypeForField field = do
    wireType <- sourceTypeForWire (haskellWireSource field.fieldWire)
    pure $ case field.fieldPresence of
        RequiredField         -> wireType
        OptionalFieldPresence -> HaskellMaybeType wireType
        NullableFieldPresence -> HaskellMaybeType wireType

sourceTypeForWire :: HaskellWireSource -> Either Text HaskellSourceType
sourceTypeForWire = \case
    HaskellTextSource -> Right (HaskellNamedType HaskellTextType)
    HaskellIntSource -> Right (HaskellNamedType HaskellIntType)
    HaskellBoolSource -> Right (HaskellNamedType HaskellBoolType)
    HaskellUuidSource -> Right (HaskellNamedType HaskellUuidType)
    HaskellDaySource -> Right (HaskellNamedType HaskellDayType)
    HaskellListSource inner -> HaskellListType <$> sourceTypeForWire inner
    HaskellOptionalSource inner -> HaskellMaybeType <$> sourceTypeForWire inner
    HaskellNullableSource inner -> HaskellMaybeType <$> sourceTypeForWire inner
    unsupported -> Left (haskellWireSourceLabel unsupported)

haskellWireSourceLabel :: HaskellWireSource -> Text
haskellWireSourceLabel = \case
    HaskellTextSource -> "Text"
    HaskellIntSource -> "Int"
    HaskellBoolSource -> "Bool"
    HaskellUuidSource -> "UUID"
    HaskellDaySource -> "Day"
    HaskellListSource inner -> "[" <> haskellWireSourceLabel inner <> "]"
    HaskellMapSource key value -> "Map " <> parenthesizeLabel key <> " " <> parenthesizeLabel value
    HaskellOptionalSource inner -> "Maybe " <> parenthesizeLabel inner
    HaskellNullableSource inner -> "Nullable " <> parenthesizeLabel inner
    HaskellRefSource marker -> "reference " <> marker
    HaskellJsonSource -> "Aeson.Value"
    HaskellSurfaceScopeSource -> "SurfaceScope"
    HaskellSurfaceFragmentKeySource -> "SurfaceFragmentKey"
  where
    parenthesizeLabel source =
        case source of
            HaskellTextSource -> haskellWireSourceLabel source
            HaskellIntSource -> haskellWireSourceLabel source
            HaskellBoolSource -> haskellWireSourceLabel source
            HaskellUuidSource -> haskellWireSourceLabel source
            HaskellDaySource -> haskellWireSourceLabel source
            HaskellJsonSource -> haskellWireSourceLabel source
            HaskellSurfaceScopeSource -> haskellWireSourceLabel source
            HaskellSurfaceFragmentKeySource -> haskellWireSourceLabel source
            _ -> "(" <> haskellWireSourceLabel source <> ")"

validateDuplicateHomes :: [SurfaceResourceAdapterHomeMetadata] -> [ContractDiagnostic]
validateDuplicateHomes homes =
    -- Checked Surface IR identifies declaration markers by reflected type name,
    -- not by their source module. Homes must use that same identity so two
    -- module-qualified marker types cannot claim one checked resource.
    homes
        |> List.sortOn ((.haskellTypeName) . (.resourceAdapterHomeResource))
        |> List.groupBy
            (\left right ->
                left.resourceAdapterHomeResource.haskellTypeName
                    == right.resourceAdapterHomeResource.haskellTypeName
            )
        |> concatMap duplicateGroup
  where
    duplicateGroup group@(first : _)
        | length group > 1 =
            [ diagnostic
                "duplicate-adapter-resource-home"
                ( "Resource " <> renderHaskellType first.resourceAdapterHomeResource
                    <> " has duplicate adapter homes: "
                    <> Text.intercalate ", " (map (renderHaskellType . (.resourceAdapterHomeFamily)) group)
                )
            ]
    duplicateGroup _ = []

validateResourceHomeCoverage :: SurfaceContractIR -> [ResolvedResourceAdapter] -> [ContractDiagnostic]
validateResourceHomeCoverage contract adapters =
    missingHomeDiagnostics <> duplicateIdentityDiagnostics
  where
    checkedResources =
        contract.contractSurfaces
            |> concatMap resourcesForSurface
            |> List.sortOn (.resourceName)
            |> List.groupBy (\left right -> left.resourceName == right.resourceName)
            |> mapMaybe listToMaybe
    adaptersByResourceName =
        adapters
            |> List.sortOn ((.resourceName) . (.resolvedResource))
            |> List.groupBy
                (\left right -> left.resolvedResource.resourceName == right.resolvedResource.resourceName)
    missingHomeDiagnostics =
        [ diagnostic
            "missing-adapter-resource-home"
            ("Checked resource " <> resource.resourceName <> " has no generated adapter home")
        | resource <- checkedResources
        , not (any ((== resource.resourceName) . (.resourceName) . (.resolvedResource)) adapters)
        ]
    duplicateIdentityDiagnostics =
        [ diagnostic
            "duplicate-adapter-resource-home"
            ( "Checked resource " <> first.resolvedResource.resourceName
                <> " has duplicate adapter homes: "
                <> Text.intercalate ", " (map (renderHaskellType . (.resourceAdapterHomeFamily) . (.resolvedHome)) group)
            )
        | group@(first : _) <- adaptersByResourceName
        , length group > 1
        ]

validateGeneratedNameCollisions :: [ResolvedResourceAdapter] -> [ContractDiagnostic]
validateGeneratedNameCollisions adapters =
    generatedNames
        |> List.sortOn (\(moduleName, generatedName, _) -> (moduleName, generatedName))
        |> List.groupBy (\(leftModule, leftName, _) (rightModule, rightName, _) -> leftModule == rightModule && leftName == rightName)
        |> concatMap collisionGroup
  where
    generatedNames =
        concatMap
            (\adapter ->
                [ (adapter.resolvedOutputModule, adapter.resolvedConstructor, adapter.resolvedHome.resourceAdapterHomeResource)
                , (adapter.resolvedOutputModule, adapter.resolvedMatcher, adapter.resolvedHome.resourceAdapterHomeResource)
                ]
            )
            adapters
    collisionGroup group@((moduleName, generatedName, _) : _)
        | length group > 1 =
            [ diagnostic
                "generated-adapter-name-collision"
                ( "Generated module " <> moduleName <> " has declaration collision " <> generatedName
                    <> " from " <> Text.intercalate ", " (map (renderHaskellType . third) group)
                )
            ]
    collisionGroup _ = []
    third (_, _, value) = value

renderGeneratedModules :: [ResolvedResourceAdapter] -> [GeneratedHaskellModule]
renderGeneratedModules adapters =
    adapters
        |> List.sortOn (\adapter -> (adapter.resolvedOutputModule, adapter.resolvedConstructor))
        |> List.groupBy (\left right -> left.resolvedOutputModule == right.resolvedOutputModule)
        |> map renderGeneratedModule

renderGeneratedModule :: [ResolvedResourceAdapter] -> GeneratedHaskellModule
renderGeneratedModule [] =
    GeneratedHaskellModule "" "" ""
renderGeneratedModule adapters@(first : _) =
    GeneratedHaskellModule
        { generatedModuleName = moduleName
        , generatedModulePath = cs (Text.replace "." "/" moduleName <> ".hs")
        , generatedModuleSource = Text.unlines sourceLines
        }
  where
    moduleName = first.resolvedOutputModule
    orderedAdapters = List.sortOn (.resolvedConstructor) adapters
    exportedNames =
        List.sort (concatMap (\adapter -> [adapter.resolvedConstructor, adapter.resolvedMatcher]) orderedAdapters)
    moduleAliases = sourceModuleAliases orderedAdapters
    sourceLines =
        [ "{-# LANGUAGE TypeApplications #-}"
        , ""
        , "-- @generated by Application.Helper.FrontendContract.Surface.HaskellAdapter.Generator"
        , "-- Do not edit; run `bash ./bin/in-env frontend-surface-adapters`."
        , "module " <> moduleName
        ]
            <> renderExportList exportedNames
            <> [""]
            <> renderImports orderedAdapters moduleAliases
            <> [""]
            <> List.intercalate [""] (map (renderResourceAdapter moduleAliases) orderedAdapters)

renderExportList :: [Text] -> [Text]
renderExportList [] = ["    () where"]
renderExportList (first : rest) =
    ["    ( " <> first]
        <> map ("    , " <>) rest
        <> ["    ) where"]

renderImports :: [ResolvedResourceAdapter] -> Map.Map Text Text -> [Text]
renderImports adapters aliases =
    renderImportList
        "Application.Helper.FrontendContract.Surface.HaskellAdapter.Family"
        ["AdapterFamilySurface"]
        <> renderImportList
            "Application.Helper.FrontendContract.Surface.Resource"
            [ "SurfaceResourceValue"
            , "frontendSurfaceResource"
            , "matchFrontendSurfaceResource"
            ]
        <> renderImportList
            "Application.Helper.FrontendContract.Surface.Values"
            valueImports
        <> conditionalImport needsDay "import Data.Time (Day)"
        <> conditionalImport needsUuid "import qualified Data.UUID as UUID"
        <> ["import IHP.Prelude"]
        <> [ "import qualified " <> sourceModule <> " as " <> alias
           | (sourceModule, alias) <- Map.toAscList aliases
           ]
  where
    fields = concatMap (.resolvedFields) adapters
    valueImports =
        [ if null fields
            then "SurfaceFields (NoSurfaceFields)"
            else "SurfaceFields (NoSurfaceFields, (:&))"
        ]
            <> ["surfaceField" | any ((== RequiredField) . (.fieldPresence) . (.resolvedFieldIR)) fields]
            <> ["surfaceNullableField" | any ((== NullableFieldPresence) . (.fieldPresence) . (.resolvedFieldIR)) fields]
            <> ["surfaceOptionalField" | any ((== OptionalFieldPresence) . (.fieldPresence) . (.resolvedFieldIR)) fields]
    allTypes = concatMap (map (.resolvedFieldType) . (.resolvedFields)) adapters
    needsDay = any sourceTypeContainsDay allTypes
    needsUuid = any sourceTypeContainsUuid allTypes
    conditionalImport True line = [line]
    conditionalImport False _   = []

renderImportList :: Text -> [Text] -> [Text]
renderImportList _ [] = []
renderImportList moduleName [name] = ["import " <> moduleName <> " (" <> name <> ")"]
renderImportList moduleName (first : second : rest) =
    let prefix = "import " <> moduleName <> " ("
        padding = Text.replicate (Text.length prefix) " "
        renderFollowing = \case
            [] -> []
            [lastName] -> [padding <> lastName <> ")"]
            name : names -> (padding <> name <> ",") : renderFollowing names
     in (prefix <> first <> ",") : renderFollowing (second : rest)

sourceModuleAliases :: [ResolvedResourceAdapter] -> Map.Map Text Text
sourceModuleAliases adapters =
    Map.fromList (zip sourceModules aliases)
  where
    sourceModules =
        adapters
            |> concatMap adapterSourceModules
            |> List.nub
            |> List.sort
    aliases =
        case sourceModules of
            [_] -> ["Family"]
            _   -> ["Types" <> tshow index | index <- [1 :: Int ..]]

adapterSourceModules :: ResolvedResourceAdapter -> [Text]
adapterSourceModules adapter =
    adapter.resolvedHome.resourceAdapterHomeFamily.haskellTypeModule
        : adapter.resolvedHome.resourceAdapterHomeResource.haskellTypeModule
        : map (.resolvedFieldMarker.haskellTypeModule) adapter.resolvedFields

renderResourceAdapter :: Map.Map Text Text -> ResolvedResourceAdapter -> [Text]
renderResourceAdapter aliases adapter =
    renderConstructorSignature adapter
        <> renderConstructorBody aliases adapter
        <> [""]
        <> renderMatcherSignature adapter
        <> renderMatcherBody aliases adapter

renderConstructorSignature :: ResolvedResourceAdapter -> [Text]
renderConstructorSignature adapter =
    case adapter.resolvedFields of
        [] -> [adapter.resolvedConstructor <> " :: SurfaceResourceValue"]
        fields ->
            [adapter.resolvedConstructor <> " ::"]
                <> map ("    " <>)
                    ( map ((<> " ->") . renderSourceType . (.resolvedFieldType)) fields
                        <> ["SurfaceResourceValue"]
                    )

renderConstructorBody :: Map.Map Text Text -> ResolvedResourceAdapter -> [Text]
renderConstructorBody aliases adapter =
    [ adapter.resolvedConstructor <> renderArguments adapter.resolvedFields <> " ="
    , "    frontendSurfaceResource"
    , "        @(AdapterFamilySurface " <> qualifyType aliases adapter.resolvedHome.resourceAdapterHomeFamily <> ")"
    , "        @" <> qualifyType aliases adapter.resolvedHome.resourceAdapterHomeResource
    ]
        <> renderFieldsExpression aliases adapter.resolvedFields

renderArguments :: [ResolvedField] -> Text
renderArguments fields =
    case map (haskellValueIdentifier . (.fieldName) . (.resolvedFieldIR)) fields of
        []    -> ""
        names -> " " <> Text.unwords names

renderFieldsExpression :: Map.Map Text Text -> [ResolvedField] -> [Text]
renderFieldsExpression _ [] = ["        NoSurfaceFields"]
renderFieldsExpression aliases (first : rest) =
    [ "        ( " <> renderFieldBuilder aliases first
    ]
        <> ["            :& " <> renderFieldBuilder aliases field | field <- rest]
        <> [ "            :& NoSurfaceFields"
           , "        )"
           ]

renderFieldBuilder :: Map.Map Text Text -> ResolvedField -> Text
renderFieldBuilder aliases field =
    helper <> " @" <> qualifyType aliases field.resolvedFieldMarker <> " " <> argument
  where
    helper = case field.resolvedFieldIR.fieldPresence of
        RequiredField         -> "surfaceField"
        OptionalFieldPresence -> "surfaceOptionalField"
        NullableFieldPresence -> "surfaceNullableField"
    argument = haskellValueIdentifier field.resolvedFieldIR.fieldName

renderMatcherSignature :: ResolvedResourceAdapter -> [Text]
renderMatcherSignature adapter =
    [ adapter.resolvedMatcher <> " :: SurfaceResourceValue -> Maybe "
        <> renderFieldValueTuple (map (.resolvedFieldType) adapter.resolvedFields)
    ]

renderMatcherBody :: Map.Map Text Text -> ResolvedResourceAdapter -> [Text]
renderMatcherBody aliases adapter =
    [ adapter.resolvedMatcher <> " ="
    , "    matchFrontendSurfaceResource"
    , "        @(AdapterFamilySurface " <> qualifyType aliases adapter.resolvedHome.resourceAdapterHomeFamily <> ")"
    , "        @" <> qualifyType aliases adapter.resolvedHome.resourceAdapterHomeResource
    ]

renderFieldValueTuple :: [HaskellSourceType] -> Text
renderFieldValueTuple = \case
    [] -> "()"
    field : rest -> "(" <> renderSourceType field <> ", " <> renderFieldValueTuple rest <> ")"

renderSourceType :: HaskellSourceType -> Text
renderSourceType = \case
    HaskellNamedType named -> case named of
        HaskellTextType -> "Text"
        HaskellIntType  -> "Int"
        HaskellBoolType -> "Bool"
        HaskellUuidType -> "UUID.UUID"
        HaskellDayType  -> "Day"
    HaskellListType inner -> "[" <> renderSourceType inner <> "]"
    HaskellMaybeType inner ->
        "Maybe " <> case inner of
            HaskellMaybeType _ -> "(" <> renderSourceType inner <> ")"
            _                  -> renderSourceType inner

sourceTypeContainsDay :: HaskellSourceType -> Bool
sourceTypeContainsDay = \case
    HaskellNamedType HaskellDayType -> True
    HaskellNamedType _ -> False
    HaskellListType inner -> sourceTypeContainsDay inner
    HaskellMaybeType inner -> sourceTypeContainsDay inner

sourceTypeContainsUuid :: HaskellSourceType -> Bool
sourceTypeContainsUuid = \case
    HaskellNamedType HaskellUuidType -> True
    HaskellNamedType _ -> False
    HaskellListType inner -> sourceTypeContainsUuid inner
    HaskellMaybeType inner -> sourceTypeContainsUuid inner

qualifyType :: Map.Map Text Text -> HaskellTypeMetadata -> Text
qualifyType aliases metadata =
    Map.findWithDefault "MissingSourceModule" metadata.haskellTypeModule aliases
        <> "." <> metadata.haskellTypeName

resourceConstructorName :: Text -> Text
resourceConstructorName typeName =
    let words = wordsFromTypeName typeName
        base = lowerCamel words
     in if listToMaybe (reverse words) == Just "resource"
            then haskellValueIdentifier base
            else haskellValueIdentifier (base <> "Resource")

lowerCamel :: [Text] -> Text
lowerCamel []             = "generated"
lowerCamel (first : rest) = first <> mconcat (map upperFirst rest)

upperFirst :: Text -> Text
upperFirst value =
    case Text.uncons value of
        Nothing            -> value
        Just (first, rest) -> Text.cons (Char.toUpper first) rest

haskellValueIdentifier :: Text -> Text
haskellValueIdentifier value
    | value `elem` haskellKeywords = value <> "_"
    | otherwise = value

haskellKeywords :: [Text]
haskellKeywords =
    [ "anyclass", "as", "by", "case", "class", "data", "default", "deriving"
    , "do", "else", "family", "forall", "foreign", "group", "hiding", "if"
    , "import", "in", "infix", "infixl", "infixr", "instance", "interruptible"
    , "let", "mdo", "module", "newtype", "of", "pattern", "proc", "qualified"
    , "rec", "role", "safe", "static", "stock", "then", "type", "unsafe"
    , "using", "via", "where"
    ]

resourcesForSurface :: SurfaceIR -> [ResourceIR]
resourcesForSurface surface =
    surface.surfaceFragments
        |> concatMap (map (.dependencyResource) . optionResourceDependencies . (.fragmentOptions))
        |> List.nubBy (\left right -> left.resourceMarker == right.resourceMarker && left.resourceFields == right.resourceFields)

surfacesWithMarker :: SurfaceContractIR -> Text -> [SurfaceIR]
surfacesWithMarker contract marker =
    filter ((== marker) . (.surfaceMarker)) contract.contractSurfaces

fieldMarkerNames :: ResourceIR -> [Text]
fieldMarkerNames = map (.fieldMarker) . (.resourceFields)

validateHaskellTypeModule :: Text -> Text -> HaskellTypeMetadata -> [ContractDiagnostic]
validateHaskellTypeModule code label metadata
    | Text.null (Text.strip metadata.haskellTypeModule) =
        [diagnostic code ("Missing Haskell source module for " <> label <> " " <> metadata.haskellTypeName)]
    | Text.null (Text.strip metadata.haskellTypeName) =
        [diagnostic code ("Missing Haskell source type name for " <> label)]
    | otherwise = []

duplicateMetadataDiagnostics ::
    Text ->
    Text ->
    (value -> HaskellTypeMetadata) ->
    [value] ->
    [ContractDiagnostic]
duplicateMetadataDiagnostics code label metadataOf values =
    values
        |> List.sortOn metadataOf
        |> List.groupBy (\left right -> metadataOf left == metadataOf right)
        |> concatMap duplicateGroup
  where
    duplicateGroup group@(first : _)
        | length group > 1 =
            [diagnostic code ("Duplicate " <> label <> " " <> renderHaskellType (metadataOf first))]
    duplicateGroup _ = []

renderHaskellType :: HaskellTypeMetadata -> Text
renderHaskellType metadata = metadata.haskellTypeModule <> "." <> metadata.haskellTypeName

featureModuleOwns :: Text -> Text -> Bool
featureModuleOwns featureModule candidateModule =
    candidateModule == featureModule
        || (featureModule <> ".") `Text.isPrefixOf` candidateModule

diagnostic :: Text -> Text -> ContractDiagnostic
diagnostic diagnosticCode diagnosticMessage =
    ContractDiagnostic { diagnosticCode, diagnosticMessage }

stableDiagnostics :: [ContractDiagnostic] -> [ContractDiagnostic]
stableDiagnostics =
    List.nub . List.sortOn (\value -> (value.diagnosticCode, value.diagnosticMessage))
