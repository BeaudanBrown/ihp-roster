module Web.Timesheets.Paths
    ( createTimesheetEntryFromSuggestionUrl
    , editTimesheetEntryUrl
    , newTimesheetEntryFromSuggestionUrl
    , newTimesheetEntryUrl
    , timesheetDayColumnsFragmentUrl
    , timesheetDaySectionFragmentUrl
    , timesheetToolbarFragmentUrl
    , timesheetWeekResetUrl
    , timesheetWeekUrl
    ) where

import Application.Helper.Url (appendQueryParams)
import Data.Time.Calendar (Day)
import Data.UUID (UUID)
import Generated.Types
import IHP.Prelude
import IHP.Router.UrlGenerator (pathTo)
import Web.Routes ()
import Web.Types

timesheetWeekUrl :: Int -> Bool -> Bool -> Bool -> Maybe UUID -> Text
timesheetWeekUrl weekOffset showApproved showAllStaff showSuggestions staffFilterId =
    appendQueryParams
        (pathTo (ShowTimesheetWeekAction weekOffset))
        [ ("showApproved", toBoolText showApproved)
        , ("showAllStaff", toBoolText showAllStaff)
        , ("showSuggestions", toBoolText showSuggestions)
        , ("staffFilterId", maybe "" tshow staffFilterId)
        ]

timesheetWeekResetUrl :: Bool -> Bool -> Bool -> Maybe UUID -> Text
timesheetWeekResetUrl showApproved showAllStaff showSuggestions staffFilterId =
    appendQueryParams
        (pathTo TimesheetsAction)
        [ ("showApproved", toBoolText showApproved)
        , ("showAllStaff", toBoolText showAllStaff)
        , ("showSuggestions", toBoolText showSuggestions)
        , ("staffFilterId", maybe "" tshow staffFilterId)
        ]

timesheetToolbarFragmentUrl :: Int -> Bool -> Bool -> Bool -> Maybe UUID -> Text
timesheetToolbarFragmentUrl weekOffset showApproved showAllStaff showSuggestions staffFilterId =
    appendQueryParams
        (pathTo ShowtimesheetToolbarLiveFragmentAction { weekOffset })
        [ ("showApproved", toBoolText showApproved)
        , ("showAllStaff", toBoolText showAllStaff)
        , ("showSuggestions", toBoolText showSuggestions)
        , ("staffFilterId", maybe "" tshow staffFilterId)
        ]

timesheetDayColumnsFragmentUrl :: Int -> Bool -> Bool -> Bool -> Maybe UUID -> Text
timesheetDayColumnsFragmentUrl weekOffset showApproved showAllStaff showSuggestions staffFilterId =
    appendQueryParams
        (pathTo ShowtimesheetDayColumnsLiveFragmentAction { weekOffset })
        [ ("showApproved", toBoolText showApproved)
        , ("showAllStaff", toBoolText showAllStaff)
        , ("showSuggestions", toBoolText showSuggestions)
        , ("staffFilterId", maybe "" tshow staffFilterId)
        ]

timesheetDaySectionFragmentUrl :: Int -> Int -> Bool -> Bool -> Bool -> Maybe UUID -> Text
timesheetDaySectionFragmentUrl weekOffset dayOffset showApproved showAllStaff showSuggestions staffFilterId =
    appendQueryParams
        (pathTo ShowTimesheetDaySectionFragmentAction { weekOffset, dayOffset })
        [ ("showApproved", toBoolText showApproved)
        , ("showAllStaff", toBoolText showAllStaff)
        , ("showSuggestions", toBoolText showSuggestions)
        , ("staffFilterId", maybe "" tshow staffFilterId)
        ]

newTimesheetEntryUrl :: Int -> Day -> Bool -> Bool -> Bool -> Maybe UUID -> Text
newTimesheetEntryUrl weekOffset workedOn showApproved showAllStaff showSuggestions staffFilterId =
    appendQueryParams
        (pathTo NewTimesheetEntryAction)
        [ ("weekOffset", tshow weekOffset)
        , ("workedOn", tshow workedOn)
        , ("showApproved", toBoolText showApproved)
        , ("showAllStaff", toBoolText showAllStaff)
        , ("showSuggestions", toBoolText showSuggestions)
        , ("staffFilterId", maybe "" tshow staffFilterId)
        ]

newTimesheetEntryFromSuggestionUrl :: Id RosterSlot -> Int -> Bool -> Bool -> Bool -> Maybe UUID -> Text
newTimesheetEntryFromSuggestionUrl rosterSlotId weekOffset showApproved showAllStaff showSuggestions staffFilterId =
    appendQueryParams
        (pathTo NewTimesheetEntryFromSuggestionAction { rosterSlotId })
        [ ("weekOffset", tshow weekOffset)
        , ("showApproved", toBoolText showApproved)
        , ("showAllStaff", toBoolText showAllStaff)
        , ("showSuggestions", toBoolText showSuggestions)
        , ("staffFilterId", maybe "" tshow staffFilterId)
        ]

createTimesheetEntryFromSuggestionUrl :: Id RosterSlot -> Int -> Bool -> Bool -> Bool -> Maybe UUID -> Text
createTimesheetEntryFromSuggestionUrl rosterSlotId weekOffset showApproved showAllStaff showSuggestions staffFilterId =
    appendQueryParams
        (pathTo CreateTimesheetEntryFromSuggestionAction { rosterSlotId })
        [ ("weekOffset", tshow weekOffset)
        , ("showApproved", toBoolText showApproved)
        , ("showAllStaff", toBoolText showAllStaff)
        , ("showSuggestions", toBoolText showSuggestions)
        , ("staffFilterId", maybe "" tshow staffFilterId)
        ]

editTimesheetEntryUrl :: Id TimesheetEntry -> Int -> Bool -> Bool -> Bool -> Maybe UUID -> Text
editTimesheetEntryUrl timesheetEntryId weekOffset showApproved showAllStaff showSuggestions staffFilterId =
    appendQueryParams
        (pathTo EditTimesheetEntryAction { timesheetEntryId })
        [ ("weekOffset", tshow weekOffset)
        , ("showApproved", toBoolText showApproved)
        , ("showAllStaff", toBoolText showAllStaff)
        , ("showSuggestions", toBoolText showSuggestions)
        , ("staffFilterId", maybe "" tshow staffFilterId)
        ]

toBoolText :: Bool -> Text
toBoolText True  = "true"
toBoolText False = "false"
