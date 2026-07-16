{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE LambdaCase          #-}
{-# LANGUAGE OverloadedRecordDot #-}

-- | Focused checked-IR projection for generated Surface scope and fragment
-- adapters. The shared core owns kind-indexed identity and generation
-- mechanics; this module owns only Live eligibility and source shapes.
module Application.Helper.FrontendContract.Surface.HaskellAdapter.Live
    ( CheckedSurfaceLiveAdapterDeclarations (..)
    , LiveAdapterDeclaration (..)
    , checkedSurfaceLiveAdapterDeclarations
    , generateSurfaceLiveAdapterModules
    , renderSurfaceLiveAdapterModules
    ) where

import Application.Helper.FrontendContract.Naming (wordsFromTypeName)
import Application.Helper.FrontendContract.Surface.ContractIR
import Application.Helper.FrontendContract.Surface.HaskellAdapter.Core
import Application.Helper.FrontendContract.Surface.HaskellAdapter.Family
import Data.Either (fromLeft)
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import qualified Data.Text as Text
import IHP.Prelude

-- | Kind remains present while declarations are selected and resolved. Scope
-- and fragment values are combined only after that checked resolution step.
data CheckedSurfaceLiveAdapterDeclarations = CheckedSurfaceLiveAdapterDeclarations
    { checkedLiveScopeDeclarations    :: ![CheckedAdapterDeclaration 'ScopeAdapterKind ScopeIR]
    , checkedLiveFragmentDeclarations :: ![CheckedAdapterDeclaration 'FragmentAdapterKind FragmentIR]
    }
    deriving (Eq, Show)

-- | The only declaration kinds admitted to the shared Generated.Live output
-- lane. Resource, action, and intent payloads cannot inhabit this type.
data LiveAdapterDeclaration
    = LiveScope !ScopeIR
    | LiveFragment !FragmentIR
    deriving (Eq, Show)

-- | Select the declaration kinds eligible for the generated Live lane directly
-- from checked Surface IR. Every checked Surface owns exactly one runtime scope;
-- passive fragment eligibility comes from the closed Live option.
checkedSurfaceLiveAdapterDeclarations ::
    SurfaceContractIR ->
    SurfaceAdapterRegistry ->
    Either [ContractDiagnostic] CheckedSurfaceLiveAdapterDeclarations
checkedSurfaceLiveAdapterDeclarations contract registry =
    case stableDiagnostics allDiagnostics of
        []          -> Right declarations
        diagnostics -> Left diagnostics
  where
    actorOnlyIdentities =
        [ (home.adapterHomeSurface.haskellTypeName, home.adapterHomeDeclaration.haskellTypeName)
        | exception <- registry.surfaceActorOnlyFragmentAdapters
        , let home = exception.actorOnlyFragmentHome
        ]
    declarations =
        CheckedSurfaceLiveAdapterDeclarations
            { checkedLiveScopeDeclarations =
                [ checkedScopeAdapterDeclaration surface scope
                | surface <- contract.contractSurfaces
                , scope <- surface.surfaceScopes
                ]
            , checkedLiveFragmentDeclarations =
                [ checkedFragmentAdapterDeclaration surface fragment
                | surface <- contract.contractSurfaces
                , fragment <- surface.surfaceFragments
                , fragmentOptionsContainLive fragment.fragmentOptions
                    || (surface.surfaceMarker, fragment.fragmentMarker) `elem` actorOnlyIdentities
                ]
            }
    allDiagnostics =
        validateSurfaceContractIR contract
            <> validateActorOnlyFragments contract registry

generateSurfaceLiveAdapterModules ::
    SurfaceContractIR ->
    SurfaceAdapterRegistry ->
    Either [ContractDiagnostic] [GeneratedHaskellModule]
generateSurfaceLiveAdapterModules contract registry = do
    declarations <- checkedSurfaceLiveAdapterDeclarations contract registry
    let resolvedScopes =
            resolveAdapterGeneration
                scopeAdapterLayout
                contract
                registry.surfaceAdapterFamilies
                registry.surfaceScopeAdapterHomes
                declarations.checkedLiveScopeDeclarations
                scopeGeneratedNames
    let resolvedFragments =
            resolveAdapterGeneration
                fragmentAdapterLayout
                contract
                registry.surfaceAdapterFamilies
                registry.surfaceFragmentAdapterHomes
                declarations.checkedLiveFragmentDeclarations
                fragmentGeneratedNames
    case (resolvedScopes, resolvedFragments) of
        (Right scopes, Right fragments) -> renderSurfaceLiveAdapterModules scopes fragments
        _ ->
            Left
                ( stableDiagnostics
                    (fromLeft [] resolvedScopes <> fromLeft [] resolvedFragments)
                )

-- | Preserve each checked kind until resolution has completed, then close over
-- exactly scopes and fragments for the shared physical Live module.
renderSurfaceLiveAdapterModules ::
    [ResolvedAdapter 'ScopeAdapterKind ScopeIR] ->
    [ResolvedAdapter 'FragmentAdapterKind FragmentIR] ->
    Either [ContractDiagnostic] [GeneratedHaskellModule]
renderSurfaceLiveAdapterModules scopes fragments =
    renderGeneratedAdapterModules
        liveModuleRenderer
        ( map (toRenderableAdapter LiveScope) scopes
            <> map (toRenderableAdapter LiveFragment) fragments
        )

scopeGeneratedNames :: CheckedAdapterDeclaration 'ScopeAdapterKind ScopeIR -> [Text]
scopeGeneratedNames declaration =
    [ constructorName
    , "match" <> upperFirst constructorName
    ]
  where
    constructorName = scopeConstructorName declaration.checkedAdapterDeclarationMarker

fragmentGeneratedNames :: CheckedAdapterDeclaration 'FragmentAdapterKind FragmentIR -> [Text]
fragmentGeneratedNames declaration =
    [ constructorName
    , "match" <> upperFirst constructorName
    ]
  where
    constructorName = fragmentConstructorName declaration.checkedAdapterDeclarationMarker

liveModuleRenderer :: AdapterModuleRenderer LiveAdapterDeclaration
liveModuleRenderer =
    AdapterModuleRenderer
        { adapterRendererLanguagePragmas = ["{-# LANGUAGE TypeApplications #-}"]
        , adapterRendererHeaderLines =
            [ "-- @generated by Application.Helper.FrontendContract.Surface.HaskellAdapter.Generator"
            , "-- Do not edit; run `bash ./bin/in-env frontend-surface-adapters`."
            ]
        , adapterRendererImports = renderLiveImports
        , adapterRendererDeclaration = renderLiveAdapter
        }

renderLiveImports ::
    Map.Map Text Text ->
    [RenderableAdapter LiveAdapterDeclaration] ->
    [Text]
renderLiveImports aliases adapters =
    renderImportList
        "Application.Helper.FrontendContract.Surface.HaskellAdapter.Family"
        ["AdapterFamilySurface"]
        <> renderImportList
            "Application.Helper.FrontendContract.Surface.Live"
            liveImports
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
    hasScopes = any isScope adapters
    hasFragments = any isFragment adapters
    isScope adapter = case adapter.renderableAdapterPayload of
        LiveScope _    -> True
        LiveFragment _ -> False
    isFragment = not . isScope
    liveImports =
        ["SurfaceFragmentKey" | hasFragments]
            <> ["SurfaceScope" | hasScopes]
            <> ["frontendSurfaceFragmentKey" | hasFragments]
            <> ["frontendSurfaceScope" | hasScopes]
            <> ["matchFrontendSurfaceFragmentKey" | hasFragments]
            <> ["matchFrontendSurfaceScope" | hasScopes]
    fields = concatMap (.renderableAdapterFields) adapters
    valueImports =
        [ if null fields
            then "SurfaceFields (NoSurfaceFields)"
            else "SurfaceFields (NoSurfaceFields, (:&))"
        ]
            <> ["surfaceField" | any ((== RequiredField) . (.fieldPresence) . (.resolvedAdapterFieldIR)) fields]
            <> ["surfaceNullableField" | any ((== NullableFieldPresence) . (.fieldPresence) . (.resolvedAdapterFieldIR)) fields]
            <> ["surfaceOptionalField" | any ((== OptionalFieldPresence) . (.fieldPresence) . (.resolvedAdapterFieldIR)) fields]
    allTypes = concatMap (map (.resolvedAdapterFieldType) . (.renderableAdapterFields)) adapters
    needsDay = any sourceTypeContainsDay allTypes
    needsUuid = any sourceTypeContainsUuid allTypes
    conditionalImport True line = [line]
    conditionalImport False _   = []

renderLiveAdapter ::
    Map.Map Text Text ->
    RenderableAdapter LiveAdapterDeclaration ->
    [Text]
renderLiveAdapter aliases adapter =
    renderLiveConstructorSignature resultType adapter
        <> renderLiveConstructorBody builder aliases adapter
        <> [""]
        <> renderLiveMatcherSignature resultType adapter
        <> renderLiveMatcherBody matcher aliases adapter
  where
    (resultType, builder, matcher) = case adapter.renderableAdapterPayload of
        LiveScope _ ->
            ( "SurfaceScope"
            , "frontendSurfaceScope"
            , "matchFrontendSurfaceScope"
            )
        LiveFragment _ ->
            ( "SurfaceFragmentKey"
            , "frontendSurfaceFragmentKey"
            , "matchFrontendSurfaceFragmentKey"
            )

renderLiveConstructorSignature :: Text -> RenderableAdapter LiveAdapterDeclaration -> [Text]
renderLiveConstructorSignature resultType adapter =
    case adapter.renderableAdapterFields of
        [] -> [resolvedConstructor adapter <> " :: " <> resultType]
        fields ->
            [resolvedConstructor adapter <> " ::"]
                <> map ("    " <>)
                    ( map ((<> " ->") . renderHaskellSourceType . (.resolvedAdapterFieldType)) fields
                        <> [resultType]
                    )

renderLiveConstructorBody ::
    Text ->
    Map.Map Text Text ->
    RenderableAdapter LiveAdapterDeclaration ->
    [Text]
renderLiveConstructorBody builder aliases adapter =
    [ resolvedConstructor adapter <> renderAdapterArguments adapter.renderableAdapterFields <> " ="
    , "    " <> builder
    , "        @(AdapterFamilySurface " <> qualifyHaskellType aliases adapter.renderableAdapterHomeFamily <> ")"
    , "        @" <> qualifyHaskellType aliases adapter.renderableAdapterHomeDeclaration
    ]
        <> renderAdapterFieldsExpression aliases adapter.renderableAdapterFields

renderLiveMatcherSignature :: Text -> RenderableAdapter LiveAdapterDeclaration -> [Text]
renderLiveMatcherSignature resultType adapter =
    [ resolvedMatcher adapter <> " :: " <> resultType <> " -> Maybe "
        <> renderAdapterFieldValueTuple (map (.resolvedAdapterFieldType) adapter.renderableAdapterFields)
    ]

renderLiveMatcherBody ::
    Text ->
    Map.Map Text Text ->
    RenderableAdapter LiveAdapterDeclaration ->
    [Text]
renderLiveMatcherBody matcher aliases adapter =
    [ resolvedMatcher adapter <> " ="
    , "    " <> matcher
    , "        @(AdapterFamilySurface " <> qualifyHaskellType aliases adapter.renderableAdapterHomeFamily <> ")"
    , "        @" <> qualifyHaskellType aliases adapter.renderableAdapterHomeDeclaration
    ]

resolvedConstructor :: RenderableAdapter LiveAdapterDeclaration -> Text
resolvedConstructor = resolvedAdapterConstructorName fallback
  where
    fallback adapter = case adapter.renderableAdapterPayload of
        LiveScope _ -> scopeConstructorName adapter.renderableAdapterHomeDeclaration.haskellTypeName
        LiveFragment _ -> fragmentConstructorName adapter.renderableAdapterHomeDeclaration.haskellTypeName

resolvedMatcher :: RenderableAdapter LiveAdapterDeclaration -> Text
resolvedMatcher = resolvedAdapterMatcherName resolvedConstructor

scopeConstructorName :: Text -> Text
scopeConstructorName = liveConstructorName "scope" ["live", "scope"]

fragmentConstructorName :: Text -> Text
fragmentConstructorName = liveConstructorName "fragment" ["live", "fragment"]

liveConstructorName :: Text -> [Text] -> Text -> Text
liveConstructorName declarationSuffix outputSuffix typeName =
    wordsFromTypeName typeName
        |> preserveOrReplaceSuffix
        |> lowerCamel
        |> haskellValueIdentifier
  where
    preserveOrReplaceSuffix words
        | outputSuffix `List.isSuffixOf` words = words
        | [declarationSuffix] `List.isSuffixOf` words =
            take (length words - 1) words <> outputSuffix
        | otherwise = words <> outputSuffix

validateActorOnlyFragments :: SurfaceContractIR -> SurfaceAdapterRegistry -> [ContractDiagnostic]
validateActorOnlyFragments contract registry =
    duplicateDiagnostics <> concatMap validateException registry.surfaceActorOnlyFragmentAdapters
  where
    duplicateDiagnostics =
        registry.surfaceActorOnlyFragmentAdapters
            |> List.sortOn exceptionIdentity
            |> List.groupBy (\left right -> exceptionIdentity left == exceptionIdentity right)
            |> concatMap \case
                group@(first : _)
                    | length group > 1 ->
                        [ diagnostic
                            "duplicate-actor-only-fragment-adapter"
                            ("Duplicate actor-only fragment adapter " <> renderExceptionIdentity first)
                        ]
                _ -> []

    validateException exception =
        reasonDiagnostics <> familyDiagnostics <> ownershipDiagnostics
      where
        home = exception.actorOnlyFragmentHome
        registeredFamily =
            find ((== home.adapterHomeFamily) . (.adapterFamilyType)) registry.surfaceAdapterFamilies
        ownedSurfaces =
            filter ((== home.adapterHomeSurface.haskellTypeName) . (.surfaceMarker)) contract.contractSurfaces
        ownedFragments =
            [ fragment
            | surface <- ownedSurfaces
            , fragment <- surface.surfaceFragments
            , fragment.fragmentMarker == home.adapterHomeDeclaration.haskellTypeName
            ]
        reasonDiagnostics =
            [ diagnostic
                "actor-only-fragment-adapter-reason"
                ("Actor-only fragment adapter " <> renderExceptionIdentity exception <> " must record a non-empty reason")
            | Text.null (Text.strip exception.actorOnlyFragmentReason)
            ]
        familyDiagnostics =
            case registeredFamily of
                Nothing ->
                    [ diagnostic
                        "actor-only-fragment-adapter-family"
                        ("Actor-only fragment adapter " <> renderExceptionIdentity exception <> " references an unregistered adapter family")
                    ]
                Just family
                    | family.adapterFamilySurfaceMarker /= home.adapterHomeSurface ->
                        [ diagnostic
                            "actor-only-fragment-adapter-family"
                            ("Actor-only fragment adapter " <> renderExceptionIdentity exception <> " does not belong to its registered family Surface")
                        ]
                    | otherwise -> []
        ownershipDiagnostics =
            case (ownedSurfaces, ownedFragments) of
                ([_], [fragment]) ->
                    [ diagnostic
                        "redundant-actor-only-fragment-adapter"
                        ("Fragment " <> renderExceptionIdentity exception <> " is already Live and must not have an actor-only exception")
                    | fragmentOptionsContainLive fragment.fragmentOptions
                    ]
                        <> [ diagnostic
                                "actor-only-fragment-adapter-fields"
                                ("Actor-only fragment adapter " <> renderExceptionIdentity exception <> " field marker metadata does not match checked IR")
                           | map (.fieldMarker) fragment.fragmentParams
                                /= map (.haskellTypeName) home.adapterHomeFieldMarkers
                           ]
                ([], _) ->
                    [ diagnostic
                        "actor-only-fragment-adapter-ownership"
                        ("Actor-only fragment adapter " <> renderExceptionIdentity exception <> " references an unregistered Surface")
                    ]
                ([_], []) ->
                    [ diagnostic
                        "actor-only-fragment-adapter-ownership"
                        ("Actor-only fragment adapter " <> renderExceptionIdentity exception <> " references a missing fragment")
                    ]
                _ ->
                    [ diagnostic
                        "actor-only-fragment-adapter-ownership"
                        ("Actor-only fragment adapter " <> renderExceptionIdentity exception <> " is ambiguous in checked IR")
                    ]

exceptionIdentity :: ActorOnlyFragmentAdapterMetadata -> (HaskellTypeMetadata, HaskellTypeMetadata)
exceptionIdentity exception =
    let home = exception.actorOnlyFragmentHome
     in (home.adapterHomeSurface, home.adapterHomeDeclaration)

renderExceptionIdentity :: ActorOnlyFragmentAdapterMetadata -> Text
renderExceptionIdentity exception =
    let home = exception.actorOnlyFragmentHome
     in home.adapterHomeSurface.haskellTypeName <> "/" <> home.adapterHomeDeclaration.haskellTypeName

fragmentOptionsContainLive :: [OptionIR] -> Bool
fragmentOptionsContainLive = any \case
    LiveOption         -> True
    LazyOption options -> fragmentOptionsContainLive options
    _                  -> False

diagnostic :: Text -> Text -> ContractDiagnostic
diagnostic diagnosticCode diagnosticMessage =
    ContractDiagnostic { diagnosticCode, diagnosticMessage }
