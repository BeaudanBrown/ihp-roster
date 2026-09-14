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
    , timesheetWindowStateQueryParams
    , timesheetWindowStateQueryParamsWithFilters
    , timesheetWindowUrl
    , timesheetWindowUrlWithFilters
    ) where

import qualified Application.Helper.FrontendContract.Surface.Timesheets.Action as TimesheetsAction
import Application.Helper.FrontendContract.Surface.Values (surfaceFieldsText)
import Application.Helper.Url (replaceQueryParams)
import Generated.Types
import IHP.Prelude
import IHP.Router.UrlGenerator (pathTo)
import Web.Routes ()
import Web.Timesheets.Filters (TimesheetViewFilters (..))
import Web.Types

timesheetWindowUrl :: Day -> Maybe UUID -> Text
timesheetWindowUrl anchorDate staffFilterId =
    timesheetWindowUrlWithFilters anchorDate (TimesheetViewFilters staffFilterId Nothing)

timesheetWindowUrlWithFilters :: Day -> TimesheetViewFilters -> Text
timesheetWindowUrlWithFilters anchorDate filters =
    replaceQueryParams
        (pathTo (ShowTimesheetWindowAction (tshow anchorDate)))
        (timesheetWindowStateQueryParamsWithFilters anchorDate filters)

timesheetToolbarFragmentUrl :: Day -> Maybe UUID -> Text
timesheetToolbarFragmentUrl anchorDate staffFilterId =
    replaceQueryParams
        (pathTo ShowtimesheetToolbarLiveFragmentAction { anchorDate = tshow anchorDate })
        (timesheetWindowStateQueryParams anchorDate staffFilterId)

timesheetSidePanelFragmentUrl :: Day -> Maybe UUID -> Text
timesheetSidePanelFragmentUrl anchorDate staffFilterId =
    replaceQueryParams
        (pathTo ShowtimesheetSidePanelContentLiveFragmentAction { anchorDate = tshow anchorDate })
        (timesheetWindowStateQueryParams anchorDate staffFilterId)

timesheetDayColumnsFragmentUrl :: Day -> Maybe UUID -> Text
timesheetDayColumnsFragmentUrl anchorDate staffFilterId =
    replaceQueryParams
        (pathTo ShowtimesheetDayColumnsLiveFragmentAction { anchorDate = tshow anchorDate })
        (timesheetWindowStateQueryParams anchorDate staffFilterId)

timesheetDaySectionFragmentUrl :: Day -> Day -> Maybe UUID -> Text
timesheetDaySectionFragmentUrl anchorDate operationalDate staffFilterId =
    replaceQueryParams
        (pathTo ShowTimesheetDaySectionFragmentAction { anchorDate = tshow anchorDate, operationalDate = tshow operationalDate })
        (timesheetWindowStateQueryParams anchorDate staffFilterId)

newTimesheetEntryUrl :: Day -> Day -> Maybe UUID -> Text
newTimesheetEntryUrl anchorDate workedOn staffFilterId =
    replaceQueryParams
        (pathTo NewTimesheetEntryAction)
        (("workedOn", tshow workedOn) : timesheetWindowStateQueryParams anchorDate staffFilterId)

newTimesheetEntryFromSuggestionUrl :: Id RosterSlot -> Day -> Maybe UUID -> Text
newTimesheetEntryFromSuggestionUrl rosterSlotId anchorDate staffFilterId =
    replaceQueryParams
        (pathTo NewTimesheetEntryFromSuggestionAction { rosterSlotId })
        (timesheetWindowStateQueryParams anchorDate staffFilterId)

createTimesheetEntryFromSuggestionUrl :: Id RosterSlot -> Day -> Maybe UUID -> Text
createTimesheetEntryFromSuggestionUrl rosterSlotId anchorDate staffFilterId =
    replaceQueryParams
        (pathTo CreateTimesheetEntryFromSuggestionAction { rosterSlotId })
        (timesheetWindowStateQueryParams anchorDate staffFilterId)

editTimesheetEntryUrl :: Id TimesheetEntry -> Day -> Maybe UUID -> Text
editTimesheetEntryUrl timesheetEntryId anchorDate staffFilterId =
    replaceQueryParams
        (pathTo EditTimesheetEntryAction { timesheetEntryId })
        (timesheetWindowStateQueryParams anchorDate staffFilterId)

timesheetWindowStateQueryParams :: Day -> Maybe UUID -> [(Text, Text)]
timesheetWindowStateQueryParams anchorDate staffFilterId =
    timesheetWindowStateQueryParamsWithFilters anchorDate (TimesheetViewFilters staffFilterId Nothing)

timesheetWindowStateQueryParamsWithFilters :: Day -> TimesheetViewFilters -> [(Text, Text)]
timesheetWindowStateQueryParamsWithFilters anchorDate filters =
    surfaceFieldsText (TimesheetsAction.navigateTimesheetWeekActionFields anchorDate filters.filterStaffId filters.filterRosterGroupId)
