module Web.RosterWeeks.Paths
    ( rosterAssignmentFiltersUrl
    , rosterCopyWeekUrl
    , rosterLayoutPreferenceUrl
    , rosterWageEstimatePreferenceUrl
    , rosterOverviewFragmentUrl
    , rosterWeekContentFragmentUrl
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

rosterOverviewFragmentUrl :: Int -> Id RosterGroup -> Text
rosterOverviewFragmentUrl weekOffset rosterGroupId =
    appendQueryParams (pathTo ShowRosterWeekOverviewFragmentAction { weekOffset }) [("rosterGroupId", tshow rosterGroupId)]

rosterWeekContentFragmentUrl :: Int -> Id RosterGroup -> Text
rosterWeekContentFragmentUrl weekOffset rosterGroupId =
    appendQueryParams (pathTo ShowRosterWeekContentFragmentAction { weekOffset }) [("rosterGroupId", tshow rosterGroupId)]

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
