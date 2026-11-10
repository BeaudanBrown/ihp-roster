module Web.TimesheetSelection (fetchTimesheetSelectionRows, selectedWorkedHours) where

import Application.Helper.Export.ReadModel (fetchReportShiftTypes,
                                            fetchStaffMap)
import Application.Helper.TimesheetSelection
import qualified Application.VenueTime.Seconds as Seconds
import qualified Data.Map.Strict as Map
import Generated.Types
import IHP.ControllerPrelude
import Web.View.TimesheetSelection (TimesheetSelectionRow (..))

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
selectedWorkedHours entries = fromRational (Seconds.toHours (Seconds.sum (map seconds entries)))
  where
    seconds entry = Seconds.subtract (Seconds.between entry.startsAt entry.endsAt) (case (entry.breakStartsAt, entry.breakEndsAt) of
        (Just start, Just end) -> Seconds.between start end
        _                      -> Seconds.fromSeconds 0)
