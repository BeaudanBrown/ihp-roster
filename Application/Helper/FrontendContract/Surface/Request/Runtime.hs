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
import Application.Helper.FrontendContract.Surface.Reflect (ReflectPrimitive (..),
                                                            ReflectedPrimitive (..))
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
    ReflectPrimitive (SurfaceActionPrimitive spec marker) =>
    SurfaceActionFields spec marker ->
    FrontendSurfaceAction
frontendSurfaceAction fields =
    frontendSurfaceActionFromIR action (surfaceFieldsText fields)
  where
    action =
        case reflectPrimitive @(SurfaceActionPrimitive spec marker) of
            ReflectedHtmxAction reflectedAction -> reflectedAction
            _ -> error "impossible: action lookup reflected a different primitive"

frontendSurfaceIntentForm ::
    forall spec marker.
    ReflectPrimitive (SurfaceIntentPrimitive spec marker) =>
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
    intent =
        case reflectPrimitive @(SurfaceIntentPrimitive spec marker) of
            ReflectedIntent reflectedIntent -> reflectedIntent
            _ -> error "impossible: intent lookup reflected a different primitive"

resolveIntentFields :: [SurfaceIR.FieldIR] -> [(Text, Text)] -> [(SurfaceIR.FieldIR, Text)]
resolveIntentFields declaredFields values =
    [ (field, value)
    | field <- declaredFields
    , value <- maybeToList (lookup field.fieldName values)
    ]
