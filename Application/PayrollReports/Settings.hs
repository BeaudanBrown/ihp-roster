module Application.PayrollReports.Settings
    ( PayrollReportSettingsInput (..)
    , PayrollReportSettingsError (..)
    , validatePayrollReportRecipients
    , fetchPayrollReportSettings
    , savePayrollReportSettings
    , withPayrollReportVenueLock
    , clearPayrollReportTemplateInCurrentTransaction
    , disablePayrollReportsForCalendarChange
    , payrollReportRunIsCurrent
    ) where

import Application.Helper.ControllerAccess (hasRole)
import Application.Helper.ControllerContext (authenticatedCurrentUser, currentVenueId, currentVenueOrNothing)
import Control.Monad (void)
import qualified Data.List as List
import qualified Data.Text as Text
import Generated.Types
import IHP.ControllerPrelude

-- Do not derive Show: settings contain private external recipient addresses.
data PayrollReportSettingsInput = PayrollReportSettingsInput
    { recipients :: ![Text]
    , configurationId :: !(Maybe UUID)
    , enabled :: !Bool
    , minuteOfDay :: !Int
    , expectedRevision :: !(Maybe Int)
    }

data PayrollReportSettingsError
    = PayrollReportAccessDenied
    | PayrollReportInvalidSettings !Text
    | PayrollReportStaleSettings
    | PayrollReportTemplateUnavailable
    deriving (Eq, Show)

validatePayrollReportRecipients :: [Text] -> Either PayrollReportSettingsError [Text]
validatePayrollReportRecipients values
    | length values > 50 = invalid "Use at most 50 recipients."
    | any invalidAddress normalized = invalid "Enter valid email addresses without display names."
    | otherwise = Right (List.nub normalized)
  where
    normalized = map (Text.toLower . Text.strip) values
    invalid message = Left (PayrollReportInvalidSettings message)
    invalidAddress address = Text.null address || Text.length address > 254
        || Text.any (`elem` ['\r', '\n', ',', ';', '<', '>']) address
        || case isEmail address of
            Success -> False
            Failure _ -> True
            FailureHtml _ -> True

canManage :: (?context :: ControllerContext) => Bool
canManage = isJust currentVenueOrNothing && hasRole VenueAdmin

fetchPayrollReportSettings :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO (Either PayrollReportSettingsError (Maybe PayrollReportSetting))
fetchPayrollReportSettings
    | not canManage = pure (Left PayrollReportAccessDenied)
    | otherwise = Right <$> (query @PayrollReportSetting |> filterWhere (#venueId, unpackId currentVenueId) |> fetchOneOrNothing)

-- A venue row exists before the first settings row. Serialising on it also makes
-- first-save races and template deletion atomic without unsafe business SQL.
withPayrollReportVenueLock :: (?modelContext :: ModelContext) => UUID -> IO ()
withPayrollReportVenueLock venueId = do
    _ :: [Only UUID] <- unsafeSqlQuery "SELECT id FROM venues WHERE id = ? FOR UPDATE" (Only venueId)
    pure ()

savePayrollReportSettings :: (?context :: ControllerContext, ?modelContext :: ModelContext) => PayrollReportSettingsInput -> IO (Either PayrollReportSettingsError PayrollReportSetting)
savePayrollReportSettings input
    | not canManage = pure (Left PayrollReportAccessDenied)
    | input.minuteOfDay < 0 || input.minuteOfDay >= 1440 =
        pure (Left (PayrollReportInvalidSettings "Choose a valid time."))
    | otherwise = case validatePayrollReportRecipients input.recipients of
        Left failure -> pure (Left failure)
        Right addresses
            | input.enabled && (null addresses || isNothing input.configurationId) ->
                pure (Left (PayrollReportInvalidSettings "Choose a template and at least one recipient before enabling."))
            | otherwise -> withTransaction do
                withPayrollReportVenueLock (unpackId currentVenueId)
                config <- query @VenueConfig |> filterWhere (#venueId, unpackId currentVenueId) |> fetchOne
                existing <- query @PayrollReportSetting |> filterWhere (#venueId, unpackId currentVenueId) |> fetchOneOrNothing
                templateValid <- case input.configurationId of
                    Nothing -> pure True
                    Just configurationId -> query @PayrollWorkbookConfiguration
                        |> filterWhere (#id, Id configurationId)
                        |> filterWhere (#venueId, unpackId currentVenueId)
                        |> fetchExists
                let recipientsChanged = maybe (not (null addresses)) ((/= addresses) . (.recipients)) existing
                if fmap (.revision) existing /= input.expectedRevision then pure (Left PayrollReportStaleSettings)
                else if not templateValid then pure (Left PayrollReportTemplateUnavailable)
                else do
                    now <- getCurrentTime
                    let record = fromMaybe (newRecord @PayrollReportSetting |> set #venueId (unpackId currentVenueId)) existing
                    let templateChanged = record.configurationId /= input.configurationId
                    let scheduleChanged = record.enabled /= input.enabled || record.weekday /= config.rosterWeekStartsOn || record.minuteOfDay /= input.minuteOfDay
                    let updated = record
                            |> set #configurationId input.configurationId
                            |> set #recipients addresses
                            |> set #enabled input.enabled
                            |> set #weekday config.rosterWeekStartsOn
                            |> set #minuteOfDay input.minuteOfDay
                            |> set #revision (maybe 0 ((+ 1) . (.revision)) existing)
                            |> set #deliveryRevision (record.deliveryRevision + if recipientsChanged || templateChanged then 1 else 0)
                            |> set #scheduleActivatedAt (if isNothing existing || scheduleChanged || recipientsChanged || templateChanged then now else record.scheduleActivatedAt)
                            |> set #updatedByUserId (unpackId authenticatedCurrentUser.id)
                            |> set #updatedAt now
                    saved <- if isNothing existing then createRecord updated else updateRecord updated
                    when (recipientsChanged || templateChanged || scheduleChanged) $
                        cancelPendingPayrollReports (unpackId currentVenueId) (recipientsChanged || templateChanged)
                    pure (Right saved)

-- Caller owns the transaction and venue lock. Clearing the template revokes
-- pending recipient snapshots through deliveryRevision, preserving timing/list.
clearPayrollReportTemplateInCurrentTransaction :: (?modelContext :: ModelContext) => UUID -> UUID -> UUID -> IO ()
clearPayrollReportTemplateInCurrentTransaction venueId configurationId actorId = do
    settings <- query @PayrollReportSetting
        |> filterWhere (#venueId, venueId)
        |> filterWhere (#configurationId, Just configurationId)
        |> fetchOneOrNothing
    forM_ settings \record -> do
        now <- getCurrentTime
        record
            |> set #configurationId Nothing
            |> set #enabled False
            |> set #revision (record.revision + 1)
            |> set #deliveryRevision (record.deliveryRevision + 1)
            |> set #scheduleActivatedAt now
            |> set #updatedByUserId actorId
            |> set #updatedAt now
            |> updateRecord
            |> void
        cancelPendingPayrollReports venueId True

-- Caller holds the roster calendar transaction; acquire the venue lock before
-- changing the calendar so report snapshots cannot cross that boundary.
disablePayrollReportsForCalendarChange :: (?modelContext :: ModelContext) => UUID -> IO ()
disablePayrollReportsForCalendarChange venueId = do
    withPayrollReportVenueLock venueId
    settings <- query @PayrollReportSetting |> filterWhere (#venueId, venueId) |> fetchOneOrNothing
    forM_ settings \record -> do
        now <- getCurrentTime
        record |> set #enabled False |> set #revision (record.revision + 1)
            |> set #scheduleActivatedAt now |> set #updatedAt now |> updateRecord |> void
    cancelPendingPayrollReports venueId False

cancelPendingPayrollReports :: (?modelContext :: ModelContext) => UUID -> Bool -> IO ()
cancelPendingPayrollReports venueId includeManual = do
    pending <- query @PayrollReportRun |> filterWhere (#venueId, venueId)
        |> filterWhereIn (#status, [PayrollReportReady, PayrollReportNoData, PayrollReportQueued]) |> fetch
    forM_ (filter (\run -> includeManual || run.origin == PayrollReportScheduled) pending) \run -> do
        now <- getCurrentTime
        run |> set #status PayrollReportCancelled |> set #updatedAt now |> updateRecord |> void

payrollReportRunIsCurrent :: PayrollReportSetting -> PayrollReportRun -> Bool
payrollReportRunIsCurrent settings run =
    settings.venueId == run.venueId && unpackId settings.id == run.settingsId
        && settings.deliveryRevision == run.deliveryRevision
        && (run.origin /= PayrollReportScheduled || (settings.enabled && settings.scheduleActivatedAt == run.scheduleActivatedAt))
