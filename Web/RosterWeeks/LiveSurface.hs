{-# LANGUAGE BlockArguments      #-}
{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE OverloadedRecordDot #-}

module Web.RosterWeeks.LiveSurface
    ( RosterLiveSurface
    , mkRosterProjectionDefinition
    , rosterLiveSurfaceDefinition
    , rosterProjectionVersion
    ) where

import Application.Helper.Controller
import Application.Helper.LiveSurface
import Application.Helper.LiveUpdate (LiveFragmentKey (..), LiveUpdateScope (..), currentLiveUpdateVersion)
import Application.Helper.SurfaceProjection
import Application.Helper.UserPreferences
import Data.Coerce (coerce)
import qualified Data.Time.Calendar as Calendar
import qualified Text.Blaze.Html as Blaze
import Web.Controller.Prelude
import Web.RosterWeeks.Dom
import Web.RosterWeeks.Filters
import Web.RosterWeeks.Paths (rosterWeekContentFragmentUrl,
                              rosterWeekDaySectionFragmentUrl,
                              rosterWeekRowFragmentUrl,
                              rosterWeekStaffPanelFragmentUrl)
import Web.RosterWeeks.Projection
import Web.RosterWeeks.Types

data RosterLiveSurface

rosterLiveSurfaceDefinition :: (?context :: ControllerContext) => TypedLiveSurfaceDefinition RosterLiveSurface RosterProjectionScope RosterProjectionFragment
rosterLiveSurfaceDefinition =
    TypedLiveSurfaceDefinition
        { typedSurfaceFeature = "roster"
        , typedSurfaceScope = rosterSurfaceScope
        , typedSurfaceScopeFromWire = rosterSurfaceScopeFromWire
        , typedSurfaceDefaultFragments = const [RosterProjectionContent, RosterProjectionStaffPanel]
        , typedSurfaceFragmentRef = \scope fragment ->
            case fragment of
                RosterProjectionContent ->
                    mkSurfaceFragmentRef
                        RosterContentFragment
                        rosterContentFragmentId
                        (rosterWeekContentFragmentUrl scope.rosterProjectionWeekOffset scope.rosterProjectionGroupId)
                RosterProjectionStaffPanel ->
                    mkSurfaceFragmentRef
                        RosterStaffPanelFragment
                        rosterStaffPanelFragmentId
                        (rosterWeekStaffPanelFragmentUrl scope.rosterProjectionWeekOffset scope.rosterProjectionGroupId)
                RosterProjectionDaySection rosterDayId ->
                    mkSurfaceFragmentRef
                        RosterDaySectionFragment { rosterDayId }
                        (rosterDaySectionDomId (coerce rosterDayId))
                        (rosterWeekDaySectionFragmentUrl scope.rosterProjectionWeekOffset scope.rosterProjectionGroupId (coerce rosterDayId))
                RosterProjectionRow rosterDayId rowIndex ->
                    mkSurfaceFragmentRef
                        RosterRowFragment { rosterDayId, rowIndex }
                        (rosterRowDomIdText (coerce rosterDayId) rowIndex)
                        (rosterWeekRowFragmentUrl scope.rosterProjectionWeekOffset scope.rosterProjectionGroupId (coerce rosterDayId) rowIndex)
        , typedSurfaceDecorateRequestsWithin = const ["#roster-week-shell"]
        , typedSurfaceAuthorize = liveSurfaceAuthorizationByRequirement (\scope -> RequireCurrentVenueRosterGroup (unpackId currentVenueId) (unpackId scope.rosterProjectionGroupId))
        }
    where
        rosterSurfaceScope scope =
            SurfaceScope (buildRosterWeekScope scope.rosterProjectionGroupId scope.rosterProjectionWeekOffset)

        rosterSurfaceScopeFromWire scope =
            case (currentVenueOrNothing, scope) of
                (Just _, RosterWeekScope { rosterGroupId, weekOffset }) ->
                    Just RosterProjectionScope
                        { rosterProjectionGroupId = coerce rosterGroupId
                        , rosterProjectionWeekOffset = weekOffset
                        }
                _ ->
                    Nothing

mkRosterProjectionDefinition ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    (RosterProjectionScope -> IO snapshot) ->
    (snapshot -> RosterProjectionFragment -> Maybe Blaze.Html) ->
    ProjectionLiveSurfaceDefinition RosterLiveSurface RosterProjectionScope snapshot RosterProjectionFragment
mkRosterProjectionDefinition =
    mkTypedSurfaceProjectionDefinition
        rosterLiveSurfaceDefinition
        "roster-week"
        defaultSurfaceProjectionCachePolicy
        (\scope -> tshow scope.rosterProjectionGroupId <> ":" <> tshow scope.rosterProjectionWeekOffset)
        do
            filters <- fetchRosterAssignmentFilters
            layoutMode <- fetchCurrentRosterLayoutMode
            pure (tshow currentUser.id <> ":" <> encodeRosterAssignmentFilters filters <> ":" <> rosterLayoutModeValue layoutMode)
        rosterProjectionVersion

rosterProjectionVersion :: (?context :: ControllerContext, ?modelContext :: ModelContext) => RosterProjectionScope -> IO Int
rosterProjectionVersion scope = do
    rosterVersion <- currentLiveUpdateVersion (buildRosterWeekScope scope.rosterProjectionGroupId scope.rosterProjectionWeekOffset)
    if hasRole ManagerRole' || currentUserIsSuperAdmin
        then pure rosterVersion
        else do
            venueConfig <- fetchVenueConfig
            operationalDay <- currentOperationalDayForVenue venueConfig
            let timesheetWeekOffset = venueWeekOffsetForDay venueConfig operationalDay
            timesheetVersion <- currentLiveUpdateVersion TimesheetWeekScope { venueId = unpackId currentVenueId, weekOffset = timesheetWeekOffset }
            leaveVersion <- currentLiveUpdateVersion LeaveRequestsScope { venueId = unpackId currentVenueId }
            pure (rosterVersion + timesheetVersion + leaveVersion + fromInteger (Calendar.toModifiedJulianDay operationalDay))
