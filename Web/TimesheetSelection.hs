module Web.TimesheetSelection (fetchTimesheetSelectionRows, selectedWorkedHours) where

import Application.Helper.Export.ReadModel (fetchStaffMap, fetchReportShiftTypes)
import Application.Helper.TimesheetSelection
import qualified Data.Map.Strict as Map
import Web.View.TimesheetSelection (TimesheetSelectionRow (..))
import Generated.Types
import IHP.ControllerPrelude

fetchTimesheetSelectionRows :: (?modelContext :: ModelContext) => [TimesheetEntry] -> IO [TimesheetSelectionRow]
fetchTimesheetSelectionRows entries = do
    staffById <- fetchStaffMap entries
    shifts <- fetchReportShiftTypes entries
    let shiftsById = Map.fromList [(unpackId shift.id, shift.name) | shift <- shifts]
    pure [TimesheetSelectionRow
        { selectionRowDay = entry.operationalDate
        , selectionRowToken = encodeTimesheetSelectionIdentity (timesheetSelectionIdentity entry)
        , selectionRowStaff = maybe "Unknown staff" (\staff -> staff.firstName <> " " <> staff.lastName) (Map.lookup entry.staffId staffById)
        , selectionRowShift = Map.findWithDefault "Unknown shift type" entry.shiftTypeId shiftsById
        , selectionRowWorkedHours = selectedWorkedHours [entry]
        } | entry <- entries]

selectedWorkedHours :: [TimesheetEntry] -> Double
selectedWorkedHours entries = realToFrac (sum (map seconds entries)) / 3600
  where
    seconds entry = diffUTCTime entry.endsAt entry.startsAt - case (entry.breakStartsAt, entry.breakEndsAt) of
        (Just start, Just end) -> diffUTCTime end start
        _ -> 0
