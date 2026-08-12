module Application.Helper.Export.Definitions where

import Application.Helper.Controller
import Application.Helper.Export.Render (fallbackReportDayLabels)
import Application.Helper.Export.Types
import Data.Time.Calendar (Day, addDays)
import Data.Time.Clock (getCurrentTime)
import Generated.Types
import IHP.ControllerPrelude

currentExportWeekSelection ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    IO ReportWeekSelection
currentExportWeekSelection = do
    venueConfig <- fetchVenueConfig
    today <- utctDay <$> getCurrentTime
    pure (exportWeekSelection venueConfig today)

exportWeekSelectionForAnchor ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    Day ->
    IO ReportWeekSelection
exportWeekSelectionForAnchor anchorDate = do
    venueConfig <- fetchVenueConfig
    pure (exportWeekSelection venueConfig anchorDate)

exportWeekSelection :: VenueConfig -> Day -> ReportWeekSelection
exportWeekSelection venueConfig anchorDate =
    reportWeekSelection (startOfWeekFor venueConfig.rosterWeekStartsOn anchorDate)

reportWeekSelection :: Day -> ReportWeekSelection
reportWeekSelection weekStart =
    ReportWeekSelection
        { weekStart
        , weekEnd = addDays 6 weekStart
        , dayLabels = fallbackReportDayLabels weekStart
        }


rangeWeekSlices ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    Day ->
    Day ->
    IO [ReportWeekSlice]
rangeWeekSlices rangeStart rangeEnd = do
    venueConfig <- fetchVenueConfig
    let firstWeekStart = startOfWeekFor venueConfig.rosterWeekStartsOn rangeStart
    let weekStarts = takeWhile (<= rangeEnd) (iterate (addDays 7) firstWeekStart)
    pure (map toSlice weekStarts)
    where
        toSlice weekStart =
            let weekEnd = addDays 6 weekStart
             in ReportWeekSlice
                    { weekSelection = reportWeekSelection weekStart
                    , sliceStart = max rangeStart weekStart
                    , sliceEnd = min rangeEnd weekEnd
                    }

data ReportWeekSlice = ReportWeekSlice
    { weekSelection :: ReportWeekSelection
    , sliceStart    :: Day
    , sliceEnd      :: Day
    }
