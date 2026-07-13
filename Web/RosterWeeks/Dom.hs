{-# LANGUAGE TypeApplications #-}

module Web.RosterWeeks.Dom
    ( closedRosterDayRows
    , minimumOpenRosterRows
    , rosterContentFragmentId
    , rosterDayTimelineContentFragmentId
    , rosterGridFrameFragmentId
    , rosterGridToolbarFragmentId
    , rosterDayColumnsFragmentId
    , rosterDayRailFragmentId
    , rosterSlotsGridFragmentId
    , rosterWageRailFragmentId
    , rosterDaySectionDomId
    , rosterRowDomIdText
    , rosterStaffPanelFragmentClasses
    , rosterStaffPanelFragmentId
    , rosterWeekShellId
    ) where

import qualified Application.Helper.FrontendContract.Surface.Roster as Surface
import Application.Helper.FrontendContract.Surface.Values
import Generated.Types
import IHP.ModelSupport (unpackId)
import IHP.Prelude

minimumOpenRosterRows :: Int
minimumOpenRosterRows = 2

closedRosterDayRows :: Int
closedRosterDayRows = 2

rosterWeekShellId :: Text
rosterWeekShellId = surfaceDomTokenValue @Surface.RosterSurface @Surface.RosterWeekShell

rosterContentFragmentId :: Text
rosterContentFragmentId = surfaceFragmentTargetId @Surface.RosterSurface @Surface.RosterContent NoSurfaceFields

rosterDayTimelineContentFragmentId :: Id RosterDay -> Text
rosterDayTimelineContentFragmentId rosterDayId =
    surfaceFragmentTargetId @Surface.RosterDayTimelineSurface @Surface.RosterDayTimelineContent
        (surfaceField @Surface.RosterDayId (unpackId rosterDayId) :& NoSurfaceFields)

rosterGridToolbarFragmentId :: Text
rosterGridToolbarFragmentId = surfaceFragmentTargetId @Surface.RosterSurface @Surface.RosterGridToolbar NoSurfaceFields

rosterGridFrameFragmentId :: Text
rosterGridFrameFragmentId = surfaceFragmentTargetId @Surface.RosterSurface @Surface.RosterGridFrame NoSurfaceFields

rosterDayColumnsFragmentId :: Text
rosterDayColumnsFragmentId = surfaceFragmentTargetId @Surface.RosterSurface @Surface.RosterDayColumns NoSurfaceFields

rosterDayRailFragmentId :: Text
rosterDayRailFragmentId = surfaceFragmentTargetId @Surface.RosterSurface @Surface.RosterDayRail NoSurfaceFields

rosterWageRailFragmentId :: Text
rosterWageRailFragmentId = surfaceFragmentTargetId @Surface.RosterSurface @Surface.RosterWageRail NoSurfaceFields

rosterSlotsGridFragmentId :: Text
rosterSlotsGridFragmentId = surfaceFragmentTargetId @Surface.RosterSurface @Surface.RosterSlotsGrid NoSurfaceFields

rosterStaffPanelFragmentId :: Text
rosterStaffPanelFragmentId = surfaceFragmentTargetId @Surface.RosterSurface @Surface.RosterStaffPanel NoSurfaceFields

rosterStaffPanelFragmentClasses :: [Text]
rosterStaffPanelFragmentClasses = ["col-12", "col-xl-4", "col-xxl-3", "roster-layout-side"]

rosterDaySectionDomId :: Id RosterDay -> Text
rosterDaySectionDomId rosterDayId =
    surfaceFragmentTargetId @Surface.RosterSurface @Surface.RosterDaySection
        (surfaceField @Surface.RosterDayId (unpackId rosterDayId) :& NoSurfaceFields)

rosterRowDomIdText :: Id RosterDay -> Int -> Text
rosterRowDomIdText rosterDayId rowIndex =
    surfaceFragmentTargetId @Surface.RosterSurface @Surface.RosterRow
        ( surfaceField @Surface.RosterDayId (unpackId rosterDayId)
            :& surfaceField @Surface.RowIndex rowIndex
            :& NoSurfaceFields
        )
