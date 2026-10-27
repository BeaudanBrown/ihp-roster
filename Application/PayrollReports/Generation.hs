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
import Application.Helper.Hasql (isUniqueViolation, isSerializationFailure)
import qualified Control.Exception as Exception
import Application.Helper.TimesheetSelection
import Application.Helper.WeekBoundaries (weekdayIndexForDay)
import Application.PayrollReports.Schedule (withinReportCatchUpWindow)
import Application.PayrollReports.Settings (withPayrollReportVenueLock, validatePayrollReportRecipients)
import Application.PayrollReports.Selection
import Application.VenueTime.Model (storedInstantLocalTime)
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.KeyMap as KeyMap
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
    , manualSelection :: !(Maybe ManualReportSelection)
    }

-- Compatibility entry point for internal callers with no submission token.
generatePayrollReportSnapshot :: (?modelContext :: ModelContext) =>
    Id Venue -> UUID -> PayrollReportOriginEnum -> Maybe UTCTime -> Day -> UTCTime -> IO (Either Text PayrollReportRun)
generatePayrollReportSnapshot venueId actorId origin scheduledAt week now = do
    runId <- UUID.nextRandom
    generatePayrollReportRequest ReportGenerationRequest { runId, venueId, actorId, origin, scheduledAt, week, now, expectedRevision = Nothing, previousRunId = Nothing, manualSelection = Nothing }

-- Caller owns authority. A token identifies one confirmed manual submission;
-- scheduling is additionally unique by venue/week. All data shares one snapshot.
-- The venue row-version fence makes concurrent group/repeat facts retry rather
-- than consume a REPEATABLE READ snapshot established before a competing send.
generatePayrollReportRequest :: (?modelContext :: ModelContext) => ReportGenerationRequest -> IO (Either Text PayrollReportRun)
generatePayrollReportRequest request = attempt (3 :: Int)
  where
    attempt remaining = Exception.catchJust retryableConflict
        (generatePayrollReportRequestSnapshot request)
        (\() -> if remaining > 0 then attempt (remaining - 1)
            else pure (Left "The report changed while preparing. Review the send confirmation again."))
    retryableConflict :: HasqlSessionError -> Maybe ()
    retryableConflict failure
        | (isUniqueViolation failure || isSerializationFailure failure) && isNothing ?modelContext.transactionRunner = Just ()
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
                | run.reportingWeek == week && run.origin == origin && (origin == PayrollReportScheduled || run.requestedByUserId == actorId)
                    && matchesSelection run -> pure (Right run)
                | otherwise -> pure (Left "That send confirmation belongs to another report.")
            Nothing -> case request.manualSelection of
                Just selection
                    | origin /= PayrollReportManual || isJust scheduledAt || isJust request.previousRunId -> pure (Left "Invalid manual report selection.")
                    | otherwise -> loadSelectedPayrollReport venueId selection.configurationId selection.recipientGroupId >>= \case
                        Left message -> pure (Left message)
                        Right selected -> case storedInstantLocalTime selected.config.timezone now of
                            Left _ -> pure (Left "The venue timezone is unavailable.")
                            Right localNow
                                | not (manualReportSelectionIsCurrent selection selected) -> pure (Left "The template, recipients or calendar changed. Review the send confirmation again.")
                                | not (validCompletedReportWeek selected.config.rosterWeekStartsOn (localDay localNow) week) -> pure (Left "Choose a completed roster week.")
                                | otherwise -> do
                                    repeated <- payrollReportAlreadyPrepared venueId selection.configurationId week
                                    if repeated && not selection.repeatSendConfirmed
                                        then pure (Left "This export week already has an email prepared or sent. Review and confirm sending another email to the whole group.")
                                        else generate Nothing selected.config selected.template (Just selected.group) selected.group.recipients entries
                Nothing -> generateFromSettings entries
  where
    end = addDays 6 week
    matchesSelection run = case request.manualSelection of
        Nothing -> isJust run.settingsId
        Just selection -> isNothing run.settingsId
            && run.configurationId == Just selection.configurationId
            && run.recipientGroupId == Just selection.recipientGroupId
            && run.recipientGroupRevision == Just selection.recipientGroupRevision
            && snapshotValue "configurationRevision" run == Just (Aeson.toJSON selection.configurationRevision)
            && snapshotValue "rosterWeekStartsOn" run == Just (Aeson.toJSON selection.rosterWeekStartsOn)
            && snapshotValue "timezone" run == Just (Aeson.toJSON selection.timezone)
    snapshotValue key run = case run.templateSnapshot of
        Aeson.Object value -> KeyMap.lookup key value
        _ -> Nothing
    validPeriod config today previous = case request.previousRunId of
        Nothing -> validCompletedReportWeek config.rosterWeekStartsOn today week
        Just _ -> origin == PayrollReportUpdated && end < today && maybe False (\run -> run.reportingWeek == week && run.rangeEnd == end) previous
    generateFromSettings :: (?modelContext :: ModelContext) => [TimesheetEntry] -> IO (Either Text PayrollReportRun)
    generateFromSettings entries = do
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
                    | otherwise -> case settings.configurationId of
                        Nothing -> pure (Left "Choose an export template before sending.")
                        Just configurationId -> fetchSavedPayrollWorkbookConfigurationForVenue venueId (Id configurationId) >>= \case
                            Left _ -> pure (Left "The selected export template is unavailable.")
                            Right saved -> case settings.recipientGroupId of
                                Nothing -> generate (Just settings) config saved Nothing settings.recipients entries
                                Just groupId -> do
                                    group <- query @RecipientGroup |> filterWhere (#id, Id groupId)
                                        |> filterWhere (#venueId, unpackId venueId) |> filterWhere (#archivedAt, Nothing) |> fetchOneOrNothing
                                    case group of
                                        Nothing -> pure (Left "The selected recipient group is unavailable.")
                                        Just group -> generate (Just settings) config saved (Just group) group.recipients entries
            _ -> pure (Left "Configure payroll reporting before sending.")
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
    generate :: (?modelContext :: ModelContext) => Maybe PayrollReportSetting -> VenueConfig -> SavedPayrollWorkbookConfiguration -> Maybe RecipientGroup -> [Text] -> [TimesheetEntry] -> IO (Either Text PayrollReportRun)
    generate settings config saved group recipients entries = case validatePayrollReportRecipients recipients of
        Left _ -> pure (Left "The recipient list is invalid.")
        Right [] -> pure (Left "Choose at least one recipient before sending.")
        Right addresses -> do
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
                    , "configurationRevision" Aeson..= saved.savedPayrollWorkbookConfigurationRecord.revision
                    , "rosterWeekStartsOn" Aeson..= config.rosterWeekStartsOn
                    , "timezone" Aeson..= config.timezone
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
                |> set #settingsId (unpackId . (.id) <$> settings)
                |> set #configurationId (Just (unpackId saved.savedPayrollWorkbookConfigurationRecord.id))
                |> set #recipientGroupId (unpackId . (.id) <$> group)
                |> set #recipientGroupRevision ((.revision) <$> group)
                |> set #exportJobId (unpackId . (.id) <$> export)
                |> set #reportingWeek week
                |> set #rangeEnd end
                |> set #origin origin
                |> set #status status
                |> set #recipients addresses
                |> set #templateSnapshot snapshot
                |> set #excludedEntryCount excluded
                |> set #approvedEntryCount count
                |> set #deliveryRevision (maybe 0 (.deliveryRevision) settings)
                |> set #scheduleActivatedAt (maybe now (.scheduleActivatedAt) settings)
                |> set #scheduledAt scheduledAt
                |> set #requestedByUserId actorId
                |> createRecord)
