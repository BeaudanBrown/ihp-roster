module Application.PayrollReports.Settings
    ( PayrollReportSettingsInput (..)
    , PayrollReportSettingsError (..)
    , validatePayrollReportRecipients
    , fetchPayrollReportSettings
    , savePayrollReportSettings
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
        cancelPendingPayrollReports venueId False

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
    forM_ (filter (\run -> run.origin == PayrollReportScheduled || (includeManual && isJust run.settingsId)) pending) \run -> do
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
