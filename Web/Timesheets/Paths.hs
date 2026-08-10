{-# LANGUAGE TypeApplications #-}

module Web.Timesheets.Paths
    ( createTimesheetEntryFromSuggestionUrl
    , editTimesheetEntryUrl
    , newTimesheetEntryFromSuggestionUrl
    , newTimesheetEntryUrl
    , timesheetDayColumnsFragmentUrl
    , timesheetDaySectionFragmentUrl
    , timesheetSidePanelFragmentUrl
    , timesheetToolbarFragmentUrl
    , timesheetStateQueryParams
    , timesheetWeekResetUrl
    , timesheetWeekUrl
    ) where

import qualified Application.Helper.FrontendContract.Surface.Timesheets.Action as TimesheetsAction
import Application.Helper.FrontendContract.Surface.Values (surfaceFieldsText)
import Application.Helper.Url (replaceQueryParams)
import Data.Time.Calendar (Day)
import Generated.Types
import IHP.Prelude
import IHP.Router.UrlGenerator (pathTo)
import Web.Routes ()
import Web.Timesheets.Filters
import Web.Types

timesheetWeekUrl :: Int -> TimesheetViewFilters -> Text
timesheetWeekUrl weekOffset filters =
    replaceQueryParams
        (pathTo (ShowTimesheetWeekAction weekOffset))
        (timesheetStateQueryParams weekOffset filters)

timesheetWeekResetUrl :: TimesheetViewFilters -> Text
timesheetWeekResetUrl filters =
    replaceQueryParams
        (pathTo TimesheetsAction)
        (timesheetStateQueryParams 0 filters)

timesheetToolbarFragmentUrl :: Int -> TimesheetViewFilters -> Text
timesheetToolbarFragmentUrl weekOffset filters =
    replaceQueryParams
        (pathTo ShowtimesheetToolbarLiveFragmentAction { weekOffset })
        (timesheetStateQueryParams weekOffset filters)

timesheetSidePanelFragmentUrl :: Int -> TimesheetViewFilters -> Text
timesheetSidePanelFragmentUrl weekOffset filters =
    replaceQueryParams
        (pathTo ShowtimesheetSidePanelContentLiveFragmentAction { weekOffset })
        (timesheetStateQueryParams weekOffset filters)

timesheetDayColumnsFragmentUrl :: Int -> TimesheetViewFilters -> Text
timesheetDayColumnsFragmentUrl weekOffset filters =
    replaceQueryParams
        (pathTo ShowtimesheetDayColumnsLiveFragmentAction { weekOffset })
        (timesheetStateQueryParams weekOffset filters)

timesheetDaySectionFragmentUrl :: Int -> Int -> TimesheetViewFilters -> Text
timesheetDaySectionFragmentUrl weekOffset dayOffset filters =
    replaceQueryParams
        (pathTo ShowTimesheetDaySectionFragmentAction { weekOffset, dayOffset })
        (timesheetStateQueryParams weekOffset filters)

newTimesheetEntryUrl :: Int -> Day -> TimesheetViewFilters -> Text
newTimesheetEntryUrl weekOffset workedOn filters =
    replaceQueryParams
        (pathTo NewTimesheetEntryAction)
        (("workedOn", tshow workedOn) : timesheetStateQueryParams weekOffset filters)

newTimesheetEntryFromSuggestionUrl :: Id RosterSlot -> Int -> TimesheetViewFilters -> Text
newTimesheetEntryFromSuggestionUrl rosterSlotId weekOffset filters =
    replaceQueryParams
        (pathTo NewTimesheetEntryFromSuggestionAction { rosterSlotId })
        (timesheetStateQueryParams weekOffset filters)

createTimesheetEntryFromSuggestionUrl :: Id RosterSlot -> Int -> TimesheetViewFilters -> Text
createTimesheetEntryFromSuggestionUrl rosterSlotId weekOffset filters =
    replaceQueryParams
        (pathTo CreateTimesheetEntryFromSuggestionAction { rosterSlotId })
        (timesheetStateQueryParams weekOffset filters)

editTimesheetEntryUrl :: Id TimesheetEntry -> Int -> TimesheetViewFilters -> Text
editTimesheetEntryUrl timesheetEntryId weekOffset filters =
    replaceQueryParams
        (pathTo EditTimesheetEntryAction { timesheetEntryId })
        (timesheetStateQueryParams weekOffset filters)

timesheetStateQueryParams :: Int -> TimesheetViewFilters -> [(Text, Text)]
timesheetStateQueryParams weekOffset filters =
    surfaceFieldsText
        ( TimesheetsAction.navigateTimesheetWeekActionFields
            weekOffset
            filters.filterStaffId
            filters.filterRosterGroupId
        )
