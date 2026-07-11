module Application.Helper.View.UiRegion
    ( uiRegionTransitionAttrs
    ) where

import Application.Helper.UiRegion (UiRegionDomAttributes (..),
                                    UiRegionTransitionProfile,
                                    canonicalUiRegionDomAttributes,
                                    uiRegionFragmentEnabledValue,
                                    uiRegionTransitionProfileText)
import IHP.Prelude
import qualified Text.Blaze.Html as Blaze

uiRegionTransitionAttrs :: UiRegionTransitionProfile -> Blaze.Attribute
uiRegionTransitionAttrs transitionProfile =
    attr canonicalUiRegionDomAttributes.uiRegionFragmentAttribute uiRegionFragmentEnabledValue
        <> attr canonicalUiRegionDomAttributes.uiRegionTransitionAttribute (uiRegionTransitionProfileText transitionProfile)

attr :: Text -> Text -> Blaze.Attribute
attr name value =
    Blaze.customAttribute (Blaze.textTag name) (Blaze.toValue value)
