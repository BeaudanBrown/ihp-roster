module Application.Helper.Export.Definitions where

import Application.Helper.Controller
import Application.Helper.Export.Render (fallbackReportDayLabels)
import Application.Helper.Export.Types
import Control.Monad (void)
import Data.Coerce (coerce)
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import Data.Time.Calendar (Day, addDays)
import Data.Time.Clock (getCurrentTime)
import Generated.Types
import IHP.ControllerPrelude

currentReportWeekOffset ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    IO Int
currentReportWeekOffset = do
    venueConfig <- fetchVenueConfig
    today <- utctDay <$> getCurrentTime
    pure (venueWeekOffsetForDay venueConfig today)

fetchReportWeekSelection ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    Int ->
    IO ReportWeekSelection
fetchReportWeekSelection selectedWeekOffset = do
    venueConfig <- fetchVenueConfig
    let reportWeekStart = venueWeekStartDate venueConfig selectedWeekOffset
    let labels = fallbackReportDayLabels reportWeekStart
    let reportWeekEnd = addDays 6 reportWeekStart
    pure
        ReportWeekSelection
            { weekOffset = selectedWeekOffset
            , weekStart = reportWeekStart
            , weekEnd = reportWeekEnd
            , dayLabels = labels
            }

reportDefinitionEngineImplemented :: ReportDefinitionEngine -> Bool
reportDefinitionEngineImplemented StaffPayCsvReport        = True
reportDefinitionEngineImplemented HourlyBreakdownZipReport = True
reportDefinitionEngineImplemented PayrollEarningsCsvReport = True

fetchCurrentVenueReportDefinitions ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    IO [VenueReportDefinition]
fetchCurrentVenueReportDefinitions =
    filter (.definition.isActive) <$> fetchCurrentVenueReportDefinitionsIncludingInactive

fetchCurrentVenueReportDefinitionsIncludingInactive ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    IO [VenueReportDefinition]
fetchCurrentVenueReportDefinitionsIncludingInactive = do
    bootstrapCurrentVenueReportDefinitionsIfMissing
    definitions <- query @ReportDefinition
        |> filterWhere (#venueId, unpackId currentVenueId)
        |> orderByAsc #sortOrder
        |> orderByAsc #createdAt
        |> fetch
    filtersByDefinitionId <- fetchReportDefinitionShiftTypeFilters definitions
    pure (map (toVenueReportDefinition filtersByDefinitionId) definitions)

bootstrapCurrentVenueReportDefinitionsIfMissing ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    IO ()
bootstrapCurrentVenueReportDefinitionsIfMissing = do
    existingDefinitions <- query @ReportDefinition
        |> filterWhere (#venueId, unpackId currentVenueId)
        |> fetchCount
    when (existingDefinitions == 0) do
        shiftTypes <- query @ShiftType
            |> filterWhere (#venueId, unpackId currentVenueId)
            |> filterWhere (#isActive, True)
            |> orderByAsc #createdAt
            |> fetch
        void $ withTransaction do
            _ <- createReportDefinition "wage" "Wage Report" (Just "Hourly staff count breakdown per day (ZIP of CSVs)") HourlyBreakdownZipReport 10
            _ <- createReportDefinition "staff_hours" "Staff Hours Report" (Just "Staff hours broken down by pay level and day") StaffPayCsvReport 20
            _ <- createReportDefinition "payroll_earnings" "Payroll Earnings CSV" (Just "Approved payroll earnings by staff, date, earnings bucket, and tracking code") PayrollEarningsCsvReport 25
            forM_ (find (\shiftType -> shiftType.name == "Kitchen") shiftTypes) \kitchenShiftType -> do
                kitchenDefinition <- createReportDefinition "kitchen" "Kitchen Report" (Just "Kitchen staff hours by day") StaffPayCsvReport 30
                newRecord @ReportDefinitionShiftTypeFilter
                    |> set #reportDefinitionId (unpackId (get #id kitchenDefinition))
                    |> set #shiftTypeId (unpackId (get #id kitchenShiftType))
                    |> createRecord
    where
        createReportDefinition slug name description engine sortOrder =
            newRecord @ReportDefinition
                |> set #venueId (unpackId currentVenueId)
                |> set #slug slug
                |> set #name name
                |> set #description description
                |> set #engine (reportDefinitionEngineToText engine)
                |> set #sortOrder sortOrder
                |> createRecord

fetchReportDefinitionShiftTypeFilters ::
    (?modelContext :: ModelContext) =>
    [ReportDefinition] ->
    IO (Map.Map UUID [ShiftType])
fetchReportDefinitionShiftTypeFilters definitions =
    if null definitions
        then pure Map.empty
        else do
            filters <- query @ReportDefinitionShiftTypeFilter
                |> filterWhereIn (#reportDefinitionId, map (coerce . get #id) definitions)
                |> filterWhere (#deletedAt, Nothing)
                |> fetch
            let shiftTypeIds = List.nub (map (.shiftTypeId) filters)
            shiftTypes <-
                if null shiftTypeIds
                    then pure []
                    else query @ShiftType |> filterWhereIn (#id, map Id shiftTypeIds) |> fetch
            let shiftTypesById = Map.fromList (map (\shiftType -> (coerce (get #id shiftType), shiftType)) shiftTypes)
            pure $
                foldl'
                    (\acc filterRow ->
                        case Map.lookup filterRow.reportDefinitionId shiftTypesById of
                            Just shiftType ->
                                Map.insertWith (<>) filterRow.reportDefinitionId [shiftType] acc
                            Nothing -> acc
                    )
                    Map.empty
                    filters

toVenueReportDefinition :: Map.Map UUID [ShiftType] -> ReportDefinition -> VenueReportDefinition
toVenueReportDefinition filtersByDefinitionId definition =
    VenueReportDefinition
        { definition
        , engine = fromMaybe StaffPayCsvReport (parseReportDefinitionEngine definition.engine)
        , shiftTypeFilters = fromMaybe [] (Map.lookup (coerce (get #id definition)) filtersByDefinitionId)
        }

rangeWeekSelections ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    Day ->
    Day ->
    IO [ReportWeekSelection]
rangeWeekSelections rangeStart rangeEnd =
    map (.weekSelection) <$> rangeWeekSlices rangeStart rangeEnd

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
