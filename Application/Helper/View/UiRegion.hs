module Application.Helper.View.UiRegion
    ( uiRegionTransitionAttrs
    , uiRegionLoadingAttrs
    ) where

import Application.Helper.UiRegion (UiRegionDomAttributes (..),
                                    UiRegionTransitionProfile,
                                    UiRegionLoadingPolicy,
                                    uiRegionLoadingPolicyText,
                                    canonicalUiRegionDomAttributes,
                                    uiRegionFragmentEnabledValue,
                                    uiRegionTransitionProfileText)
import IHP.Prelude

-- Defaults are delayed dimming and a brief arrival fade for user requests.
-- Background initiators opt out of both, independently of region preferences.
uiRegionLoadingAttrs :: UiRegionLoadingPolicy -> [(Text, Text)]
uiRegionLoadingAttrs policy =
    [ (canonicalUiRegionDomAttributes.uiRegionFragmentAttribute, uiRegionFragmentEnabledValue)
    , (canonicalUiRegionDomAttributes.uiRegionLoadingAttribute, uiRegionLoadingPolicyText policy)
    ]

uiRegionTransitionAttrs :: UiRegionTransitionProfile -> [(Text, Text)]
uiRegionTransitionAttrs transitionProfile =
    [ (canonicalUiRegionDomAttributes.uiRegionFragmentAttribute, uiRegionFragmentEnabledValue)
    , (canonicalUiRegionDomAttributes.uiRegionTransitionAttribute, uiRegionTransitionProfileText transitionProfile)
    ]
