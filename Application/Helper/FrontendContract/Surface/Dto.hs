{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE FlexibleContexts    #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications    #-}
{-# LANGUAGE TypeFamilies        #-}

-- | Exact server-rendered payloads for explicitly browser-reachable Surface
-- DTOs. The owning Surface, DTO marker, role marker, field order, presence, and
-- wire types are all fixed by the declaration; callers provide values only.
module Application.Helper.FrontendContract.Surface.Dto
    ( surfaceBrowserDtoJson
    , surfaceBrowserDtoRoleAttrs
    ) where

import Application.Helper.FrontendContract.Surface.ContractIR (BrowserAttributeIR (..))
import Application.Helper.FrontendContract.Surface.Reflect (ReflectBrowserRolePrimitive,
                                                            ReflectSurfaceSpec)
import Application.Helper.FrontendContract.Surface.Values
import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Text.Encoding as TextEncoding
import IHP.Prelude

surfaceBrowserDtoJson ::
    forall spec dto.
    AssertBrowserReachableSurfaceDto (SurfaceDtoPrimitive spec dto) =>
    SurfaceFields (SurfaceDtoFieldSpecs spec dto) ->
    Text
surfaceBrowserDtoJson =
    TextEncoding.decodeUtf8 . LBS.toStrict . Aeson.encode . surfaceFieldsJson

surfaceBrowserDtoRoleAttrs ::
    forall spec roleMarker dto.
    ( AssertBrowserReachableSurfaceDto (SurfaceDtoPrimitive spec dto)
    , ReflectSurfaceSpec spec
    , ReflectBrowserRolePrimitive (SurfaceBrowserRolePrimitive spec roleMarker)
    ) =>
    SurfaceFields (SurfaceDtoFieldSpecs spec dto) ->
    [(Text, Text)]
surfaceBrowserDtoRoleAttrs fields =
    [ ( (surfaceBrowserRoleValue @spec @roleMarker).browserAttributeDomAttribute
      , surfaceBrowserDtoJson @spec @dto fields
      )
    ]
