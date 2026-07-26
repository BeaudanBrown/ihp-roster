module Application.WageSourceNotifications
    ( emitLatestAwardDriftNotifications
    , performWageSourceDriftNotificationJob
    , wageSourceDriftNotificationJobKind
    ) where

import Application.Async.Queue
import Application.Helper.Controller (PlatformRole (SuperAdminRole), platformRoleToEnum)
import Application.Helper.EmailVerification (isEmailDeliveryDisabled)
import Application.Helper.Mail
import Application.WageSourcePolicy
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import qualified Data.List as List
import qualified Data.Set as Set
import qualified Data.Text as Text
import Generated.Types
import IHP.ControllerPrelude
import IHP.FrameworkConfig (ConfigProvider, FrameworkConfig)
import IHP.Job.Types (JobStatus (JobStatusSucceeded))
import IHP.Mail
import Web.Mail.WageSourceDrift

wageSourceDriftNotificationJobKind :: Text
wageSourceDriftNotificationJobKind = "wage_source_award_drift_notification"

data DriftPayload = DriftPayload
    { payloadUserId       :: !UUID
    , payloadKind         :: !Text
    , payloadExpected     :: !Text
    , payloadObserved     :: !Text
    , payloadDedupeKey    :: !Text
    }

instance Aeson.FromJSON DriftPayload where
    parseJSON = Aeson.withObject "Wage source drift notification" \object ->
        DriftPayload
            <$> object Aeson..: "userId"
            <*> object Aeson..: "kind"
            <*> object Aeson..: "expectedValue"
            <*> object Aeson..: "observedValue"
            <*> object Aeson..: "driftDedupeKey"

emitLatestAwardDriftNotifications :: (?modelContext :: ModelContext) => IO [AppJob]
emitLatestAwardDriftNotifications = do
    fingerprints <- loadLatestAwardFingerprints
    case fingerprints of
        current : previous : _ -> do
            recipients <- query @User
                |> filterWhere (#platformRole, Just (platformRoleToEnum SuperAdminRole))
                |> filterWhere (#deactivatedAt, Nothing)
                |> fetch
            concat <$> mapM (enqueueSignal recipients) (detectAwardDrift previous current)
        _ -> pure []
  where
    enqueueSignal recipients signal = mapM (enqueueRecipient signal) recipients

    enqueueRecipient signal recipient = do
        let permanentKey = signal.dedupeKey <> ":" <> inputValue recipient.id
        existing <- query @AppJob
            |> filterWhere (#dedupeKey, Just permanentKey)
            |> orderByAsc #createdAt
            |> fetchOneOrNothing
        case existing of
            Just appJob -> pure appJob
            Nothing -> do
                result <- enqueueAppJob AppJobRequest
                    { jobKind = wageSourceDriftNotificationJobKind
                    , payload = Aeson.object
                        [ "userId" Aeson..= unpackId recipient.id
                        , "kind" Aeson..= tshow signal.kind
                        , "expectedValue" Aeson..= signal.expectedValue
                        , "observedValue" Aeson..= signal.observedValue
                        , "driftDedupeKey" Aeson..= signal.dedupeKey
                        ]
                    , payloadSchemaVersion = 1
                    , requestedByUserId = Nothing
                    , venueId = Nothing
                    , relatedTable = Nothing
                    , relatedId = Nothing
                    , dedupeKey = Just permanentKey
                    , runAt = Nothing
                    }
                pure $ case result of
                    EnqueuedAppJob appJob       -> appJob
                    ExistingActiveAppJob appJob -> appJob

loadLatestAwardFingerprints :: (?modelContext :: ModelContext) => IO [AwardFingerprint]
loadLatestAwardFingerprints = do
    awards <- query @FwcMapdAward
        |> filterWhere (#code, "MA000009" :: Text)
        |> orderByDesc #syncedAt
        |> fetch
    let snapshotTimes = List.nub (map (.syncedAt) awards)
    mapM fingerprintAt (take 2 snapshotTimes)
  where
    fingerprintAt syncedAt = do
        award <- query @FwcMapdAward
            |> filterWhere (#code, "MA000009" :: Text)
            |> filterWhere (#syncedAt, syncedAt)
            |> fetchOne
        classifications <- query @FwcMapdClassification
            |> filterWhere (#awardFixedId, award.awardFixedId)
            |> filterWhere (#syncedAt, syncedAt)
            |> fetch
        penalties <- query @FwcMapdPenaltyRate
            |> filterWhere (#awardFixedId, award.awardFixedId)
            |> filterWhere (#syncedAt, syncedAt)
            |> fetch
        allowances <- query @FwcMapdWageAllowance
            |> filterWhere (#awardFixedId, award.awardFixedId)
            |> filterWhere (#syncedAt, syncedAt)
            |> fetch
        pure AwardFingerprint
            { documentChecksum = tshow award.rawJson
            , documentVersion = tshow award.publishedYear <> ":" <> tshow award.versionNumber
            , classificationKeys = Set.fromList
                [ tshow row.classificationFixedId <> ":" <> Text.strip row.classification
                | row <- classifications
                ]
            , categoryKeys = Set.fromList
                ( [ "penalty:" <> maybe "unknown" tshow row.penaltyFixedId <> ":" <> Text.strip (fromMaybe "" row.penaltyDescription)
                  | row <- penalties
                  ]
                    <> [ "allowance:" <> maybe "unknown" tshow row.wageAllowanceFixedId <> ":" <> Text.strip (fromMaybe "" row.allowance)
                       | row <- allowances
                       ]
                )
            }

performWageSourceDriftNotificationJob ::
    (?context :: FrameworkConfig, ?modelContext :: ModelContext) =>
    AppJob ->
    IO ()
performWageSourceDriftNotificationJob appJob =
    case Aeson.fromJSON appJob.payload of
        Aeson.Error err -> fail ("Invalid wage source drift notification payload: " <> err)
        Aeson.Success DriftPayload { .. } -> do
            recipient <- fetch (Id payloadUserId :: Id User)
            let eligible = isNothing recipient.deactivatedAt
                    && recipient.platformRole == Just (platformRoleToEnum SuperAdminRole)
            when eligible do
                AppMailSettings { .. } <- loadAppMailSettings
                deliveryDisabled <- isEmailDeliveryDisabled
                unless deliveryDisabled do
                    sendMail WageSourceDriftMail
                        { recipient
                        , driftKind = payloadKind
                        , expectedValue = payloadExpected
                        , observedValue = payloadObserved
                        , fromAddress = mailFromAddress
                        , replyToAddress = mailReplyToAddress
                        , supportEmail = mailSupportEmail
                        }
            void $ appJob
                |> set #status JobStatusSucceeded
                |> set #result (Aeson.object
                    [ "userId" Aeson..= payloadUserId
                    , "driftDedupeKey" Aeson..= payloadDedupeKey
                    , "deliveryStatus" Aeson..= if eligible then ("sent" :: Text) else "skipped_ineligible_recipient"
                    ])
                |> updateRecord
