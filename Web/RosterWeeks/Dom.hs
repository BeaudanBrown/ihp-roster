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

import Generated.Types
import IHP.Prelude

minimumOpenRosterRows :: Int
minimumOpenRosterRows = 2

closedRosterDayRows :: Int
closedRosterDayRows = 2

rosterWeekShellId :: Text
rosterWeekShellId = "roster-week-shell"

rosterContentFragmentId :: Text
rosterContentFragmentId = "roster-content"

rosterDayTimelineContentFragmentId :: Id RosterDay -> Text
rosterDayTimelineContentFragmentId rosterDayId = "roster-day-timeline-content-" <> tshow rosterDayId

rosterGridToolbarFragmentId :: Text
rosterGridToolbarFragmentId = "roster-grid-toolbar"

rosterGridFrameFragmentId :: Text
rosterGridFrameFragmentId = "roster-grid-frame"

rosterDayColumnsFragmentId :: Text
rosterDayColumnsFragmentId = "roster-day-columns"

rosterDayRailFragmentId :: Text
rosterDayRailFragmentId = "roster-day-rail"

rosterWageRailFragmentId :: Text
rosterWageRailFragmentId = "roster-wage-rail"

rosterSlotsGridFragmentId :: Text
rosterSlotsGridFragmentId = "roster-slots-grid"

rosterStaffPanelFragmentId :: Text
rosterStaffPanelFragmentId = "roster-staff-panel-fragment"

rosterStaffPanelFragmentClasses :: [Text]
rosterStaffPanelFragmentClasses = ["col-12", "col-xl-4", "col-xxl-3", "roster-layout-side"]

rosterDaySectionDomId :: Id RosterDay -> Text
rosterDaySectionDomId rosterDayId = "roster-day-section-" <> tshow rosterDayId

rosterRowDomIdText :: Id RosterDay -> Int -> Text
rosterRowDomIdText rosterDayId rowIndex = "roster-row-" <> tshow rosterDayId <> "-" <> tshow rowIndex
