{-# LANGUAGE TypeApplications #-}

module Application.Helper.Frontend.Dto.UiRegion
    ( UiRegionEvents (..)
    , canonicalUiRegionEvents
    ) where

import Application.Helper.Frontend.Codec (HasFrontendCodec (..))
import Application.Helper.Frontend.Generic (genericFrontendCodecWith)
import Application.Helper.Frontend.Options (FrontendCodecOptions (..),
                                            camelToKebabLower,
                                            defaultFrontendCodecOptions,
                                            dropPrefix, dropSuffix,
                                            lowerInitial)
import Application.Helper.UiRegion
import GHC.Generics (Generic)
import IHP.Prelude

instance HasFrontendCodec UiRegionDomAttributes where
    frontendCodec = genericFrontendCodecWith defaultFrontendCodecOptions
        { frontendTypeNameOverride = Just "UiRegionDom"
        , frontendFieldNameModifier = lowerInitial . dropSuffix "Attribute" . dropPrefix "uiRegion"
        }

instance HasFrontendCodec UiRegionTransitionProfile where
    frontendCodec = genericFrontendCodecWith defaultFrontendCodecOptions
        { frontendTypeNameOverride = Just "UiRegionTransitionProfile"
        , frontendConstructorTagModifier = \case
            "UiRegionTransitionNone" -> "none"
            "UiRegionTransitionFade" -> "fade"
            "UiRegionTransitionFadeSlide" -> "fade-slide"
            "UiRegionTransitionPanel" -> "panel"
            constructorName -> camelToKebabLower (dropPrefix "UiRegionTransition" constructorName)
        }

instance HasFrontendCodec UiRegionLifecycleEvent where
    frontendCodec = genericFrontendCodecWith defaultFrontendCodecOptions
        { frontendTypeNameOverride = Just "UiRegionLifecycleEvent"
        , frontendConstructorTagModifier = ("bepis:region-" <>) . camelToKebabLower . dropPrefix "UiRegion"
        }

data UiRegionEvents = UiRegionEvents
    { regionRequestStart :: !Text
    , regionBeforeSwap   :: !Text
    , regionAfterSwap    :: !Text
    , regionSettle       :: !Text
    , regionError        :: !Text
    }
    deriving (Eq, Show, Generic)

canonicalUiRegionEvents :: UiRegionEvents
canonicalUiRegionEvents = UiRegionEvents
    { regionRequestStart = uiRegionLifecycleEventName UiRegionRequestStart
    , regionBeforeSwap = uiRegionLifecycleEventName UiRegionBeforeSwap
    , regionAfterSwap = uiRegionLifecycleEventName UiRegionAfterSwap
    , regionSettle = uiRegionLifecycleEventName UiRegionSettle
    , regionError = uiRegionLifecycleEventName UiRegionError
    }

instance HasFrontendCodec UiRegionEvents where
    frontendCodec = genericFrontendCodecWith defaultFrontendCodecOptions
        { frontendTypeNameOverride = Just "UiRegionEvents"
        , frontendFieldNameModifier = lowerInitial . dropPrefix "region"
        }
