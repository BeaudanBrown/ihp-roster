{-# LANGUAGE AllowAmbiguousTypes   #-}
{-# LANGUAGE DataKinds             #-}
{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE FlexibleInstances     #-}
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
-- Homes mention only a family and a declaration marker; field order, presence,
-- and wires continue to come from the associated Surface declaration.
module Application.Helper.FrontendContract.Surface.HaskellAdapter.Family
    ( AdapterFamilySurface
    , HaskellTypeMetadata (..)
    , ReflectSurfaceAdapterFamilies
    , ReflectSurfaceResourceAdapterHomes
    , SurfaceAdapterFamily
    , SurfaceAdapterFamilyMetadata (..)
    , SurfaceAdapterRegistry (..)
    , SurfaceResourceAdapterHome
    , SurfaceResourceAdapterHomeMetadata (..)
    , reflectSurfaceAdapterRegistry
    ) where

import Application.Helper.FrontendContract.Surface.DSL
import Application.Helper.FrontendContract.Surface.Values (SurfaceResourceFieldSpecs)
import Data.Kind (Type)
import Data.Typeable (Typeable, tyConModule, tyConName, typeRep, typeRepTyCon)
import IHP.Prelude

class SurfaceAdapterFamily adapterFamily where
    type AdapterFamilySurface adapterFamily :: SurfaceSpec

-- | A typed declaration that one resource marker is generated in a family's
-- feature-adjacent home. It deliberately carries no field or wire schema.
data SurfaceResourceAdapterHome (adapterFamily :: Type) (resource :: Type)

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

data SurfaceResourceAdapterHomeMetadata = SurfaceResourceAdapterHomeMetadata
    { resourceAdapterHomeFamily       :: !HaskellTypeMetadata
    , resourceAdapterHomeSurface      :: !HaskellTypeMetadata
    , resourceAdapterHomeResource     :: !HaskellTypeMetadata
    , resourceAdapterHomeFieldMarkers :: ![HaskellTypeMetadata]
    }
    deriving (Eq, Show)

data SurfaceAdapterRegistry = SurfaceAdapterRegistry
    { surfaceAdapterFamilies      :: ![SurfaceAdapterFamilyMetadata]
    , surfaceResourceAdapterHomes :: ![SurfaceResourceAdapterHomeMetadata]
    }
    deriving (Eq, Show)

type family AdapterSurfaceMarker (surface :: SurfaceSpec) :: Type where
    AdapterSurfaceMarker ('Surface marker primitives) = marker

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

class ReflectSurfaceResourceAdapterHomes (homes :: [Type]) where
    reflectSurfaceResourceAdapterHomes :: [SurfaceResourceAdapterHomeMetadata]

instance ReflectSurfaceResourceAdapterHomes '[] where
    reflectSurfaceResourceAdapterHomes = []

instance
    ( SurfaceAdapterFamily adapterFamily
    , Typeable adapterFamily
    , Typeable resource
    , Typeable (AdapterSurfaceMarker (AdapterFamilySurface adapterFamily))
    , ReflectSurfaceFieldMarkerTypes (SurfaceResourceFieldSpecs (AdapterFamilySurface adapterFamily) resource)
    , ReflectSurfaceResourceAdapterHomes rest
    ) => ReflectSurfaceResourceAdapterHomes (SurfaceResourceAdapterHome adapterFamily resource ': rest) where
    reflectSurfaceResourceAdapterHomes =
        SurfaceResourceAdapterHomeMetadata
            { resourceAdapterHomeFamily = haskellTypeMetadata @adapterFamily
            , resourceAdapterHomeSurface = haskellTypeMetadata @(AdapterSurfaceMarker (AdapterFamilySurface adapterFamily))
            , resourceAdapterHomeResource = haskellTypeMetadata @resource
            , resourceAdapterHomeFieldMarkers = reflectSurfaceFieldMarkerTypes @(SurfaceResourceFieldSpecs (AdapterFamilySurface adapterFamily) resource)
            }
            : reflectSurfaceResourceAdapterHomes @rest

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
    forall families homes.
    ( ReflectSurfaceAdapterFamilies families
    , ReflectSurfaceResourceAdapterHomes homes
    ) =>
    SurfaceAdapterRegistry
reflectSurfaceAdapterRegistry =
    SurfaceAdapterRegistry
        { surfaceAdapterFamilies = reflectSurfaceAdapterFamilies @families
        , surfaceResourceAdapterHomes = reflectSurfaceResourceAdapterHomes @homes
        }

haskellTypeMetadata :: forall value. Typeable value => HaskellTypeMetadata
haskellTypeMetadata =
    let tyCon = typeRepTyCon (typeRep (Proxy @value))
     in HaskellTypeMetadata
            { haskellTypeModule = cs (tyConModule tyCon)
            , haskellTypeName = cs (tyConName tyCon)
            }
