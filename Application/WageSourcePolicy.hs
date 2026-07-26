module Application.WageSourcePolicy
    ( AwardDriftAudience (..)
    , AwardDriftKind (..)
    , AwardDriftPayrollEffect (..)
    , AwardDriftSignal (..)
    , AwardFingerprint (..)
    , DataVicSnapshot (..)
    , DraftSourceDecision (..)
    , FinalSourceDecision (..)
    , PolicyClock (..)
    , SnapshotStatus (..)
    , SourceDiagnostic (..)
    , SourceRequirement (..)
    , SourceSnapshot (..)
    , WageSourceDecision (..)
    , WageSourcePolicyInput (..)
    , dataVicMaximumAge
    , detectAwardDrift
    , evaluateWageSourcePolicy
    , firstVenueWeekStartingOnOrAfter
    , fwcMaximumAge
    ) where

import qualified "crypton" Crypto.Hash as Hash
import qualified Data.Set as Set
import qualified Data.Text as Text
import qualified Data.Text.Encoding as TextEncoding
import Data.Time.Calendar (Day, DayOfWeek, addDays, dayOfWeek, fromGregorian,
                           toGregorian)
import Data.Time.Clock (NominalDiffTime, UTCTime, diffUTCTime)
import IHP.Prelude

newtype PolicyClock = PolicyClock
    { now :: UTCTime
    }
    deriving (Eq, Show)

data SourceRequirement
    = HospitalityAwardSources
    | ImportedXeroOverride
    deriving (Eq, Show)

data SnapshotStatus
    = CompleteSuccess
    | IncompleteCandidate
    | FailedCandidate
    deriving (Eq, Show)

data SourceSnapshot = SourceSnapshot
    { completedAt :: !UTCTime
    , status      :: !SnapshotStatus
    }
    deriving (Eq, Show)

data DataVicSnapshot = DataVicSnapshot
    { targetYear :: !Integer
    , snapshot   :: !SourceSnapshot
    }
    deriving (Eq, Show)

data WageSourcePolicyInput = WageSourcePolicyInput
    { sourceRequirement            :: !SourceRequirement
    , payWeekStart                 :: !Day
    , venueWeekStartsOn            :: !DayOfWeek
    , applicableDataVicTargetYears :: !(Set.Set Integer)
    , fwcSnapshots                 :: ![SourceSnapshot]
    , dataVicSnapshots             :: ![DataVicSnapshot]
    }
    deriving (Eq, Show)

data SourceDiagnostic
    = FwcSnapshotMissing
    | FwcSnapshotStale
        { staleCompleteFwcSuccess :: !UTCTime
        , maximumFwcAge           :: !NominalDiffTime
        }
    | FwcAnnualRefreshMissing
        { annualRefreshRequiredOnOrAfter :: !Day
        , firstFullPayWeekStart          :: !Day
        , latestCompleteFwcSuccess       :: !(Maybe UTCTime)
        }
    | DataVicSnapshotMissing
        { missingDataVicTargetYear :: !Integer
        }
    | DataVicSnapshotStale
        { staleDataVicTargetYear       :: !Integer
        , latestCompleteDataVicSuccess :: !UTCTime
        , maximumDataVicAge            :: !NominalDiffTime
        }
    deriving (Eq, Show)

data DraftSourceDecision
    = DraftSourcesReady
    | DraftSourceWarning ![SourceDiagnostic]
    deriving (Eq, Show)

data FinalSourceDecision
    = FinalSourcesReady
    | FinalSourceBlock ![SourceDiagnostic]
    deriving (Eq, Show)

data WageSourceDecision = WageSourceDecision
    { draftDecision :: !DraftSourceDecision
    , finalDecision :: !FinalSourceDecision
    }
    deriving (Eq, Show)

fwcMaximumAge :: NominalDiffTime
fwcMaximumAge = 8 * day

dataVicMaximumAge :: NominalDiffTime
dataVicMaximumAge = 45 * day

day :: NominalDiffTime
day = 24 * 60 * 60

evaluateWageSourcePolicy :: PolicyClock -> WageSourcePolicyInput -> WageSourceDecision
evaluateWageSourcePolicy clock input
    | input.sourceRequirement == ImportedXeroOverride = readyDecision
    | null diagnostics = readyDecision
    | otherwise =
        WageSourceDecision
            { draftDecision = DraftSourceWarning diagnostics
            , finalDecision = FinalSourceBlock diagnostics
            }
  where
    diagnostics =
        fwcDiagnostics clock input
            <> dataVicDiagnostics clock input

readyDecision :: WageSourceDecision
readyDecision = WageSourceDecision DraftSourcesReady FinalSourcesReady

fwcDiagnostics :: PolicyClock -> WageSourcePolicyInput -> [SourceDiagnostic]
fwcDiagnostics clock input = freshnessDiagnostic <> annualRefreshDiagnostic
  where
    latestSuccess = latestCompleteSuccess clock.now input.fwcSnapshots
    freshnessDiagnostic = case latestSuccess of
        Nothing -> [FwcSnapshotMissing]
        Just completedAt
            | snapshotAge clock.now completedAt > fwcMaximumAge ->
                [FwcSnapshotStale completedAt fwcMaximumAge]
            | otherwise -> []
    annualRefreshDiagnostic
        | input.payWeekStart /= annualFirstWeek = []
        | maybe False ((>= annualStart) . utctDay) latestSuccess = []
        | otherwise =
            [ FwcAnnualRefreshMissing
                { annualRefreshRequiredOnOrAfter = annualStart
                , firstFullPayWeekStart = annualFirstWeek
                , latestCompleteFwcSuccess = latestSuccess
                }
            ]
    (payWeekYear, _, _) = toGregorian input.payWeekStart
    annualStart = fromGregorian payWeekYear 7 1
    annualFirstWeek = firstVenueWeekStartingOnOrAfter input.venueWeekStartsOn annualStart

dataVicDiagnostics :: PolicyClock -> WageSourcePolicyInput -> [SourceDiagnostic]
dataVicDiagnostics clock input =
    input.applicableDataVicTargetYears
        |> Set.toAscList
        |> concatMap diagnosticForYear
  where
    diagnosticForYear targetYear =
        case latestCompleteSuccess clock.now snapshotsForYear of
            Nothing -> [DataVicSnapshotMissing targetYear]
            Just completedAt
                | snapshotAge clock.now completedAt > dataVicMaximumAge ->
                    [DataVicSnapshotStale targetYear completedAt dataVicMaximumAge]
                | otherwise -> []
      where
        snapshotsForYear =
            input.dataVicSnapshots
                |> filter (\candidate -> candidate.targetYear == targetYear)
                |> map (.snapshot)

latestCompleteSuccess :: UTCTime -> [SourceSnapshot] -> Maybe UTCTime
latestCompleteSuccess now snapshots =
    snapshots
        |> mapMaybe usableCompletion
        |> maximumMaybe
  where
    usableCompletion candidate
        | candidate.status == CompleteSuccess && candidate.completedAt <= now = Just candidate.completedAt
        | otherwise = Nothing

snapshotAge :: UTCTime -> UTCTime -> NominalDiffTime
snapshotAge now completedAt = diffUTCTime now completedAt

firstVenueWeekStartingOnOrAfter :: DayOfWeek -> Day -> Day
firstVenueWeekStartingOnOrAfter weekStartsOn boundary =
    fromMaybe boundary
        (find ((== weekStartsOn) . dayOfWeek) [addDays offset boundary | offset <- [0 .. 6]])

maximumMaybe :: Ord value => [value] -> Maybe value
maximumMaybe []     = Nothing
maximumMaybe values = Just (maximum values)

data AwardFingerprint = AwardFingerprint
    { documentChecksum   :: !Text
    , documentVersion    :: !Text
    , classificationKeys :: !(Set.Set Text)
    , categoryKeys       :: !(Set.Set Text)
    }
    deriving (Eq, Show)

data AwardDriftKind
    = AwardDocumentChecksumChanged
    | AwardDocumentVersionChanged
    | AwardClassificationStructureChanged
    | AwardCategoryStructureChanged
    deriving (Eq, Show)

data AwardDriftAudience = PlatformSuperAdmins
    deriving (Eq, Show)

data AwardDriftPayrollEffect = AwardDriftDoesNotBlockPayroll
    deriving (Eq, Show)

data AwardDriftSignal = AwardDriftSignal
    { kind          :: !AwardDriftKind
    , dedupeKey     :: !Text
    , audience      :: !AwardDriftAudience
    , payrollEffect :: !AwardDriftPayrollEffect
    , expectedValue :: !Text
    , observedValue :: !Text
    }
    deriving (Eq, Show)

detectAwardDrift :: AwardFingerprint -> AwardFingerprint -> [AwardDriftSignal]
detectAwardDrift expected observed =
    catMaybes
        [ changedSignal
            AwardDocumentChecksumChanged
            expected.documentChecksum
            observed.documentChecksum
        , changedSignal
            AwardDocumentVersionChanged
            expected.documentVersion
            observed.documentVersion
        , changedSignal
            AwardClassificationStructureChanged
            (renderKeys expected.classificationKeys)
            (renderKeys observed.classificationKeys)
        , changedSignal
            AwardCategoryStructureChanged
            (renderKeys expected.categoryKeys)
            (renderKeys observed.categoryKeys)
        ]

changedSignal :: AwardDriftKind -> Text -> Text -> Maybe AwardDriftSignal
changedSignal kind expectedValue observedValue
    | expectedValue == observedValue = Nothing
    | otherwise =
        Just
            AwardDriftSignal
                { kind
                , dedupeKey = awardDriftDedupeKey kind expectedValue observedValue
                , audience = PlatformSuperAdmins
                , payrollEffect = AwardDriftDoesNotBlockPayroll
                , expectedValue
                , observedValue
                }

renderKeys :: Set.Set Text -> Text
renderKeys = Text.intercalate "\NUL" . Set.toAscList

awardDriftDedupeKey :: AwardDriftKind -> Text -> Text -> Text
awardDriftDedupeKey kind expectedValue observedValue =
    "award-drift:"
        <> driftKindValue kind
        <> ":"
        <> tshow digest
  where
    payload = Text.intercalate "\NUL" [driftKindValue kind, expectedValue, observedValue]
    digest = Hash.hash (TextEncoding.encodeUtf8 payload) :: Hash.Digest Hash.SHA256

driftKindValue :: AwardDriftKind -> Text
driftKindValue AwardDocumentChecksumChanged        = "document-checksum"
driftKindValue AwardDocumentVersionChanged         = "document-version"
driftKindValue AwardClassificationStructureChanged = "classification-structure"
driftKindValue AwardCategoryStructureChanged       = "category-structure"
