{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE KindSignatures      #-}
{-# LANGUAGE LambdaCase          #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications    #-}

-- | Kind-indexed validation, source metadata, and deterministic module
-- rendering shared by the focused Surface resource, live, action, and intent
-- adapter renderers.
--
-- Focused renderers select declarations from checked IR and own their public
-- function shapes. This module owns the mechanics that must not diverge between
-- those projections: typed identities, home/family validation, source types,
-- locality, collisions, import aliases, module layout, and generated-file
-- bookkeeping.
module Application.Helper.FrontendContract.Surface.HaskellAdapter.Core
    ( AdapterIdentity
    , AdapterModuleLayout
    , adapterKindLabel
    , adapterKindSlug
    , AdapterModuleRenderer (..)
    , CheckedAdapterDeclaration
    , checkedAdapterDeclarationMarker
    , checkedAdapterDeclarationName
    , checkedAdapterFields
    , checkedAdapterIdentity
    , checkedAdapterPayload
    , checkedAdapterSurfaceMarker
    , checkedAdapterSurfaceName
    , GeneratedHaskellModule (..)
    , HaskellSourceType
    , HaskellTypeMetadata (..)
    , RenderableAdapter
    , renderableAdapterFields
    , renderableAdapterGeneratedNames
    , renderableAdapterHomeDeclaration
    , renderableAdapterHomeFamily
    , renderableAdapterOutputModule
    , renderableAdapterPayload
    , ResolvedAdapter
    , resolvedAdapterDeclaration
    , resolvedAdapterFields
    , resolvedAdapterGeneratedNames
    , resolvedAdapterHome
    , resolvedAdapterOutputModule
    , ResolvedAdapterField
    , resolvedAdapterFieldIR
    , resolvedAdapterFieldMarker
    , resolvedAdapterFieldType
    , SurfaceAdapterFamilyMetadata (..)
    , SurfaceAdapterHomeMetadata (..)
    , SurfaceAdapterKind (..)
    , actionAdapterIdentity
    , actionAdapterLayout
    , checkedActionAdapterDeclaration
    , checkedFragmentAdapterDeclaration
    , checkedIntentAdapterDeclaration
    , checkedResourceAdapterDeclaration
    , checkedScopeAdapterDeclaration
    , adapterFacadeModuleName
    , adapterGeneratedModuleName
    , adapterIdentityCollisionKey
    , fragmentAdapterIdentity
    , fragmentAdapterLayout
    , haskellTypeMetadata
    , haskellValueIdentifier
    , intentAdapterIdentity
    , intentAdapterLayout
    , lowerCamel
    , mapCheckedAdapterPayload
    , prepareResolvedAdapter
    , qualifyHaskellType
    , renderAdapterArguments
    , renderAdapterFieldBuilder
    , renderAdapterFieldValueTuple
    , renderAdapterFieldsExpression
    , renderGeneratedAdapterModules
    , renderHaskellSourceType
    , renderImportList
    , resolveAdapterGeneration
    , resolvedAdapterConstructorName
    , resolvedAdapterMatcherName
    , resourceAdapterIdentity
    , resourceAdapterLayout
    , scopeAdapterIdentity
    , scopeAdapterLayout
    , sourceTypeContainsDay
    , sourceTypeContainsUuid
    , stableDiagnostics
    , toRenderableAdapter
    , upperFirst
    ) where

import Application.Helper.FrontendContract.Naming (wordsFromTypeName)
import Application.Helper.FrontendContract.Surface.ContractIR
import Application.Helper.FrontendContract.Wire.Carrier (HaskellWireSource (..),
                                                         haskellWireSource)
import qualified Data.Char as Char
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import qualified Data.Text as Text
import Data.Typeable (Typeable, tyConModule, tyConName, typeRep, typeRepTyCon)
import IHP.Prelude

-- | Declaration kind is part of the Haskell type of every home and checked
-- identity. Marker/name reuse across constructors is therefore valid by
-- construction, while collisions within one focused renderer remain checked.
data SurfaceAdapterKind
    = ResourceAdapterKind
    | ScopeAdapterKind
    | FragmentAdapterKind
    | ActionAdapterKind
    | IntentAdapterKind

-- | The protocol identity used for completeness and duplicate-home checks.
-- The constructor stays private so each smart constructor below fixes the
-- identity parts to the existing checked/runtime semantics for that kind.
newtype AdapterIdentity (kind :: SurfaceAdapterKind) = AdapterIdentity [Text]
    deriving (Eq, Ord, Show)

resourceAdapterIdentity :: Text -> AdapterIdentity 'ResourceAdapterKind
resourceAdapterIdentity resourceName = AdapterIdentity [resourceName]

-- Runtime scope transport identity is the Surface identity, not the reflected
-- scope marker/name.
scopeAdapterIdentity :: Text -> AdapterIdentity 'ScopeAdapterKind
scopeAdapterIdentity surfaceName = AdapterIdentity [surfaceName]

fragmentAdapterIdentity :: Text -> Text -> AdapterIdentity 'FragmentAdapterKind
fragmentAdapterIdentity surfaceName fragmentName = AdapterIdentity [surfaceName, fragmentName]

actionAdapterIdentity :: Text -> Text -> AdapterIdentity 'ActionAdapterKind
actionAdapterIdentity surfaceName actionName = AdapterIdentity [surfaceName, actionName]

intentAdapterIdentity :: Text -> Text -> AdapterIdentity 'IntentAdapterKind
intentAdapterIdentity surfaceName intentName = AdapterIdentity [surfaceName, intentName]

-- | Fixed output/facade layout for one declaration kind. Scope and fragment
-- adapters deliberately share the Live namespace and facade; action and intent
-- remain in distinct modules even when their reflected markers/names match.
data AdapterModuleLayout (kind :: SurfaceAdapterKind) = AdapterModuleLayout
    { adapterKindSlug        :: !Text
    , adapterKindLabel       :: !Text
    , adapterGeneratedSuffix :: !Text
    , adapterFacadeSuffix    :: !Text
    }

resourceAdapterLayout :: AdapterModuleLayout 'ResourceAdapterKind
resourceAdapterLayout =
    AdapterModuleLayout
        { adapterKindSlug = "resource"
        , adapterKindLabel = "Resource"
        , adapterGeneratedSuffix = "Generated.Resource"
        , adapterFacadeSuffix = "Resource"
        }

scopeAdapterLayout :: AdapterModuleLayout 'ScopeAdapterKind
scopeAdapterLayout =
    AdapterModuleLayout
        { adapterKindSlug = "scope"
        , adapterKindLabel = "Scope"
        , adapterGeneratedSuffix = "Generated.Live"
        , adapterFacadeSuffix = "Live"
        }

fragmentAdapterLayout :: AdapterModuleLayout 'FragmentAdapterKind
fragmentAdapterLayout =
    AdapterModuleLayout
        { adapterKindSlug = "fragment"
        , adapterKindLabel = "Fragment"
        , adapterGeneratedSuffix = "Generated.Live"
        , adapterFacadeSuffix = "Live"
        }

actionAdapterLayout :: AdapterModuleLayout 'ActionAdapterKind
actionAdapterLayout =
    AdapterModuleLayout
        { adapterKindSlug = "action"
        , adapterKindLabel = "Action"
        , adapterGeneratedSuffix = "Generated.Action"
        , adapterFacadeSuffix = "Action"
        }

intentAdapterLayout :: AdapterModuleLayout 'IntentAdapterKind
intentAdapterLayout =
    AdapterModuleLayout
        { adapterKindSlug = "intent"
        , adapterKindLabel = "Intent"
        , adapterGeneratedSuffix = "Generated.Intent"
        , adapterFacadeSuffix = "Intent"
        }

adapterGeneratedModuleName :: AdapterModuleLayout kind -> HaskellTypeMetadata -> Text
adapterGeneratedModuleName layout surfaceMarker =
    surfaceMarker.haskellTypeModule <> "." <> layout.adapterGeneratedSuffix

adapterFacadeModuleName :: AdapterModuleLayout kind -> HaskellTypeMetadata -> Text
adapterFacadeModuleName layout surfaceMarker =
    surfaceMarker.haskellTypeModule <> "." <> layout.adapterFacadeSuffix

-- | Comparable diagnostic key used by tests and validation. Including the kind
-- slug makes cross-kind marker/name reuse distinct without changing the
-- underlying runtime identity parts.
adapterIdentityCollisionKey :: AdapterModuleLayout kind -> AdapterIdentity kind -> Text
adapterIdentityCollisionKey layout (AdapterIdentity parts) =
    layout.adapterKindSlug <> ":" <> Text.intercalate "/" parts

data HaskellTypeMetadata = HaskellTypeMetadata
    { haskellTypeModule :: !Text
    , haskellTypeName   :: !Text
    }
    deriving (Eq, Ord, Show)

data SurfaceAdapterFamilyMetadata = SurfaceAdapterFamilyMetadata
    { adapterFamilyType          :: !HaskellTypeMetadata
    , adapterFamilySurfaceMarker :: !HaskellTypeMetadata
    }
    deriving (Eq, Show)

-- | Typeable metadata for one typed home. The kind index prevents a resource,
-- scope, fragment, action, or intent home from satisfying another renderer.
data SurfaceAdapterHomeMetadata (kind :: SurfaceAdapterKind) = SurfaceAdapterHomeMetadata
    { adapterHomeFamily       :: !HaskellTypeMetadata
    , adapterHomeSurface      :: !HaskellTypeMetadata
    , adapterHomeDeclaration  :: !HaskellTypeMetadata
    , adapterHomeFieldMarkers :: ![HaskellTypeMetadata]
    }
    deriving (Eq, Show)

-- | One declaration selected by a focused renderer from checked Surface IR.
-- The core never switches on reflected names to recover declaration semantics.
data CheckedAdapterDeclaration (kind :: SurfaceAdapterKind) payload = CheckedAdapterDeclaration
    { checkedAdapterIdentity          :: !(AdapterIdentity kind)
    , checkedAdapterSurfaceMarker     :: !Text
    , checkedAdapterSurfaceName       :: !Text
    , checkedAdapterDeclarationMarker :: !Text
    , checkedAdapterDeclarationName   :: !Text
    , checkedAdapterFields            :: ![FieldIR]
    , checkedAdapterPayload           :: !payload
    }
    deriving (Eq, Show)

-- | Normalize one checked resource occurrence directly from its owning
-- Surface. Shared resource identity intentionally omits that occurrence's
-- Surface while all declaration metadata remains IR-derived.
checkedResourceAdapterDeclaration ::
    SurfaceIR ->
    ResourceIR ->
    CheckedAdapterDeclaration 'ResourceAdapterKind ResourceIR
checkedResourceAdapterDeclaration surface resource =
    CheckedAdapterDeclaration
        { checkedAdapterIdentity = resourceAdapterIdentity resource.resourceName
        , checkedAdapterSurfaceMarker = surface.surfaceMarker
        , checkedAdapterSurfaceName = surface.surfaceName
        , checkedAdapterDeclarationMarker = resource.resourceMarker
        , checkedAdapterDeclarationName = resource.resourceName
        , checkedAdapterFields = resource.resourceFields
        , checkedAdapterPayload = resource
        }

-- | Normalize one checked scope directly from its owning Surface. Callers
-- cannot choose identity, names, or fields independently of the checked IR.
checkedScopeAdapterDeclaration ::
    SurfaceIR ->
    ScopeIR ->
    CheckedAdapterDeclaration 'ScopeAdapterKind ScopeIR
checkedScopeAdapterDeclaration surface scope =
    CheckedAdapterDeclaration
        { checkedAdapterIdentity = scopeAdapterIdentity surface.surfaceName
        , checkedAdapterSurfaceMarker = surface.surfaceMarker
        , checkedAdapterSurfaceName = surface.surfaceName
        , checkedAdapterDeclarationMarker = scope.scopeMarker
        , checkedAdapterDeclarationName = scope.scopeName
        , checkedAdapterFields = scope.scopeFields
        , checkedAdapterPayload = scope
        }

-- | Normalize one checked fragment directly from its owning Surface. Fragment
-- identity always includes that Surface and the checked fragment declaration.
checkedFragmentAdapterDeclaration ::
    SurfaceIR ->
    FragmentIR ->
    CheckedAdapterDeclaration 'FragmentAdapterKind FragmentIR
checkedFragmentAdapterDeclaration surface fragment =
    CheckedAdapterDeclaration
        { checkedAdapterIdentity = fragmentAdapterIdentity surface.surfaceName fragment.fragmentName
        , checkedAdapterSurfaceMarker = surface.surfaceMarker
        , checkedAdapterSurfaceName = surface.surfaceName
        , checkedAdapterDeclarationMarker = fragment.fragmentMarker
        , checkedAdapterDeclarationName = fragment.fragmentName
        , checkedAdapterFields = fragment.fragmentParams
        , checkedAdapterPayload = fragment
        }

checkedActionAdapterDeclaration ::
    SurfaceIR ->
    HtmxActionIR ->
    CheckedAdapterDeclaration 'ActionAdapterKind HtmxActionIR
checkedActionAdapterDeclaration surface action =
    CheckedAdapterDeclaration
        { checkedAdapterIdentity = actionAdapterIdentity surface.surfaceName action.htmxActionName
        , checkedAdapterSurfaceMarker = surface.surfaceMarker
        , checkedAdapterSurfaceName = surface.surfaceName
        , checkedAdapterDeclarationMarker = action.htmxActionMarker
        , checkedAdapterDeclarationName = action.htmxActionName
        , checkedAdapterFields = action.htmxActionFields
        , checkedAdapterPayload = action
        }

checkedIntentAdapterDeclaration ::
    SurfaceIR ->
    IntentIR ->
    CheckedAdapterDeclaration 'IntentAdapterKind IntentIR
checkedIntentAdapterDeclaration surface intent =
    CheckedAdapterDeclaration
        { checkedAdapterIdentity = intentAdapterIdentity surface.surfaceName intent.intentName
        , checkedAdapterSurfaceMarker = surface.surfaceMarker
        , checkedAdapterSurfaceName = surface.surfaceName
        , checkedAdapterDeclarationMarker = intent.intentMarker
        , checkedAdapterDeclarationName = intent.intentName
        , checkedAdapterFields = intent.intentFields
        , checkedAdapterPayload = intent
        }

-- | Attach focused-renderer data without reopening checked identity, names, or
-- fields. This is the only payload conversion before kind-indexed resolution.
mapCheckedAdapterPayload ::
    (sourcePayload -> renderedPayload) ->
    CheckedAdapterDeclaration kind sourcePayload ->
    CheckedAdapterDeclaration kind renderedPayload
mapCheckedAdapterPayload transform declaration =
    declaration { checkedAdapterPayload = transform declaration.checkedAdapterPayload }

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
    | HaskellClosedType !HaskellTypeMetadata
    deriving (Eq, Show)

data ResolvedAdapterField = ResolvedAdapterField
    { resolvedAdapterFieldIR     :: !FieldIR
    , resolvedAdapterFieldMarker :: !HaskellTypeMetadata
    , resolvedAdapterFieldType   :: !HaskellSourceType
    }
    deriving (Eq, Show)

data ResolvedAdapter (kind :: SurfaceAdapterKind) payload = ResolvedAdapter
    { resolvedAdapterHome           :: !(SurfaceAdapterHomeMetadata kind)
    , resolvedAdapterDeclaration    :: !(CheckedAdapterDeclaration kind payload)
    , resolvedAdapterOutputModule   :: !Text
    , resolvedAdapterGeneratedNames :: ![Text]
    , resolvedAdapterFields         :: ![ResolvedAdapterField]
    }
    deriving (Eq, Show)

-- | Kind-erased input to deterministic module rendering. Resolution remains
-- kind-indexed, while this value lets one focused renderer combine declaration
-- kinds that intentionally share a physical module (scope and fragment in
-- @Generated.Live@). Generated-name collisions are therefore checked across
-- the complete output module, not only within each typed home list.
data RenderableAdapter payload = RenderableAdapter
    { renderableAdapterHomeFamily      :: !HaskellTypeMetadata
    , renderableAdapterHomeDeclaration :: !HaskellTypeMetadata
    , renderableAdapterOutputModule    :: !Text
    , renderableAdapterGeneratedNames  :: ![Text]
    , renderableAdapterFields          :: ![ResolvedAdapterField]
    , renderableAdapterPayload         :: !payload
    }

-- | Reuse one fully validated, source-resolved adapter while attaching the
-- focused renderer payload and generated operation names. Request inventory
-- resolution uses this to avoid a second home/source validation projection.
prepareResolvedAdapter ::
    (sourcePayload -> renderedPayload) ->
    (CheckedAdapterDeclaration kind renderedPayload -> [Text]) ->
    ResolvedAdapter kind sourcePayload ->
    ResolvedAdapter kind renderedPayload
prepareResolvedAdapter transform generatedNames adapter =
    adapter
        { resolvedAdapterDeclaration = declaration
        , resolvedAdapterGeneratedNames = generatedNames declaration
        }
  where
    declaration = mapCheckedAdapterPayload transform adapter.resolvedAdapterDeclaration

toRenderableAdapter ::
    (sourcePayload -> renderedPayload) ->
    ResolvedAdapter kind sourcePayload ->
    RenderableAdapter renderedPayload
toRenderableAdapter transform adapter =
    RenderableAdapter
        { renderableAdapterHomeFamily = adapter.resolvedAdapterHome.adapterHomeFamily
        , renderableAdapterHomeDeclaration = adapter.resolvedAdapterHome.adapterHomeDeclaration
        , renderableAdapterOutputModule = adapter.resolvedAdapterOutputModule
        , renderableAdapterGeneratedNames = adapter.resolvedAdapterGeneratedNames
        , renderableAdapterFields = adapter.resolvedAdapterFields
        , renderableAdapterPayload = transform adapter.resolvedAdapterDeclaration.checkedAdapterPayload
        }

-- | One repository-relative generated Haskell module. Callers write these
-- values only after the complete focused registry validates successfully.
data GeneratedHaskellModule = GeneratedHaskellModule
    { generatedModuleName   :: !Text
    , generatedModulePath   :: !FilePath
    , generatedModuleSource :: !Text
    }
    deriving (Eq, Show)

-- | Focused renderers provide only their function-level imports and bodies.
-- Canonical module grouping, ordering, exports, aliases, cross-kind generated
-- name collisions, source headers, paths, and whitespace remain shared here.
data AdapterModuleRenderer payload = AdapterModuleRenderer
    { adapterRendererLanguagePragmas :: ![Text]
    , adapterRendererHeaderLines     :: ![Text]
    , adapterRendererImports         :: Map.Map Text Text -> [RenderableAdapter payload] -> [Text]
    , adapterRendererDeclaration     :: Map.Map Text Text -> RenderableAdapter payload -> [Text]
    }

resolveAdapterGeneration ::
    AdapterModuleLayout kind ->
    SurfaceContractIR ->
    [SurfaceAdapterFamilyMetadata] ->
    [SurfaceAdapterHomeMetadata kind] ->
    [CheckedAdapterDeclaration kind payload] ->
    (CheckedAdapterDeclaration kind payload -> [Text]) ->
    Either [ContractDiagnostic] [ResolvedAdapter kind payload]
resolveAdapterGeneration layout contract families homes declarations generatedNames =
    case stableDiagnostics allDiagnostics of
        []          -> Right resolvedAdapters
        diagnostics -> Left diagnostics
  where
    contractDiagnostics = validateSurfaceContractIR contract
    familyDiagnostics = validateFamilies contract families
    (homeDiagnostics, ownedAdapters) =
        unzip (map (resolveAdapterHome layout contract families declarations generatedNames) homes)
    resolvedOwnedAdapters = catMaybes ownedAdapters
    homeCoverageDiagnostics =
        validateAdapterHomeCoverage layout declarations resolvedOwnedAdapters
    (sourceDiagnostics, resolvedAdapters) =
        unzip (map (resolveAdapterSourceTypes layout) resolvedOwnedAdapters)
            |> second catMaybes
    collisionDiagnostics = validateResolvedGeneratedNameCollisions resolvedAdapters
    allDiagnostics =
        contractDiagnostics
            <> familyDiagnostics
            <> concat homeDiagnostics
            <> homeCoverageDiagnostics
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

resolveAdapterHome ::
    AdapterModuleLayout kind ->
    SurfaceContractIR ->
    [SurfaceAdapterFamilyMetadata] ->
    [CheckedAdapterDeclaration kind payload] ->
    (CheckedAdapterDeclaration kind payload -> [Text]) ->
    SurfaceAdapterHomeMetadata kind ->
    ([ContractDiagnostic], Maybe (ResolvedAdapter kind payload))
resolveAdapterHome layout contract families declarations generatedNames home =
    case (registeredFamily, ownedSurface, ownedDeclarations) of
        (Just adapterFamily, [_], [declaration])
            | adapterFamily.adapterFamilySurfaceMarker /= home.adapterHomeSurface ->
                ( commonDiagnostics
                    <> [ diagnostic
                            ("adapter-" <> layout.adapterKindSlug <> "-home-family-mismatch")
                            ( layout.adapterKindLabel <> " home " <> renderHaskellType home.adapterHomeDeclaration
                                <> " records Surface " <> renderHaskellType home.adapterHomeSurface
                                <> " but family " <> renderHaskellType home.adapterHomeFamily
                                <> " associates " <> renderHaskellType adapterFamily.adapterFamilySurfaceMarker
                            )
                       ]
                , Nothing
                )
            | fieldMarkerNames declaration /= map (.haskellTypeName) home.adapterHomeFieldMarkers ->
                ( commonDiagnostics
                    <> [ diagnostic
                            ("adapter-" <> layout.adapterKindSlug <> "-home-field-metadata")
                            ( layout.adapterKindLabel <> " home " <> renderHaskellType home.adapterHomeDeclaration
                                <> " field marker metadata does not match checked "
                                <> layout.adapterKindSlug <> " " <> declaration.checkedAdapterDeclarationName
                            )
                       ]
                , Nothing
                )
            | otherwise ->
                ( commonDiagnostics
                , Just ResolvedAdapter
                    { resolvedAdapterHome = home
                    , resolvedAdapterDeclaration = declaration
                    , resolvedAdapterOutputModule = adapterGeneratedModuleName layout home.adapterHomeSurface
                    , resolvedAdapterGeneratedNames = generatedNames declaration
                    , resolvedAdapterFields =
                        zipWith unresolvedField declaration.checkedAdapterFields home.adapterHomeFieldMarkers
                    }
                )
          where
            unresolvedField field marker =
                ResolvedAdapterField field marker (HaskellNamedType HaskellTextType)
        _ -> (commonDiagnostics <> ownershipDiagnostics, Nothing)
  where
    registeredFamily =
        find ((== home.adapterHomeFamily) . (.adapterFamilyType)) families
    ownedSurface = surfacesWithMarker contract home.adapterHomeSurface.haskellTypeName
    ownedDeclarations =
        declarations
            |> filter
                (\declaration ->
                    declaration.checkedAdapterSurfaceMarker == home.adapterHomeSurface.haskellTypeName
                        && declaration.checkedAdapterDeclarationMarker == home.adapterHomeDeclaration.haskellTypeName
                )
    commonDiagnostics =
        validateHaskellTypeModule "adapter-family-source-module" "adapter family" home.adapterHomeFamily
            <> validateHaskellTypeModule "adapter-surface-source-module" "adapter Surface" home.adapterHomeSurface
            <> validateHaskellTypeModule
                ("adapter-" <> layout.adapterKindSlug <> "-source-module")
                ("adapter " <> layout.adapterKindSlug)
                home.adapterHomeDeclaration
            <> concatMap (validateHaskellTypeModule "adapter-field-source-module" "adapter field") home.adapterHomeFieldMarkers
            <> concatMap validateGeneratedImportLocality generatedImports
    generatedImports =
        ("adapter family", home.adapterHomeFamily)
            : (layout.adapterKindSlug <> " marker", home.adapterHomeDeclaration)
            : map (\marker -> ("field marker", marker)) home.adapterHomeFieldMarkers
    validateGeneratedImportLocality (label, importedType)
        | featureModuleOwns home.adapterHomeSurface.haskellTypeModule importedType.haskellTypeModule = []
        | otherwise =
            [ diagnostic
                "adapter-import-locality"
                ( layout.adapterKindLabel <> " " <> renderHaskellType home.adapterHomeDeclaration
                    <> " would import " <> label <> " " <> renderHaskellType importedType
                    <> " outside owning feature module tree " <> home.adapterHomeSurface.haskellTypeModule
                )
            ]
    ownershipDiagnostics =
        missingFamilyDiagnostics <> missingSurfaceDiagnostics <> missingDeclarationDiagnostics
    missingFamilyDiagnostics =
        case registeredFamily of
            Nothing ->
                [ diagnostic
                    "unregistered-adapter-family"
                    ( layout.adapterKindLabel <> " home " <> renderHaskellType home.adapterHomeDeclaration
                        <> " references unregistered adapter family " <> renderHaskellType home.adapterHomeFamily
                    )
                ]
            Just _ -> []
    missingSurfaceDiagnostics =
        case ownedSurface of
            [] ->
                [ diagnostic
                    ("adapter-" <> layout.adapterKindSlug <> "-home-ownership")
                    ( "Adapter family " <> renderHaskellType home.adapterHomeFamily
                        <> " has no checked Surface " <> renderHaskellType home.adapterHomeSurface
                        <> " for " <> layout.adapterKindSlug <> " " <> renderHaskellType home.adapterHomeDeclaration
                    )
                ]
            [_] -> []
            _ ->
                [ diagnostic
                    ("adapter-" <> layout.adapterKindSlug <> "-home-ownership")
                    ( "Adapter family " <> renderHaskellType home.adapterHomeFamily
                        <> " has ambiguous checked Surface " <> renderHaskellType home.adapterHomeSurface
                        <> " for " <> layout.adapterKindSlug <> " " <> renderHaskellType home.adapterHomeDeclaration
                    )
                ]
    missingDeclarationDiagnostics =
        case ownedSurface of
            [_]
                | null ownedDeclarations ->
                    [ diagnostic
                        ("adapter-" <> layout.adapterKindSlug <> "-home-ownership")
                        ( "Adapter family " <> renderHaskellType home.adapterHomeFamily
                            <> " Surface " <> renderHaskellType home.adapterHomeSurface
                            <> " does not own " <> layout.adapterKindSlug <> " " <> renderHaskellType home.adapterHomeDeclaration
                        )
                    ]
                | length ownedDeclarations > 1 ->
                    [ diagnostic
                        ("adapter-" <> layout.adapterKindSlug <> "-home-ownership")
                        ( "Adapter family " <> renderHaskellType home.adapterHomeFamily
                            <> " Surface " <> renderHaskellType home.adapterHomeSurface
                            <> " has ambiguous " <> layout.adapterKindSlug <> " " <> renderHaskellType home.adapterHomeDeclaration
                        )
                    ]
            _ -> []

resolveAdapterSourceTypes ::
    AdapterModuleLayout kind ->
    ResolvedAdapter kind payload ->
    ([ContractDiagnostic], Maybe (ResolvedAdapter kind payload))
resolveAdapterSourceTypes layout adapter =
    case partitionEithers (map resolveField adapter.resolvedAdapterFields) of
        ([], fields)     -> ([], Just adapter { resolvedAdapterFields = fields })
        (diagnostics, _) -> (diagnostics, Nothing)
  where
    declaration = adapter.resolvedAdapterDeclaration
    resolveField field =
        case sourceTypeForField field.resolvedAdapterFieldIR of
            Right sourceType -> Right field { resolvedAdapterFieldType = sourceType }
            Left unsupported ->
                Left $ diagnostic
                    "unsupported-generated-source-type"
                    ( layout.adapterKindLabel <> " " <> declaration.checkedAdapterSurfaceName
                        <> "/" <> declaration.checkedAdapterDeclarationName
                        <> " field " <> diagnosticFieldName field
                        <> " has unsupported generated Haskell source type " <> unsupported
                    )

diagnosticFieldName :: ResolvedAdapterField -> Text
diagnosticFieldName field =
    Text.intercalate "-" (wordsFromTypeName field.resolvedAdapterFieldMarker.haskellTypeName)

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
    HaskellClosedSource sourceModule sourceType ->
        Right (HaskellNamedType (HaskellClosedType HaskellTypeMetadata
            { haskellTypeModule = sourceModule
            , haskellTypeName = sourceType
            }))
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
    HaskellClosedSource sourceModule sourceType -> sourceModule <> "." <> sourceType
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
            HaskellClosedSource {} -> haskellWireSourceLabel source
            HaskellJsonSource -> haskellWireSourceLabel source
            HaskellSurfaceScopeSource -> haskellWireSourceLabel source
            HaskellSurfaceFragmentKeySource -> haskellWireSourceLabel source
            _ -> "(" <> haskellWireSourceLabel source <> ")"

validateAdapterHomeCoverage ::
    AdapterModuleLayout kind ->
    [CheckedAdapterDeclaration kind payload] ->
    [ResolvedAdapter kind payload] ->
    [ContractDiagnostic]
validateAdapterHomeCoverage layout declarations adapters =
    missingHomeDiagnostics <> duplicateIdentityDiagnostics
  where
    checkedDeclarations =
        declarations
            |> List.sortOn (adapterIdentityCollisionKey layout . (.checkedAdapterIdentity))
            |> List.groupBy
                (\left right -> left.checkedAdapterIdentity == right.checkedAdapterIdentity)
            |> mapMaybe listToMaybe
    adaptersByIdentity =
        adapters
            |> List.sortOn
                (adapterIdentityCollisionKey layout . (.checkedAdapterIdentity) . (.resolvedAdapterDeclaration))
            |> List.groupBy
                (\left right ->
                    left.resolvedAdapterDeclaration.checkedAdapterIdentity
                        == right.resolvedAdapterDeclaration.checkedAdapterIdentity
                )
    missingHomeDiagnostics =
        [ diagnostic
            ("missing-adapter-" <> layout.adapterKindSlug <> "-home")
            ( "Checked " <> layout.adapterKindSlug <> " " <> declaration.checkedAdapterDeclarationName
                <> " has no generated adapter home"
            )
        | declaration <- checkedDeclarations
        , not
            ( any
                (\adapter ->
                    adapter.resolvedAdapterDeclaration.checkedAdapterIdentity
                        == declaration.checkedAdapterIdentity
                )
                adapters
            )
        ]
    duplicateIdentityDiagnostics =
        [ diagnostic
            ("duplicate-adapter-" <> layout.adapterKindSlug <> "-home")
            ( "Checked " <> layout.adapterKindSlug <> " "
                <> first.resolvedAdapterDeclaration.checkedAdapterDeclarationName
                <> " has duplicate adapter homes: "
                <> Text.intercalate ", " (map (renderHaskellType . (.adapterHomeFamily) . (.resolvedAdapterHome)) group)
            )
        | group@(first : _) <- adaptersByIdentity
        , length group > 1
        ]

validateResolvedGeneratedNameCollisions :: [ResolvedAdapter kind payload] -> [ContractDiagnostic]
validateResolvedGeneratedNameCollisions adapters =
    validateGeneratedNameCollisionRows
        [ (adapter.resolvedAdapterOutputModule, generatedName, adapter.resolvedAdapterHome.adapterHomeDeclaration)
        | adapter <- adapters
        , generatedName <- adapter.resolvedAdapterGeneratedNames
        ]

validateRenderableGeneratedNameCollisions :: [RenderableAdapter payload] -> [ContractDiagnostic]
validateRenderableGeneratedNameCollisions adapters =
    validateGeneratedNameCollisionRows
        [ (adapter.renderableAdapterOutputModule, generatedName, adapter.renderableAdapterHomeDeclaration)
        | adapter <- adapters
        , generatedName <- adapter.renderableAdapterGeneratedNames
        ]

validateGeneratedNameCollisionRows :: [(Text, Text, HaskellTypeMetadata)] -> [ContractDiagnostic]
validateGeneratedNameCollisionRows generatedNames =
    generatedNames
        |> List.sortOn (\(moduleName, generatedName, _) -> (moduleName, generatedName))
        |> List.groupBy
            (\(leftModule, leftName, _) (rightModule, rightName, _) ->
                leftModule == rightModule && leftName == rightName
            )
        |> concatMap collisionGroup
  where
    collisionGroup group@((moduleName, generatedName, _) : _)
        | length group > 1 =
            [ diagnostic
                "generated-adapter-name-collision"
                ( "Generated module " <> moduleName <> " has declaration collision " <> generatedName
                    <> " from " <> Text.intercalate ", " (map (renderHaskellType . declarationMetadata) group)
                )
            ]
    collisionGroup _ = []
    declarationMetadata (_, _, metadata) = metadata

renderGeneratedAdapterModules ::
    AdapterModuleRenderer payload ->
    [RenderableAdapter payload] ->
    Either [ContractDiagnostic] [GeneratedHaskellModule]
renderGeneratedAdapterModules renderer adapters =
    case stableDiagnostics (validateRenderableGeneratedNameCollisions adapters) of
        [] ->
            Right
                ( adapters
                    |> List.sortOn
                        (\adapter ->
                            ( adapter.renderableAdapterOutputModule
                            , adapter.renderableAdapterGeneratedNames
                            )
                        )
                    |> List.groupBy
                        (\left right ->
                            left.renderableAdapterOutputModule == right.renderableAdapterOutputModule
                        )
                    |> map (renderGeneratedAdapterModule renderer)
                )
        diagnostics -> Left diagnostics

renderGeneratedAdapterModule ::
    AdapterModuleRenderer payload ->
    [RenderableAdapter payload] ->
    GeneratedHaskellModule
renderGeneratedAdapterModule _ [] =
    GeneratedHaskellModule "" "" ""
renderGeneratedAdapterModule renderer adapters@(first : _) =
    GeneratedHaskellModule
        { generatedModuleName = moduleName
        , generatedModulePath = cs (Text.replace "." "/" moduleName <> ".hs")
        , generatedModuleSource = Text.unlines sourceLines
        }
  where
    moduleName = first.renderableAdapterOutputModule
    orderedAdapters = List.sortOn (.renderableAdapterGeneratedNames) adapters
    exportedNames = List.sort (concatMap (.renderableAdapterGeneratedNames) orderedAdapters)
    moduleAliases = sourceModuleAliases orderedAdapters
    sourceLines =
        renderer.adapterRendererLanguagePragmas
            <> [""]
            <> renderer.adapterRendererHeaderLines
            <> ["module " <> moduleName]
            <> renderExportList exportedNames
            <> [""]
            <> renderer.adapterRendererImports moduleAliases orderedAdapters
            <> [""]
            <> List.intercalate [""] (map (renderer.adapterRendererDeclaration moduleAliases) orderedAdapters)

renderExportList :: [Text] -> [Text]
renderExportList [] = ["    () where"]
renderExportList (first : rest) =
    ["    ( " <> first]
        <> map ("    , " <>) rest
        <> ["    ) where"]

sourceModuleAliases :: [RenderableAdapter payload] -> Map.Map Text Text
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

adapterSourceModules :: RenderableAdapter payload -> [Text]
adapterSourceModules adapter =
    adapter.renderableAdapterHomeFamily.haskellTypeModule
        : adapter.renderableAdapterHomeDeclaration.haskellTypeModule
        : map (.resolvedAdapterFieldMarker.haskellTypeModule) adapter.renderableAdapterFields
        <> concatMap (sourceTypeModules . (.resolvedAdapterFieldType)) adapter.renderableAdapterFields

sourceTypeModules :: HaskellSourceType -> [Text]
sourceTypeModules = \case
    HaskellNamedType (HaskellClosedType metadata) -> [metadata.haskellTypeModule]
    HaskellNamedType _ -> []
    HaskellListType inner -> sourceTypeModules inner
    HaskellMaybeType inner -> sourceTypeModules inner

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

-- | Shared declaration-level source mechanics used by focused renderers. The
-- renderer still chooses the public builder, result type, and generated name;
-- this core fixes field argument ordering and exact SurfaceFields syntax.
renderAdapterArguments :: [ResolvedAdapterField] -> Text
renderAdapterArguments fields =
    case map (haskellValueIdentifier . (.fieldName) . (.resolvedAdapterFieldIR)) fields of
        []    -> ""
        names -> " " <> Text.unwords names

renderAdapterFieldsExpression :: Map.Map Text Text -> [ResolvedAdapterField] -> [Text]
renderAdapterFieldsExpression = renderAdapterFieldsExpressionWithIndent "        "

renderAdapterFieldsExpressionWithIndent :: Text -> Map.Map Text Text -> [ResolvedAdapterField] -> [Text]
renderAdapterFieldsExpressionWithIndent indentation _ [] = [indentation <> "noSurfaceFields"]
renderAdapterFieldsExpressionWithIndent indentation aliases (first : rest) =
    [indentation <> "( " <> renderAdapterFieldBuilder aliases first]
        <> [continuationIndentation <> "&: " <> renderAdapterFieldBuilder aliases field | field <- rest]
        <> [ continuationIndentation <> "&: noSurfaceFields"
           , indentation <> ")"
           ]
  where
    continuationIndentation = indentation <> "    "

renderAdapterFieldBuilder :: Map.Map Text Text -> ResolvedAdapterField -> Text
renderAdapterFieldBuilder aliases field =
    helper <> " @" <> qualifyHaskellType aliases field.resolvedAdapterFieldMarker <> " " <> argument
  where
    helper = case field.resolvedAdapterFieldIR.fieldPresence of
        RequiredField         -> "surfaceField"
        OptionalFieldPresence -> "surfaceOptionalField"
        NullableFieldPresence -> "surfaceNullableField"
    argument = haskellValueIdentifier field.resolvedAdapterFieldIR.fieldName

renderAdapterFieldValueTuple :: Map.Map Text Text -> [HaskellSourceType] -> Text
renderAdapterFieldValueTuple aliases = \case
    [] -> "()"
    field : rest -> "(" <> renderHaskellSourceType aliases field <> ", " <> renderAdapterFieldValueTuple aliases rest <> ")"

resolvedAdapterConstructorName ::
    (RenderableAdapter payload -> Text) ->
    RenderableAdapter payload ->
    Text
resolvedAdapterConstructorName fallback adapter =
    case adapter.renderableAdapterGeneratedNames of
        constructorName : _ -> constructorName
        []                  -> fallback adapter

resolvedAdapterMatcherName ::
    (RenderableAdapter payload -> Text) ->
    RenderableAdapter payload ->
    Text
resolvedAdapterMatcherName constructorName adapter =
    case adapter.renderableAdapterGeneratedNames of
        _ : matcherName : _ -> matcherName
        _                   -> "match" <> upperFirst (constructorName adapter)

renderHaskellSourceType :: Map.Map Text Text -> HaskellSourceType -> Text
renderHaskellSourceType aliases = \case
    HaskellNamedType named -> case named of
        HaskellTextType            -> "Text"
        HaskellIntType             -> "Int"
        HaskellBoolType            -> "Bool"
        HaskellUuidType            -> "UUID.UUID"
        HaskellDayType             -> "Day"
        HaskellClosedType metadata -> qualifyHaskellType aliases metadata
    HaskellListType inner -> "[" <> renderHaskellSourceType aliases inner <> "]"
    HaskellMaybeType inner ->
        "Maybe " <> case inner of
            HaskellMaybeType _ -> "(" <> renderHaskellSourceType aliases inner <> ")"
            _                  -> renderHaskellSourceType aliases inner

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

qualifyHaskellType :: Map.Map Text Text -> HaskellTypeMetadata -> Text
qualifyHaskellType aliases metadata =
    Map.findWithDefault "MissingSourceModule" metadata.haskellTypeModule aliases
        <> "." <> metadata.haskellTypeName

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

haskellTypeMetadata :: forall value. Typeable value => HaskellTypeMetadata
haskellTypeMetadata =
    let tyCon = typeRepTyCon (typeRep (Proxy @value))
     in HaskellTypeMetadata
            { haskellTypeModule = cs (tyConModule tyCon)
            , haskellTypeName = cs (tyConName tyCon)
            }

fieldMarkerNames :: CheckedAdapterDeclaration kind payload -> [Text]
fieldMarkerNames = map (.fieldMarker) . (.checkedAdapterFields)

surfacesWithMarker :: SurfaceContractIR -> Text -> [SurfaceIR]
surfacesWithMarker contract marker =
    filter ((== marker) . (.surfaceMarker)) contract.contractSurfaces

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
        || candidateModule `elem` sharedSurfaceAdapterSourceModules

-- Shared Surface aliases may own field markers used by more than one feature,
-- but they must remain focused contract modules rather than another feature's
-- source tree. Action and Intent drag/drop adapters both exercise this module.
sharedSurfaceAdapterSourceModules :: [Text]
sharedSurfaceAdapterSourceModules =
    ["Application.Helper.FrontendContract.Surface.Interaction"]

diagnostic :: Text -> Text -> ContractDiagnostic
diagnostic diagnosticCode diagnosticMessage =
    ContractDiagnostic { diagnosticCode, diagnosticMessage }

stableDiagnostics :: [ContractDiagnostic] -> [ContractDiagnostic]
stableDiagnostics =
    List.nub . List.sortOn (\value -> (value.diagnosticCode, value.diagnosticMessage))
