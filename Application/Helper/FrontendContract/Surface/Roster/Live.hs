module Application.Helper.FrontendContract.Surface.Roster.Live
    ( activeRosterWeekScopes
    , activeRosterWeekScopesWithBus
    , matchRosterWeekLiveScope
    , rosterContentLiveFragment
    , rosterDayColumnsLiveFragment
    , rosterDayRailLiveFragment
    , rosterDaySectionLiveFragment
    , rosterDayTimelineLiveScope
    , rosterGridFrameLiveFragment
    , rosterGridToolbarLiveFragment
    , rosterRowLiveFragment
    , rosterSlotsGridLiveFragment
    , rosterStaffPanelLiveFragment
    , rosterTemplateLibraryLiveFragment
    , rosterWageRailLiveFragment
    , rosterWeekLiveScope
    ) where

import Application.Helper.FrontendContract.Surface.Live (SurfaceScope)
import Application.Helper.FrontendContract.Surface.Roster.Generated.Live (rosterContentLiveFragment,
                                                                          rosterDayColumnsLiveFragment,
                                                                          rosterDayRailLiveFragment,
                                                                          rosterDaySectionLiveFragment,
                                                                          rosterDayTimelineLiveScope,
                                                                          rosterGridFrameLiveFragment,
                                                                          rosterGridToolbarLiveFragment,
                                                                          rosterRowLiveFragment,
                                                                          rosterSlotsGridLiveFragment,
                                                                          rosterStaffPanelLiveFragment,
                                                                          rosterTemplateLibraryLiveFragment,
                                                                          rosterWageRailLiveFragment,
                                                                          rosterWeekLiveScope)
import qualified Application.Helper.FrontendContract.Surface.Roster.Generated.Live as Generated
import Application.Helper.LiveUpdate.Runtime (LiveBus,
                                              activeSurfaceScopeMatches,
                                              activeSurfaceScopeMatchesWithBus)
import qualified Data.UUID as UUID
import IHP.Prelude

-- | Recover the domain-shaped roster scope used by active-scope expansion.
matchRosterWeekLiveScope :: SurfaceScope -> Maybe (UUID.UUID, UUID.UUID, Int)
matchRosterWeekLiveScope scope = do
    (venueId, (rosterGroupId, (weekOffset, ()))) <- Generated.matchRosterWeekLiveScope scope
    pure (venueId, rosterGroupId, weekOffset)

activeRosterWeekScopes :: IO [(UUID.UUID, UUID.UUID, Int)]
activeRosterWeekScopes = activeSurfaceScopeMatches matchRosterWeekLiveScope

activeRosterWeekScopesWithBus :: LiveBus -> IO [(UUID.UUID, UUID.UUID, Int)]
activeRosterWeekScopesWithBus bus =
    activeSurfaceScopeMatchesWithBus bus matchRosterWeekLiveScope
