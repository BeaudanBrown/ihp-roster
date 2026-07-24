module Application.Helper.FrontendContract.Surface.Timesheets.Live
    ( activeTimesheetWeekScopes
    , activeTimesheetWeekScopesWithBus
    , matchTimesheetDayColumnsLiveFragment
    , matchTimesheetDaySectionLiveFragment
    , matchTimesheetToolbarLiveFragment
    , matchTimesheetWeekLiveScope
    , timesheetDayColumnsLiveFragment
    , timesheetDaySectionLiveFragment
    , timesheetToolbarLiveFragment
    , timesheetWeekLiveScope
    ) where

import Application.Helper.FrontendContract.Surface.Live (SurfaceScope)
import Application.Helper.FrontendContract.Surface.Timesheets.Generated.Live (matchTimesheetDayColumnsLiveFragment,
                                                                              matchTimesheetDaySectionLiveFragment,
                                                                              matchTimesheetToolbarLiveFragment,
                                                                              timesheetDayColumnsLiveFragment,
                                                                              timesheetDaySectionLiveFragment,
                                                                              timesheetToolbarLiveFragment,
                                                                              timesheetWeekLiveScope)
import qualified Application.Helper.FrontendContract.Surface.Timesheets.Generated.Live as Generated
import Application.Helper.LiveUpdate.Runtime (LiveBus,
                                              activeSurfaceScopeMatches,
                                              activeSurfaceScopeMatchesWithBus)
import qualified Data.UUID as UUID
import IHP.Prelude

matchTimesheetWeekLiveScope :: SurfaceScope -> Maybe (UUID.UUID, Int)
matchTimesheetWeekLiveScope scope = do
    (venueId, (weekOffset, ())) <- Generated.matchTimesheetWeekLiveScope scope
    pure (venueId, weekOffset)

activeTimesheetWeekScopes :: IO [(UUID.UUID, Int)]
activeTimesheetWeekScopes = activeSurfaceScopeMatches matchTimesheetWeekLiveScope

activeTimesheetWeekScopesWithBus :: LiveBus -> IO [(UUID.UUID, Int)]
activeTimesheetWeekScopesWithBus bus =
    activeSurfaceScopeMatchesWithBus bus matchTimesheetWeekLiveScope
