{-# LANGUAGE AllowAmbiguousTypes   #-}
{-# LANGUAGE ConstraintKinds       #-}
{-# LANGUAGE DataKinds             #-}
{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE KindSignatures        #-}
{-# LANGUAGE LambdaCase            #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE PolyKinds             #-}
{-# LANGUAGE ScopedTypeVariables   #-}
{-# LANGUAGE TypeApplications      #-}
{-# LANGUAGE TypeFamilies          #-}
{-# LANGUAGE TypeOperators         #-}
{-# LANGUAGE UndecidableInstances  #-}

-- | Typed ownership input for deterministic Haskell Surface adapters.
--
-- A family is a nominal marker associated with one existing Surface alias.
-- Kind-indexed homes mention only that family and one declaration marker;
-- field order, presence, and wires continue to come from the associated
-- Surface declaration.
module Application.Helper.FrontendContract.Surface.HaskellAdapter.Family
    ( ActorOnlyFragmentAdapterMetadata (..)
    , AdapterFamilySurface
    , CheckedSurfaceRequestAdapterRegistration
    , checkedSurfaceRequestAdapter
    , checkedSurfaceRequestAdapterEvidenceMode
    , checkedSurfaceRequestAdapterOperations
    , HaskellTypeMetadata (..)
    , ReflectSurfaceAdapterFamilies
    , ReflectSurfaceAdapterHomes
    , ReflectSurfaceResourceAdapterHomes
    , SurfaceActionAdapterHome
    , SurfaceAdapterFamily
    , SurfaceAdapterOperationEligibility (..)
    , SurfaceAdapterFamilyMetadata (..)
    , SurfaceAdapterHome
    , SurfaceAdapterHomeMetadata (..)
    , SurfaceAdapterRegistry (..)
    , SurfaceFragmentAdapterHome
    , SurfaceIntentAdapterHome
    , SurfaceRequestAdapterOperations (..)
    , SurfaceRequestAdapterEvidenceMode (..)
    , SurfaceRequestAdapterRegistration
    , SurfaceResourceAdapterHome
    , SurfaceResourceAdapterHomeMetadata
    , SurfaceScopeAdapterHome
    , reflectSurfaceAdapterHomes
    , reflectSurfaceAdapterRegistry
    , reflectSurfaceResourceAdapterHomes
    , resolveSurfaceRequestAdapterRegistrations
    , surfaceActionAdapter
    , surfaceActionAdapterExcluded
    , surfaceOperationLocalActionAdapter
    , surfaceOperationLocalActionAdapterExcluded
    , surfaceActorOnlyFragmentAdapter
    , surfaceAdapterOperationIsGenerated
    , surfaceIntentAdapter
    , surfaceOperationLocalIntentAdapter
    ) where

import Application.Error.Startup (startupInvariantFailure)
import Application.Helper.FrontendContract.Surface.ContractIR (ContractDiagnostic (..),
                                                               SurfaceContractIR)
import Application.Helper.FrontendContract.Surface.DSL
import Application.Helper.FrontendContract.Surface.HaskellAdapter.Association
import Application.Helper.FrontendContract.Surface.HaskellAdapter.Core
import Application.Helper.FrontendContract.Surface.Values (SurfaceActionFieldSpecs,
                                                           SurfaceFragmentFieldSpecs,
                                                           SurfaceIntentFieldSpecs,
                                                           SurfaceResourceFieldSpecs,
                                                           SurfaceScopeFieldSpecs)
import Data.Kind (Type)
import qualified Data.Text as Text
import Data.Typeable (Typeable)
import IHP.Prelude

-- | One typed declaration home. The promoted kind selects the declaration
-- lookup and prevents homes from crossing resource/live/action/intent seams.
data SurfaceAdapterHome
    (kind :: SurfaceAdapterKind)
    (adapterFamily :: Type)
    (declaration :: Type)

type SurfaceResourceAdapterHome adapterFamily resource =
    SurfaceAdapterHome 'ResourceAdapterKind adapterFamily resource

type SurfaceScopeAdapterHome adapterFamily scope =
    SurfaceAdapterHome 'ScopeAdapterKind adapterFamily scope

type SurfaceFragmentAdapterHome adapterFamily fragment =
    SurfaceAdapterHome 'FragmentAdapterKind adapterFamily fragment

type SurfaceActionAdapterHome adapterFamily action =
    SurfaceAdapterHome 'ActionAdapterKind adapterFamily action

type SurfaceIntentAdapterHome adapterFamily intent =
    SurfaceAdapterHome 'IntentAdapterKind adapterFamily intent

-- | Explicit eligibility for a semantic fragment key used only by actor-local
-- workflows. The owning family and fragment remain type checked, while the
-- required reason remains reviewable term-level documentation.
data ActorOnlyFragmentAdapterMetadata = ActorOnlyFragmentAdapterMetadata
    { actorOnlyFragmentHome   :: !(SurfaceAdapterHomeMetadata 'FragmentAdapterKind)
    , actorOnlyFragmentReason :: !Text
    }
    deriving (Eq, Show)

type SurfaceResourceAdapterHomeMetadata =
    SurfaceAdapterHomeMetadata 'ResourceAdapterKind

-- | Whether one operation has an inventoried current consumer. Exclusions are
-- explicit and carry the reviewable reason that prevents speculative output.
data SurfaceAdapterOperationEligibility
    = GenerateSurfaceAdapterOperation
    | ExcludeSurfaceAdapterOperation !Text
    deriving (Eq, Show)

data SurfaceRequestAdapterEvidenceMode
    = WholeSurfaceRequestEvidence
    | OperationLocalRequestEvidence
    deriving (Eq, Show)

data SurfaceRequestAdapterOperations = SurfaceRequestAdapterOperations
    { surfaceAdapterFieldsBuilderOperation :: !SurfaceAdapterOperationEligibility
    , surfaceAdapterRenderMetadataOperation :: !SurfaceAdapterOperationEligibility
    , surfaceAdapterRequestParserOperation :: !SurfaceAdapterOperationEligibility
    , surfaceAdapterParamsPresentOperation  :: !SurfaceAdapterOperationEligibility
    }
    deriving (Eq, Show)

-- | One complete typed inventory decision. A generated declaration records an
-- explicit decision for every supported operation; an excluded declaration
-- records why no Haskell action/intent adapter currently has a consumer.
data SurfaceRequestAdapterRegistration (kind :: SurfaceAdapterKind)
    = GenerateSurfaceRequestAdapter
        !(SurfaceAdapterHomeMetadata kind)
        !SurfaceRequestAdapterOperations
        !SurfaceRequestAdapterEvidenceMode
    | ExcludeSurfaceRequestAdapter
        !(SurfaceAdapterHomeMetadata kind)
        !Text
        !SurfaceRequestAdapterEvidenceMode
    deriving (Eq, Show)

-- | Validated inventory row. Its declaration was normalized from checked IR
-- and resolved through the same family/home/source-type seam as emitted code.
data CheckedSurfaceRequestAdapterRegistration kind payload =
    CheckedSurfaceRequestAdapterRegistration
        { checkedSurfaceRequestAdapter             :: !(ResolvedAdapter kind payload)
        , checkedSurfaceRequestAdapterOperations   :: !(Maybe SurfaceRequestAdapterOperations)
        , checkedSurfaceRequestAdapterEvidenceMode :: !SurfaceRequestAdapterEvidenceMode
        }
    deriving (Eq, Show)

data SurfaceAdapterRegistry = SurfaceAdapterRegistry
    { surfaceAdapterFamilies              :: ![SurfaceAdapterFamilyMetadata]
    , surfaceResourceAdapterHomes         :: ![SurfaceResourceAdapterHomeMetadata]
    , surfaceScopeAdapterHomes            :: ![SurfaceAdapterHomeMetadata 'ScopeAdapterKind]
    , surfaceFragmentAdapterHomes         :: ![SurfaceAdapterHomeMetadata 'FragmentAdapterKind]
    , surfaceActorOnlyFragmentAdapters    :: ![ActorOnlyFragmentAdapterMetadata]
    , surfaceActionAdapterRegistrations   :: ![SurfaceRequestAdapterRegistration 'ActionAdapterKind]
    , surfaceIntentAdapterRegistrations   :: ![SurfaceRequestAdapterRegistration 'IntentAdapterKind]
    }
    deriving (Eq, Show)

type family SurfaceAdapterFieldSpecs
    (kind :: SurfaceAdapterKind)
    (surface :: SurfaceSpec)
    (declaration :: Type) :: [FieldSpec] where
    SurfaceAdapterFieldSpecs 'ResourceAdapterKind surface declaration =
        SurfaceResourceFieldSpecs surface declaration
    SurfaceAdapterFieldSpecs 'ScopeAdapterKind surface declaration =
        SurfaceScopeFieldSpecs surface declaration
    SurfaceAdapterFieldSpecs 'FragmentAdapterKind surface declaration =
        SurfaceFragmentFieldSpecs surface declaration
    SurfaceAdapterFieldSpecs 'ActionAdapterKind surface declaration =
        SurfaceActionFieldSpecs surface declaration
    SurfaceAdapterFieldSpecs 'IntentAdapterKind surface declaration =
        SurfaceIntentFieldSpecs surface declaration

class ReflectSurfaceAdapterFamilies (families :: [Type]) where
    reflectSurfaceAdapterFamilies :: [SurfaceAdapterFamilyMetadata]

instance ReflectSurfaceAdapterFamilies '[] where
    reflectSurfaceAdapterFamilies = []

instance
    ( SurfaceAdapterFamily adapterFamily
    , Typeable adapterFamily
    , Typeable (AdapterSurfaceMarker (AdapterFamilySurface adapterFamily))
    , ReflectSurfaceAdapterFamilies rest
    ) => ReflectSurfaceAdapterFamilies (adapterFamily ': rest) where
    reflectSurfaceAdapterFamilies =
        SurfaceAdapterFamilyMetadata
            { adapterFamilyType = haskellTypeMetadata @adapterFamily
            , adapterFamilySurfaceMarker = haskellTypeMetadata @(AdapterSurfaceMarker (AdapterFamilySurface adapterFamily))
            }
            : reflectSurfaceAdapterFamilies @rest

class ReflectSurfaceAdapterHomes
    (kind :: SurfaceAdapterKind)
    (homes :: [Type]) where
    reflectSurfaceAdapterHomes :: [SurfaceAdapterHomeMetadata kind]

instance ReflectSurfaceAdapterHomes kind '[] where
    reflectSurfaceAdapterHomes = []

instance
    ( SurfaceAdapterFamily adapterFamily
    , Typeable adapterFamily
    , Typeable declaration
    , Typeable (AdapterSurfaceMarker (AdapterFamilySurface adapterFamily))
    , ReflectSurfaceFieldMarkerTypes
        (SurfaceAdapterFieldSpecs kind (AdapterFamilySurface adapterFamily) declaration)
    , ReflectSurfaceAdapterHomes kind rest
    ) => ReflectSurfaceAdapterHomes
        kind
        (SurfaceAdapterHome kind adapterFamily declaration ': rest) where
    reflectSurfaceAdapterHomes =
        SurfaceAdapterHomeMetadata
            { adapterHomeFamily = haskellTypeMetadata @adapterFamily
            , adapterHomeSurface = haskellTypeMetadata @(AdapterSurfaceMarker (AdapterFamilySurface adapterFamily))
            , adapterHomeDeclaration = haskellTypeMetadata @declaration
            , adapterHomeFieldMarkers =
                reflectSurfaceFieldMarkerTypes
                    @(SurfaceAdapterFieldSpecs kind (AdapterFamilySurface adapterFamily) declaration)
            }
            : reflectSurfaceAdapterHomes @kind @rest

-- Compatibility name retained for the existing resource registry while the
-- focused future renderers use the kind-indexed class directly.
type ReflectSurfaceResourceAdapterHomes homes =
    ReflectSurfaceAdapterHomes 'ResourceAdapterKind homes

reflectSurfaceResourceAdapterHomes ::
    forall homes.
    ReflectSurfaceResourceAdapterHomes homes =>
    [SurfaceResourceAdapterHomeMetadata]
reflectSurfaceResourceAdapterHomes =
    reflectSurfaceAdapterHomes @'ResourceAdapterKind @homes

surfaceActorOnlyFragmentAdapter ::
    forall adapterFamily fragment.
    ReflectSurfaceAdapterHomes
        'FragmentAdapterKind
        '[SurfaceFragmentAdapterHome adapterFamily fragment] =>
    Text ->
    ActorOnlyFragmentAdapterMetadata
surfaceActorOnlyFragmentAdapter actorOnlyFragmentReason =
    ActorOnlyFragmentAdapterMetadata
        { actorOnlyFragmentHome =
            singleSurfaceAdapterHome
                @'FragmentAdapterKind
                @adapterFamily
                @fragment
        , actorOnlyFragmentReason
        }

surfaceActionAdapter ::
    forall adapterFamily action.
    ReflectSurfaceAdapterHomes
        'ActionAdapterKind
        '[SurfaceActionAdapterHome adapterFamily action] =>
    SurfaceRequestAdapterOperations ->
    SurfaceRequestAdapterRegistration 'ActionAdapterKind
surfaceActionAdapter operations =
    GenerateSurfaceRequestAdapter
        (singleSurfaceAdapterHome @'ActionAdapterKind @adapterFamily @action)
        operations
        WholeSurfaceRequestEvidence

surfaceOperationLocalActionAdapter ::
    forall adapterFamily action.
    ReflectSurfaceAdapterHomes
        'ActionAdapterKind
        '[SurfaceActionAdapterHome adapterFamily action] =>
    SurfaceRequestAdapterOperations ->
    SurfaceRequestAdapterRegistration 'ActionAdapterKind
surfaceOperationLocalActionAdapter operations =
    GenerateSurfaceRequestAdapter
        (singleSurfaceAdapterHome @'ActionAdapterKind @adapterFamily @action)
        operations
        OperationLocalRequestEvidence

surfaceActionAdapterExcluded ::
    forall adapterFamily action.
    ReflectSurfaceAdapterHomes
        'ActionAdapterKind
        '[SurfaceActionAdapterHome adapterFamily action] =>
    Text ->
    SurfaceRequestAdapterRegistration 'ActionAdapterKind
surfaceActionAdapterExcluded reason =
    ExcludeSurfaceRequestAdapter
        (singleSurfaceAdapterHome @'ActionAdapterKind @adapterFamily @action)
        reason
        WholeSurfaceRequestEvidence

surfaceOperationLocalActionAdapterExcluded ::
    forall adapterFamily action.
    ReflectSurfaceAdapterHomes
        'ActionAdapterKind
        '[SurfaceActionAdapterHome adapterFamily action] =>
    Text ->
    SurfaceRequestAdapterRegistration 'ActionAdapterKind
surfaceOperationLocalActionAdapterExcluded reason =
    ExcludeSurfaceRequestAdapter
        (singleSurfaceAdapterHome @'ActionAdapterKind @adapterFamily @action)
        reason
        OperationLocalRequestEvidence

surfaceIntentAdapter ::
    forall adapterFamily intent.
    ReflectSurfaceAdapterHomes
        'IntentAdapterKind
        '[SurfaceIntentAdapterHome adapterFamily intent] =>
    SurfaceRequestAdapterOperations ->
    SurfaceRequestAdapterRegistration 'IntentAdapterKind
surfaceIntentAdapter operations =
    GenerateSurfaceRequestAdapter
        (singleSurfaceAdapterHome @'IntentAdapterKind @adapterFamily @intent)
        operations
        WholeSurfaceRequestEvidence

surfaceOperationLocalIntentAdapter ::
    forall adapterFamily intent.
    ReflectSurfaceAdapterHomes
        'IntentAdapterKind
        '[SurfaceIntentAdapterHome adapterFamily intent] =>
    SurfaceRequestAdapterOperations ->
    SurfaceRequestAdapterRegistration 'IntentAdapterKind
surfaceOperationLocalIntentAdapter operations =
    GenerateSurfaceRequestAdapter
        (singleSurfaceAdapterHome @'IntentAdapterKind @adapterFamily @intent)
        operations
        OperationLocalRequestEvidence

singleSurfaceAdapterHome ::
    forall kind adapterFamily declaration.
    ReflectSurfaceAdapterHomes
        kind
        '[SurfaceAdapterHome kind adapterFamily declaration] =>
    SurfaceAdapterHomeMetadata kind
singleSurfaceAdapterHome =
    case reflectSurfaceAdapterHomes
        @kind
        @'[SurfaceAdapterHome kind adapterFamily declaration] of
        [home] -> home
        _      -> startupInvariantFailure "single Surface adapter reflection did not produce exactly one typed home"

surfaceAdapterOperationIsGenerated :: SurfaceAdapterOperationEligibility -> Bool
surfaceAdapterOperationIsGenerated GenerateSurfaceAdapterOperation    = True
surfaceAdapterOperationIsGenerated (ExcludeSurfaceAdapterOperation _) = False

resolveSurfaceRequestAdapterRegistrations ::
    AdapterModuleLayout kind ->
    SurfaceContractIR ->
    [SurfaceAdapterFamilyMetadata] ->
    [CheckedAdapterDeclaration kind payload] ->
    [SurfaceRequestAdapterRegistration kind] ->
    Either [ContractDiagnostic] [CheckedSurfaceRequestAdapterRegistration kind payload]
resolveSurfaceRequestAdapterRegistrations layout contract families declarations registrations =
    case stableDiagnostics (registrationDiagnostics <> resolutionDiagnostics) of
        []          -> Right (map checkedRegistration resolvedAdapters)
        diagnostics -> Left diagnostics
  where
    resolution =
        resolveAdapterGeneration
            layout
            contract
            families
            (map requestAdapterRegistrationHome registrations)
            declarations
            (const [])
    (resolutionDiagnostics, resolvedAdapters) =
        case resolution of
            Left diagnostics -> (diagnostics, [])
            Right adapters   -> ([], adapters)
    registrationDiagnostics = concatMap validateRegistration registrations

    checkedRegistration adapter =
        let registration =
                fromMaybe
                    (startupInvariantFailure "resolved Surface request adapter has no inventory registration")
                    (find ((== adapter.resolvedAdapterHome) . requestAdapterRegistrationHome) registrations)
         in CheckedSurfaceRequestAdapterRegistration
                { checkedSurfaceRequestAdapter = adapter
                , checkedSurfaceRequestAdapterOperations = requestAdapterGeneratedOperations registration
                , checkedSurfaceRequestAdapterEvidenceMode = requestAdapterEvidenceMode registration
                }

    validateRegistration registration =
        case registration of
            ExcludeSurfaceRequestAdapter home reason _ ->
                [ ContractDiagnostic
                    { diagnosticCode = "adapter-" <> layout.adapterKindSlug <> "-declaration-exclusion-reason"
                    , diagnosticMessage =
                        layout.adapterKindLabel <> " adapter " <> requestAdapterHomeLabel home
                            <> " must record a non-empty declaration exclusion reason"
                    }
                | Text.null (Text.strip reason)
                ]
            GenerateSurfaceRequestAdapter home operations _ ->
                operationReasonDiagnostics home operations
                    <> [ ContractDiagnostic
                            { diagnosticCode = "adapter-" <> layout.adapterKindSlug <> "-empty-operation-set"
                            , diagnosticMessage =
                                layout.adapterKindLabel <> " adapter " <> requestAdapterHomeLabel home
                                    <> " emits no inventoried operations; exclude the declaration instead"
                            }
                       | not (any surfaceAdapterOperationIsGenerated (requestAdapterOperationValues operations))
                       ]

    operationReasonDiagnostics home operations =
        [ ContractDiagnostic
            { diagnosticCode = "adapter-" <> layout.adapterKindSlug <> "-operation-exclusion-reason"
            , diagnosticMessage =
                layout.adapterKindLabel <> " adapter " <> requestAdapterHomeLabel home
                    <> " operation " <> operationLabel
                    <> " must record a non-empty exclusion reason"
            }
        | (operationLabel, ExcludeSurfaceAdapterOperation reason) <- requestAdapterOperationRows operations
        , Text.null (Text.strip reason)
        ]

requestAdapterRegistrationHome ::
    SurfaceRequestAdapterRegistration kind ->
    SurfaceAdapterHomeMetadata kind
requestAdapterRegistrationHome = \case
    GenerateSurfaceRequestAdapter home _ _ -> home
    ExcludeSurfaceRequestAdapter home _ _  -> home

requestAdapterGeneratedOperations ::
    SurfaceRequestAdapterRegistration kind ->
    Maybe SurfaceRequestAdapterOperations
requestAdapterGeneratedOperations = \case
    GenerateSurfaceRequestAdapter _ operations _ -> Just operations
    ExcludeSurfaceRequestAdapter _ _ _            -> Nothing

requestAdapterEvidenceMode ::
    SurfaceRequestAdapterRegistration kind ->
    SurfaceRequestAdapterEvidenceMode
requestAdapterEvidenceMode = \case
    GenerateSurfaceRequestAdapter _ _ mode -> mode
    ExcludeSurfaceRequestAdapter _ _ mode  -> mode

requestAdapterOperationRows :: SurfaceRequestAdapterOperations -> [(Text, SurfaceAdapterOperationEligibility)]
requestAdapterOperationRows operations =
    [ ("fields-builder", operations.surfaceAdapterFieldsBuilderOperation)
    , ("render-metadata", operations.surfaceAdapterRenderMetadataOperation)
    , ("request-parser", operations.surfaceAdapterRequestParserOperation)
    , ("params-present", operations.surfaceAdapterParamsPresentOperation)
    ]

requestAdapterOperationValues :: SurfaceRequestAdapterOperations -> [SurfaceAdapterOperationEligibility]
requestAdapterOperationValues = map snd . requestAdapterOperationRows

requestAdapterHomeLabel :: SurfaceAdapterHomeMetadata kind -> Text
requestAdapterHomeLabel home =
    home.adapterHomeSurface.haskellTypeName <> "/" <> home.adapterHomeDeclaration.haskellTypeName

class ReflectSurfaceFieldMarkerTypes (fields :: [FieldSpec]) where
    reflectSurfaceFieldMarkerTypes :: [HaskellTypeMetadata]

instance ReflectSurfaceFieldMarkerTypes '[] where
    reflectSurfaceFieldMarkerTypes = []

instance
    (Typeable marker, ReflectSurfaceFieldMarkerTypes rest) =>
    ReflectSurfaceFieldMarkerTypes ('Field marker wire ': rest) where
    reflectSurfaceFieldMarkerTypes =
        haskellTypeMetadata @marker : reflectSurfaceFieldMarkerTypes @rest

instance
    (Typeable marker, ReflectSurfaceFieldMarkerTypes rest) =>
    ReflectSurfaceFieldMarkerTypes ('OptionalField marker wire ': rest) where
    reflectSurfaceFieldMarkerTypes =
        haskellTypeMetadata @marker : reflectSurfaceFieldMarkerTypes @rest

instance
    (Typeable marker, ReflectSurfaceFieldMarkerTypes rest) =>
    ReflectSurfaceFieldMarkerTypes ('NullableField marker wire ': rest) where
    reflectSurfaceFieldMarkerTypes =
        haskellTypeMetadata @marker : reflectSurfaceFieldMarkerTypes @rest

reflectSurfaceAdapterRegistry ::
    forall families resourceHomes scopeHomes fragmentHomes.
    ( ReflectSurfaceAdapterFamilies families
    , ReflectSurfaceResourceAdapterHomes resourceHomes
    , ReflectSurfaceAdapterHomes 'ScopeAdapterKind scopeHomes
    , ReflectSurfaceAdapterHomes 'FragmentAdapterKind fragmentHomes
    ) =>
    [ActorOnlyFragmentAdapterMetadata] ->
    [SurfaceRequestAdapterRegistration 'ActionAdapterKind] ->
    [SurfaceRequestAdapterRegistration 'IntentAdapterKind] ->
    SurfaceAdapterRegistry
reflectSurfaceAdapterRegistry
    surfaceActorOnlyFragmentAdapters
    surfaceActionAdapterRegistrations
    surfaceIntentAdapterRegistrations =
        SurfaceAdapterRegistry
            { surfaceAdapterFamilies = reflectSurfaceAdapterFamilies @families
            , surfaceResourceAdapterHomes = reflectSurfaceResourceAdapterHomes @resourceHomes
            , surfaceScopeAdapterHomes = reflectSurfaceAdapterHomes @'ScopeAdapterKind @scopeHomes
            , surfaceFragmentAdapterHomes = reflectSurfaceAdapterHomes @'FragmentAdapterKind @fragmentHomes
            , surfaceActorOnlyFragmentAdapters = surfaceActorOnlyFragmentAdapters
            , surfaceActionAdapterRegistrations = surfaceActionAdapterRegistrations
            , surfaceIntentAdapterRegistrations = surfaceIntentAdapterRegistrations
            }
