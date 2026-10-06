-- | Authorized frozen-run detail. No live evaluator, current definition or
-- current recipient list is allowed to substitute for the retained report.
module Application.Daysheet.ReportHistory
    ( FrozenReport (..), FrozenRecipient (..), readFrozenReport
    ) where

import Application.Daysheet.Authority (withAuthority)
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

readFrozenReport :: (?modelContext :: ModelContext) => VenueMembership -> Id DaysheetReportSnapshot -> IO (AppResult FrozenReport)
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
