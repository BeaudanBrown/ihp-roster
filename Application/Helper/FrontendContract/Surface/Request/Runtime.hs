{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE GADTs               #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications    #-}
{-# LANGUAGE TypeFamilies        #-}

-- | Focused runtime metadata for generated Surface Action and Intent adapters.
--
-- This module deliberately owns only opaque request metadata construction. It
-- does not import the registered Surface catalog, mount/live implementation, or
-- HTML rendering runtime, so feature-owned generated request facades retain a
-- bounded compile closure.
module Application.Helper.FrontendContract.Surface.Request.Runtime
    ( FrontendSurfaceAction
    , FrontendSurfaceHtmxMethod (..)
    , FrontendSurfaceHtmxRequest (..)
    , FrontendSurfaceIntentForm
    , frontendSurfaceAction
    , frontendSurfaceActionFieldPairs
    , frontendSurfaceActionIR
    , frontendSurfaceIntentForm
    , intentFormFields
    , intentFormName
    , intentFormSubmit
    ) where

import qualified Application.Helper.FrontendContract.Surface.ContractIR as SurfaceIR
import Application.Helper.FrontendContract.Surface.Reflect (ReflectActionPrimitive (..),
                                                            ReflectIntentPrimitive (..))
import Application.Helper.FrontendContract.Surface.Request.Runtime.Internal (FrontendSurfaceAction,
                                                                             FrontendSurfaceHtmxMethod (..),
                                                                             FrontendSurfaceHtmxRequest (..),
                                                                             FrontendSurfaceIntentForm (..),
                                                                             frontendSurfaceActionFieldPairs,
                                                                             frontendSurfaceActionFromIR,
                                                                             frontendSurfaceActionIR)
import Application.Helper.FrontendContract.Surface.Values (SurfaceActionFields,
                                                           SurfaceActionPrimitive,
                                                           SurfaceIntentFields,
                                                           SurfaceIntentPrimitive,
                                                           surfaceFieldsText)
import IHP.Prelude

frontendSurfaceAction ::
    forall spec marker.
    ReflectActionPrimitive (SurfaceActionPrimitive spec marker) =>
    SurfaceActionFields spec marker ->
    FrontendSurfaceAction
frontendSurfaceAction fields =
    frontendSurfaceActionFromIR action (surfaceFieldsText fields)
  where
    action = reflectActionPrimitive @(SurfaceActionPrimitive spec marker)

frontendSurfaceIntentForm ::
    forall spec marker.
    ReflectIntentPrimitive (SurfaceIntentPrimitive spec marker) =>
    SurfaceIntentFields spec marker ->
    FrontendSurfaceHtmxRequest ->
    FrontendSurfaceIntentForm
frontendSurfaceIntentForm fields request =
    FrontendSurfaceIntentForm
        { intentFormName = intent.intentName
        , intentFormSubmit = request
        , intentFormFields = resolveIntentFields intent.intentFields (surfaceFieldsText fields)
        }
  where
    intent = reflectIntentPrimitive @(SurfaceIntentPrimitive spec marker)

resolveIntentFields :: [SurfaceIR.FieldIR] -> [(Text, Text)] -> [(SurfaceIR.FieldIR, Text)]
resolveIntentFields declaredFields values =
    [ (field, value)
    | field <- declaredFields
    , value <- maybeToList (lookup field.fieldName values)
    ]
