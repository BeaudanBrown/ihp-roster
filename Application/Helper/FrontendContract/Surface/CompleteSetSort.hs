{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE FlexibleContexts    #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications    #-}
{-# LANGUAGE TypeFamilies        #-}

-- | Marker-indexed rendering for complete client-side presentation sorts.
-- Haskell supplies exact row payloads and declared control keys; TypeScript
-- receives no free-form field names, comparator policy, or defaults from views.
module Application.Helper.FrontendContract.Surface.CompleteSetSort
    ( surfaceCompleteSetSortControlAttrs
    , surfaceCompleteSetSortRootAttrs
    , surfaceCompleteSetSortRowAttrs
    ) where

import Application.Helper.FrontendContract.Naming (FrontendSurfaceNameContext (SortKeyName),
                                                   deriveFrontendSurfaceTypeName)
import Application.Helper.FrontendContract.Surface.ContractIR (BrowserAttributeIR (..),
                                                               CompleteSetSortIR (..))
import Application.Helper.FrontendContract.Surface.Dto (surfaceBrowserDtoJson)
import Application.Helper.FrontendContract.Surface.Reflect (ReflectCompleteSetSortPrimitive,
                                                            ReflectSurfaceSpec)
import Application.Helper.FrontendContract.Surface.Values
import Data.Typeable (Typeable)
import IHP.Prelude

surfaceCompleteSetSortRootAttrs ::
    forall spec sortMarker.
    ( ReflectSurfaceSpec spec
    , ReflectCompleteSetSortPrimitive (SurfaceCompleteSetSortPrimitive spec sortMarker)
    ) =>
    [(Text, Text)]
surfaceCompleteSetSortRootAttrs =
    [ (sortDefinition.completeSetSortRootRole.browserAttributeDomAttribute, "true") ]
  where
    sortDefinition = surfaceCompleteSetSortValue @spec @sortMarker

surfaceCompleteSetSortRowAttrs ::
    forall spec sortMarker.
    ( ReflectSurfaceSpec spec
    , ReflectCompleteSetSortPrimitive (SurfaceCompleteSetSortPrimitive spec sortMarker)
    , AssertBrowserReachableSurfaceDto
        (SurfaceDtoPrimitive spec (SurfaceCompleteSetSortRowDto spec sortMarker))
    ) =>
    SurfaceFields (SurfaceCompleteSetSortRowFieldSpecs spec sortMarker) ->
    [(Text, Text)]
surfaceCompleteSetSortRowAttrs fields =
    [ ( sortDefinition.completeSetSortRowRole.browserAttributeDomAttribute
      , surfaceBrowserDtoJson
            @spec
            @(SurfaceCompleteSetSortRowDto spec sortMarker)
            fields
      )
    ]
  where
    sortDefinition = surfaceCompleteSetSortValue @spec @sortMarker

surfaceCompleteSetSortControlAttrs ::
    forall spec sortMarker key.
    ( ReflectSurfaceSpec spec
    , ReflectCompleteSetSortPrimitive (SurfaceCompleteSetSortPrimitive spec sortMarker)
    , RequireCompleteSetSortKey (SurfaceCompleteSetSortPrimitive spec sortMarker) key
    , Typeable key
    ) =>
    [(Text, Text)]
surfaceCompleteSetSortControlAttrs =
    [ ( sortDefinition.completeSetSortControlRole.browserAttributeDomAttribute
      , deriveFrontendSurfaceTypeName @key SortKeyName
      )
    ]
  where
    sortDefinition = surfaceCompleteSetSortValue @spec @sortMarker
