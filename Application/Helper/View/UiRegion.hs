module Application.Helper.View.UiRegion
    ( uiRegionTransitionAttrs
    ) where

import Application.Helper.UiRegion (UiRegionDomAttributes (..),
                                    UiRegionTransitionProfile,
                                    canonicalUiRegionDomAttributes,
                                    uiRegionFragmentEnabledValue,
                                    uiRegionTransitionProfileText)
import IHP.Prelude

uiRegionTransitionAttrs :: UiRegionTransitionProfile -> [(Text, Text)]
uiRegionTransitionAttrs transitionProfile =
    [ (canonicalUiRegionDomAttributes.uiRegionFragmentAttribute, uiRegionFragmentEnabledValue)
    , (canonicalUiRegionDomAttributes.uiRegionTransitionAttribute, uiRegionTransitionProfileText transitionProfile)
    ]
