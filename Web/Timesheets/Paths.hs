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
    , timesheetWindowUrl
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

timesheetWindowUrl :: Day -> Maybe UUID -> Text
timesheetWindowUrl anchorDate staffFilterId =
    replaceQueryParams
        (pathTo (ShowTimesheetWindowAction anchorDate))
        (timesheetWindowStateQueryParams anchorDate staffFilterId)

timesheetToolbarFragmentUrl :: Day -> Maybe UUID -> Text
timesheetToolbarFragmentUrl anchorDate staffFilterId =
    replaceQueryParams
        (pathTo ShowtimesheetToolbarLiveFragmentAction { anchorDate })
        (timesheetWindowStateQueryParams anchorDate staffFilterId)

timesheetSidePanelFragmentUrl :: Day -> Maybe UUID -> Text
timesheetSidePanelFragmentUrl anchorDate staffFilterId =
    replaceQueryParams
        (pathTo ShowtimesheetSidePanelContentLiveFragmentAction { anchorDate })
        (timesheetWindowStateQueryParams anchorDate staffFilterId)

timesheetDayColumnsFragmentUrl :: Day -> Maybe UUID -> Text
timesheetDayColumnsFragmentUrl anchorDate staffFilterId =
    replaceQueryParams
        (pathTo ShowtimesheetDayColumnsLiveFragmentAction { anchorDate })
        (timesheetWindowStateQueryParams anchorDate staffFilterId)

timesheetDaySectionFragmentUrl :: Day -> Day -> Maybe UUID -> Text
timesheetDaySectionFragmentUrl anchorDate operationalDate staffFilterId =
    replaceQueryParams
        (pathTo ShowTimesheetDaySectionFragmentAction { anchorDate, operationalDate })
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
    surfaceFieldsText (TimesheetsAction.navigateTimesheetWeekActionFields anchorDate staffFilterId)
