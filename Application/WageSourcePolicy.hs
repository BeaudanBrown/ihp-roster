module Application.WageSourcePolicy
    ( AwardDriftAudience (..)
    , AwardDriftKind (..)
    , AwardDriftPayrollEffect (..)
    , AwardDriftSignal (..)
    , AwardFingerprint (..)
    , DataVicCoverage (..)
    , DataVicSnapshot (..)
    , DraftSourceDecision (..)
    , FinalSourceDecision (..)
    , FwcSnapshot (..)
    , FwcSnapshotProvenance (..)
    , PolicyClock (..)
    , SnapshotStatus (..)
    , SourceDiagnostic (..)
    , SourceRequirement (..)
    , SourceSnapshot (..)
    , WageSourceDecision (..)
    , WageSourcePolicyInput (..)
    , awardDriftKindText
    , dataVicMaximumAge
    , detectAwardDrift
    , evaluateDataVicDiagnostics
    , evaluateFwcAnnualDiagnostics
    , evaluateFwcFreshnessDiagnostics
    , evaluateWageSourcePolicy
    , firstVenueWeekStartingOnOrAfter
    , fwcMaximumAge
    ) where

import qualified "crypton" Crypto.Hash as Hash
import qualified Data.Set as Set
import qualified Data.Text as Text
import qualified Data.Text.Encoding as TextEncoding
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

data FwcSnapshotProvenance
    = ValidatedMapdSnapshot
    | UnvalidatedFwcCandidate
    deriving (Eq, Show)

data FwcSnapshot = FwcSnapshot
    { fwcSnapshotMetadata :: !SourceSnapshot
    , provenance          :: !FwcSnapshotProvenance
    }
    deriving (Eq, Show)

data DataVicCoverage
    = StatewideVictoria
    | RegionalVictoria
    deriving (Eq, Show)

data DataVicSnapshot = DataVicSnapshot
    { targetYear :: !Integer
    , snapshot   :: !SourceSnapshot
    , coverage   :: !DataVicCoverage
    }
    deriving (Eq, Show)

data WageSourcePolicyInput = WageSourcePolicyInput
    { sourceRequirement            :: !SourceRequirement
    , payWeekStart                 :: !Day
    , venueWeekStartsOn            :: !DayOfWeek
    , applicableDataVicTargetYears :: !(Set.Set Integer)
    , fwcSnapshots                 :: ![FwcSnapshot]
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
fwcMaximumAge = 8 * secondsPerDay

dataVicMaximumAge :: NominalDiffTime
dataVicMaximumAge = 45 * secondsPerDay

secondsPerDay :: NominalDiffTime
secondsPerDay = 24 * 60 * 60

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
fwcDiagnostics clock input =
    evaluateFwcFreshnessDiagnostics clock input.fwcSnapshots
        <> evaluateFwcAnnualDiagnostics
            clock
            input.payWeekStart
            input.venueWeekStartsOn
            input.fwcSnapshots

evaluateFwcFreshnessDiagnostics :: PolicyClock -> [FwcSnapshot] -> [SourceDiagnostic]
evaluateFwcFreshnessDiagnostics clock snapshots =
    case latestValidatedFwcSuccess clock snapshots of
        Nothing -> [FwcSnapshotMissing]
        Just completedAt
            | snapshotAge clock.now completedAt > fwcMaximumAge ->
                [FwcSnapshotStale completedAt fwcMaximumAge]
            | otherwise -> []

evaluateFwcAnnualDiagnostics :: PolicyClock -> Day -> DayOfWeek -> [FwcSnapshot] -> [SourceDiagnostic]
evaluateFwcAnnualDiagnostics clock payWeekStart venueWeekStartsOn snapshots
    | payWeekStart /= annualFirstWeek = []
    | maybe False ((>= annualStart) . utctDay) latestSuccess = []
    | otherwise =
        [ FwcAnnualRefreshMissing
            { annualRefreshRequiredOnOrAfter = annualStart
            , firstFullPayWeekStart = annualFirstWeek
            , latestCompleteFwcSuccess = latestSuccess
            }
        ]
  where
    latestSuccess = latestValidatedFwcSuccess clock snapshots
    (payWeekYear, _, _) = toGregorian payWeekStart
    annualStart = fromGregorian payWeekYear 7 1
    annualFirstWeek = firstVenueWeekStartingOnOrAfter venueWeekStartsOn annualStart

latestValidatedFwcSuccess :: PolicyClock -> [FwcSnapshot] -> Maybe UTCTime
latestValidatedFwcSuccess clock snapshots =
    snapshots
        |> filter ((== ValidatedMapdSnapshot) . (.provenance))
        |> map (.fwcSnapshotMetadata)
        |> latestCompleteSuccess clock.now

dataVicDiagnostics :: PolicyClock -> WageSourcePolicyInput -> [SourceDiagnostic]
dataVicDiagnostics clock input =
    evaluateDataVicDiagnostics clock input.applicableDataVicTargetYears input.dataVicSnapshots

evaluateDataVicDiagnostics :: PolicyClock -> Set.Set Integer -> [DataVicSnapshot] -> [SourceDiagnostic]
evaluateDataVicDiagnostics clock targetYears snapshots =
    targetYears
        |> Set.toAscList
        |> concatMap diagnosticForYear
  where
    diagnosticForYear targetYear =
        case latestCompleteSuccess clock.now (snapshotsForYear targetYear) of
            Nothing -> [DataVicSnapshotMissing targetYear]
            Just completedAt
                | snapshotAge clock.now completedAt > dataVicMaximumAge ->
                    [DataVicSnapshotStale targetYear completedAt dataVicMaximumAge]
                | otherwise -> []
    snapshotsForYear targetYear =
        snapshots
            |> filter
                ( \candidate ->
                    candidate.targetYear == targetYear
                        && candidate.coverage == StatewideVictoria
                )
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
maximumMaybe []             = Nothing
maximumMaybe (first : rest) = Just (foldl' max first rest)

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
        , changedSetSignal
            AwardClassificationStructureChanged
            expected.classificationKeys
            observed.classificationKeys
        , changedSetSignal
            AwardCategoryStructureChanged
            expected.categoryKeys
            observed.categoryKeys
        ]

changedSignal :: AwardDriftKind -> Text -> Text -> Maybe AwardDriftSignal
changedSignal kind expectedValue observedValue =
    changedSignalWithCanonicalValues kind expectedValue observedValue expectedValue observedValue

changedSetSignal :: AwardDriftKind -> Set.Set Text -> Set.Set Text -> Maybe AwardDriftSignal
changedSetSignal kind expectedValues observedValues =
    changedSignalWithCanonicalValues
        kind
        (renderKeys expectedValues)
        (renderKeys observedValues)
        (canonicalTextParts (Set.toAscList expectedValues))
        (canonicalTextParts (Set.toAscList observedValues))

changedSignalWithCanonicalValues :: AwardDriftKind -> Text -> Text -> Text -> Text -> Maybe AwardDriftSignal
changedSignalWithCanonicalValues kind expectedValue observedValue expectedCanonical observedCanonical
    | expectedCanonical == observedCanonical = Nothing
    | otherwise =
        Just
            AwardDriftSignal
                { kind
                , dedupeKey = awardDriftDedupeKey kind expectedCanonical observedCanonical
                , audience = PlatformSuperAdmins
                , payrollEffect = AwardDriftDoesNotBlockPayroll
                , expectedValue
                , observedValue
                }

renderKeys :: Set.Set Text -> Text
renderKeys = Text.intercalate ", " . Set.toAscList

awardDriftDedupeKey :: AwardDriftKind -> Text -> Text -> Text
awardDriftDedupeKey kind expectedCanonical observedCanonical =
    "award-drift:"
        <> awardDriftKindText kind
        <> ":"
        <> tshow digest
  where
    payload = canonicalTextParts [awardDriftKindText kind, expectedCanonical, observedCanonical]
    digest = Hash.hash (TextEncoding.encodeUtf8 payload) :: Hash.Digest Hash.SHA256

canonicalTextParts :: [Text] -> Text
canonicalTextParts = Text.concat . map (\value -> tshow (Text.length value) <> ":" <> value)

awardDriftKindText :: AwardDriftKind -> Text
awardDriftKindText AwardDocumentChecksumChanged        = "document-checksum"
awardDriftKindText AwardDocumentVersionChanged         = "document-version"
awardDriftKindText AwardClassificationStructureChanged = "classification-structure"
awardDriftKindText AwardCategoryStructureChanged       = "category-structure"
