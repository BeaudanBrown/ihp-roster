module Application.WageSourceNotification.Email
    ( AwardDriftMailProjection (..)
    , awardDriftMailKind
    , isAwardDriftMailKind
    , loadAwardDriftMail
    ) where

import Application.Helper.Mail
import Application.WageSourceNotification.Fingerprint
import Application.WageSourcePolicy
import Generated.Types
import IHP.ControllerPrelude
import Web.Mail.WageSourceDrift


data AwardDriftMailProjection
    = AwardDriftMailReady !WageSourceDriftMail
    | AwardDriftMailSkipped !Text

awardDriftMailKind :: AwardDriftKind -> Text
awardDriftMailKind kind =
    "wage_source_award_drift_" <> awardDriftKindText kind <> "_v1"

isAwardDriftMailKind :: Text -> Bool
isAwardDriftMailKind candidate =
    isJust (awardDriftKindFromMailKind candidate)

loadAwardDriftMail ::
    (?modelContext :: ModelContext) =>
    Text ->
    UUID ->
    Text ->
    UUID ->
    AppMailSettings ->
    IO AwardDriftMailProjection
loadAwardDriftMail mailKind recipientAccountId recipientAddress referenceAwardId settings =
    case awardDriftKindFromMailKind mailKind of
        Nothing -> pure (AwardDriftMailSkipped "unknown_mail_kind")
        Just requestedKind -> do
            maybeRecipient <- query @User |> filterWhere (#id, Id recipientAccountId) |> fetchOneOrNothing
            maybePair <- loadAwardFingerprintPair referenceAwardId
            case (maybeRecipient, maybePair) of
                (Nothing, _) -> pure (AwardDriftMailSkipped "recipient_missing")
                (_, Nothing) -> pure (AwardDriftMailSkipped "domain_reference_missing")
                (Just recipient, Just (current, previous))
                    | isJust recipient.deactivatedAt || recipient.platformRole /= Just SuperAdmin ->
                        pure (AwardDriftMailSkipped "recipient_ineligible")
                    | otherwise ->
                        case find ((== requestedKind) . (.kind)) (detectAwardDrift previous.fingerprint current.fingerprint) of
                            Nothing -> pure (AwardDriftMailSkipped "drift_not_in_snapshot")
                            Just signal ->
                                pure
                                    ( AwardDriftMailReady
                                        WageSourceDriftMail
                                            { recipientAddress
                                            , driftKind = tshow signal.kind
                                            , expectedValue = signal.expectedValue
                                            , observedValue = signal.observedValue
                                            , fromAddress = settings.mailFromAddress
                                            , replyToAddress = settings.mailReplyToAddress
                                            , supportEmail = settings.mailSupportEmail
                                            }
                                    )

awardDriftKindFromMailKind :: Text -> Maybe AwardDriftKind
awardDriftKindFromMailKind candidate =
    find ((== candidate) . awardDriftMailKind) allAwardDriftKinds

allAwardDriftKinds :: [AwardDriftKind]
allAwardDriftKinds =
    [ AwardDocumentChecksumChanged
    , AwardDocumentVersionChanged
    , AwardClassificationStructureChanged
    , AwardCategoryStructureChanged
    ]
