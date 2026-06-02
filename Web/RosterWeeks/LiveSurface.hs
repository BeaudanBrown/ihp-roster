{-# LANGUAGE BlockArguments      #-}
{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE LambdaCase          #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# OPTIONS_GHC -Werror=incomplete-patterns #-}

module Web.RosterWeeks.LiveSurface
    ( RosterLiveSurface
    , mkRosterProjectionDefinition
    , rosterLiveSurfaceDefinition
    , rosterProjectionVersion
    ) where

import Application.Helper.Controller
import Application.Helper.LiveResource (LiveResource (..))
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
                              rosterWeekDayColumnsFragmentUrl,
                              rosterWeekDayRailFragmentUrl,
                              rosterWeekDaySectionFragmentUrl,
                              rosterWeekGridFrameFragmentUrl,
                              rosterWeekGridToolbarFragmentUrl,
                              rosterWeekRowFragmentUrl,
                              rosterWeekSlotsGridFragmentUrl,
                              rosterWeekStaffPanelFragmentUrl,
                              rosterWeekWageRailFragmentUrl)
import Web.RosterWeeks.Projection
import Web.RosterWeeks.Types

data RosterLiveSurface

rosterLiveSurfaceDefinition :: (?context :: ControllerContext) => TypedLiveSurfaceDefinition RosterLiveSurface RosterProjectionScope RosterProjectionFragment
rosterLiveSurfaceDefinition =
    TypedLiveSurfaceDefinition
        { typedSurfaceFeature = "roster"
        , typedSurfaceScope = rosterSurfaceScope
        , typedSurfaceScopeFromWire = rosterSurfaceScopeFromWire
        , typedSurfaceDefaultFragments = const [RosterProjectionGridToolbar, RosterProjectionDayColumns, RosterProjectionDayRail, RosterProjectionWageRail, RosterProjectionSlotsGrid, RosterProjectionStaffPanel]
        , typedSurfaceFragmentContract = \scope fragment ->
            mkSurfaceFragmentContract
                (rosterFragmentRef scope fragment)
                (rosterFragmentDependencies scope fragment)
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

rosterFragmentRef :: RosterProjectionScope -> RosterProjectionFragment -> SurfaceFragmentRef RosterLiveSurface
rosterFragmentRef scope = \case
    RosterProjectionContent ->
        mkSurfaceFragmentRef
            RosterContentFragment
            rosterContentFragmentId
            (rosterWeekContentFragmentUrl scope.rosterProjectionWeekOffset scope.rosterProjectionGroupId)
            |> surfaceFragmentRefWithPath (rosterFragmentContainmentPath RosterProjectionContent)
    RosterProjectionGridToolbar ->
        mkSurfaceFragmentRef
            RosterGridToolbarFragment
            rosterGridToolbarFragmentId
            (rosterWeekGridToolbarFragmentUrl scope.rosterProjectionWeekOffset scope.rosterProjectionGroupId)
            |> surfaceFragmentRefWithPath (rosterFragmentContainmentPath RosterProjectionGridToolbar)
    RosterProjectionGridFrame ->
        mkSurfaceFragmentRef
            RosterGridFrameFragment
            rosterGridFrameFragmentId
            (rosterWeekGridFrameFragmentUrl scope.rosterProjectionWeekOffset scope.rosterProjectionGroupId)
            |> surfaceFragmentRefWithPath (rosterFragmentContainmentPath RosterProjectionGridFrame)
    RosterProjectionDayColumns ->
        mkSurfaceFragmentRef
            RosterDayColumnsFragment
            rosterDayColumnsFragmentId
            (rosterWeekDayColumnsFragmentUrl scope.rosterProjectionWeekOffset scope.rosterProjectionGroupId)
            |> surfaceFragmentRefWithPath (rosterFragmentContainmentPath RosterProjectionDayColumns)
    RosterProjectionDayRail ->
        mkSurfaceFragmentRef
            RosterDayRailFragment
            rosterDayRailFragmentId
            (rosterWeekDayRailFragmentUrl scope.rosterProjectionWeekOffset scope.rosterProjectionGroupId)
            |> surfaceFragmentRefWithPath (rosterFragmentContainmentPath RosterProjectionDayRail)
    RosterProjectionWageRail ->
        mkSurfaceFragmentRef
            RosterWageRailFragment
            rosterWageRailFragmentId
            (rosterWeekWageRailFragmentUrl scope.rosterProjectionWeekOffset scope.rosterProjectionGroupId)
            |> surfaceFragmentRefWithPath (rosterFragmentContainmentPath RosterProjectionWageRail)
    RosterProjectionSlotsGrid ->
        mkSurfaceFragmentRef
            RosterSlotsGridFragment
            rosterSlotsGridFragmentId
            (rosterWeekSlotsGridFragmentUrl scope.rosterProjectionWeekOffset scope.rosterProjectionGroupId)
            |> surfaceFragmentRefWithPath (rosterFragmentContainmentPath RosterProjectionSlotsGrid)
    RosterProjectionStaffPanel ->
        mkSurfaceFragmentRef
            RosterStaffPanelFragment
            rosterStaffPanelFragmentId
            (rosterWeekStaffPanelFragmentUrl scope.rosterProjectionWeekOffset scope.rosterProjectionGroupId)
            |> surfaceFragmentRefWithPath (rosterFragmentContainmentPath RosterProjectionStaffPanel)
    RosterProjectionDaySection rosterDayId ->
        mkSurfaceFragmentRef
            RosterDaySectionFragment { rosterDayId }
            (rosterDaySectionDomId (coerce rosterDayId))
            (rosterWeekDaySectionFragmentUrl scope.rosterProjectionWeekOffset scope.rosterProjectionGroupId (coerce rosterDayId))
            |> surfaceFragmentRefWithPath (rosterFragmentContainmentPath (RosterProjectionDaySection rosterDayId))
    RosterProjectionRow rosterDayId rowIndex ->
        mkSurfaceFragmentRef
            RosterRowFragment { rosterDayId, rowIndex }
            (rosterRowDomIdText (coerce rosterDayId) rowIndex)
            (rosterWeekRowFragmentUrl scope.rosterProjectionWeekOffset scope.rosterProjectionGroupId (coerce rosterDayId) rowIndex)
            |> surfaceFragmentRefWithPath (rosterFragmentContainmentPath (RosterProjectionRow rosterDayId rowIndex))

rosterFragmentDependencies :: (?context :: ControllerContext) => RosterProjectionScope -> RosterProjectionFragment -> FragmentDependencies
rosterFragmentDependencies scope =
    let venueId = unpackId currentVenueId
     in \case
            RosterProjectionContent ->
                liveFragmentDependsOn
                    (RosterWeekResource (unpackId scope.rosterProjectionGroupId) scope.rosterProjectionWeekOffset)
                    [ RosterEndTimesConfigResource venueId
                    , RosterWeekBoundaryConfigResource venueId
                    ]
            RosterProjectionGridToolbar ->
                liveFragmentDependsOn
                    (RosterWeekResource (unpackId scope.rosterProjectionGroupId) scope.rosterProjectionWeekOffset)
                    [ RosterEndTimesConfigResource venueId
                    , RosterWeekBoundaryConfigResource venueId
                    ]
            RosterProjectionGridFrame ->
                liveFragmentDependsOn
                    (RosterWeekResource (unpackId scope.rosterProjectionGroupId) scope.rosterProjectionWeekOffset)
                    [ RosterEndTimesConfigResource venueId
                    , RosterWeekBoundaryConfigResource venueId
                    ]
            RosterProjectionDayColumns ->
                liveFragmentDependsOn
                    (RosterWeekResource (unpackId scope.rosterProjectionGroupId) scope.rosterProjectionWeekOffset)
                    [ RosterEndTimesConfigResource venueId
                    , RosterWeekBoundaryConfigResource venueId
                    ]
            RosterProjectionDayRail ->
                liveFragmentDependsOn
                    (RosterWeekResource (unpackId scope.rosterProjectionGroupId) scope.rosterProjectionWeekOffset)
                    [ RosterEndTimesConfigResource venueId
                    , RosterWeekBoundaryConfigResource venueId
                    ]
            RosterProjectionWageRail ->
                liveFragmentDependsOn
                    (RosterWeekResource (unpackId scope.rosterProjectionGroupId) scope.rosterProjectionWeekOffset)
                    [ RosterEndTimesConfigResource venueId
                    , RosterWeekBoundaryConfigResource venueId
                    ]
            RosterProjectionSlotsGrid ->
                liveFragmentDependsOn
                    (RosterWeekResource (unpackId scope.rosterProjectionGroupId) scope.rosterProjectionWeekOffset)
                    [ RosterEndTimesConfigResource venueId
                    , RosterWeekBoundaryConfigResource venueId
                    ]
            RosterProjectionStaffPanel ->
                liveFragmentDependsOn (RosterWeekResource (unpackId scope.rosterProjectionGroupId) scope.rosterProjectionWeekOffset) []
            RosterProjectionDaySection rosterDayId ->
                liveFragmentDependsOn
                    (RosterDayResource rosterDayId)
                    [ RosterEndTimesConfigResource venueId
                    , RosterWeekBoundaryConfigResource venueId
                    ]
            RosterProjectionRow rosterDayId _ ->
                liveFragmentDependsOn
                    (RosterDayResource rosterDayId)
                    [ RosterEndTimesConfigResource venueId
                    , RosterWeekBoundaryConfigResource venueId
                    ]

rosterFragmentContainmentPath :: RosterProjectionFragment -> [Text]
rosterFragmentContainmentPath = \case
    RosterProjectionContent ->
        [rosterContentFragmentId]
    RosterProjectionGridToolbar ->
        [rosterContentFragmentId, rosterGridToolbarFragmentId]
    RosterProjectionGridFrame ->
        [rosterContentFragmentId, rosterGridFrameFragmentId]
    RosterProjectionDayColumns ->
        [rosterContentFragmentId, rosterGridFrameFragmentId, rosterDayColumnsFragmentId]
    RosterProjectionDayRail ->
        [rosterContentFragmentId, rosterGridFrameFragmentId, rosterDayRailFragmentId]
    RosterProjectionWageRail ->
        [rosterContentFragmentId, rosterGridFrameFragmentId, rosterWageRailFragmentId]
    RosterProjectionSlotsGrid ->
        [rosterContentFragmentId, rosterGridFrameFragmentId, rosterSlotsGridFragmentId]
    RosterProjectionStaffPanel ->
        [rosterStaffPanelFragmentId]
    RosterProjectionDaySection rosterDayId ->
        [rosterContentFragmentId, rosterGridFrameFragmentId, rosterDaySectionDomId (coerce rosterDayId)]
    RosterProjectionRow rosterDayId rowIndex ->
        [rosterContentFragmentId, rosterGridFrameFragmentId, rosterDaySectionDomId (coerce rosterDayId), rosterRowDomIdText (coerce rosterDayId) rowIndex]

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
            userShowWageEstimates <- fetchCurrentUserShowWageEstimates
            venueConfig <- fetchVenueConfig
            let showWageEstimates = venueConfig.rosterEndTimesEnabled && userShowWageEstimates
            pure (tshow currentUser.id <> ":" <> encodeRosterAssignmentFilters filters <> ":" <> rosterLayoutModeValue layoutMode <> ":" <> (if showWageEstimates then "wages" else "no-wages"))
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
