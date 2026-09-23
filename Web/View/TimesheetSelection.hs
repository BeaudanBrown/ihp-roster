module Web.View.TimesheetSelection
    ( TimesheetSelectionRow (..)
    , TimesheetSelectionDialog (..)
    , renderTimesheetSelectionDialog
    , renderTimesheetSelectionChecklist
    , timesheetSelectionFormAttributes
    ) where

import qualified Application.Helper.FrontendContract.Toggle as Toggle
import Application.Helper.FrontendContract.Values (domAttrValue)
import Application.Helper.View.Overlay
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

-- Both workflows supply their typed form/transport; all dialog chrome is shared.
data TimesheetSelectionDialog = TimesheetSelectionDialog
    { selectionDialogTitle :: Text
    , selectionDialogBody :: Html
    , selectionDialogSubmitLabel :: Text
    , selectionDialogLoadingLabel :: Text
    , selectionDialogHasSelection :: Bool
    }

renderTimesheetSelectionDialog :: TimesheetSelectionDialog -> Html
renderTimesheetSelectionDialog config@TimesheetSelectionDialog { selectionDialogBody } = renderDialogOverlay DialogOverlayConfig
    { dialogOverlayTitle = config.selectionDialogTitle
    , dialogOverlayBody = selectionDialogBody
    , dialogOverlayStartButtons = []
    , dialogOverlayButtons =
        [ dialogOverlayCloseButton "Cancel"
        , OverlayButton
            { overlayButtonLabel = config.selectionDialogSubmitLabel
            , overlayButtonClass = "btn btn-primary"
            , overlayButtonAction = OverlaySubmitFormLoadingAction
                { overlaySubmitFormId = "timesheet-selection-form"
                , overlaySubmitLoadingLabel = config.selectionDialogLoadingLabel
                , overlaySubmitEnabled = config.selectionDialogHasSelection
                , overlaySubmitExtraAttrs = [(domAttrValue @Toggle.CheckboxListSubmit, "true")]
                }
            }
        ]
    , dialogOverlayDialogClass = "modal-lg modal-dialog-scrollable"
    }

timesheetSelectionFormAttributes :: [(Text, Text)]
timesheetSelectionFormAttributes = [("id", "timesheet-selection-form"), (domAttrValue @Toggle.CheckboxListRoot, "true")]

renderTimesheetSelectionChecklist :: Text -> [TimesheetSelectionRow] -> [Text] -> Html
renderTimesheetSelectionChecklist fieldName rows selected = [hsx|
    <div class="d-flex flex-wrap gap-2 mb-3">
        <button type="button" class="btn btn-outline-primary" {...[(domAttrValue @Toggle.CheckboxListSelectAll, "true" :: Text)]}>Select all</button>
        <button type="button" class="btn btn-outline-primary" {...[(domAttrValue @Toggle.CheckboxListClearAll, "true" :: Text)]}>Clear all</button>
    </div>
    <p role="status"><output role="none" {...[(domAttrValue @Toggle.CheckboxListCount, "true" :: Text)]}>{tshow (length selectedRows)}</output> shifts selected · <output role="none" {...[(domAttrValue @Toggle.CheckboxListTotal, "true" :: Text)]}>{hoursLabel totalHours}</output> worked hours</p>
    <input type="hidden" name={fieldName} value="" />
    <div class="timesheet-selection-list">
        <div class="timesheet-selection-columns fw-semibold" aria-hidden="true">
            <span></span><span>Staff</span><span>Shift</span><span class="text-end">Worked hours</span>
        </div>
        {forEach grouped renderDay}
    </div>
|]
  where
    selectedRows = filter isSelected rows
    isSelected row = row.selectionRowToken `elem` selected
    totalHours = sum (map (.selectionRowWorkedHours) selectedRows)
    grouped = List.groupBy (\left right -> left.selectionRowDay == right.selectionRowDay) (List.sortOn (.selectionRowDay) rows)
    renderDay [] = mempty
    renderDay dayRows@(first : _) = [hsx|
        <fieldset class="timesheet-selection-day" {...[(domAttrValue @Toggle.CheckboxListGroup, "true" :: Text)]}>
            <legend>
                <label class="timesheet-selection-day-heading">
                    <input type="checkbox" id={"timesheet-selection-day-" <> tshow first.selectionRowDay} class="form-check-input" checked={all isSelected dayRows}
                           {...[(domAttrValue @Toggle.CheckboxListGroupToggle, "true" :: Text)]} />
                    <span>{dayLabel first.selectionRowDay}</span>
                </label>
            </legend>
            {forEach dayRows renderRow}
        </fieldset>
    |]
    renderRow row = [hsx|
        <label class="timesheet-selection-row timesheet-selection-columns">
            <input type="checkbox" class="form-check-input" name={fieldName} value={row.selectionRowToken} checked={isSelected row}
                   {...[(domAttrValue @Toggle.CheckboxListItem, "true"), (domAttrValue @Toggle.CheckboxListWeight, tshow row.selectionRowWorkedHours)]} />
            <span>{row.selectionRowStaff}</span>
            <span><span class="visually-hidden">Shift </span>{row.selectionRowShift}</span>
            <span class="text-end">{hoursLabel row.selectionRowWorkedHours}<span class="visually-hidden"> worked hours</span></span>
        </label>
    |]
    dayLabel day = cs (formatTime defaultTimeLocale "%A %d/%m" day) :: Text
    hoursLabel value = tshow (fromIntegral (round (value * 100) :: Integer) / 100 :: Double)
