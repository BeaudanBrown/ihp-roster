{-# LANGUAGE TypeApplications #-}

module Application.Helper.Frontend.Dto.App
    ( OverlayLane (..)
    ) where

import Application.Helper.Frontend.AppConstants (AppEvents, AppOverlayDom)
import Application.Helper.Frontend.Codec (FrontendCodec, HasFrontendCodec (..))
import Application.Helper.Frontend.Generic (genericFrontendCodecWith)
import Application.Helper.Frontend.Options (FrontendCodecOptions (..),
                                            defaultFrontendCodecOptions,
                                            dropPrefix, dropSuffix,
                                            lowerInitial)
import GHC.Generics (Generic)
import IHP.Prelude

data OverlayLane
    = DialogLane
    | PickerLane
    | ToastLane
    deriving (Eq, Show, Generic)

instance HasFrontendCodec OverlayLane where
    frontendCodec = genericFrontendCodecWith defaultFrontendCodecOptions
        { frontendTypeNameOverride = Just "OverlayLane"
        , frontendConstructorTagModifier = lowerInitial . dropSuffix "Lane"
        }

instance HasFrontendCodec AppOverlayDom where
    frontendCodec = genericFrontendCodecWith defaultFrontendCodecOptions
        { frontendTypeNameOverride = Just "AppOverlayDom"
        , frontendFieldNameModifier = lowerInitial . dropPrefix "app"
        }

instance HasFrontendCodec AppEvents where
    frontendCodec = genericFrontendCodecWith appEventsOptions

appEventsOptions :: FrontendCodecOptions
appEventsOptions = defaultFrontendCodecOptions
    { frontendTypeNameOverride = Just "AppEvents"
    , frontendFieldNameModifier = lowerInitial . dropSuffix "EventName" . dropPrefix "app"
    }
