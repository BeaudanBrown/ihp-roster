module Web.RosterWeeks.Projection
    ( RosterMutationProjection (..)
    , actorRosterRowFragments
    , rosterGridFrameFragment
    , rosterGridToolbarFragment
    , rosterGridInnerAndStaffPanelFragments
    , rosterGridStructuralAndStaffPanelFragments
    , rosterGridStructuralFragments
    , rosterMutationProjectionFragments
    , rosterDaySectionFragment
    , rosterRowFragment
    , rosterRowFragments
    , rosterStaffPanelFragment
    ) where

import Application.Helper.UserPreferences (rosterLayoutModeIsDayColumns)
import qualified Data.UUID as UUID
import Web.Controller.Prelude
import Web.RosterWeeks.Types


data RosterMutationProjection
    = RosterDayMutation !UUID.UUID
    | RosterRowsMutation ![(UUID.UUID, Int)]
    | RosterTimelineMutation
    deriving (Eq, Show)

rosterMutationProjectionFragments :: RosterLayoutModeEnum -> RosterMutationProjection -> [RosterProjectionFragment]
rosterMutationProjectionFragments layoutMode mutationProjection =
    case mutationProjection of
        RosterTimelineMutation -> rosterGridStructuralAndStaffPanelFragments
        RosterDayMutation rosterDayId ->
            rosterGridInnerAndStaffPanelFragments
                <> rowLayoutFragments [rosterDaySectionFragment rosterDayId]
        RosterRowsMutation impactedRows ->
            rosterGridInnerAndStaffPanelFragments
                <> rowLayoutFragments (actorRosterRowFragments impactedRows)
  where
    rowLayoutFragments fragments
        | rosterLayoutModeIsDayColumns layoutMode = []
        | otherwise = fragments


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
