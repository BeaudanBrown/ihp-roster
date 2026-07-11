module Web.RosterWeeks.Projection
    ( actorRosterRowFragments
    , rosterContentAndStaffPanelFragments
    , rosterContentFragment
    , rosterGridFrameFragment
    , rosterGridToolbarFragment
    , rosterGridInnerAndStaffPanelFragments
    , rosterGridFrameAndStaffPanelFragments
    , rosterGridStructuralFragments
    , rosterDaySectionFragment
    , rosterDaySectionFragments
    , rosterRowFragment
    , rosterRowFragments
    , rosterStaffPanelFragment
    ) where

import qualified Data.UUID as UUID
import Web.Controller.Prelude
import Web.RosterWeeks.Types

rosterContentFragment :: RosterProjectionFragment
rosterContentFragment =
    RosterProjectionContent

rosterGridToolbarFragment :: RosterProjectionFragment
rosterGridToolbarFragment =
    RosterProjectionGridToolbar

rosterGridFrameFragment :: RosterProjectionFragment
rosterGridFrameFragment =
    RosterProjectionGridFrame

rosterStaffPanelFragment :: RosterProjectionFragment
rosterStaffPanelFragment =
    RosterProjectionStaffPanel

rosterGridStructuralFragments :: [RosterProjectionFragment]
rosterGridStructuralFragments =
    [ rosterGridToolbarFragment
    , rosterGridFrameFragment
    ]

rosterGridInnerAndStaffPanelFragments :: [RosterProjectionFragment]
rosterGridInnerAndStaffPanelFragments =
    [ RosterProjectionDayColumns
    , RosterProjectionDayRail
    , RosterProjectionWageRail
    , RosterProjectionSlotsGrid
    , rosterStaffPanelFragment
    ]

rosterGridFrameAndStaffPanelFragments :: [RosterProjectionFragment]
rosterGridFrameAndStaffPanelFragments =
    [ rosterGridFrameFragment
    , rosterStaffPanelFragment
    ]

rosterContentAndStaffPanelFragments :: [RosterProjectionFragment]
rosterContentAndStaffPanelFragments =
    [ rosterContentFragment
    , rosterStaffPanelFragment
    ]

rosterDaySectionFragment :: UUID.UUID -> RosterProjectionFragment
rosterDaySectionFragment =
    RosterProjectionDaySection

rosterDaySectionFragments :: [UUID.UUID] -> [RosterProjectionFragment]
rosterDaySectionFragments =
    map rosterDaySectionFragment . nub

rosterRowFragment :: UUID.UUID -> Int -> RosterProjectionFragment
rosterRowFragment =
    RosterProjectionRow

rosterRowFragments :: [(UUID.UUID, Int)] -> [RosterProjectionFragment]
rosterRowFragments =
    map (uncurry rosterRowFragment) . nub

actorRosterRowFragments :: [(UUID.UUID, Int)] -> [RosterProjectionFragment]
actorRosterRowFragments =
    rosterRowFragments
