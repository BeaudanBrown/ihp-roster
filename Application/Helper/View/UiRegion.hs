{-# LANGUAGE TypeApplications #-}

module Application.Helper.View.UiRegion
    ( uiRegionTransitionAttrs
    , uiRegionLoadingAttrs
    , uiRegionBackgroundAttrs
    , uiRegionNavigationWriteBarrierAttrs
    ) where

import Application.Helper.UiRegion (UiRegionDomAttributes (..),
                                    UiRegionTransitionProfile,
                                    UiRegionLoadingPolicy,
                                    uiRegionLoadingPolicyText,
                                    canonicalUiRegionDomAttributes,
                                    uiRegionFragmentEnabledValue,
                                    uiRegionTransitionProfileText)
import qualified Application.Helper.FrontendContract.UiRegion as Contract
import Application.Helper.FrontendContract.Values (domAttrValue)
import IHP.Prelude

-- Defaults are delayed dimming and a brief arrival fade for user requests.
-- Background initiators opt out of both, independently of region preferences.
uiRegionLoadingAttrs :: UiRegionLoadingPolicy -> [(Text, Text)]
uiRegionLoadingAttrs policy =
    [ (canonicalUiRegionDomAttributes.uiRegionFragmentAttribute, uiRegionFragmentEnabledValue)
    , (canonicalUiRegionDomAttributes.uiRegionLoadingAttribute, uiRegionLoadingPolicyText policy)
    ]

uiRegionBackgroundAttrs :: [(Text, Text)]
uiRegionBackgroundAttrs =
    [(canonicalUiRegionDomAttributes.uiRegionBackgroundAttribute, uiRegionFragmentEnabledValue)]

-- Navigation waits for document writes; HTMX owns the resumed request and read sync.
uiRegionNavigationWriteBarrierAttrs :: [(Text, Text)]
uiRegionNavigationWriteBarrierAttrs =
    [(domAttrValue @Contract.NavigationWriteBarrier, uiRegionFragmentEnabledValue)]

uiRegionTransitionAttrs :: UiRegionTransitionProfile -> [(Text, Text)]
uiRegionTransitionAttrs transitionProfile =
    [ (canonicalUiRegionDomAttributes.uiRegionFragmentAttribute, uiRegionFragmentEnabledValue)
    , (canonicalUiRegionDomAttributes.uiRegionTransitionAttribute, uiRegionTransitionProfileText transitionProfile)
    ]
