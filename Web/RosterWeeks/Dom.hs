module Web.RosterWeeks.Dom
    ( closedRosterDayRows
    , minimumOpenRosterRows
    , rosterContentFragmentId
    , rosterGridFrameFragmentId
    , rosterGridToolbarFragmentId
    , rosterDaySectionDomId
    , rosterRowDomIdText
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

rosterGridToolbarFragmentId :: Text
rosterGridToolbarFragmentId = "roster-grid-toolbar"

rosterGridFrameFragmentId :: Text
rosterGridFrameFragmentId = "roster-grid-frame"

rosterStaffPanelFragmentId :: Text
rosterStaffPanelFragmentId = "roster-staff-panel-fragment"

rosterDaySectionDomId :: Id RosterDay -> Text
rosterDaySectionDomId rosterDayId = "roster-day-section-" <> tshow rosterDayId

rosterRowDomIdText :: Id RosterDay -> Int -> Text
rosterRowDomIdText rosterDayId rowIndex = "roster-row-" <> tshow rosterDayId <> "-" <> tshow rowIndex
