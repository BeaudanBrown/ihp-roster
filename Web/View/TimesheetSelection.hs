module Web.View.TimesheetSelection
    ( TimesheetSelectionRow (..)
    , renderTimesheetSelectionChecklist
    ) where

import qualified Data.List as List
import Web.View.Prelude

-- Quantities here are a worked-time display only, never payroll inputs.
data TimesheetSelectionRow = TimesheetSelectionRow
    { selectionRowDay :: Day
    , selectionRowToken :: Text
    , selectionRowStaff :: Text
    , selectionRowShift :: Text
    , selectionRowWorkedHours :: Double
    }

renderTimesheetSelectionChecklist :: Text -> [TimesheetSelectionRow] -> [Text] -> (Maybe Day -> Bool -> Html) -> Html
renderTimesheetSelectionChecklist fieldName rows selected groupControl = [hsx|
    <div class="d-flex flex-wrap gap-2 mb-3">
        {groupControl Nothing True}
        {groupControl Nothing False}
    </div>
    <p role="status">{tshow (length selectedRows)} shifts selected · {hoursLabel totalHours} worked hours</p>
    <input type="hidden" name={fieldName} value="" />
    {forEach grouped renderDay}
|]
  where
    selectedRows = filter (\row -> row.selectionRowToken `elem` selected) rows
    totalHours = sum (map (.selectionRowWorkedHours) selectedRows)
    grouped = List.groupBy (\left right -> left.selectionRowDay == right.selectionRowDay) (List.sortOn (.selectionRowDay) rows)
    renderDay [] = mempty
    renderDay dayRows@(first : _) = [hsx|
        <fieldset class="mb-3">
            <legend class="fs-6">{tshow first.selectionRowDay}</legend>
            <div class="d-flex gap-2 mb-2">
                {groupControl (Just first.selectionRowDay) True}
                {groupControl (Just first.selectionRowDay) False}
            </div>
            {forEach dayRows renderRow}
        </fieldset>
    |]
    renderRow row = [hsx|
        <label class="d-flex gap-2 align-items-start mb-2">
            <input type="checkbox" name={fieldName} value={row.selectionRowToken} checked={row.selectionRowToken `elem` selected} />
            <span>{row.selectionRowStaff} · {row.selectionRowShift} · {hoursLabel row.selectionRowWorkedHours} worked hours</span>
        </label>
    |]
    hoursLabel value = tshow (fromIntegral (round (value * 100) :: Integer) / 100 :: Double)
