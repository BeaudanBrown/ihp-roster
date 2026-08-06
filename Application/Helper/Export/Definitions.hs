module Application.Helper.Export.Definitions where

import Application.Helper.Controller
import Application.Helper.Export.Render (fallbackReportDayLabels)
import Application.Helper.Export.Types
import Data.Time.Calendar (Day, addDays)
import Data.Time.Clock (getCurrentTime)
import Generated.Types (VenueConfig)
import IHP.ControllerPrelude

currentExportWeekSelection ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    IO ReportWeekSelection
currentExportWeekSelection = do
    venueConfig <- fetchVenueConfig
    today <- utctDay <$> getCurrentTime
    pure (exportWeekSelection venueConfig (venueWeekOffsetForDay venueConfig today))

exportWeekSelectionForOffset ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    Int ->
    IO ReportWeekSelection
exportWeekSelectionForOffset weekOffset = do
    venueConfig <- fetchVenueConfig
    pure (exportWeekSelection venueConfig weekOffset)

exportWeekSelection :: VenueConfig -> Int -> ReportWeekSelection
exportWeekSelection venueConfig weekOffset =
    ReportWeekSelection
        { weekOffset
        , weekStart
        , weekEnd = addDays 6 weekStart
        , dayLabels = fallbackReportDayLabels weekStart
        }
  where
    weekStart = venueWeekStartDate venueConfig weekOffset


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
