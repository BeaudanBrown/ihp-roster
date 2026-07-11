module Application.Helper.Export.Definitions where

import Application.Helper.Controller
import Application.Helper.Export.Render (fallbackReportDayLabels)
import Application.Helper.Export.Types
import Data.Time.Calendar (Day, addDays)
import Data.Time.Clock (getCurrentTime)
import IHP.ControllerPrelude

currentExportDateRange ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    IO (Day, Day)
currentExportDateRange = do
    venueConfig <- fetchVenueConfig
    today <- utctDay <$> getCurrentTime
    let weekStart = venueWeekStartDate venueConfig (venueWeekOffsetForDay venueConfig today)
    pure (weekStart, addDays 6 weekStart)

rangeWeekSlices ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    Day ->
    Day ->
    IO [ReportWeekSlice]
rangeWeekSlices rangeStart rangeEnd = do
    venueConfig <- fetchVenueConfig
    let firstWeekStart = venueWeekStartDate venueConfig (venueWeekOffsetForDay venueConfig rangeStart)
    let weekStarts = takeWhile (<= rangeEnd) (iterate (addDays 7) firstWeekStart)
    pure (map (toSlice venueConfig) weekStarts)
    where
        toSlice venueConfig weekStart =
            let weekEnd = addDays 6 weekStart
             in ReportWeekSlice
                    { weekSelection =
                        ReportWeekSelection
                            { weekOffset = venueWeekOffsetForDay venueConfig weekStart
                            , weekStart
                            , weekEnd
                            , dayLabels = fallbackReportDayLabels weekStart
                            }
                    , sliceStart = max rangeStart weekStart
                    , sliceEnd = min rangeEnd weekEnd
                    }

data ReportWeekSlice = ReportWeekSlice
    { weekSelection :: ReportWeekSelection
    , sliceStart    :: Day
    , sliceEnd      :: Day
    }
