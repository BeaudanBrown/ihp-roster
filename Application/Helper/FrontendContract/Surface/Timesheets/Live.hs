module Application.Helper.FrontendContract.Surface.Timesheets.Live
    ( matchTimesheetDayColumnsLiveFragment
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
import qualified Data.UUID as UUID
import IHP.Prelude

-- | Recover the domain-shaped Timesheets scope used by feature code rather
-- than exposing the declaration-internal nested field tuple.
matchTimesheetWeekLiveScope :: SurfaceScope -> Maybe (UUID.UUID, Int)
matchTimesheetWeekLiveScope scope = do
    (venueId, (weekOffset, ())) <- Generated.matchTimesheetWeekLiveScope scope
    pure (venueId, weekOffset)
