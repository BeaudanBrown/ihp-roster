{-# LANGUAGE TypeApplications #-}

module Application.Helper.FrontendContract.LiveUpdateValues
    ( liveUpdateSocketPathSegment
    , surfaceActionDomAttribute
    , surfaceConfigDomAttribute
    , surfaceDomAttribute
    ) where

import qualified Application.Helper.FrontendContract.Interaction as Interaction
import qualified Application.Helper.FrontendContract.LiveUpdate as LiveUpdate
import Application.Helper.FrontendContract.Values
import IHP.Prelude

liveUpdateSocketPathSegment :: Text
liveUpdateSocketPathSegment = constantValue @LiveUpdate.LiveUpdateSocketPath

surfaceDomAttribute :: Text
surfaceDomAttribute = domAttrValue @Interaction.Surface

surfaceConfigDomAttribute :: Text
surfaceConfigDomAttribute = domAttrValue @LiveUpdate.SurfaceConfig

surfaceActionDomAttribute :: Text
surfaceActionDomAttribute = domAttrValue @LiveUpdate.SurfaceAction
