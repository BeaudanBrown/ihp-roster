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
import Data.UUID (UUID)
import Generated.Types
import IHP.Prelude
import IHP.Router.UrlGenerator (pathTo)
import Web.Routes ()
import Web.Types

timesheetWeekUrl :: Int -> Maybe UUID -> Text
timesheetWeekUrl weekOffset staffFilterId =
    replaceQueryParams
        (pathTo (ShowTimesheetWeekAction weekOffset))
        (timesheetStateQueryParams weekOffset staffFilterId)

timesheetWeekResetUrl :: Maybe UUID -> Text
timesheetWeekResetUrl staffFilterId =
    replaceQueryParams
        (pathTo TimesheetsAction)
        (timesheetStateQueryParams 0 staffFilterId)

timesheetToolbarFragmentUrl :: Int -> Maybe UUID -> Text
timesheetToolbarFragmentUrl weekOffset staffFilterId =
    replaceQueryParams
        (pathTo ShowtimesheetToolbarLiveFragmentAction { weekOffset })
        (timesheetStateQueryParams weekOffset staffFilterId)

timesheetSidePanelFragmentUrl :: Int -> Maybe UUID -> Text
timesheetSidePanelFragmentUrl weekOffset staffFilterId =
    replaceQueryParams
        (pathTo ShowtimesheetSidePanelContentLiveFragmentAction { weekOffset })
        (timesheetStateQueryParams weekOffset staffFilterId)

timesheetDayColumnsFragmentUrl :: Int -> Maybe UUID -> Text
timesheetDayColumnsFragmentUrl weekOffset staffFilterId =
    replaceQueryParams
        (pathTo ShowtimesheetDayColumnsLiveFragmentAction { weekOffset })
        (timesheetStateQueryParams weekOffset staffFilterId)

timesheetDaySectionFragmentUrl :: Int -> Int -> Maybe UUID -> Text
timesheetDaySectionFragmentUrl weekOffset dayOffset staffFilterId =
    replaceQueryParams
        (pathTo ShowTimesheetDaySectionFragmentAction { weekOffset, dayOffset })
        (timesheetStateQueryParams weekOffset staffFilterId)

newTimesheetEntryUrl :: Int -> Day -> Maybe UUID -> Text
newTimesheetEntryUrl weekOffset workedOn staffFilterId =
    replaceQueryParams
        (pathTo NewTimesheetEntryAction)
        (("workedOn", tshow workedOn) : timesheetStateQueryParams weekOffset staffFilterId)

newTimesheetEntryFromSuggestionUrl :: Id RosterSlot -> Int -> Maybe UUID -> Text
newTimesheetEntryFromSuggestionUrl rosterSlotId weekOffset staffFilterId =
    replaceQueryParams
        (pathTo NewTimesheetEntryFromSuggestionAction { rosterSlotId })
        (timesheetStateQueryParams weekOffset staffFilterId)

createTimesheetEntryFromSuggestionUrl :: Id RosterSlot -> Int -> Maybe UUID -> Text
createTimesheetEntryFromSuggestionUrl rosterSlotId weekOffset staffFilterId =
    replaceQueryParams
        (pathTo CreateTimesheetEntryFromSuggestionAction { rosterSlotId })
        (timesheetStateQueryParams weekOffset staffFilterId)

editTimesheetEntryUrl :: Id TimesheetEntry -> Int -> Maybe UUID -> Text
editTimesheetEntryUrl timesheetEntryId weekOffset staffFilterId =
    replaceQueryParams
        (pathTo EditTimesheetEntryAction { timesheetEntryId })
        (timesheetStateQueryParams weekOffset staffFilterId)

timesheetStateQueryParams :: Int -> Maybe UUID -> [(Text, Text)]
timesheetStateQueryParams weekOffset staffFilterId =
    surfaceFieldsText
        (TimesheetsAction.navigateTimesheetWeekActionFields weekOffset staffFilterId)
