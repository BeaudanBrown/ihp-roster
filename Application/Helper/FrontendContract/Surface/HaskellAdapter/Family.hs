{-# LANGUAGE AllowAmbiguousTypes   #-}
{-# LANGUAGE ConstraintKinds       #-}
{-# LANGUAGE DataKinds             #-}
{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE KindSignatures        #-}
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
    , HaskellTypeMetadata (..)
    , ReflectSurfaceAdapterFamilies
    , ReflectSurfaceAdapterHomes
    , ReflectSurfaceResourceAdapterHomes
    , SurfaceActionAdapterHome
    , SurfaceAdapterFamily
    , SurfaceAdapterFamilyMetadata (..)
    , SurfaceAdapterHome
    , SurfaceAdapterHomeMetadata (..)
    , SurfaceAdapterRegistry (..)
    , SurfaceFragmentAdapterHome
    , SurfaceIntentAdapterHome
    , SurfaceResourceAdapterHome
    , SurfaceResourceAdapterHomeMetadata
    , SurfaceScopeAdapterHome
    , reflectSurfaceAdapterHomes
    , reflectSurfaceAdapterRegistry
    , reflectSurfaceResourceAdapterHomes
    , surfaceActorOnlyFragmentAdapter
    ) where

import Application.Helper.FrontendContract.Surface.DSL
import Application.Helper.FrontendContract.Surface.HaskellAdapter.Core
import Application.Helper.FrontendContract.Surface.Values (SurfaceActionFieldSpecs,
                                                           SurfaceFragmentFieldSpecs,
                                                           SurfaceIntentFieldSpecs,
                                                           SurfaceResourceFieldSpecs,
                                                           SurfaceScopeFieldSpecs)
import Data.Kind (Type)
import Data.Typeable (Typeable)
import IHP.Prelude

class SurfaceAdapterFamily adapterFamily where
    type AdapterFamilySurface adapterFamily :: SurfaceSpec

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

data SurfaceAdapterRegistry = SurfaceAdapterRegistry
    { surfaceAdapterFamilies             :: ![SurfaceAdapterFamilyMetadata]
    , surfaceResourceAdapterHomes        :: ![SurfaceResourceAdapterHomeMetadata]
    , surfaceScopeAdapterHomes           :: ![SurfaceAdapterHomeMetadata 'ScopeAdapterKind]
    , surfaceFragmentAdapterHomes        :: ![SurfaceAdapterHomeMetadata 'FragmentAdapterKind]
    , surfaceActorOnlyFragmentAdapters   :: ![ActorOnlyFragmentAdapterMetadata]
    }
    deriving (Eq, Show)

type family AdapterSurfaceMarker (surface :: SurfaceSpec) :: Type where
    AdapterSurfaceMarker ('Surface marker primitives) = marker

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
            case reflectSurfaceAdapterHomes
                @'FragmentAdapterKind
                @'[SurfaceFragmentAdapterHome adapterFamily fragment] of
                [home] -> home
                _      -> error "actor-only fragment reflection did not produce exactly one typed home"
        , actorOnlyFragmentReason
        }

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
    SurfaceAdapterRegistry
reflectSurfaceAdapterRegistry surfaceActorOnlyFragmentAdapters =
    SurfaceAdapterRegistry
        { surfaceAdapterFamilies = reflectSurfaceAdapterFamilies @families
        , surfaceResourceAdapterHomes = reflectSurfaceResourceAdapterHomes @resourceHomes
        , surfaceScopeAdapterHomes = reflectSurfaceAdapterHomes @'ScopeAdapterKind @scopeHomes
        , surfaceFragmentAdapterHomes = reflectSurfaceAdapterHomes @'FragmentAdapterKind @fragmentHomes
        , surfaceActorOnlyFragmentAdapters = surfaceActorOnlyFragmentAdapters
        }
