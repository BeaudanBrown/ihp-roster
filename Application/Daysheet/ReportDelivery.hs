-- | The shared transport calls this resolver while holding recipient eligibility.
-- It reads immutable selected results, never the live Daysheet or evaluator.
module Application.Daysheet.ReportDelivery (resolveFrozenReport) where

import Application.Async.Boundary (throwAppJobError)
import Application.Async.Error (AppJobError (..))
import Application.Daysheet.EmailContract (daysheetReportMailKind)
import Application.Daysheet.ReportCodec (decodeReportContent)
import Application.EmailDelivery.Envelope
import qualified Data.Aeson as Aeson
import Generated.Types
import IHP.ControllerPrelude
import Web.Mail.DaysheetReport

resolveFrozenReport :: (?modelContext :: ModelContext) => ExternalEmailPayload -> IO (Maybe ReportMailContent)
resolveFrozenReport payload
    | payload.externalMailKind /= daysheetReportMailKind = pure Nothing
    | otherwise = do
        let identity = payload.externalRecipient
        stored <- query @DaysheetReportSnapshot
            |> filterWhere (#id, Id payload.externalDomainReferenceId)
            |> filterWhere (#venueId, Id identity.externalVenueId)
            |> filterWhere (#reportId, identity.externalReportId) |> fetchOneOrNothing
        case stored of
            Nothing -> pure Nothing
            Just snapshot -> do
                recipients <- case Aeson.fromJSON snapshot.recipientIds of
                    Aeson.Success (keys :: [UUID]) -> pure keys
                    Aeson.Error _ -> throwAppJobError JobMalformedPersistedPayload
                if identity.externalRecipientId `notElem` recipients then pure Nothing else do
                    recipient <- query @DaysheetReportRecipient
                        |> filterWhere (#id, Id identity.externalRecipientId)
                        |> filterWhere (#venueId, identity.externalVenueId)
                        |> filterWhere (#reportId, identity.externalReportId)
                        |> filterWhere (#address, payload.externalRecipientAddress)
                        |> filterWhere (#removedAt, Nothing) |> fetchOneOrNothing
                    captured <- query @DaysheetDefinitionCapture
                        |> filterWhere (#id, snapshot.definitionCaptureId)
                        |> filterWhere (#venueId, identity.externalVenueId) |> fetchOneOrNothing
                    case (recipient, captured) of
                        (Just _, Just meaning) -> do
                            selected <- either (const (throwAppJobError JobMalformedPersistedPayload)) pure (decodeReportContent snapshot.content)
                            pure (Just (frozenReportMailContent
                                FrozenReportIdentity { operationalDate = meaning.operationalDate, capturedAt = snapshot.capturedAt, cutoffAt = snapshot.cutoffAt }
                                selected))
                        _ -> pure Nothing
