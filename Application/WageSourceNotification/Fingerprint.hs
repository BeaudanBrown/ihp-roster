module Application.WageSourceNotification.Fingerprint
    ( AwardFingerprintSnapshot (..)
    , loadAwardFingerprintPair
    , loadLatestAwardFingerprintSnapshots
    ) where

import Application.WageSourcePolicy
import qualified Data.List as List
import qualified Data.Set as Set
import qualified Data.Text as Text
import Generated.Types
import IHP.ControllerPrelude


data AwardFingerprintSnapshot = AwardFingerprintSnapshot
    { referenceAward :: !FwcMapdAward
    , fingerprint    :: !AwardFingerprint
    }

loadLatestAwardFingerprintSnapshots ::
    (?modelContext :: ModelContext) =>
    IO [AwardFingerprintSnapshot]
loadLatestAwardFingerprintSnapshots = do
    awards <- hospitalityAwards
    let snapshotTimes = List.nub (map (.syncedAt) awards)
    mapM loadAt (take 2 snapshotTimes)

loadAwardFingerprintPair ::
    (?modelContext :: ModelContext) =>
    UUID ->
    IO (Maybe (AwardFingerprintSnapshot, AwardFingerprintSnapshot))
loadAwardFingerprintPair referenceAwardId = do
    maybeReference <-
        query @FwcMapdAward
            |> filterWhere (#id, Id referenceAwardId)
            |> fetchOneOrNothing
    case maybeReference of
        Nothing -> pure Nothing
        Just reference -> do
            awards <- hospitalityAwards
            let previousTimes =
                    awards
                        |> map (.syncedAt)
                        |> filter (< reference.syncedAt)
                        |> List.nub
            case previousTimes of
                [] -> pure Nothing
                previousAt : _ -> do
                    current <- loadAt reference.syncedAt
                    previous <- loadAt previousAt
                    pure (Just (current, previous))

hospitalityAwards :: (?modelContext :: ModelContext) => IO [FwcMapdAward]
hospitalityAwards =
    query @FwcMapdAward
        |> filterWhere (#code, "MA000009" :: Text)
        |> orderByDesc #syncedAt
        |> fetch

loadAt :: (?modelContext :: ModelContext) => UTCTime -> IO AwardFingerprintSnapshot
loadAt syncedAt = do
    award <-
        query @FwcMapdAward
            |> filterWhere (#code, "MA000009" :: Text)
            |> filterWhere (#syncedAt, syncedAt)
            |> fetchOne
    classifications <-
        query @FwcMapdClassification
            |> filterWhere (#awardFixedId, award.awardFixedId)
            |> filterWhere (#syncedAt, syncedAt)
            |> fetch
    penalties <-
        query @FwcMapdPenaltyRate
            |> filterWhere (#awardFixedId, award.awardFixedId)
            |> filterWhere (#syncedAt, syncedAt)
            |> fetch
    allowances <-
        query @FwcMapdWageAllowance
            |> filterWhere (#awardFixedId, award.awardFixedId)
            |> filterWhere (#syncedAt, syncedAt)
            |> fetch
    pure
        AwardFingerprintSnapshot
            { referenceAward = award
            , fingerprint =
                AwardFingerprint
                    { documentChecksum = tshow award.rawJson
                    , documentVersion = tshow award.publishedYear <> ":" <> tshow award.versionNumber
                    , classificationKeys =
                        Set.fromList
                            [ tshow row.classificationFixedId <> ":" <> Text.strip row.classification
                            | row <- classifications
                            ]
                    , categoryKeys =
                        Set.fromList
                            ( [ "penalty:" <> maybe "unknown" tshow row.penaltyFixedId <> ":" <> Text.strip (fromMaybe "" row.penaltyDescription)
                              | row <- penalties
                              ]
                                <> [ "allowance:" <> maybe "unknown" tshow row.wageAllowanceFixedId <> ":" <> Text.strip (fromMaybe "" row.allowance)
                                   | row <- allowances
                                   ]
                            )
                    }
            }
