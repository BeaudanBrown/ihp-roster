module Web.View.Admin.Xero.Calendars
    ( renderXeroPayrollCalendarSelection
    ) where

import Application.Helper.XeroAdminTypes
import qualified Data.Text as Text
import Web.View.Prelude

renderXeroPayrollCalendarSelection :: [XeroPayrollCalendar] -> Maybe XeroPayrollCalendarSelection -> Html
renderXeroPayrollCalendarSelection payrollCalendars maybeSelection
    | null payrollCalendars = [hsx|
        <div class={appSurfaceClasses "p-3"}>
            <h3 class="h6 mb-2">Payroll calendar</h3>
            <p class="small app-muted mb-0">Sync payroll reference data before selecting the venue's Xero payroll calendar.</p>
        </div>
    |]
    | otherwise = [hsx|
        <div class={appSurfaceClasses "p-3"}>
            <h3 class="h6 mb-2">Payroll calendar</h3>
            <p class="small app-muted mb-3">Choose the Xero pay calendar this venue uses for timesheet exports.</p>
            <form method="POST"
                  action={SaveXeroPayrollCalendarSelectionAction}
                  data-disable-javascript-submission="true"
                  hx-post={pathTo SaveXeroPayrollCalendarSelectionAction}
                  hx-target="#admin-xero-fragment"
                  hx-trigger="change"
                  hx-swap="outerHTML">
                <select class="form-select form-select-sm" name="xeroPayrollCalendarSelection" aria-label="Xero payroll calendar">
                    <option value="" selected={currentSelection == ""}>Not selected</option>
                    {forEach payrollCalendars (renderXeroPayrollCalendarOption currentSelection)}
                </select>
            </form>
        </div>
    |]
    where
        currentSelection =
            case maybeSelection of
                Just selection | selection.calendarStatus == "verified" -> fromMaybe "" selection.xeroPayrollCalendarId
                _ -> ""

renderXeroPayrollCalendarOption :: Text -> XeroPayrollCalendar -> Html
renderXeroPayrollCalendarOption currentSelection payrollCalendar = [hsx|
    <option value={payrollCalendar.xeroPayrollCalendarId} selected={currentSelection == payrollCalendar.xeroPayrollCalendarId}>
        {xeroPayrollCalendarLabel payrollCalendar}
    </option>
|]

xeroPayrollCalendarLabel :: XeroPayrollCalendar -> Text
xeroPayrollCalendarLabel payrollCalendar =
    Text.intercalate " - " (filter (not . Text.null) [payrollCalendar.name, fromMaybe "" payrollCalendar.calendarType])
