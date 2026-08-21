module Application.WageSourceNotifications
    ( emitLatestAwardDriftNotifications
    ) where

import Application.EmailDelivery
import Application.WageSourceNotification.Email (awardDriftMailKind)
import Application.WageSourceNotification.Fingerprint
import Application.WageSourcePolicy
import Generated.Types
import IHP.ControllerPrelude


emitLatestAwardDriftNotifications :: (?modelContext :: ModelContext) => IO [AppJob]
emitLatestAwardDriftNotifications = do
    snapshots <- loadLatestAwardFingerprintSnapshots
    case snapshots of
        current : previous : _ -> do
            recipients <-
                query @User
                    |> filterWhere (#platformRole, Just SuperAdmin)
                    |> filterWhere (#deactivatedAt, Nothing)
                    |> orderByAsc #id
                    |> fetch
            concat <$> mapM (enqueueSignal current recipients) (detectAwardDrift previous.fingerprint current.fingerprint)
        _ -> pure []
  where
    enqueueSignal current recipients signal =
        forM recipients \recipient ->
            enqueueEmailDelivery
                EmailDeliveryRequest
                    { mailKind = awardDriftMailKind signal.kind
                    , recipientAccountId = unpackId recipient.id
                    , recipientAddress = recipient.email
                    , domainReferenceTable = "fwc_mapd_awards"
                    , domainReferenceId = unpackId current.referenceAward.id
                    , semanticEventKey = signal.dedupeKey
                    , requestedByUserId = Nothing
                    , venueId = Nothing
                    }
