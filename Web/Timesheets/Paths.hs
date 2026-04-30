module Web.Timesheets.Paths
    ( editTimesheetEntryUrl
    , newTimesheetEntryUrl
    , timesheetDaySectionFragmentUrl
    , timesheetWeekResetUrl
    , timesheetWeekUrl
    ) where

import Application.Helper.Url (appendQueryParams)
import Data.Time.Calendar (Day)
import Generated.Types
import IHP.Prelude
import IHP.Router.UrlGenerator (pathTo)
import Web.Routes ()
import Web.Types

timesheetWeekUrl :: Int -> Bool -> Bool -> Text
timesheetWeekUrl weekOffset showApproved showAllStaff =
    appendQueryParams
        (pathTo (ShowTimesheetWeekAction weekOffset))
        [ ("showApproved", toBoolText showApproved)
        , ("showAllStaff", toBoolText showAllStaff)
        ]

timesheetWeekResetUrl :: Bool -> Bool -> Text
timesheetWeekResetUrl showApproved showAllStaff =
    appendQueryParams
        (pathTo TimesheetsAction)
        [ ("showApproved", toBoolText showApproved)
        , ("showAllStaff", toBoolText showAllStaff)
        ]

timesheetDaySectionFragmentUrl :: Int -> Int -> Bool -> Bool -> Text
timesheetDaySectionFragmentUrl weekOffset dayOffset showApproved showAllStaff =
    appendQueryParams
        (pathTo ShowTimesheetDaySectionFragmentAction { weekOffset, dayOffset })
        [ ("showApproved", toBoolText showApproved)
        , ("showAllStaff", toBoolText showAllStaff)
        ]

newTimesheetEntryUrl :: Int -> Day -> Bool -> Bool -> Text
newTimesheetEntryUrl weekOffset workedOn showApproved showAllStaff =
    appendQueryParams
        (pathTo NewTimesheetEntryAction)
        [ ("weekOffset", tshow weekOffset)
        , ("workedOn", tshow workedOn)
        , ("showApproved", toBoolText showApproved)
        , ("showAllStaff", toBoolText showAllStaff)
        ]

editTimesheetEntryUrl :: Id TimesheetEntry -> Int -> Bool -> Bool -> Text
editTimesheetEntryUrl timesheetEntryId weekOffset showApproved showAllStaff =
    appendQueryParams
        (pathTo EditTimesheetEntryAction { timesheetEntryId })
        [ ("weekOffset", tshow weekOffset)
        , ("showApproved", toBoolText showApproved)
        , ("showAllStaff", toBoolText showAllStaff)
        ]

toBoolText :: Bool -> Text
toBoolText True  = "true"
toBoolText False = "false"
