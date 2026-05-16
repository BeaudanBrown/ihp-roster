module Web.RosterWeeks.Projection
    ( buildActorRosterRowFragmentRefs
    , buildAssignmentRefreshFragmentRefs
    , buildRosterContentFragmentRef
    , buildRosterDaySectionFragmentRef
    , buildRosterProjectionScope
    , buildRosterRowFragmentRef
    , buildRosterRowFragmentRefs
    , buildRosterStaffPanelFragmentRef
    , buildRosterWeekScope
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

buildRosterContentFragmentRef :: Id RosterGroup -> Int -> RosterProjectionFragment
buildRosterContentFragmentRef _ _ =
    RosterProjectionContent

buildRosterStaffPanelFragmentRef :: Id RosterGroup -> Int -> RosterProjectionFragment
buildRosterStaffPanelFragmentRef _ _ =
    RosterProjectionStaffPanel

buildRosterDaySectionFragmentRef :: Id RosterGroup -> Int -> UUID.UUID -> RosterProjectionFragment
buildRosterDaySectionFragmentRef _ _ rosterDayId =
    RosterProjectionDaySection rosterDayId

buildRosterRowFragmentRefs :: Id RosterGroup -> Int -> [(UUID.UUID, Int)] -> [RosterProjectionFragment]
buildRosterRowFragmentRefs rosterGroupId weekOffset =
    map (uncurry (buildRosterRowFragmentRef rosterGroupId weekOffset)) . nub

buildActorRosterRowFragmentRefs :: Maybe Text -> Id RosterGroup -> Int -> [(UUID.UUID, Int)] -> [RosterProjectionFragment]
buildActorRosterRowFragmentRefs _ =
    buildRosterRowFragmentRefs

buildAssignmentRefreshFragmentRefs :: Maybe Text -> Id RosterGroup -> Int -> [RosterProjectionFragment]
buildAssignmentRefreshFragmentRefs maybeStaffParam rosterGroupId weekOffset =
    [ buildRosterContentFragmentRef rosterGroupId weekOffset
    | isJust maybeStaffParam
    ]

buildRosterRowFragmentRef :: Id RosterGroup -> Int -> UUID.UUID -> Int -> RosterProjectionFragment
buildRosterRowFragmentRef _ _ rosterDayId rowIndex =
    RosterProjectionRow rosterDayId rowIndex
