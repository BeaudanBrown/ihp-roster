module Web.RosterWeeks.Projection
    ( actorRosterRowFragments
    , assignmentRefreshFragments
    , buildRosterProjectionScope
    , buildRosterWeekScope
    , rosterContentAndStaffPanelFragments
    , rosterContentFragment
    , rosterDaySectionFragment
    , rosterDaySectionFragments
    , rosterRowFragment
    , rosterRowFragments
    , rosterStaffPanelFragment
    ) where

import Application.Helper.LiveUpdate (LiveUpdateScope (..))
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
    RosterWeekScope
        { venueId = unpackId currentVenueId
        , rosterGroupId = unpackId rosterGroupId
        , weekOffset
        }

rosterContentFragment :: RosterProjectionFragment
rosterContentFragment =
    RosterProjectionContent

rosterStaffPanelFragment :: RosterProjectionFragment
rosterStaffPanelFragment =
    RosterProjectionStaffPanel

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
assignmentRefreshFragments maybeStaffParam =
    [ rosterContentFragment
    | isJust maybeStaffParam
    ]
