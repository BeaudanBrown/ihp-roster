module Application.PayrollReports.Selection
    ( ManualReportSelection (..)
    , SelectedPayrollReport (..)
    , loadSelectedPayrollReport
    , selectedReportConfirmation
    , manualReportSelectionIsCurrent
    , validCompletedReportWeek
    , isCompletedPayrollReportWeek
    , payrollReportAlreadyPrepared
    ) where

import Application.Helper.Export.PayrollWorkbookConfiguration
import Application.Helper.WeekBoundaries (startOfWeekFor)
import Application.VenueTime.Model (storedInstantLocalTime)
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.KeyMap as KeyMap
import Generated.Types
import IHP.ControllerPrelude

-- Confirmation facts, not recipient addresses. A group edit before acceptance
-- requires review again; after preparation the run itself owns the addresses.
data ManualReportSelection = ManualReportSelection
    { configurationId :: !UUID
    , configurationRevision :: !Int
    , recipientGroupId :: !UUID
    , recipientGroupRevision :: !Int
    , rosterWeekStartsOn :: !Int
    , timezone :: !Text
    , repeatSendConfirmed :: !Bool
    }

data SelectedPayrollReport = SelectedPayrollReport
    { config :: !VenueConfig
    , template :: !SavedPayrollWorkbookConfiguration
    , group :: !RecipientGroup
    }

-- Caller owns venue business/support authority; all request IDs are scoped here.
loadSelectedPayrollReport :: (?modelContext :: ModelContext) => Id Venue -> UUID -> UUID -> IO (Either Text SelectedPayrollReport)
loadSelectedPayrollReport venueId configurationId groupId = do
    config <- query @VenueConfig |> filterWhere (#venueId, unpackId venueId) |> fetchOneOrNothing
    group <- query @RecipientGroup |> filterWhere (#id, Id groupId)
        |> filterWhere (#venueId, unpackId venueId) |> filterWhere (#archivedAt, Nothing) |> fetchOneOrNothing
    template <- fetchSavedPayrollWorkbookConfigurationForVenue venueId (Id configurationId)
    pure case (config, template, group) of
        (Just config, Right template, Just group) -> Right SelectedPayrollReport { config, template, group }
        _ -> Left "The selected export template or recipient group is unavailable."

selectedReportConfirmation :: SelectedPayrollReport -> ManualReportSelection
selectedReportConfirmation selected = ManualReportSelection
    { configurationId = unpackId selected.template.savedPayrollWorkbookConfigurationRecord.id
    , configurationRevision = selected.template.savedPayrollWorkbookConfigurationRecord.revision
    , recipientGroupId = unpackId selected.group.id
    , recipientGroupRevision = selected.group.revision
    , rosterWeekStartsOn = selected.config.rosterWeekStartsOn
    , timezone = selected.config.timezone
    , repeatSendConfirmed = False
    }

manualReportSelectionIsCurrent :: ManualReportSelection -> SelectedPayrollReport -> Bool
manualReportSelectionIsCurrent selection selected =
    selection.configurationId == unpackId selected.template.savedPayrollWorkbookConfigurationRecord.id
        && selection.configurationRevision == selected.template.savedPayrollWorkbookConfigurationRecord.revision
        && selection.recipientGroupId == unpackId selected.group.id
        && selection.recipientGroupRevision == selected.group.revision
        && selection.rosterWeekStartsOn == selected.config.rosterWeekStartsOn
        && selection.timezone == selected.config.timezone

validCompletedReportWeek :: Int -> Day -> Day -> Bool
validCompletedReportWeek startsOn today week = startOfWeekFor startsOn week == week && addDays 6 week < today

isCompletedPayrollReportWeek :: VenueConfig -> UTCTime -> Day -> Bool
isCompletedPayrollReportWeek config now week = case storedInstantLocalTime config.timezone now of
    Left _ -> False
    Right localNow -> validCompletedReportWeek config.rosterWeekStartsOn (localDay localNow) week

-- Prepared/queued/uncertain/accepted are warning-worthy; this is never a claim
-- of inbox delivery. Failed-before-send, cancelled, missed and disabled are not.
-- Legacy identity comes from its immutable definition key, NEVER current settings.
payrollReportAlreadyPrepared :: (?modelContext :: ModelContext) => Id Venue -> UUID -> Day -> IO Bool
payrollReportAlreadyPrepared venueId configurationId week = do
    let candidates = query @PayrollReportRun |> filterWhere (#venueId, unpackId venueId)
            |> filterWhere (#reportingWeek, week)
            |> filterWhereIn (#status, [PayrollReportReady, PayrollReportNoData, PayrollReportQueued, PayrollReportAccepted, PayrollReportBounced, PayrollReportAmbiguous])
    current <- candidates |> filterWhere (#configurationId, Just configurationId) |> fetchExists
    if current then pure True else do
        legacy <- candidates |> filterWhere (#configurationId, Nothing) |> fetch
        pure (any matchesLegacy legacy)
  where
    matchesLegacy run = case run.templateSnapshot of
        Aeson.Object value -> KeyMap.lookup "definitionKey" value == Just (Aeson.String ("saved-" <> tshow configurationId))
        _ -> False
