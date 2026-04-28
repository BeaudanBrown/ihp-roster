module Web.Timesheets.Paths
    ( timesheetWeekUrl
    ) where

import Web.View.Prelude

timesheetWeekUrl :: Int -> Bool -> Bool -> Text
timesheetWeekUrl weekOffset showApproved showAllStaff =
    appendQueryParams
        (pathTo (ShowTimesheetWeekAction weekOffset))
        [ ("showApproved", toBoolText showApproved)
        , ("showAllStaff", toBoolText showAllStaff)
        ]

toBoolText :: Bool -> Text
toBoolText True  = "true"
toBoolText False = "false"
