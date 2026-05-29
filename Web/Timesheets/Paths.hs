module Web.Timesheets.Paths
    ( editTimesheetEntryUrl
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

timesheetWeekUrl :: Int -> Bool -> Bool -> Maybe UUID -> Text
timesheetWeekUrl weekOffset showApproved showAllStaff staffFilterId =
    appendQueryParams
        (pathTo (ShowTimesheetWeekAction weekOffset))
        [ ("showApproved", toBoolText showApproved)
        , ("showAllStaff", toBoolText showAllStaff)
        , ("staffFilterId", maybe "" tshow staffFilterId)
        ]

timesheetWeekResetUrl :: Bool -> Bool -> Maybe UUID -> Text
timesheetWeekResetUrl showApproved showAllStaff staffFilterId =
    appendQueryParams
        (pathTo TimesheetsAction)
        [ ("showApproved", toBoolText showApproved)
        , ("showAllStaff", toBoolText showAllStaff)
        , ("staffFilterId", maybe "" tshow staffFilterId)
        ]

timesheetToolbarFragmentUrl :: Int -> Bool -> Bool -> Maybe UUID -> Text
timesheetToolbarFragmentUrl weekOffset showApproved showAllStaff staffFilterId =
    appendQueryParams
        (pathTo ShowTimesheetToolbarFragmentAction { weekOffset })
        [ ("showApproved", toBoolText showApproved)
        , ("showAllStaff", toBoolText showAllStaff)
        , ("staffFilterId", maybe "" tshow staffFilterId)
        ]

timesheetDayColumnsFragmentUrl :: Int -> Bool -> Bool -> Maybe UUID -> Text
timesheetDayColumnsFragmentUrl weekOffset showApproved showAllStaff staffFilterId =
    appendQueryParams
        (pathTo ShowTimesheetDayColumnsFragmentAction { weekOffset })
        [ ("showApproved", toBoolText showApproved)
        , ("showAllStaff", toBoolText showAllStaff)
        , ("staffFilterId", maybe "" tshow staffFilterId)
        ]

timesheetDaySectionFragmentUrl :: Int -> Int -> Bool -> Bool -> Maybe UUID -> Text
timesheetDaySectionFragmentUrl weekOffset dayOffset showApproved showAllStaff staffFilterId =
    appendQueryParams
        (pathTo ShowTimesheetDaySectionFragmentAction { weekOffset, dayOffset })
        [ ("showApproved", toBoolText showApproved)
        , ("showAllStaff", toBoolText showAllStaff)
        , ("staffFilterId", maybe "" tshow staffFilterId)
        ]

newTimesheetEntryUrl :: Int -> Day -> Bool -> Bool -> Maybe UUID -> Text
newTimesheetEntryUrl weekOffset workedOn showApproved showAllStaff staffFilterId =
    appendQueryParams
        (pathTo NewTimesheetEntryAction)
        [ ("weekOffset", tshow weekOffset)
        , ("workedOn", tshow workedOn)
        , ("showApproved", toBoolText showApproved)
        , ("showAllStaff", toBoolText showAllStaff)
        , ("staffFilterId", maybe "" tshow staffFilterId)
        ]

editTimesheetEntryUrl :: Id TimesheetEntry -> Int -> Bool -> Bool -> Maybe UUID -> Text
editTimesheetEntryUrl timesheetEntryId weekOffset showApproved showAllStaff staffFilterId =
    appendQueryParams
        (pathTo EditTimesheetEntryAction { timesheetEntryId })
        [ ("weekOffset", tshow weekOffset)
        , ("showApproved", toBoolText showApproved)
        , ("showAllStaff", toBoolText showAllStaff)
        , ("staffFilterId", maybe "" tshow staffFilterId)
        ]

toBoolText :: Bool -> Text
toBoolText True  = "true"
toBoolText False = "false"
