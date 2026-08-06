module Web.RosterWeeks.Projection
    ( actorRosterRowFragments
    , rosterGridFrameFragment
    , rosterGridToolbarFragment
    , rosterGridInnerAndStaffPanelFragments
    , rosterGridStructuralAndStaffPanelFragments
    , rosterGridStructuralFragments
    , rosterDaySectionFragment
    , rosterRowFragment
    , rosterRowFragments
    , rosterStaffPanelFragment
    ) where

import qualified Data.UUID as UUID
import Web.Controller.Prelude
import Web.RosterWeeks.Types


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

rosterGridStructuralAndStaffPanelFragments :: [RosterProjectionFragment]
rosterGridStructuralAndStaffPanelFragments =
    rosterGridStructuralFragments <> [rosterStaffPanelFragment]

rosterGridInnerAndStaffPanelFragments :: [RosterProjectionFragment]
rosterGridInnerAndStaffPanelFragments =
    [ RosterProjectionDayColumns
    , RosterProjectionDayRail
    , RosterProjectionWageRail
    , RosterProjectionSlotsGrid
    , rosterStaffPanelFragment
    ]


rosterDaySectionFragment :: UUID.UUID -> RosterProjectionFragment
rosterDaySectionFragment =
    RosterProjectionDaySection


rosterRowFragment :: UUID.UUID -> Int -> RosterProjectionFragment
rosterRowFragment =
    RosterProjectionRow

rosterRowFragments :: [(UUID.UUID, Int)] -> [RosterProjectionFragment]
rosterRowFragments =
    map (uncurry rosterRowFragment) . nub

actorRosterRowFragments :: [(UUID.UUID, Int)] -> [RosterProjectionFragment]
actorRosterRowFragments =
    rosterRowFragments
