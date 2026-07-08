module Web.View.Admin.Xero.Calendars
    ( renderXeroPayrollCalendarSelection
    ) where

import Application.Helper.FrontendContract.Surface.Runtime (FrontendSurfaceActionRoute (..),
                                                            FrontendSurfaceCustomHtmxAttrs (..),
                                                            renderFrontendSurfaceActionForm)
import Application.Helper.XeroAdminTypes
import qualified Data.Text as Text
import Web.Admin.FrontendSurface (adminXeroAction)
import Web.View.Prelude

renderXeroPayrollCalendarSelection :: [XeroPayrollCalendar] -> Maybe XeroPayrollCalendarSelection -> Html
renderXeroPayrollCalendarSelection payrollCalendars maybeSelection
    | null payrollCalendars = [hsx|
        <div>
            <h3 class="h6 mb-2">Payroll calendar</h3>
            <select class="form-select form-select-sm" name="xeroPayrollCalendarSelection" aria-label="Xero payroll calendar" disabled>
                <option value="" selected>Not selected</option>
            </select>
        </div>
    |]
    | otherwise = [hsx|
        <div>
            <h3 class="h6 mb-2">Payroll calendar</h3>
            {renderXeroPayrollCalendarSelectionForm payrollCalendars currentSelection}
        </div>
    |]
    where
        currentSelection =
            case maybeSelection of
                Just selection | selection.calendarStatus == "verified" -> fromMaybe "" selection.xeroPayrollCalendarId
                _ ->
                    case payrollCalendars of
                        [payrollCalendar] -> payrollCalendar.xeroPayrollCalendarId
                        _                 -> ""

renderXeroPayrollCalendarSelectionForm :: [XeroPayrollCalendar] -> Text -> Html
renderXeroPayrollCalendarSelectionForm payrollCalendars currentSelection =
    renderFrontendSurfaceActionForm
        (adminXeroAction "save-xero-payroll-calendar-selection")
        (xeroSurfaceChangeActionRoute (pathTo SaveXeroPayrollCalendarSelectionAction))
        [hsx|
            <select class="form-select form-select-sm" name="xeroPayrollCalendarSelection" aria-label="Xero payroll calendar">
                <option value="" selected={currentSelection == ""}>Not selected</option>
                {forEach payrollCalendars (renderXeroPayrollCalendarOption currentSelection)}
            </select>
        |]

xeroSurfaceChangeActionRoute :: Text -> FrontendSurfaceActionRoute
xeroSurfaceChangeActionRoute actionUrl =
    FrontendSurfaceActionRoute
        { actionRouteUrl = actionUrl
        , actionRouteFields = []
        , actionRouteCustomHtmx =
            [ FrontendSurfaceCustomHtmxAttrs
                { customHtmxAttrMarker = "change-autosave-custom-htmx"
                , customHtmxAttrValues = [("hx-trigger", "change")]
                }
            ]
        , actionRouteStandardUrl = Just actionUrl
        , actionRouteExtraAttrs = [("data-disable-javascript-submission", "true")]
        }

renderXeroPayrollCalendarOption :: Text -> XeroPayrollCalendar -> Html
renderXeroPayrollCalendarOption currentSelection payrollCalendar = [hsx|
    <option value={payrollCalendar.xeroPayrollCalendarId} selected={currentSelection == payrollCalendar.xeroPayrollCalendarId}>
        {xeroPayrollCalendarLabel payrollCalendar}
    </option>
|]

xeroPayrollCalendarLabel :: XeroPayrollCalendar -> Text
xeroPayrollCalendarLabel payrollCalendar =
    Text.intercalate " - " (filter (not . Text.null) [payrollCalendar.name, fromMaybe "" payrollCalendar.calendarType])
