module Application.PublicHolidays.OverrideIncident
    ( extendPublicHolidayOverrideReview
    , reconcilePublicHolidayOverride
    , reconcilePublicHolidayOverridesAt
    , retirePublicHolidayOverride
    ) where

import Application.Error.Runtime (ExternalRuntimeCategory (PersistedRuntimeInvariant), externalRuntimeInvariantFailure)
import Application.OperationalIncident
import Application.OperationalIncident.Reconciliation (reconcileOperationalIncidentInCurrentTransaction)
import Application.PublicHolidays.Override
import qualified Data.Aeson as Aeson
import qualified Data.Text as Text
import Generated.Types
import IHP.ControllerPrelude

reviewWindow :: NominalDiffTime
reviewWindow = 7 * 24 * 60 * 60

reconcilePublicHolidayOverridesAt ::
    (?modelContext :: ModelContext) =>
    UTCTime ->
    IO [ReconciliationResult]
reconcilePublicHolidayOverridesAt now = do
    overrides <- fetchActivePublicHolidayOverrides
    holidays <-
        query @PublicHoliday
            |> filterWhere (#jurisdiction, "VIC" :: Text)
            |> filterWhere (#isRegional, False)
            |> fetch
    mapM (reconcilePublicHolidayOverride now holidays) overrides

reconcilePublicHolidayOverride ::
    (?modelContext :: ModelContext) =>
    UTCTime ->
    [PublicHoliday] ->
    PublicHolidayOverride ->
    IO ReconciliationResult
reconcilePublicHolidayOverride now holidays entry =
    reconcileOperationalIncident (observationFor now holidays entry)

extendPublicHolidayOverrideReview ::
    (?modelContext :: ModelContext) =>
    User ->
    Id PublicHolidayOverride ->
    UTCTime ->
    Text ->
    UTCTime ->
    IO (Maybe PublicHolidayOverride)
extendPublicHolidayOverrideReview actor overrideId newReviewDueAt rawAction reviewedAt
    | not (eligibleReviewer actor) = pure Nothing
    | Text.null action || Text.length action > 160 = pure Nothing
    | newReviewDueAt <= reviewedAt = pure Nothing
    | otherwise = withTransaction do
        lockOverride overrideId
        current <- fetch overrideId
        if isJust current.retiredAt || newReviewDueAt <= current.reviewDueAt
            then pure Nothing
            else do
                holidays <- holidaysFor current
                _ <- reconcileOperationalIncidentInCurrentTransaction ((observationFor reviewedAt holidays current) { isActive = False, impactKey = "extended", impactRank = 0, symptomCodes = [] })
                updated <-
                    current
                        |> set #verifiedAt reviewedAt
                        |> set #reviewDueAt newReviewDueAt
                        |> set #reviewCycle (current.reviewCycle + 1)
                        |> set #reviewedByUserId (Just (unpackId actor.id))
                        |> set #reviewAction action
                        |> set #updatedAt reviewedAt
                        |> updateRecord
                _ <- reconcileOperationalIncidentInCurrentTransaction (observationFor reviewedAt holidays updated)
                pure (Just updated)
  where
    action = Text.strip rawAction

retirePublicHolidayOverride ::
    (?modelContext :: ModelContext) =>
    User ->
    Id PublicHolidayOverride ->
    Text ->
    UTCTime ->
    IO (Maybe PublicHolidayOverride)
retirePublicHolidayOverride actor overrideId rawAction retiredAt
    | not (eligibleReviewer actor) = pure Nothing
    | Text.null action || Text.length action > 160 = pure Nothing
    | otherwise = withTransaction do
        lockOverride overrideId
        current <- fetch overrideId
        case current.retiredAt of
            Just _ -> pure Nothing
            Nothing -> do
                holidays <- holidaysFor current
                updated <-
                    current
                        |> set #retiredAt (Just retiredAt)
                        |> set #reviewedByUserId (Just (unpackId actor.id))
                        |> set #reviewAction action
                        |> set #updatedAt retiredAt
                        |> updateRecord
                _ <- reconcileOperationalIncidentInCurrentTransaction ((observationFor retiredAt holidays current) { isActive = False, impactKey = "retired", impactRank = 0, symptomCodes = [], safeMetadata = metadataFor updated })
                pure (Just updated)
  where
    action = Text.strip rawAction

observationFor :: UTCTime -> [PublicHoliday] -> PublicHolidayOverride -> IncidentObservation
observationFor now holidays entry =
    let status = overrideStatus now holidays entry
        inReviewWindow = now >= addUTCTime (negate reviewWindow) entry.reviewDueAt
        (active, severity, impactKey, impactRank, symptoms) = case status of
            OverrideExpired -> (True, IncidentCritical, "expired", 20, ["review_expired"])
            OverrideReady | inReviewWindow -> (True, IncidentWarning, "review_window", 10, ["review_window_open"])
            _ -> (False, IncidentInfo, "not_due", 0, [])
     in IncidentObservation
            { category = "holiday_override"
            , scopeKey = "global"
            , stableIdentity = overrideIdentity entry
            , affectedSource = "public_holiday_override"
            , venueId = Nothing
            , observedAt = now
            , isActive = active
            , severity
            , impactKey
            , impactRank
            , symptomCodes = symptoms
            , safeMetadata = metadataFor entry
            }

metadataFor :: PublicHolidayOverride -> Aeson.Value
metadataFor entry =
    Aeson.object
        [ "jurisdiction" Aeson..= entry.jurisdiction
        , "year" Aeson..= entry.targetYear
        , "verificationSource" Aeson..= entry.sourceUrl
        , "reviewDueAt" Aeson..= entry.reviewDueAt
        , "reviewCycle" Aeson..= entry.reviewCycle
        , "reviewedAction" Aeson..= entry.reviewAction
        ]

overrideIdentity :: PublicHolidayOverride -> Text
overrideIdentity entry =
    Text.intercalate ":" [entry.jurisdiction, tshow entry.targetYear, tshow entry.reviewCycle]

holidaysFor :: (?modelContext :: ModelContext) => PublicHolidayOverride -> IO [PublicHoliday]
holidaysFor entry =
    query @PublicHoliday
        |> filterWhere (#jurisdiction, entry.jurisdiction)
        |> filterWhere (#isRegional, False)
        |> fetch

eligibleReviewer :: User -> Bool
eligibleReviewer actor = actor.platformRole == Just SuperAdmin && isNothing actor.deactivatedAt

lockOverride :: (?modelContext :: ModelContext) => Id PublicHolidayOverride -> IO ()
lockOverride overrideId = do
    rows :: [Only Bool] <-
        unsafeSqlQuery
            "SELECT TRUE FROM (SELECT pg_advisory_xact_lock(hashtext(?))) AS public_holiday_override_review_lock"
            (Only (tshow (unpackId overrideId)))
    unless (rows == [Only True]) $
        externalRuntimeInvariantFailure PersistedRuntimeInvariant "Unable to lock public holiday override review"
