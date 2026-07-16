module Application.Helper.FrontendContract.Surface.Roster.Resource
    ( matchRosterEndTimesConfigResource
    , matchRosterWeekBoundaryConfigResource
    , rosterDayResource
    , rosterEndTimesConfigResource
    , rosterWeekBoundaryConfigResource
    , rosterWeekResource
    , timePickerConfigResource
    ) where

import Application.Helper.FrontendContract.Surface.Resource (SurfaceResourceValue)
import Application.Helper.FrontendContract.Surface.Roster.Generated.Resource (rosterDayResource,
                                                                              rosterEndTimesConfigResource,
                                                                              rosterWeekBoundaryConfigResource,
                                                                              rosterWeekResource,
                                                                              timePickerConfigResource)
import qualified Application.Helper.FrontendContract.Surface.Roster.Generated.Resource as Generated
import qualified Data.UUID as UUID
import IHP.Prelude

matchRosterEndTimesConfigResource :: SurfaceResourceValue -> Maybe UUID.UUID
matchRosterEndTimesConfigResource = fmap fst . Generated.matchRosterEndTimesConfigResource

matchRosterWeekBoundaryConfigResource :: SurfaceResourceValue -> Maybe UUID.UUID
matchRosterWeekBoundaryConfigResource = fmap fst . Generated.matchRosterWeekBoundaryConfigResource
