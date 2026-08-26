module Application.Helper.FrontendContract.Surface.Timesheets.Live
    ( activeTimesheetWindowScopes
    , activeTimesheetWindowScopesWithBus
    , matchTimesheetDayColumnsLiveFragment
    , matchTimesheetDaySectionLiveFragment
    , matchTimesheetSidePanelContentLiveFragment
    , matchTimesheetToolbarLiveFragment
    , matchTimesheetWindowLiveScope
    , timesheetDayColumnsLiveFragment
    , timesheetDaySectionLiveFragment
    , timesheetSidePanelContentLiveFragment
    , timesheetToolbarLiveFragment
    , timesheetWeekLiveScope
    ) where

import Application.Helper.FrontendContract.Surface.Live (SurfaceScope)
import Application.Helper.FrontendContract.Surface.Timesheets.Generated.Live (matchTimesheetDayColumnsLiveFragment,
                                                                              matchTimesheetDaySectionLiveFragment,
                                                                              matchTimesheetSidePanelContentLiveFragment,
                                                                              matchTimesheetToolbarLiveFragment,
                                                                              timesheetDayColumnsLiveFragment,
                                                                              timesheetDaySectionLiveFragment,
                                                                              timesheetSidePanelContentLiveFragment,
                                                                              timesheetToolbarLiveFragment,
                                                                              timesheetWeekLiveScope)
import qualified Application.Helper.FrontendContract.Surface.Timesheets.Generated.Live as Generated
import Application.Helper.LiveUpdate.Runtime (LiveBus,
                                              activeSurfaceScopeMatches,
                                              activeSurfaceScopeMatchesWithBus)
import Data.Time.Calendar (Day)
import qualified Data.UUID as UUID
import IHP.Prelude

matchTimesheetWindowLiveScope :: SurfaceScope -> Maybe (UUID.UUID, Day, Day, Int)
matchTimesheetWindowLiveScope scope = do
    (venueId, (windowStart, (windowEnd, (calendarRevision, ())))) <- Generated.matchTimesheetWeekLiveScope scope
    pure (venueId, windowStart, windowEnd, calendarRevision)

activeTimesheetWindowScopes :: IO [(UUID.UUID, Day, Day, Int)]
activeTimesheetWindowScopes = activeSurfaceScopeMatches matchTimesheetWindowLiveScope

activeTimesheetWindowScopesWithBus :: LiveBus -> IO [(UUID.UUID, Day, Day, Int)]
activeTimesheetWindowScopesWithBus bus =
    activeSurfaceScopeMatchesWithBus bus matchTimesheetWindowLiveScope
