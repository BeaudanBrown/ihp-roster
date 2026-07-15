{-# LANGUAGE TypeApplications #-}

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
import qualified Application.Helper.FrontendContract.Surface.Resource as Resource
import qualified Application.Helper.FrontendContract.Surface.Roster as Surface
import Application.Helper.FrontendContract.Surface.Values
import qualified Data.UUID as UUID
import IHP.Prelude

rosterWeekResource :: UUID.UUID -> Int -> SurfaceResourceValue
rosterWeekResource rosterGroupId weekOffset =
    Resource.frontendSurfaceResource @Surface.RosterSurface @Surface.RosterWeek
        ( surfaceField @Surface.RosterGroupId rosterGroupId
            :& surfaceField @Surface.WeekOffset weekOffset
            :& NoSurfaceFields
        )

rosterDayResource :: UUID.UUID -> SurfaceResourceValue
rosterDayResource rosterDayId =
    Resource.frontendSurfaceResource @Surface.RosterSurface @Surface.RosterDay
        (surfaceField @Surface.RosterDayId rosterDayId :& NoSurfaceFields)

rosterEndTimesConfigResource, rosterWeekBoundaryConfigResource, timePickerConfigResource :: UUID.UUID -> SurfaceResourceValue
rosterEndTimesConfigResource venueId =
    Resource.frontendSurfaceResource @Surface.RosterSurface @Surface.RosterEndTimesConfig
        (surfaceField @Surface.VenueId venueId :& NoSurfaceFields)
rosterWeekBoundaryConfigResource venueId =
    Resource.frontendSurfaceResource @Surface.RosterSurface @Surface.RosterWeekBoundaryConfig
        (surfaceField @Surface.VenueId venueId :& NoSurfaceFields)
timePickerConfigResource venueId =
    Resource.frontendSurfaceResource @Surface.RosterDayTimelineSurface @Surface.TimePickerConfig
        (surfaceField @Surface.VenueId venueId :& NoSurfaceFields)

matchRosterEndTimesConfigResource :: SurfaceResourceValue -> Maybe UUID.UUID
matchRosterEndTimesConfigResource value = do
    (venueId, ()) <-
        Resource.matchFrontendSurfaceResource @Surface.RosterSurface @Surface.RosterEndTimesConfig value
    pure venueId

matchRosterWeekBoundaryConfigResource :: SurfaceResourceValue -> Maybe UUID.UUID
matchRosterWeekBoundaryConfigResource value = do
    (venueId, ()) <-
        Resource.matchFrontendSurfaceResource @Surface.RosterSurface @Surface.RosterWeekBoundaryConfig value
    pure venueId
