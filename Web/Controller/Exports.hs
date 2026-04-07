module Web.Controller.Exports where

import Application.Helper.Export
import qualified Data.ByteString.Base64 as Base64
import qualified Data.List as List
import qualified Data.Text as Text
import Data.Text.Encoding (encodeUtf8)
import Data.Time.Calendar (addDays)
import Network.HTTP.Types.Header (hContentDisposition, hContentType)
import Network.HTTP.Types.Status (status200)
import Network.Wai (responseLBS)
import Web.Controller.Prelude
import Web.View.Exports.Index

instance Controller ExportsController where
    beforeAction = do
        ensureIsUser
        ensureCurrentVenue
        ensureProfileCompleted
        ensureManagerRole

    action ExportJobsAction = do
        exportJobs <- fetchCurrentVenueExportJobs
        reportDefinitions <- fetchCurrentVenueReportDefinitions
        allReportDefinitions <- fetchCurrentVenueReportDefinitionsIncludingInactive
        shiftTypes <- query @ShiftType
            |> filterWhere (#venueId, unpackId currentVenueId)
            |> orderByAsc #sortOrder
            |> orderByAsc #name
            |> fetch
        currentWeekOffset <- currentReportWeekOffset
        let selectedWeekOffset = paramOrDefault currentWeekOffset "weekOffset"
        reportWeekSelection <- fetchReportWeekSelection selectedWeekOffset
        today <- utctDay <$> getCurrentTime
        let defaultRangeEnd = today
        let defaultRangeStart = addDays (-6) today
        let canManageReportDefinitions = hasRole VenueAdminRole
        render IndexView { .. }

    action CreateExportJobAction = do
        currentWeekOffset <- currentReportWeekOffset
        let selectedWeekOffset = paramOrDefault currentWeekOffset "weekOffset"
        case paramOrNothing @Text "reportSlug" of
            Just reportSlug -> do
                requestReportDefinitionExport reportSlug selectedWeekOffset >>= \case
                    Left message -> setErrorMessage message
                    Right _ -> setSuccessMessage "Export generated"
                redirectToPath (pathTo ExportJobsAction <> "?weekOffset=" <> tshow selectedWeekOffset)
            Nothing -> do
                let maybeRangeStart = paramOrNothing @Day "rangeStart"
                let maybeRangeEnd = paramOrNothing @Day "rangeEnd"

                case (maybeRangeStart, maybeRangeEnd) of
                    (Just rangeStart, Just rangeEnd) | rangeStart <= rangeEnd -> do
                        _ <- requestApprovedTimesheetsCsvExport rangeStart rangeEnd
                        setSuccessMessage "Export generated"
                        redirectTo ExportJobsAction
                    _ -> do
                        setErrorMessage "Choose a valid start and end date for the export range."
                        redirectTo ExportJobsAction

    action CreateReportDefinitionAction = do
        ensureAdminRole
        parseReportDefinitionParams Nothing >>= \case
            Nothing -> redirectTo ExportJobsAction
            Just reportParams -> do
                reportDefinition <- newRecord @ReportDefinition
                    |> set #venueId (unpackId currentVenueId)
                    |> applyReportDefinitionParams reportParams
                    |> createRecord
                syncReportDefinitionShiftTypeFilters reportDefinition reportParams.shiftTypeIds
                setSuccessMessage "Report definition added"
                redirectTo ExportJobsAction

    action UpdateReportDefinitionAction { reportDefinitionId } = do
        ensureAdminRole
        reportDefinition <- fetch reportDefinitionId
        ensureRecordInCurrentVenue reportDefinition.venueId
        parseReportDefinitionParams (Just reportDefinition) >>= \case
            Nothing -> redirectTo ExportJobsAction
            Just reportParams -> do
                updatedDefinition <- reportDefinition
                    |> applyReportDefinitionParams reportParams
                    |> updateRecord
                syncReportDefinitionShiftTypeFilters updatedDefinition reportParams.shiftTypeIds
                setSuccessMessage "Report definition updated"
                redirectTo ExportJobsAction

    action DownloadExportJobAction { exportJobId } = do
        let downloadToken = param @UUID "token"
        exportJob <- authorizeExportDownload exportJobId downloadToken >>= recordExportDownload

        let fileName = fromMaybe "export.csv" exportJob.fileName
        let contentType = fromMaybe "text/csv; charset=utf-8" exportJob.contentType
        let fileContents =
                case exportJob.fileEncoding of
                    "base64" ->
                        case Base64.decode (encodeUtf8 (fromMaybe "" exportJob.fileContents)) of
                            Left _      -> ""
                            Right bytes -> cs bytes
                    _ -> cs (fromMaybe "" exportJob.fileContents)
        let contentDisposition = "attachment; filename=\"" <> fileName <> "\""

        respondAndExit $
            responseLBS
                status200
                [ (hContentType, cs contentType)
                , (hContentDisposition, cs contentDisposition)
                ]
                fileContents

data ReportDefinitionParams = ReportDefinitionParams
    { slug         :: !Text
    , name         :: !Text
    , description  :: !(Maybe Text)
    , engine       :: !Text
    , sortOrder    :: !Int
    , isActive     :: !Bool
    , shiftTypeIds :: ![Id ShiftType]
    }

applyReportDefinitionParams :: ReportDefinitionParams -> ReportDefinition -> ReportDefinition
applyReportDefinitionParams reportParams reportDefinition =
    reportDefinition
        |> set #slug reportParams.slug
        |> set #name reportParams.name
        |> set #description reportParams.description
        |> set #engine reportParams.engine
        |> set #sortOrder reportParams.sortOrder
        |> set #isActive reportParams.isActive

parseReportDefinitionParams ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Maybe ReportDefinition ->
    IO (Maybe ReportDefinitionParams)
parseReportDefinitionParams existingDefinition = do
    let rawSlug = Text.strip (paramOrDefault "" "slug")
    let rawName = Text.strip (paramOrDefault "" "name")
    let rawDescription = Text.strip (paramOrDefault "" "description")
    let rawEngine = Text.strip (paramOrDefault "" "engine")
    let reportSortOrder = paramOrDefault @Int 0 "sortOrder"
    let reportIsActive = paramOrDefault "true" "isActive" == ("true" :: Text)
    let reportShiftTypeIds = paramList @(Id ShiftType) "shiftTypeIds"

    if
        | Text.null rawSlug -> setErrorMessage "Report slug is required." >> pure Nothing
        | Text.null rawName -> setErrorMessage "Report name is required." >> pure Nothing
        | isNothing (parseReportDefinitionEngine rawEngine) -> setErrorMessage "Choose a valid report engine." >> pure Nothing
        | otherwise -> do
            existingDefinitions <- fetchCurrentVenueReportDefinitionsIncludingInactive
            let slugConflict =
                    any
                        (\candidate ->
                            candidate.definition.slug == rawSlug
                                && maybe True (\existing -> get #id existing /= get #id candidate.definition) existingDefinition
                        )
                        existingDefinitions
            if slugConflict
                then setErrorMessage "That report slug is already in use for this venue." >> pure Nothing
                else do
                    shiftTypeIdsAreValid <- validateShiftTypeIds reportShiftTypeIds
                    if not shiftTypeIdsAreValid
                        then setErrorMessage "Choose shift types from the current venue." >> pure Nothing
                        else
                            pure
                                ( Just
                                    ReportDefinitionParams
                                        { slug = rawSlug
                                        , name = rawName
                                        , description = if Text.null rawDescription then Nothing else Just rawDescription
                                        , engine = rawEngine
                                        , sortOrder = reportSortOrder
                                        , isActive = reportIsActive
                                        , shiftTypeIds = List.nub reportShiftTypeIds
                                        }
                                )

validateShiftTypeIds :: (?context :: ControllerContext, ?modelContext :: ModelContext) => [Id ShiftType] -> IO Bool
validateShiftTypeIds shiftTypeIds
    | null shiftTypeIds = pure True
    | otherwise = do
        validCount <- query @ShiftType
            |> filterWhere (#venueId, unpackId currentVenueId)
            |> filterWhereIn (#id, shiftTypeIds)
            |> fetchCount
        pure (validCount == length (List.nub shiftTypeIds))

syncReportDefinitionShiftTypeFilters ::
    (?modelContext :: ModelContext) =>
    ReportDefinition ->
    [Id ShiftType] ->
    IO ()
syncReportDefinitionShiftTypeFilters reportDefinition shiftTypeIds = withTransaction do
    existingFilters <- query @ReportDefinitionShiftTypeFilter
        |> filterWhere (#reportDefinitionId, unpackId (get #id reportDefinition))
        |> fetch
    let desiredShiftTypeIds = map unpackId shiftTypeIds
    forM_ existingFilters \existingFilter ->
        when (existingFilter.shiftTypeId `notElem` desiredShiftTypeIds) do
            deleteRecord existingFilter
    let existingShiftTypeIds = map (.shiftTypeId) existingFilters
    forM_ desiredShiftTypeIds \shiftTypeId ->
        when (shiftTypeId `notElem` existingShiftTypeIds) do
            newRecord @ReportDefinitionShiftTypeFilter
                |> set #reportDefinitionId (unpackId (get #id reportDefinition))
                |> set #shiftTypeId shiftTypeId
                |> createRecordDiscardResult
