module Web.RosterWeeks.Paths
    ( rosterAssignmentFiltersUrl
    , rosterCopyWeekUrl
    , rosterLayoutPreferenceUrl
    , rosterMoveShiftUrl
    , rosterTimelineMoveShiftUrl
    , rosterDuplicateShiftUrl
    , rosterDropStaffUrl
    , rosterWarningPreferenceUrl
    , rosterWageEstimatePreferenceUrl
    , rosterOverviewFragmentUrl
    , rosterDayTimelineUrl
    , rosterDayTimelineContentFragmentUrl
    , rosterWeekContentFragmentUrl
    , rosterWeekGridFrameFragmentUrl
    , rosterWeekGridToolbarFragmentUrl
    , rosterWeekDayColumnsFragmentUrl
    , rosterWeekDayRailFragmentUrl
    , rosterWeekWageRailFragmentUrl
    , rosterWeekSlotsGridFragmentUrl
    , rosterWeekDaySectionFragmentUrl
    , rosterWeekRowFragmentUrl
    , rosterWeekStaffPanelFragmentUrl
    , rosterWeekUrl
    , rosterWeekWithDateUrl
    ) where

import Application.Helper.Url (appendQueryParams)
import Data.Time.Calendar (Day)
import Data.Time.Format (defaultTimeLocale, formatTime)
import Generated.Types
import IHP.Prelude
import IHP.Router.UrlGenerator (pathTo)
import Web.Routes ()
import Web.Types

rosterWeekUrl :: Int -> Id RosterGroup -> Text
rosterWeekUrl weekOffset rosterGroupId =
    appendQueryParams (pathTo ShowRosterWeekAction { weekOffset }) [("rosterGroupId", tshow rosterGroupId)]

rosterWeekWithDateUrl :: Int -> Id RosterGroup -> Day -> Text
rosterWeekWithDateUrl weekOffset rosterGroupId date =
    appendQueryParams
        (pathTo ShowRosterWeekAction { weekOffset })
        [ ("rosterGroupId", tshow rosterGroupId)
        , ("weekDate", formatDayParam date)
        ]

rosterViewQueryParams :: Id RosterGroup -> Maybe Int -> [(Text, Text)]
rosterViewQueryParams rosterGroupId maybeTimelineDayOffset =
    ("rosterGroupId", tshow rosterGroupId) : case maybeTimelineDayOffset of
        Nothing -> []
        Just dayOffset -> [("rosterView", "timeline"), ("dayOffset", tshow dayOffset)]

rosterDayTimelineUrl :: Int -> Id RosterGroup -> Int -> Text
rosterDayTimelineUrl weekOffset rosterGroupId dayOffset =
    appendQueryParams
        (pathTo ShowRosterWeekAction { weekOffset })
        [ ("rosterGroupId", tshow rosterGroupId)
        , ("rosterView", "timeline")
        , ("dayOffset", tshow dayOffset)
        ]

rosterDayTimelineContentFragmentUrl :: Int -> Id RosterGroup -> Id RosterDay -> Text
rosterDayTimelineContentFragmentUrl weekOffset rosterGroupId rosterDayId =
    appendQueryParams
        (pathTo ShowRosterDayTimelineContentFragmentAction { weekOffset, rosterDayId })
        [("rosterGroupId", tshow rosterGroupId)]

rosterOverviewFragmentUrl :: Int -> Id RosterGroup -> Text
rosterOverviewFragmentUrl weekOffset rosterGroupId =
    appendQueryParams (pathTo ShowRosterWeekOverviewFragmentAction { weekOffset }) [("rosterGroupId", tshow rosterGroupId)]

rosterWeekContentFragmentUrl :: Int -> Id RosterGroup -> Text
rosterWeekContentFragmentUrl weekOffset rosterGroupId =
    appendQueryParams (pathTo ShowRosterWeekContentFragmentAction { weekOffset }) [("rosterGroupId", tshow rosterGroupId)]

rosterWeekGridToolbarFragmentUrl :: Int -> Id RosterGroup -> Maybe Int -> Text
rosterWeekGridToolbarFragmentUrl weekOffset rosterGroupId maybeTimelineDayOffset =
    appendQueryParams (pathTo ShowRosterWeekGridToolbarFragmentAction { weekOffset }) (rosterViewQueryParams rosterGroupId maybeTimelineDayOffset)

rosterWeekGridFrameFragmentUrl :: Int -> Id RosterGroup -> Maybe Int -> Text
rosterWeekGridFrameFragmentUrl weekOffset rosterGroupId maybeTimelineDayOffset =
    appendQueryParams (pathTo ShowRosterWeekGridFrameFragmentAction { weekOffset }) (rosterViewQueryParams rosterGroupId maybeTimelineDayOffset)

rosterWeekDayColumnsFragmentUrl :: Int -> Id RosterGroup -> Text
rosterWeekDayColumnsFragmentUrl weekOffset rosterGroupId =
    appendQueryParams (pathTo ShowRosterWeekDayColumnsFragmentAction { weekOffset }) [("rosterGroupId", tshow rosterGroupId)]

rosterWeekDayRailFragmentUrl :: Int -> Id RosterGroup -> Text
rosterWeekDayRailFragmentUrl weekOffset rosterGroupId =
    appendQueryParams (pathTo ShowRosterWeekDayRailFragmentAction { weekOffset }) [("rosterGroupId", tshow rosterGroupId)]

rosterWeekWageRailFragmentUrl :: Int -> Id RosterGroup -> Text
rosterWeekWageRailFragmentUrl weekOffset rosterGroupId =
    appendQueryParams (pathTo ShowRosterWeekWageRailFragmentAction { weekOffset }) [("rosterGroupId", tshow rosterGroupId)]

rosterWeekSlotsGridFragmentUrl :: Int -> Id RosterGroup -> Text
rosterWeekSlotsGridFragmentUrl weekOffset rosterGroupId =
    appendQueryParams (pathTo ShowRosterWeekSlotsGridFragmentAction { weekOffset }) [("rosterGroupId", tshow rosterGroupId)]

rosterWeekStaffPanelFragmentUrl :: Int -> Id RosterGroup -> Text
rosterWeekStaffPanelFragmentUrl weekOffset rosterGroupId =
    appendQueryParams (pathTo ShowRosterWeekStaffPanelFragmentAction { weekOffset }) [("rosterGroupId", tshow rosterGroupId)]

rosterWeekDaySectionFragmentUrl :: Int -> Id RosterGroup -> Id RosterDay -> Text
rosterWeekDaySectionFragmentUrl weekOffset rosterGroupId rosterDayId =
    appendQueryParams
        (pathTo ShowRosterWeekDaySectionFragmentAction { weekOffset, rosterDayId })
        [("rosterGroupId", tshow rosterGroupId)]

rosterWeekRowFragmentUrl :: Int -> Id RosterGroup -> Id RosterDay -> Int -> Text
rosterWeekRowFragmentUrl weekOffset rosterGroupId rosterDayId rowIndex =
    appendQueryParams
        (pathTo ShowRosterWeekRowFragmentAction { weekOffset, rosterDayId, rowIndex })
        [("rosterGroupId", tshow rosterGroupId)]

rosterAssignmentFiltersUrl :: Int -> Id RosterGroup -> Text
rosterAssignmentFiltersUrl weekOffset rosterGroupId =
    appendQueryParams (pathTo UpdateRosterAssignmentFiltersAction { weekOffset }) [("rosterGroupId", tshow rosterGroupId)]

rosterLayoutPreferenceUrl :: Int -> Id RosterGroup -> Text
rosterLayoutPreferenceUrl weekOffset rosterGroupId =
    appendQueryParams (pathTo UpdateRosterLayoutPreferenceAction { weekOffset }) [("rosterGroupId", tshow rosterGroupId)]

rosterMoveShiftUrl :: Int -> Id RosterGroup -> Text
rosterMoveShiftUrl weekOffset rosterGroupId =
    appendQueryParams (pathTo MoveRosterShiftToSlotAction { weekOffset }) [("rosterGroupId", tshow rosterGroupId)]

rosterTimelineMoveShiftUrl :: Int -> Id RosterGroup -> Int -> Text
rosterTimelineMoveShiftUrl weekOffset rosterGroupId dayOffset =
    appendQueryParams
        (pathTo MoveRosterTimelineShiftAction { weekOffset })
        [ ("rosterGroupId", tshow rosterGroupId)
        , ("rosterView", "timeline")
        , ("dayOffset", tshow dayOffset)
        ]

rosterDuplicateShiftUrl :: Int -> Id RosterGroup -> Text
rosterDuplicateShiftUrl weekOffset rosterGroupId =
    appendQueryParams (pathTo DuplicateRosterShiftToDayAction { weekOffset }) [("rosterGroupId", tshow rosterGroupId)]

rosterDropStaffUrl :: Int -> Id RosterGroup -> Text
rosterDropStaffUrl weekOffset rosterGroupId =
    appendQueryParams (pathTo DropRosterStaffAction { weekOffset }) [("rosterGroupId", tshow rosterGroupId)]

rosterWarningPreferenceUrl :: Int -> Id RosterGroup -> Text
rosterWarningPreferenceUrl weekOffset rosterGroupId =
    appendQueryParams (pathTo UpdateRosterWarningPreferenceAction { weekOffset }) [("rosterGroupId", tshow rosterGroupId)]

rosterWageEstimatePreferenceUrl :: Int -> Id RosterGroup -> Text
rosterWageEstimatePreferenceUrl weekOffset rosterGroupId =
    appendQueryParams (pathTo UpdateRosterWageEstimatePreferenceAction { weekOffset }) [("rosterGroupId", tshow rosterGroupId)]

rosterCopyWeekUrl :: Int -> Int -> Id RosterGroup -> Text
rosterCopyWeekUrl sourceWeekOffset targetWeekOffset rosterGroupId =
    appendQueryParams
        (pathTo CopyRosterWeekAction { sourceWeekOffset, targetWeekOffset })
        [("rosterGroupId", tshow rosterGroupId)]

formatDayParam :: Day -> Text
formatDayParam date = cs (formatTime defaultTimeLocale "%Y-%m-%d" date)
