module Application.Helper.View.UiRegion
    ( uiRegionAttrs
    , uiRegionTransitionAttrs
    ) where

import Application.Helper.UiRegion (UiRegionTransitionProfile (..),
                                    uiRegionFragmentEnabledValue,
                                    uiRegionTransitionProfileText)
import IHP.Prelude
import qualified Text.Blaze.Html as Blaze

uiRegionAttrs :: Blaze.Attribute
uiRegionAttrs =
    uiRegionTransitionAttrs UiRegionTransitionNone

uiRegionTransitionAttrs :: UiRegionTransitionProfile -> Blaze.Attribute
uiRegionTransitionAttrs transitionProfile =
    attr "data-bepis-fragment" uiRegionFragmentEnabledValue
        <> attr "data-bepis-region-transition" (uiRegionTransitionProfileText transitionProfile)

attr :: Text -> Text -> Blaze.Attribute
attr name value =
    Blaze.customAttribute (Blaze.textTag name) (Blaze.toValue value)
