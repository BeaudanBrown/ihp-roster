{-# LANGUAGE TypeApplications #-}

module Web.Timesheets.Paths
    ( createTimesheetEntryFromSuggestionUrl
    , editTimesheetEntryUrl
    , newTimesheetEntryFromSuggestionUrl
    , newTimesheetEntryUrl
    , timesheetDayColumnsFragmentUrl
    , timesheetDaySectionFragmentUrl
    , timesheetToolbarFragmentUrl
    , timesheetStateQueryParams
    , timesheetWeekResetUrl
    , timesheetWeekUrl
    ) where

import qualified Application.Helper.FrontendContract.Surface.Timesheets as Surface
import Application.Helper.FrontendContract.Surface.Values
import Application.Helper.Url (replaceQueryParams)
import Data.Time.Calendar (Day)
import Data.UUID (UUID)
import Generated.Types
import IHP.Prelude
import IHP.Router.UrlGenerator (pathTo)
import Web.Routes ()
import Web.Types

timesheetWeekUrl :: Int -> Bool -> Bool -> Bool -> Maybe UUID -> Text
timesheetWeekUrl weekOffset showApproved showAllStaff showSuggestions staffFilterId =
    replaceQueryParams
        (pathTo (ShowTimesheetWeekAction weekOffset))
        (timesheetStateQueryParams weekOffset showApproved showAllStaff showSuggestions staffFilterId)

timesheetWeekResetUrl :: Bool -> Bool -> Bool -> Maybe UUID -> Text
timesheetWeekResetUrl showApproved showAllStaff showSuggestions staffFilterId =
    replaceQueryParams
        (pathTo TimesheetsAction)
        (timesheetStateQueryParams 0 showApproved showAllStaff showSuggestions staffFilterId)

timesheetToolbarFragmentUrl :: Int -> Bool -> Bool -> Bool -> Maybe UUID -> Text
timesheetToolbarFragmentUrl weekOffset showApproved showAllStaff showSuggestions staffFilterId =
    replaceQueryParams
        (pathTo ShowtimesheetToolbarLiveFragmentAction { weekOffset })
        (timesheetStateQueryParams weekOffset showApproved showAllStaff showSuggestions staffFilterId)

timesheetDayColumnsFragmentUrl :: Int -> Bool -> Bool -> Bool -> Maybe UUID -> Text
timesheetDayColumnsFragmentUrl weekOffset showApproved showAllStaff showSuggestions staffFilterId =
    replaceQueryParams
        (pathTo ShowtimesheetDayColumnsLiveFragmentAction { weekOffset })
        (timesheetStateQueryParams weekOffset showApproved showAllStaff showSuggestions staffFilterId)

timesheetDaySectionFragmentUrl :: Int -> Int -> Bool -> Bool -> Bool -> Maybe UUID -> Text
timesheetDaySectionFragmentUrl weekOffset dayOffset showApproved showAllStaff showSuggestions staffFilterId =
    replaceQueryParams
        (pathTo ShowTimesheetDaySectionFragmentAction { weekOffset, dayOffset })
        (timesheetStateQueryParams weekOffset showApproved showAllStaff showSuggestions staffFilterId)

newTimesheetEntryUrl :: Int -> Day -> Bool -> Bool -> Bool -> Maybe UUID -> Text
newTimesheetEntryUrl weekOffset workedOn showApproved showAllStaff showSuggestions staffFilterId =
    replaceQueryParams
        (pathTo NewTimesheetEntryAction)
        (("workedOn", tshow workedOn) : timesheetStateQueryParams weekOffset showApproved showAllStaff showSuggestions staffFilterId)

newTimesheetEntryFromSuggestionUrl :: Id RosterSlot -> Int -> Bool -> Bool -> Bool -> Maybe UUID -> Text
newTimesheetEntryFromSuggestionUrl rosterSlotId weekOffset showApproved showAllStaff showSuggestions staffFilterId =
    replaceQueryParams
        (pathTo NewTimesheetEntryFromSuggestionAction { rosterSlotId })
        (timesheetStateQueryParams weekOffset showApproved showAllStaff showSuggestions staffFilterId)

createTimesheetEntryFromSuggestionUrl :: Id RosterSlot -> Int -> Bool -> Bool -> Bool -> Maybe UUID -> Text
createTimesheetEntryFromSuggestionUrl rosterSlotId weekOffset showApproved showAllStaff showSuggestions staffFilterId =
    replaceQueryParams
        (pathTo CreateTimesheetEntryFromSuggestionAction { rosterSlotId })
        (timesheetStateQueryParams weekOffset showApproved showAllStaff showSuggestions staffFilterId)

editTimesheetEntryUrl :: Id TimesheetEntry -> Int -> Bool -> Bool -> Bool -> Maybe UUID -> Text
editTimesheetEntryUrl timesheetEntryId weekOffset showApproved showAllStaff showSuggestions staffFilterId =
    replaceQueryParams
        (pathTo EditTimesheetEntryAction { timesheetEntryId })
        (timesheetStateQueryParams weekOffset showApproved showAllStaff showSuggestions staffFilterId)

timesheetStateQueryParams :: Int -> Bool -> Bool -> Bool -> Maybe UUID -> [(Text, Text)]
timesheetStateQueryParams weekOffset showApproved showAllStaff showSuggestions staffFilterId =
    surfaceFieldsText
        ( surfaceField @Surface.WeekOffset weekOffset
            :& surfaceField @Surface.ShowApproved showApproved
            :& surfaceField @Surface.ShowAllStaff showAllStaff
            :& surfaceField @Surface.ShowSuggestions showSuggestions
            :& surfaceOptionalField @Surface.StaffFilterId staffFilterId
            :& NoSurfaceFields
            :: SurfaceFields (SurfaceActionFieldSpecs Surface.TimesheetsSurface Surface.NavigateTimesheetWeek)
        )
