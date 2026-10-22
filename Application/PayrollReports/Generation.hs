module Application.PayrollReports.Generation
    ( generatePayrollReportSnapshot
    , validCompletedReportWeek
    ) where

import Application.Helper.Export.PayrollWorkbook
import Application.Helper.Export.PayrollWorkbookConfiguration
import Application.Helper.Export.Persistence (persistBackgroundPayrollExport)
import Application.Helper.Export.Render (payrollWorkbookFileName)
import Application.Helper.Export.Payloads (collapseVersionManifests)
import Application.Helper.Export.WorkbookGeneration
import Application.Helper.TimesheetSelection
import Application.Helper.WeekBoundaries (startOfWeekFor)
import Application.PayrollReports.Settings (withPayrollReportVenueLock, validatePayrollReportRecipients)
import Application.VenueTime.Model (storedInstantLocalTime)
import qualified Data.Aeson as Aeson
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import Data.Time.LocalTime (localDay)
import Generated.Types
import IHP.ControllerPrelude

validCompletedReportWeek :: Int -> Day -> Day -> Bool
validCompletedReportWeek startsOn today week = startOfWeekFor startsOn week == week && addDays 6 week < today

-- Caller supplies authority (scheduled configuration or authorised manual action).
-- All settings, entries, sealed facts, warnings and bytes share one transaction
-- snapshot; no browser context or mutable payroll recalculation is fabricated.
generatePayrollReportSnapshot :: (?modelContext :: ModelContext) =>
    Id Venue -> UUID -> PayrollReportOriginEnum -> Maybe UTCTime -> Day -> UTCTime -> IO (Either Text PayrollReportRun)
generatePayrollReportSnapshot venueId actorId origin scheduledAt week now =
    withTimesheetSelectionSnapshot (unpackId venueId) week end AllEligible fetchEntries \entries -> do
        settings <- query @PayrollReportSetting |> filterWhere (#venueId, unpackId venueId) |> fetchOneOrNothing
        config <- query @VenueConfig |> filterWhere (#venueId, unpackId venueId) |> fetchOneOrNothing
        case (settings, config) of
            (Just settings, Just config) -> case storedInstantLocalTime config.timezone now of
                Left _ -> pure (Left "The venue timezone is unavailable.")
                Right localNow
                    | not (validCompletedReportWeek config.rosterWeekStartsOn (localDay localNow) week) -> pure (Left "Choose a completed roster week.")
                    | origin == PayrollReportScheduled && (not settings.enabled || isNothing scheduledAt) -> pure (Left "The automatic schedule is disabled or unavailable.")
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
        generateWorkbookForVenue venueId config entries definition week end >>= \case
            Left _ -> pure (Left "Payroll report generation failed. Review approved payroll entries before trying again.")
            Right generated -> do
                export <- case generated of
                    Nothing -> pure Nothing
                    Just generated -> do
                        let contents = renderPayrollWorkbookBase64 generated.workbook
                        let manifests = List.sort (List.nub (Map.elems generated.manifests))
                        Just <$> persistBackgroundPayrollExport (unpackId venueId) actorId week end
                            (Aeson.object ["template" Aeson..= snapshot, "versionManifests" Aeson..= manifests, "entryCount" Aeson..= length generated.entries])
                            (payrollWorkbookFileName name week end) contents (collapseVersionManifests manifests) generated.entries
                Right <$> (newRecord @PayrollReportRun
                    |> set #venueId (unpackId venueId)
                    |> set #settingsId (unpackId settings.id)
                    |> set #exportJobId (unpackId . (.id) <$> export)
                    |> set #reportingWeek week
                    |> set #rangeEnd end
                    |> set #origin origin
                    |> set #status (if isNothing export then PayrollReportNoData else PayrollReportReady)
                    |> set #recipients settings.recipients
                    |> set #templateSnapshot snapshot
                    |> set #excludedEntryCount excluded
                    |> set #approvedEntryCount (maybe 0 (length . (.entries)) generated)
                    |> set #deliveryRevision settings.deliveryRevision
                    |> set #scheduleActivatedAt settings.scheduleActivatedAt
                    |> set #scheduledAt scheduledAt
                    |> set #requestedByUserId actorId
                    |> createRecord)
