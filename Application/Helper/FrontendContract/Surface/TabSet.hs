{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE FlexibleContexts    #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications    #-}
{-# LANGUAGE TypeFamilies        #-}

-- | Marker-indexed rendering for mount-local remembered tab sets. Tab keys are
-- opaque browser correlation values; Bootstrap remains the mechanical tab
-- adapter and Haskell owns the allowed/default key inventory.
module Application.Helper.FrontendContract.Surface.TabSet
    ( surfaceTabSetAttrs
    ) where

import Application.Helper.FrontendContract.Naming (FrontendSurfaceNameContext (TabKeyName),
                                                   deriveFrontendSurfaceTypeName)
import Application.Helper.FrontendContract.Surface.ContractIR (BrowserAttributeIR (..),
                                                               TabSetIR (..))
import Application.Helper.FrontendContract.Surface.Reflect (ReflectSurfaceSpec,
                                                            ReflectTabSetPrimitive)
import Application.Helper.FrontendContract.Surface.Values
import IHP.Prelude

surfaceTabSetAttrs ::
    forall spec tabSetMarker key.
    ( ReflectSurfaceSpec spec
    , ReflectTabSetPrimitive (SurfaceTabSetPrimitive spec tabSetMarker)
    , RequireSurfaceTabKey (SurfaceTabSetPrimitive spec tabSetMarker) key
    , Typeable key
    ) =>
    [(Text, Text)]
surfaceTabSetAttrs =
    [ ( tabSet.tabSetRole.browserAttributeDomAttribute
      , deriveFrontendSurfaceTypeName @key TabKeyName
      )
    ]
  where
    tabSet = surfaceTabSetValue @spec @tabSetMarker
