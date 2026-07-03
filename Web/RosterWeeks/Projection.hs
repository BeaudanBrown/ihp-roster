module Web.RosterWeeks.Projection
    ( actorRosterRowFragments
    , assignmentRefreshFragments
    , buildRosterProjectionScope
    , buildRosterWeekScope
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

import Application.Helper.LiveUpdate
import Data.Coerce (coerce)
import qualified Data.UUID as UUID
import Web.Controller.Prelude
import Web.RosterWeeks.Types

buildRosterProjectionScope :: Id RosterGroup -> Int -> RosterProjectionScope
buildRosterProjectionScope rosterGroupId weekOffset =
    RosterProjectionScope
        { rosterProjectionGroupId = rosterGroupId
        , rosterProjectionWeekOffset = weekOffset
        }

buildRosterWeekScope :: (?context :: ControllerContext) => Id RosterGroup -> Int -> LiveUpdateScope
buildRosterWeekScope rosterGroupId weekOffset =
    rosterWeekLiveScope (unpackId currentVenueId) (unpackId rosterGroupId) weekOffset

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

actorRosterRowFragments :: Maybe Text -> [(UUID.UUID, Int)] -> [RosterProjectionFragment]
actorRosterRowFragments _ =
    rosterRowFragments

assignmentRefreshFragments :: Maybe Text -> [RosterProjectionFragment]
assignmentRefreshFragments _ =
    []
