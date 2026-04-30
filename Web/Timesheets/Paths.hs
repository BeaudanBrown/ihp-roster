module Web.Timesheets.Paths
    ( timesheetWeekUrl
    ) where

import Application.Helper.Url (appendQueryParams)
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

toBoolText :: Bool -> Text
toBoolText True  = "true"
toBoolText False = "false"
