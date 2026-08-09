module Application.Helper.FrontendContract.Surface.Roster.Live
    ( activeRosterWindowScopes
    , activeRosterWindowScopesWithBus
    , matchRosterWindowLiveScope
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
import Data.Time.Calendar (Day)
import qualified Data.UUID as UUID
import IHP.Prelude

-- | Recover explicit date range and calendar revision identity for active windows.
matchRosterWindowLiveScope :: SurfaceScope -> Maybe (UUID.UUID, UUID.UUID, Day, Day, Int)
matchRosterWindowLiveScope scope = do
    (venueId, (rosterGroupId, (windowStart, (windowEnd, (calendarRevision, ()))))) <- Generated.matchRosterWeekLiveScope scope
    pure (venueId, rosterGroupId, windowStart, windowEnd, calendarRevision)

activeRosterWindowScopes :: IO [(UUID.UUID, UUID.UUID, Day, Day, Int)]
activeRosterWindowScopes = activeSurfaceScopeMatches matchRosterWindowLiveScope

activeRosterWindowScopesWithBus :: LiveBus -> IO [(UUID.UUID, UUID.UUID, Day, Day, Int)]
activeRosterWindowScopesWithBus bus =
    activeSurfaceScopeMatchesWithBus bus matchRosterWindowLiveScope
