module Web.RosterWeeks.Projection
    ( buildActorRosterRowFragmentRefs
    , buildAssignmentRefreshFragmentRefs
    , buildDeferredRosterContentFragmentRef
    , buildRosterContentFragmentRef
    , buildRosterDaySectionFragmentRef
    , buildRosterProjectionScope
    , buildRosterRowFragmentRef
    , buildRosterRowFragmentRefs
    , buildRosterStaffPanelFragmentRef
    , buildRosterWeekScope
    , disableFragmentBlurDeferral
    ) where

import Application.Helper.LiveUpdate
import Application.Helper.Url (appendQueryParams)
import Data.Coerce (coerce)
import qualified Data.UUID as UUID
import Web.Controller.Prelude
import Web.RosterWeeks.Dom
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

buildRosterContentFragmentRef :: (?context :: ControllerContext) => Id RosterGroup -> Int -> LiveFragmentRef
buildRosterContentFragmentRef rosterGroupId weekOffset =
    mkLiveFragmentRef
        RosterContentFragment
        rosterContentFragmentId
        (appendQueryParams (pathTo ShowRosterWeekContentFragmentAction { weekOffset }) [("rosterGroupId", tshow rosterGroupId)])

buildDeferredRosterContentFragmentRef :: (?context :: ControllerContext) => Id RosterGroup -> Int -> LiveFragmentRef
buildDeferredRosterContentFragmentRef rosterGroupId weekOffset =
    (buildRosterContentFragmentRef rosterGroupId weekOffset)
        { deferUntilBlur = True
        , protectionPolicy = focusedFieldProtection
        }

buildRosterStaffPanelFragmentRef :: (?context :: ControllerContext) => Id RosterGroup -> Int -> LiveFragmentRef
buildRosterStaffPanelFragmentRef rosterGroupId weekOffset =
    mkLiveFragmentRef
        RosterStaffPanelFragment
        rosterStaffPanelFragmentId
        (appendQueryParams (pathTo ShowRosterWeekStaffPanelFragmentAction { weekOffset }) [("rosterGroupId", tshow rosterGroupId)])

buildRosterDaySectionFragmentRef :: (?context :: ControllerContext) => Id RosterGroup -> Int -> UUID.UUID -> LiveFragmentRef
buildRosterDaySectionFragmentRef rosterGroupId weekOffset rosterDayId =
    LiveFragmentRef
        { fragmentKey = RosterDaySectionFragment { rosterDayId }
        , targetId = rosterDaySectionDomId (coerce rosterDayId)
        , url = appendQueryParams (pathTo ShowRosterWeekDaySectionFragmentAction { weekOffset, rosterDayId = coerce rosterDayId }) [("rosterGroupId", tshow rosterGroupId)]
        , deferUntilBlur = True
        , protectionPolicy = focusedFieldProtection
        }

buildRosterRowFragmentRefs :: (?context :: ControllerContext) => Id RosterGroup -> Int -> [(UUID.UUID, Int)] -> [LiveFragmentRef]
buildRosterRowFragmentRefs rosterGroupId weekOffset =
    map (uncurry (buildRosterRowFragmentRef rosterGroupId weekOffset)) . nub

buildActorRosterRowFragmentRefs :: (?context :: ControllerContext) => Maybe Text -> Id RosterGroup -> Int -> [(UUID.UUID, Int)] -> [LiveFragmentRef]
buildActorRosterRowFragmentRefs maybeStaffParam rosterGroupId weekOffset rowKeys =
    let refs = buildRosterRowFragmentRefs rosterGroupId weekOffset rowKeys
     in if isJust maybeStaffParam
            then map disableFragmentBlurDeferral refs
            else refs

buildAssignmentRefreshFragmentRefs :: (?context :: ControllerContext) => Maybe Text -> Id RosterGroup -> Int -> [LiveFragmentRef]
buildAssignmentRefreshFragmentRefs maybeStaffParam rosterGroupId weekOffset =
    [ buildDeferredRosterContentFragmentRef rosterGroupId weekOffset
    | isJust maybeStaffParam
    ]

buildRosterRowFragmentRef :: (?context :: ControllerContext) => Id RosterGroup -> Int -> UUID.UUID -> Int -> LiveFragmentRef
buildRosterRowFragmentRef rosterGroupId weekOffset rosterDayId rowIndex =
    LiveFragmentRef
        { fragmentKey = RosterRowFragment { rosterDayId, rowIndex }
        , targetId = rosterRowDomIdText (coerce rosterDayId) rowIndex
        , url = appendQueryParams (pathTo ShowRosterWeekRowFragmentAction { weekOffset, rosterDayId = coerce rosterDayId, rowIndex }) [("rosterGroupId", tshow rosterGroupId)]
        , deferUntilBlur = True
        , protectionPolicy = focusedFieldProtection
        }

disableFragmentBlurDeferral :: LiveFragmentRef -> LiveFragmentRef
disableFragmentBlurDeferral fragment = fragment { deferUntilBlur = False, protectionPolicy = NoProtection }

focusedFieldProtection :: LiveFragmentProtection
focusedFieldProtection =
    FocusedFieldProtection
        FocusedFieldProtectionConfig
            { activeSelector = ".slot-note-input:focus"
            , fieldKeyAttr = "data-roster-field-key"
            , fieldNameFallback = True
            , containerSelector = Just "tr[data-roster-row]"
            }
