module Application.PayrollReports.Settings
    ( PayrollReportSettingsInput (..)
    , PayrollReportSettingsError (..)
    , validatePayrollReportRecipients
    , fetchPayrollReportSettings
    , savePayrollReportSettings
    , savePayrollReportSettingsInCurrentTransaction
    , withPayrollReportVenueLock
    , clearPayrollReportTemplateInCurrentTransaction
    , clearPayrollReportRecipientGroupInCurrentTransaction
    , disablePayrollReportsForCalendarChange
    , payrollReportRunIsCurrent
    ) where

import Application.Helper.ControllerAccess (hasRole)
import Application.Helper.ControllerContext (authenticatedCurrentUser, currentVenueId, currentVenueOrNothing)
import Application.RecipientGroups.Validation (validateRecipientAddresses)
import Control.Monad (void)
import Generated.Types
import IHP.ControllerPrelude

-- Do not derive Show: settings contain private external recipient addresses.
data PayrollReportSettingsInput = PayrollReportSettingsInput
    { configurationId :: !(Maybe UUID)
    , recipientGroupId :: !(Maybe UUID)
    , enabled :: !Bool
    , expectedRevision :: !(Maybe Int)
    }

data PayrollReportSettingsError
    = PayrollReportAccessDenied
    | PayrollReportInvalidSettings !Text
    | PayrollReportStaleSettings
    | PayrollReportTemplateUnavailable
    | PayrollReportRecipientGroupUnavailable
    deriving (Eq, Show)

validatePayrollReportRecipients :: [Text] -> Either PayrollReportSettingsError [Text]
validatePayrollReportRecipients = either (Left . PayrollReportInvalidSettings) Right . validateRecipientAddresses

canManage :: (?context :: ControllerContext) => Bool
canManage = isJust currentVenueOrNothing && hasRole VenueAdmin

fetchPayrollReportSettings :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO (Either PayrollReportSettingsError (Maybe PayrollReportSetting))
fetchPayrollReportSettings
    | not canManage = pure (Left PayrollReportAccessDenied)
    | otherwise = Right <$> (query @PayrollReportSetting |> filterWhere (#venueId, unpackId currentVenueId) |> fetchOneOrNothing)

-- A venue row exists before the first settings row. Touching its row version
-- makes a waiting REPEATABLE READ preparation fail/retry with a fresh snapshot:
-- SELECT FOR UPDATE alone would leave it reading pre-lock group/repeat facts.
-- No business field changes. Every group/settings/preparation mutation uses this
-- same fence before other locks; generation retries SQLSTATE 40001.
withPayrollReportVenueLock :: (?modelContext :: ModelContext) => UUID -> IO ()
withPayrollReportVenueLock venueId = do
    _ :: [Only UUID] <- unsafeSqlQuery "UPDATE venues SET id = id WHERE id = ? RETURNING id" (Only venueId)
    pure ()

savePayrollReportSettings :: (?context :: ControllerContext, ?modelContext :: ModelContext) => PayrollReportSettingsInput -> IO (Either PayrollReportSettingsError PayrollReportSetting)
savePayrollReportSettings input = withTransaction (savePayrollReportSettingsInCurrentTransaction input)

-- Caller owns the transaction so settings and durable UI invalidation commit together.
savePayrollReportSettingsInCurrentTransaction :: (?context :: ControllerContext, ?modelContext :: ModelContext) => PayrollReportSettingsInput -> IO (Either PayrollReportSettingsError PayrollReportSetting)
savePayrollReportSettingsInCurrentTransaction input
    | not canManage = pure (Left PayrollReportAccessDenied)
    | otherwise = do
        withPayrollReportVenueLock (unpackId currentVenueId)
        config <- query @VenueConfig |> filterWhere (#venueId, unpackId currentVenueId) |> fetchOne
        existing <- query @PayrollReportSetting |> filterWhere (#venueId, unpackId currentVenueId) |> fetchOneOrNothing
        if fmap (.revision) existing /= input.expectedRevision then pure (Left PayrollReportStaleSettings)
        else do
            let record = fromMaybe (newRecord @PayrollReportSetting |> set #venueId (unpackId currentVenueId) |> set #minuteOfDay 360) existing
            -- Disabled HTML controls are omitted. Preserve saved selections;
            -- neither omission nor a tampered disabled request may erase them.
            let selectedTemplate = if input.enabled then input.configurationId else record.configurationId
            let selectedGroup = if input.enabled then input.recipientGroupId else record.recipientGroupId
            templateValid <- case selectedTemplate of
                Nothing -> pure False
                Just identifier -> query @PayrollWorkbookConfiguration
                    |> filterWhere (#id, Id identifier) |> filterWhere (#venueId, unpackId currentVenueId) |> fetchExists
            group <- case selectedGroup of
                Nothing -> pure Nothing
                Just identifier -> query @RecipientGroup
                    |> filterWhere (#id, Id identifier) |> filterWhere (#venueId, unpackId currentVenueId)
                    |> filterWhere (#archivedAt, Nothing) |> fetchOneOrNothing
            if input.enabled && not templateValid then pure (Left PayrollReportTemplateUnavailable)
            else if input.enabled && isNothing group then pure (Left PayrollReportRecipientGroupUnavailable)
            else do
                -- Legacy settings retain their old list/time for compatibility;
                -- enabled group-backed settings mirror the chosen group's list
                -- only for the existing database constraint. Preparation resolves
                -- the current group under this same venue fence.
                let addresses = if input.enabled then maybe [] (.recipients) group else record.recipients
                case if input.enabled then validatePayrollReportRecipients addresses else Right addresses of
                    Left failure -> pure (Left failure)
                    Right addresses -> do
                        now <- getCurrentTime
                        let changed = record.enabled /= input.enabled || record.weekday /= config.rosterWeekStartsOn
                                || record.configurationId /= selectedTemplate || record.recipientGroupId /= selectedGroup
                        let updated = record
                                |> set #configurationId selectedTemplate |> set #recipientGroupId selectedGroup
                                |> set #recipients addresses |> set #enabled input.enabled
                                |> set #weekday config.rosterWeekStartsOn
                                |> set #revision (maybe 0 ((+ 1) . (.revision)) existing)
                                |> set #scheduleActivatedAt (if isNothing existing || changed then now else record.scheduleActivatedAt)
                                |> set #updatedByUserId (unpackId authenticatedCurrentUser.id) |> set #updatedAt now
                        saved <- if isNothing existing then createRecord updated else updateRecord updated
                        when changed (cancelPendingPayrollReports (unpackId currentVenueId))
                        pure (Right saved)

-- Caller owns the transaction and venue lock. Template removal disables future
-- automation; prepared explicit snapshots retain their accepted recipients/bytes.
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
            |> set #scheduleActivatedAt now
            |> set #updatedByUserId actorId
            |> set #updatedAt now
            |> updateRecord
            |> void
        cancelPendingPayrollReports venueId

-- Group deletion is explicit schedule disablement, not recipient revocation.
-- Caller owns the transaction and venue lock, and has confirmed the impact.
-- Keep deliveryRevision unchanged so prepared manual snapshots remain valid.
clearPayrollReportRecipientGroupInCurrentTransaction :: (?modelContext :: ModelContext) => UUID -> UUID -> UUID -> IO ()
clearPayrollReportRecipientGroupInCurrentTransaction venueId groupId actorId = do
    settings <- query @PayrollReportSetting
        |> filterWhere (#venueId, venueId)
        |> filterWhere (#recipientGroupId, Just groupId)
        |> fetchOneOrNothing
    forM_ settings \record -> do
        now <- getCurrentTime
        record |> set #recipientGroupId Nothing |> set #enabled False
            |> set #revision (record.revision + 1)
            |> set #scheduleActivatedAt now |> set #updatedAt now
            |> set #updatedByUserId actorId |> updateRecord |> void
        cancelPendingPayrollReports venueId

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
    cancelPendingPayrollReports venueId

cancelPendingPayrollReports :: (?modelContext :: ModelContext) => UUID -> IO ()
cancelPendingPayrollReports venueId = do
    pending <- query @PayrollReportRun |> filterWhere (#venueId, venueId)
        |> filterWhereIn (#status, [PayrollReportReady, PayrollReportNoData, PayrollReportQueued]) |> fetch
    forM_ (filter (\run -> run.origin == PayrollReportScheduled) pending) \run -> do
        now <- getCurrentTime
        run |> set #status PayrollReportCancelled |> set #updatedAt now |> updateRecord |> void

payrollReportRunIsCurrent :: Maybe PayrollReportSetting -> PayrollReportRun -> Bool
payrollReportRunIsCurrent settings run = case run.settingsId of
    Nothing -> run.origin == PayrollReportManual && isJust run.configurationId
        && isJust run.recipientGroupId && isJust run.recipientGroupRevision
    Just settingId -> case settings of
        Nothing -> False
        Just settings -> settings.venueId == run.venueId && unpackId settings.id == settingId
            && settings.deliveryRevision == run.deliveryRevision
            && (run.origin /= PayrollReportScheduled || (settings.enabled && settings.scheduleActivatedAt == run.scheduleActivatedAt))
