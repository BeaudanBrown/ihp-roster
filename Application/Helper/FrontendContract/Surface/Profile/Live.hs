module Application.Helper.FrontendContract.Surface.Profile.Live
    ( matchProfileLiveScope
    , matchStaffLiveScope
    , profileDetailsSectionLiveFragment
    , profileLeaveSectionLiveFragment
    , profileLiveScope
    , profilePreferencesSectionLiveFragment
    , profileRsaSectionLiveFragment
    , profileSecuritySectionLiveFragment
    , staffDetailsSectionLiveFragment
    , staffLeaveSectionLiveFragment
    , staffLiveScope
    , staffPreferencesSectionLiveFragment
    ) where

import Application.Helper.FrontendContract.Surface.Live (SurfaceScope)
import Application.Helper.FrontendContract.Surface.Profile.Generated.Live (profileDetailsSectionLiveFragment,
                                                                           profileLeaveSectionLiveFragment,
                                                                           profileLiveScope,
                                                                           profilePreferencesSectionLiveFragment,
                                                                           profileRsaSectionLiveFragment,
                                                                           profileSecuritySectionLiveFragment,
                                                                           staffDetailsSectionLiveFragment,
                                                                           staffLeaveSectionLiveFragment,
                                                                           staffLiveScope,
                                                                           staffPreferencesSectionLiveFragment)
import qualified Application.Helper.FrontendContract.Surface.Profile.Generated.Live as Generated
import qualified Data.UUID as UUID
import IHP.Prelude

-- | Recover the domain-shaped profile scope rather than exposing the
-- declaration-internal nested field tuple.
matchProfileLiveScope :: SurfaceScope -> Maybe (UUID.UUID, UUID.UUID)
matchProfileLiveScope scope = do
    (venueId, (staffId, ())) <- Generated.matchProfileLiveScope scope
    pure (venueId, staffId)

-- | Recover the domain-shaped staff-management scope.
matchStaffLiveScope :: SurfaceScope -> Maybe (UUID.UUID, UUID.UUID)
matchStaffLiveScope scope = do
    (venueId, (staffId, ())) <- Generated.matchStaffLiveScope scope
    pure (venueId, staffId)
