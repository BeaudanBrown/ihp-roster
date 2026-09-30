{-# LANGUAGE TypeApplications #-}

module Web.Timesheets.Paths
    ( editTimesheetEntryUrl
    , newTimesheetEntryFromRosterPrefillUrl
    , newTimesheetEntryUrl
    , timesheetDayColumnsFragmentUrl
    , timesheetDaySectionFragmentUrl
    , timesheetSidePanelFragmentUrl
    , timesheetStaffContentFragmentUrl
    , timesheetToolbarFragmentUrl
    , timesheetWindowStateQueryParams
    , timesheetWindowStateQueryParamsWithFilters
    , timesheetWindowUrl
    , timesheetWindowUrlWithFilters
    , withTimesheetFilters
    ) where

import qualified Application.Helper.FrontendContract.Surface.Timesheets as Surface
import qualified Application.Helper.FrontendContract.Surface.Timesheets.Action as TimesheetsAction
import Application.Helper.FrontendContract.Surface.Values (surfaceFieldNameFrom)
import Application.Helper.Url (replaceQueryParams)
import Generated.Types
import IHP.Prelude
import IHP.Router.UrlGenerator (pathTo)
import Web.Routes ()
import Web.Timesheets.Filters (TimesheetViewFilters (..))
import Web.Types

timesheetWindowUrl :: Day -> Maybe UUID -> Text
timesheetWindowUrl anchorDate staffFilterId =
    timesheetWindowUrlWithFilters anchorDate (TimesheetViewFilters (maybeToList staffFilterId) [] [])

timesheetWindowUrlWithFilters :: Day -> TimesheetViewFilters -> Text
timesheetWindowUrlWithFilters anchorDate filters =
    replaceQueryParams
        (pathTo (ShowTimesheetWindowAction (tshow anchorDate)))
        (timesheetWindowStateQueryParamsWithFilters anchorDate filters)

withTimesheetFilters :: TimesheetViewFilters -> Text -> Text
withTimesheetFilters filters url = replaceQueryParams url (timesheetFilterQueryParams filters)

timesheetFilterQueryParams :: TimesheetViewFilters -> [(Text, Text)]
timesheetFilterQueryParams filters =
    values (surfaceFieldNameFrom @Surface.StaffFilterIds fields) filters.filterStaffIds
        <> values (surfaceFieldNameFrom @Surface.RosterGroupFilterIds fields) filters.filterRosterGroupIds
        <> values (surfaceFieldNameFrom @Surface.ShiftTypeFilterIds fields) filters.filterShiftTypeIds
  where
    fields = TimesheetsAction.navigateTimesheetWeekActionFields (ModifiedJulianDay 0) (Just filters.filterStaffIds) (Just filters.filterRosterGroupIds) (Just filters.filterShiftTypeIds)
    values key ids = (key, "") : [(key, tshow value) | value <- ids]

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

timesheetStaffContentFragmentUrl :: Day -> Maybe UUID -> Text
timesheetStaffContentFragmentUrl anchorDate staffFilterId =
    replaceQueryParams
        (pathTo ShowTimesheetStaffContentFragmentAction { anchorDate = tshow anchorDate })
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

newTimesheetEntryFromRosterPrefillUrl :: Id RosterSlot -> Day -> Maybe UUID -> Text
newTimesheetEntryFromRosterPrefillUrl rosterSlotId anchorDate staffFilterId =
    replaceQueryParams
        (pathTo NewTimesheetEntryFromRosterShiftAction { rosterSlotId })
        (timesheetWindowStateQueryParams anchorDate staffFilterId)

editTimesheetEntryUrl :: Id TimesheetEntry -> Day -> Maybe UUID -> Text
editTimesheetEntryUrl timesheetEntryId anchorDate staffFilterId =
    replaceQueryParams
        (pathTo EditTimesheetEntryAction { timesheetEntryId })
        (timesheetWindowStateQueryParams anchorDate staffFilterId)

timesheetWindowStateQueryParams :: Day -> Maybe UUID -> [(Text, Text)]
timesheetWindowStateQueryParams anchorDate staffFilterId =
    timesheetWindowStateQueryParamsWithFilters anchorDate (TimesheetViewFilters (maybeToList staffFilterId) [] [])

timesheetWindowStateQueryParamsWithFilters :: Day -> TimesheetViewFilters -> [(Text, Text)]
timesheetWindowStateQueryParamsWithFilters anchorDate filters =
    (surfaceFieldNameFrom @Surface.AnchorDate fields, tshow anchorDate) : timesheetFilterQueryParams filters
  where
    fields = TimesheetsAction.navigateTimesheetWeekActionFields anchorDate (Just filters.filterStaffIds) (Just filters.filterRosterGroupIds) (Just filters.filterShiftTypeIds)
