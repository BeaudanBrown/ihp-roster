-- | Authorized frozen-run detail. No live evaluator, current definition or
-- current recipient list is allowed to substitute for the retained report.
module Application.Daysheet.ReportHistory
    ( FrozenReport (..), FrozenRecipient (..), FrozenHistory (..), readFrozenReport, readFrozenHistory
    ) where

import Application.Daysheet.Authority (DaysheetAccess, venueId, withAuthority)
import Application.Daysheet.EmailContract
import Application.Daysheet.Report (ReportContent)
import Application.Daysheet.ReportCodec (decodeReportContent)
import Application.Daysheet.ReportError
import Application.EmailDelivery.Enqueue (emailDeliveryJobKind)
import Application.EmailDelivery.Envelope
import Application.EmailDelivery.Status
import Application.Error.Domain (projectDomainError)
import Application.Error.Types
import Control.Monad.Trans.Except (throwE)
import qualified Data.Aeson as Aeson
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Generated.Types
import IHP.ControllerPrelude

data FrozenRecipient = FrozenRecipient
    { recipientId :: !(Id DaysheetReportRecipient)
    , address :: !Text
    , removed :: !Bool
    , delivery :: !DeliveryProgress
    }

data FrozenReport = FrozenReport
    { snapshotId :: !(Id DaysheetReportSnapshot)
    , daysheetId :: !(Id Daysheet)
    , reportId :: !UUID
    , operationalDate :: !Day
    , origin :: !DaysheetReportOrigin
    , capturedAt :: !UTCTime
    , cutoffAt :: !(Maybe UTCTime)
    , senderId :: !(Maybe (Id User))
    , senderAddress :: !(Maybe Text)
    , content :: !ReportContent
    , recipients :: ![FrozenRecipient]
    }

-- One immutable run at a time, with stable chronological neighbours. History
-- navigation never loads an unbounded list of retained report documents.
data FrozenHistory = FrozenHistory
    { venueId :: !UUID
    , daysheetId :: !(Id Daysheet)
    , operationalDate :: !Day
    , selected :: !(Maybe FrozenReport)
    , older :: !(Maybe (Id DaysheetReportSnapshot))
    , newer :: !(Maybe (Id DaysheetReportSnapshot))
    }

readFrozenHistory :: (?modelContext :: ModelContext) => DaysheetAccess -> Id Daysheet -> Maybe UUID -> IO (AppResult FrozenHistory)
readFrozenHistory member day requested = do
    navigation <- withAuthority member [Manager, VenueAdmin, VenueOwner] do
        source <- liftIO (query @Daysheet |> filterWhere (#id, day) |> filterWhere (#venueId, Id member.venueId) |> fetchOneOrNothing)
        record <- maybe unavailable pure source
        let scoped = query @DaysheetReportSnapshot |> filterWhere (#daysheetId, day) |> filterWhere (#venueId, Id member.venueId)
        snapshot <- liftIO (case requested of
            Nothing -> scoped |> orderByDesc #capturedAt |> orderByDesc #id |> fetchOneOrNothing
            Just key -> scoped |> filterWhere (#id, Id key) |> fetchOneOrNothing)
        when (isJust requested && isNothing snapshot) unavailable
        (older, newer) <- case snapshot of
            Nothing -> pure (Nothing, Nothing)
            Just value -> liftIO do
                older <- scoped |> queryOr (filterWhereLessThan (#capturedAt, value.capturedAt))
                    (filterWhere (#capturedAt, value.capturedAt) . filterWhereLessThan (#id, value.id))
                    |> orderByDesc #capturedAt |> orderByDesc #id |> fetchOneOrNothing
                newer <- scoped |> queryOr (filterWhereGreaterThan (#capturedAt, value.capturedAt))
                    (filterWhere (#capturedAt, value.capturedAt) . filterWhereGreaterThan (#id, value.id))
                    |> orderByAsc #capturedAt |> orderByAsc #id |> fetchOneOrNothing
                pure ((.id) <$> older, (.id) <$> newer)
        pure (record.operationalDate, (.id) <$> snapshot, older, newer)
    case navigation of
        Left failure -> pure (Left failure)
        Right (date, Nothing, older, newer) -> pure (Right (FrozenHistory member.venueId day date Nothing older newer))
        Right (date, Just key, older, newer) -> do
            detail <- readFrozenReport member key
            pure ((\value -> FrozenHistory member.venueId day date (Just value) older newer) <$> detail)
  where
    unavailable = throwE (projectDomainError ReportHistoryUnavailable)

readFrozenReport :: (?modelContext :: ModelContext) => DaysheetAccess -> Id DaysheetReportSnapshot -> IO (AppResult FrozenReport)
readFrozenReport member key = withAuthority member [Manager, VenueAdmin, VenueOwner] do
    stored <- liftIO (query @DaysheetReportSnapshot |> filterWhere (#id, key)
        |> filterWhere (#venueId, Id member.venueId) |> fetchOneOrNothing)
    snapshot <- maybe (throwE (projectDomainError ReportHistoryUnavailable)) pure stored
    content <- either (const invalid) pure (decodeReportContent snapshot.content)
    ids <- case Aeson.fromJSON snapshot.recipientIds of
        Aeson.Success values -> pure (values :: [UUID])
        Aeson.Error _ -> invalid
    unless (length ids <= 10000 && Set.size (Set.fromList ids) == length ids) invalid
    captured <- liftIO (query @DaysheetDefinitionCapture |> filterWhere (#id, snapshot.definitionCaptureId)
        |> filterWhere (#venueId, member.venueId) |> fetchOneOrNothing)
    meaning <- maybe invalid pure captured
    people <- liftIO (query @DaysheetReportRecipient |> filterWhereIn (#id, map Id ids)
        |> filterWhere (#venueId, member.venueId) |> filterWhere (#reportId, snapshot.reportId) |> fetch)
    unless (length people == length ids) invalid
    jobs <- liftIO (query @AppJob |> filterWhere (#jobKind, emailDeliveryJobKind)
        |> filterWhere (#venueId, Just member.venueId) |> filterWhere (#relatedTable, Just daysheetReportReferenceTable)
        |> filterWhere (#relatedId, Just (unpackId snapshot.id)) |> filterWhere (#payloadSchemaVersion, 2) |> fetch)
    let peopleById = Map.fromList [(unpackId person.id, person) | person <- people]
    let validJobs = [(identity.externalRecipientId, job) | job <- jobs
            , Aeson.Success payload <- [Aeson.fromJSON @ExternalEmailPayload job.payload]
            , let identity = payload.externalRecipient
            , payload.externalMailKind == daysheetReportMailKind
            , payload.externalDomainReferenceId == unpackId snapshot.id
            , identity.externalVenueId == member.venueId && identity.externalReportId == snapshot.reportId
            , Just person <- [Map.lookup identity.externalRecipientId peopleById]
            , payload.externalRecipientAddress == person.address]
    states <- liftIO (query @EmailDeliveryProviderState
        |> filterWhereIn (#emailDeliveryJobId, [Id (unpackId job.id) | (_, job) <- validJobs]) |> fetch)
    let statesByJob = Map.fromList [(unpackId state.emailDeliveryJobId, state) | state <- states]
    let jobsByRecipient = Map.fromListWith (<>) [(recipient, [job]) | (recipient, job) <- validJobs]
    let recipient person = FrozenRecipient person.id person.address (isJust person.removedAt)
            ((if isJust person.removedAt then cancelPendingDelivery else (\value -> value))
                (case Map.lookup (unpackId person.id) jobsByRecipient of
                    Just [job] -> deliveryProgress job (Map.lookup (unpackId job.id) statesByJob)
                    _ -> unavailableDelivery))
    sender <- liftIO (case snapshot.senderId of
        Nothing -> pure Nothing
        Just senderKey -> query @User |> filterWhere (#id, senderKey) |> fetchOneOrNothing)
    pure FrozenReport
        { snapshotId = snapshot.id, daysheetId = snapshot.daysheetId, reportId = snapshot.reportId
        , operationalDate = meaning.operationalDate, origin = snapshot.origin
        , capturedAt = snapshot.capturedAt, cutoffAt = snapshot.cutoffAt, senderId = snapshot.senderId
        , senderAddress = (.email) <$> sender, content
        , recipients = [recipient person | key <- ids, Just person <- [Map.lookup key peopleById]]
        }
  where
    invalid = throwE (projectDomainError ReportHistoryInvalid)
