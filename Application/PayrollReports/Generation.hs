module Application.PayrollReports.Generation
    ( ReportGenerationRequest (..)
    , generatePayrollReportSnapshot
    , generatePayrollReportRequest
    , validCompletedReportWeek
    ) where

import Application.Helper.Export.PayrollWorkbook
import Application.Helper.Export.PayrollWorkbookConfiguration
import Application.Helper.Export.Persistence (persistBackgroundPayrollExport)
import Application.Helper.Export.Render (payrollWorkbookFileName)
import Application.Helper.Export.Payloads (collapseVersionManifests)
import Application.Helper.Export.WorkbookGeneration
import Application.Helper.Hasql (isUniqueViolation)
import qualified Control.Exception as Exception
import Application.Helper.TimesheetSelection
import Application.Helper.WeekBoundaries (startOfWeekFor, weekdayIndexForDay)
import Application.PayrollReports.Schedule (withinReportCatchUpWindow)
import Application.PayrollReports.Settings (withPayrollReportVenueLock, validatePayrollReportRecipients)
import Application.VenueTime.Model (storedInstantLocalTime)
import qualified Data.Aeson as Aeson
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import qualified Data.UUID.V4 as UUID
import Generated.Types
import IHP.ControllerPrelude

data ReportGenerationRequest = ReportGenerationRequest
    { runId :: !UUID
    , venueId :: !(Id Venue)
    , actorId :: !UUID
    , origin :: !PayrollReportOriginEnum
    , scheduledAt :: !(Maybe UTCTime)
    , week :: !Day
    , now :: !UTCTime
    , expectedRevision :: !(Maybe Int)
    , previousRunId :: !(Maybe UUID)
    }

validCompletedReportWeek :: Int -> Day -> Day -> Bool
validCompletedReportWeek startsOn today week = startOfWeekFor startsOn week == week && addDays 6 week < today

-- Compatibility entry point for internal callers with no submission token.
generatePayrollReportSnapshot :: (?modelContext :: ModelContext) =>
    Id Venue -> UUID -> PayrollReportOriginEnum -> Maybe UTCTime -> Day -> UTCTime -> IO (Either Text PayrollReportRun)
generatePayrollReportSnapshot venueId actorId origin scheduledAt week now = do
    runId <- UUID.nextRandom
    generatePayrollReportRequest ReportGenerationRequest { runId, venueId, actorId, origin, scheduledAt, week, now, expectedRevision = Nothing, previousRunId = Nothing }

-- Caller owns authority. A token identifies one confirmed manual submission;
-- scheduling is additionally unique by venue/week. All data shares one snapshot.
generatePayrollReportRequest :: (?modelContext :: ModelContext) => ReportGenerationRequest -> IO (Either Text PayrollReportRun)
generatePayrollReportRequest request =
    Exception.catchJust retryableConflict
        (generatePayrollReportRequestSnapshot request)
        (\() -> generatePayrollReportRequestSnapshot request)
  where
    retryableConflict :: HasqlSessionError -> Maybe ()
    retryableConflict failure
        | isUniqueViolation failure && isNothing ?modelContext.transactionRunner = Just ()
        | otherwise = Nothing

generatePayrollReportRequestSnapshot :: (?modelContext :: ModelContext) => ReportGenerationRequest -> IO (Either Text PayrollReportRun)
generatePayrollReportRequestSnapshot request@ReportGenerationRequest { venueId, actorId, origin, scheduledAt, week, now } =
    withTimesheetSelectionSnapshot (unpackId venueId) week end AllEligible fetchEntries \entries -> do
        existing <- query @PayrollReportRun |> filterWhere (#venueId, unpackId venueId) |> filterWhere (#id, Id request.runId) |> fetchOneOrNothing
        scheduled <- if origin == PayrollReportScheduled then
            query @PayrollReportRun |> filterWhere (#venueId, unpackId venueId) |> filterWhere (#origin, PayrollReportScheduled) |> filterWhere (#reportingWeek, week) |> fetchOneOrNothing
            else pure Nothing
        case existing <|> scheduled of
            Just run
                | run.reportingWeek == week && run.origin == origin && (origin == PayrollReportScheduled || run.requestedByUserId == actorId) -> pure (Right run)
                | otherwise -> pure (Left "That send confirmation belongs to another report.")
            Nothing -> do
                settings <- query @PayrollReportSetting |> filterWhere (#venueId, unpackId venueId) |> fetchOneOrNothing
                config <- query @VenueConfig |> filterWhere (#venueId, unpackId venueId) |> fetchOneOrNothing
                previous <- case request.previousRunId of
                    Nothing -> pure Nothing
                    Just previousId -> query @PayrollReportRun |> filterWhere (#venueId, unpackId venueId) |> filterWhere (#id, Id previousId) |> fetchOneOrNothing
                case (settings, config) of
                    (Just settings, Just config) -> case storedInstantLocalTime config.timezone now of
                        Left _ -> pure (Left "The venue timezone is unavailable.")
                        Right localNow
                            | maybe False (/= settings.revision) request.expectedRevision -> pure (Left "Report settings changed. Review the send confirmation again.")
                            | not (validPeriod config (localDay localNow) previous) -> pure (Left "Choose a completed roster week.")
                            | origin == PayrollReportScheduled && (not settings.enabled || maybe True (\due -> due <= settings.scheduleActivatedAt || due > now) scheduledAt) -> pure (Left "The automatic schedule changed or is disabled.")
                            | null settings.recipients || isNothing settings.configurationId -> pure (Left "Choose a template and recipients before sending.")
                            | otherwise -> case validatePayrollReportRecipients settings.recipients of
                                Left _ -> pure (Left "The recipient list is invalid.")
                                Right _ -> case settings.configurationId of
                                    Nothing -> pure (Left "Choose a template before sending.")
                                    Just configurationId -> fetchSavedPayrollWorkbookConfigurationForVenue venueId (Id configurationId) >>= \case
                                        Left _ -> pure (Left "The selected template is unavailable.")
                                        Right saved -> generate settings config saved entries
                    _ -> pure (Left "Configure payroll reporting before sending.")
  where
    end = addDays 6 week
    validPeriod config today previous = case request.previousRunId of
        Nothing -> validCompletedReportWeek config.rosterWeekStartsOn today week
        Just _ -> origin == PayrollReportUpdated && end < today && maybe False (\run -> run.reportingWeek == week && run.rangeEnd == end) previous
    fetchEntries :: (?modelContext :: ModelContext) => IO [TimesheetEntry]
    fetchEntries = do
        withPayrollReportVenueLock (unpackId venueId)
        query @TimesheetEntry
            |> filterWhere (#venueId, unpackId venueId)
            |> filterWhere (#isApproved, True)
            |> filterWhere (#deletedAt, Nothing)
            |> filterWhereGreaterThanOrEqualTo (#operationalDate, week)
            |> filterWhereLessThan (#operationalDate, addDays 7 week)
            |> orderByAsc #operationalDate
            |> orderByAsc #startsAt
            |> fetch
    generate :: (?modelContext :: ModelContext) => PayrollReportSetting -> VenueConfig -> SavedPayrollWorkbookConfiguration -> [TimesheetEntry] -> IO (Either Text PayrollReportRun)
    generate settings config saved entries = do
        excluded <- query @TimesheetEntry
            |> filterWhere (#venueId, unpackId venueId)
            |> filterWhere (#isApproved, False)
            |> filterWhere (#deletedAt, Nothing)
            |> filterWhereGreaterThanOrEqualTo (#operationalDate, week)
            |> filterWhereLessThan (#operationalDate, addDays 7 week)
            |> fetchCount
        let definition = saved.savedPayrollWorkbookConfigurationDefinition
        let name = saved.savedPayrollWorkbookConfigurationRecord.name
        let snapshot = Aeson.object
                [ "name" Aeson..= name
                , "definitionKey" Aeson..= definition.payrollWorkbookDefinitionKey
                , "definitionVersion" Aeson..= definition.payrollWorkbookDefinitionVersion
                , "sheetFamilies" Aeson..= map payrollWorkbookSheetFamilyKey definition.payrollWorkbookDefinitionSheetFamilies
                ]
        let missed = origin == PayrollReportScheduled && maybe False (not . withinReportCatchUpWindow now) scheduledAt
        outcome <- if missed then pure (Right Nothing) else generateWorkbookForVenue venueId (config |> set #rosterWeekStartsOn (weekdayIndexForDay week)) entries definition week end
        (export, count, status) <- case outcome of
            Left _ -> pure (Nothing, 0, PayrollReportFailed)
            Right Nothing -> pure (Nothing, 0, if missed then PayrollReportMissed else PayrollReportNoData)
            Right (Just generated) -> do
                let contents = renderPayrollWorkbookBase64 generated.workbook
                let manifests = List.sort (List.nub (Map.elems generated.manifests))
                export <- persistBackgroundPayrollExport (unpackId venueId) actorId week end
                    (Aeson.object ["template" Aeson..= snapshot, "versionManifests" Aeson..= manifests, "entryCount" Aeson..= length generated.entries])
                    (payrollWorkbookFileName name week end) contents (collapseVersionManifests manifests) generated.entries
                pure (Just export, length generated.entries, PayrollReportReady)
        Right <$> (newRecord @PayrollReportRun
            |> set #id (Id request.runId)
            |> set #venueId (unpackId venueId)
            |> set #settingsId (unpackId settings.id)
            |> set #exportJobId (unpackId . (.id) <$> export)
            |> set #reportingWeek week
            |> set #rangeEnd end
            |> set #origin origin
            |> set #status status
            |> set #recipients settings.recipients
            |> set #templateSnapshot snapshot
            |> set #excludedEntryCount excluded
            |> set #approvedEntryCount count
            |> set #deliveryRevision settings.deliveryRevision
            |> set #scheduleActivatedAt settings.scheduleActivatedAt
            |> set #scheduledAt scheduledAt
            |> set #requestedByUserId actorId
            |> createRecord)
