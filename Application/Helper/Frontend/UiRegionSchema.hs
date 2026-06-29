{-# LANGUAGE TypeApplications #-}

module Application.Helper.Frontend.UiRegionSchema
    ( uiRegionSchemaDeclaration
    ) where

import Application.Helper.Frontend.Codec (FrontendCodec (..),
                                          FrontendSchema (..),
                                          HasFrontendCodec (..), field,
                                          recordSchema, someFrontendCodec,
                                          stringEnumCodec)
import Application.Helper.Frontend.ContractGroup (FrontendContractGroup (..),
                                                  renderFrontendContractGroup,
                                                  typedConstant)
import Application.Helper.Frontend.TypeScript (TypeScriptDeclaration (..))
import Application.Helper.UiRegion
import qualified Data.Aeson as Aeson
import IHP.Prelude

uiRegionSchemaDeclaration :: TypeScriptDeclaration
uiRegionSchemaDeclaration =
    renderFrontendContractGroup FrontendContractGroup
        { contractGroupName = "UiRegionContracts"
        , contractGroupComment = Just "UI region capability vocabulary generated from Haskell."
        , contractGroupCodecs =
            [ someFrontendCodec @UiRegionDomAttributes
            , someFrontendCodec @UiRegionTransitionProfile
            , someFrontendCodec @UiRegionLifecycleEvent
            , someFrontendCodec @UiRegionEvents
            ]
        , contractGroupConstants =
            [ typedConstant "UiRegionDom" (frontendCodec @UiRegionDomAttributes) canonicalUiRegionDomAttributes
            , typedConstant "UiRegionEvents" (frontendCodec @UiRegionEvents) canonicalUiRegionEvents
            ]
        }

instance HasFrontendCodec UiRegionDomAttributes where
    frontendCodec = FrontendCodec
        { codecName = Just "UiRegionDom"
    , codecSchema = recordSchema "UiRegionDom"
        [ field "fragment" SchemaString
        , field "lazySurface" SchemaString
        , field "lazyFragment" SchemaString
        , field "lazyRetry" SchemaString
        , field "transition" SchemaString
        ]
    , codecEncode = \dom -> Aeson.object
        [ "fragment" Aeson..= dom.uiRegionFragmentAttribute
        , "lazySurface" Aeson..= dom.uiRegionLazySurfaceAttribute
        , "lazyFragment" Aeson..= dom.uiRegionLazyFragmentAttribute
        , "lazyRetry" Aeson..= dom.uiRegionLazyRetryAttribute
        , "transition" Aeson..= dom.uiRegionTransitionAttribute
        ]
    , codecParse = Aeson.withObject "UiRegionDom" \object ->
        UiRegionDomAttributes
            <$> object Aeson..: "fragment"
            <*> object Aeson..: "lazySurface"
            <*> object Aeson..: "lazyFragment"
            <*> object Aeson..: "lazyRetry"
            <*> object Aeson..: "transition"
    }

instance HasFrontendCodec UiRegionTransitionProfile where
    frontendCodec =
        stringEnumCodec "UiRegionTransitionProfile"
            [ (UiRegionTransitionNone, uiRegionTransitionProfileText UiRegionTransitionNone)
            , (UiRegionTransitionFade, uiRegionTransitionProfileText UiRegionTransitionFade)
            , (UiRegionTransitionFadeSlide, uiRegionTransitionProfileText UiRegionTransitionFadeSlide)
            , (UiRegionTransitionPanel, uiRegionTransitionProfileText UiRegionTransitionPanel)
            ]

instance HasFrontendCodec UiRegionLifecycleEvent where
    frontendCodec =
        stringEnumCodec "UiRegionLifecycleEvent" canonicalUiRegionLifecycleEvents

data UiRegionEvents = UiRegionEvents
    { regionRequestStart :: !Text
    , regionBeforeSwap   :: !Text
    , regionAfterSwap    :: !Text
    , regionSettle       :: !Text
    , regionError        :: !Text
    }
    deriving (Eq, Show)

canonicalUiRegionEvents :: UiRegionEvents
canonicalUiRegionEvents = UiRegionEvents
    { regionRequestStart = uiRegionLifecycleEventName UiRegionRequestStart
    , regionBeforeSwap = uiRegionLifecycleEventName UiRegionBeforeSwap
    , regionAfterSwap = uiRegionLifecycleEventName UiRegionAfterSwap
    , regionSettle = uiRegionLifecycleEventName UiRegionSettle
    , regionError = uiRegionLifecycleEventName UiRegionError
    }

instance HasFrontendCodec UiRegionEvents where
    frontendCodec = FrontendCodec
        { codecName = Just "UiRegionEvents"
    , codecSchema = recordSchema "UiRegionEvents"
        [ field "requestStart" SchemaString
        , field "beforeSwap" SchemaString
        , field "afterSwap" SchemaString
        , field "settle" SchemaString
        , field "error" SchemaString
        ]
    , codecEncode = \events -> Aeson.object
        [ "requestStart" Aeson..= events.regionRequestStart
        , "beforeSwap" Aeson..= events.regionBeforeSwap
        , "afterSwap" Aeson..= events.regionAfterSwap
        , "settle" Aeson..= events.regionSettle
        , "error" Aeson..= events.regionError
        ]
    , codecParse = Aeson.withObject "UiRegionEvents" \object ->
        UiRegionEvents
            <$> object Aeson..: "requestStart"
            <*> object Aeson..: "beforeSwap"
            <*> object Aeson..: "afterSwap"
            <*> object Aeson..: "settle"
            <*> object Aeson..: "error"
    }
