module Test.WageSourcePolicySpec where

import Application.WageSourcePolicy
import qualified Data.Set as Set
import Data.Time.Calendar (DayOfWeek (Monday), fromGregorian)
import Data.Time.Clock (UTCTime (..), addUTCTime, secondsToDiffTime)
import IHP.Prelude hiding (utc)
import Test.Hspec
import Test.QuickCheck (NonNegative (..), property)

tests :: Spec
tests = do
    describe "WageSourcePolicy HIGA-SOURCE-FRESHNESS pure wage-source policy" do
        it "accepts an FWC complete success exactly 8 days old and blocks one second beyond the boundary" do
            let clock = PolicyClock (utc 2026 6 29)
                boundary = addUTCTime (negate fwcMaximumAge) clock.now
                input = healthyInput { fwcSnapshots = [fwcCompleteAt boundary], dataVicSnapshots = [dataVicCompleteAt 2026 clock.now] }
            evaluateWageSourcePolicy clock input `shouldBe` sourcesReady
            let staleInput = input { fwcSnapshots = [fwcCompleteAt (addUTCTime (-1) boundary)] }
            evaluateWageSourcePolicy clock staleInput
                `shouldBe` blockedBy [FwcSnapshotStale (addUTCTime (-1) boundary) fwcMaximumAge]

        it "requires the first full Monday pay week after 1 July to use a complete success on or after 1 July" do
            let clock = PolicyClock (utc 2026 7 6)
                beforeJuly = fwcCompleteAt (utcSeconds 2026 6 30 (23 * 60 * 60 + 59 * 60 + 59))
                annualInput =
                    healthyInput
                        { payWeekStart = fromGregorian 2026 7 6
                        , venueWeekStartsOn = Monday
                        , fwcSnapshots = [beforeJuly]
                        , dataVicSnapshots = [dataVicCompleteAt 2026 clock.now]
                        }
                diagnostic =
                    FwcAnnualRefreshMissing
                        { annualRefreshRequiredOnOrAfter = fromGregorian 2026 7 1
                        , firstFullPayWeekStart = fromGregorian 2026 7 6
                        , latestCompleteFwcSuccess = Just beforeJuly.fwcSnapshotMetadata.completedAt
                        }
            evaluateWageSourcePolicy clock annualInput `shouldBe` blockedBy [diagnostic]
            evaluateWageSourcePolicy clock (annualInput { fwcSnapshots = [fwcCompleteAt (utc 2026 7 1)] })
                `shouldBe` sourcesReady

        it "accepts DataVic target-year data exactly 45 days old and blocks one second beyond the boundary" do
            let clock = PolicyClock (utc 2026 5 1)
                boundary = addUTCTime (negate dataVicMaximumAge) clock.now
                input = healthyInput { dataVicSnapshots = [dataVicCompleteAt 2026 boundary] }
            evaluateWageSourcePolicy clock input `shouldBe` sourcesReady
            let staleAt = addUTCTime (-1) boundary
            evaluateWageSourcePolicy clock (input { dataVicSnapshots = [dataVicCompleteAt 2026 staleAt] })
                `shouldBe` blockedBy [DataVicSnapshotStale 2026 staleAt dataVicMaximumAge]

        it "reports actionable missing diagnostics for every applicable source" do
            let input =
                    healthyInput
                        { fwcSnapshots = []
                        , applicableDataVicTargetYears = Set.fromList [2026, 2027]
                        , dataVicSnapshots = []
                        }
            evaluateWageSourcePolicy (PolicyClock (utc 2026 5 1)) input
                `shouldBe` blockedBy [FwcSnapshotMissing, DataVicSnapshotMissing 2026, DataVicSnapshotMissing 2027]

        it "ignores failed, incomplete and unvalidated FWC candidates instead of replacing the last validated success" do
            let clock = PolicyClock (utc 2026 5 1)
                oldSuccess = fwcCompleteAt (addUTCTime (negate (fwcMaximumAge + 1)) clock.now)
                input =
                    healthyInput
                        { fwcSnapshots =
                            [ oldSuccess
                            , FwcSnapshot (SourceSnapshot clock.now FailedCandidate) ValidatedMapdSnapshot
                            , FwcSnapshot (SourceSnapshot clock.now IncompleteCandidate) ValidatedMapdSnapshot
                            , FwcSnapshot (SourceSnapshot clock.now CompleteSuccess) UnvalidatedFwcCandidate
                            ]
                        }
            evaluateWageSourcePolicy clock input
                `shouldBe` blockedBy [FwcSnapshotStale oldSuccess.fwcSnapshotMetadata.completedAt fwcMaximumAge]

        it "requires authoritative statewide Victoria coverage for each DataVic target year" do
            let clock = PolicyClock (utc 2026 5 1)
                regional = DataVicSnapshot 2026 (completeAt clock.now) RegionalVictoria
                input = healthyInput { dataVicSnapshots = [regional] }
            evaluateWageSourcePolicy clock input
                `shouldBe` blockedBy [DataVicSnapshotMissing 2026]

        it "lets imported Xero overrides bypass FWC and DataVic freshness entirely" do
            let input =
                    healthyInput
                        { sourceRequirement = ImportedXeroOverride
                        , fwcSnapshots = []
                        , applicableDataVicTargetYears = Set.fromList [2026, 2027]
                        , dataVicSnapshots = []
                        }
            evaluateWageSourcePolicy (PolicyClock (utc 2026 7 6)) input `shouldBe` sourcesReady

        it "property: adding failed candidates never changes a freshness decision" $
            property propFailedCandidatesIgnored

        it "property: every complete FWC success up to the exact 8-day boundary is accepted" $
            property propFwcFreshThroughExactBoundary

    describe "WageSourcePolicy Award drift policy" do
        it "emits stable deduplicable platform-super-admin signals without blocking payroll" do
            let expected = baselineFingerprint
                observed =
                    baselineFingerprint
                        { documentChecksum = "sha256:new"
                        , categoryKeys = Set.fromList ["sunday", "ordinary", "new-category"]
                        }
                first = detectAwardDrift expected observed
                repeated = detectAwardDrift expected observed
            first `shouldBe` repeated
            map (.kind) first
                `shouldBe` [AwardDocumentChecksumChanged, AwardCategoryStructureChanged]
            first `shouldSatisfy` all (\signal -> signal.audience == PlatformSuperAdmins && signal.payrollEffect == AwardDriftDoesNotBlockPayroll)
            map (.dedupeKey) first `shouldSatisfy` \keys -> length keys == length (nub keys)

        it "does not signal rate-only refreshes or unchanged Award structure" do
            detectAwardDrift baselineFingerprint baselineFingerprint `shouldBe` []

        it "property: category input order cannot change a drift dedupe key" $
            property \(NonNegative rawValue) ->
                let suffix = tshow (rawValue `mod` (1000 :: Int))
                    categories = ["ordinary", "saturday", "category-" <> suffix]
                    observedA = baselineFingerprint { categoryKeys = Set.fromList categories }
                    observedB = baselineFingerprint { categoryKeys = Set.fromList (reverse categories) }
                 in detectAwardDrift baselineFingerprint observedA
                        == detectAwardDrift baselineFingerprint observedB

propFailedCandidatesIgnored :: NonNegative Int -> Bool
propFailedCandidatesIgnored (NonNegative rawSeconds) =
    let seconds = fromIntegral (rawSeconds `mod` (20 * 24 * 60 * 60))
        clock = PolicyClock (utc 2026 5 1)
        input = healthyInput { fwcSnapshots = [fwcCompleteAt (addUTCTime (negate seconds) clock.now)] }
        failed = FwcSnapshot (SourceSnapshot (addUTCTime 1 clock.now) FailedCandidate) ValidatedMapdSnapshot
     in evaluateWageSourcePolicy clock input
            == evaluateWageSourcePolicy clock (input { fwcSnapshots = failed : input.fwcSnapshots })

propFwcFreshThroughExactBoundary :: NonNegative Int -> Bool
propFwcFreshThroughExactBoundary (NonNegative rawSeconds) =
    let seconds = fromIntegral (rawSeconds `mod` (8 * 24 * 60 * 60 + 1))
        clock = PolicyClock (utc 2026 5 1)
        input = healthyInput { fwcSnapshots = [fwcCompleteAt (addUTCTime (negate seconds) clock.now)] }
     in evaluateWageSourcePolicy clock input == sourcesReady

healthyInput :: WageSourcePolicyInput
healthyInput =
    WageSourcePolicyInput
        { sourceRequirement = HospitalityAwardSources
        , payWeekStart = fromGregorian 2026 4 27
        , venueWeekStartsOn = Monday
        , applicableDataVicTargetYears = Set.singleton 2026
        , fwcSnapshots = [fwcCompleteAt (utc 2026 5 1)]
        , dataVicSnapshots = [dataVicCompleteAt 2026 (utc 2026 5 1)]
        }

sourcesReady :: WageSourceDecision
sourcesReady = WageSourceDecision DraftSourcesReady FinalSourcesReady

blockedBy :: [SourceDiagnostic] -> WageSourceDecision
blockedBy diagnostics =
    WageSourceDecision
        (DraftSourceWarning diagnostics)
        (FinalSourceBlock diagnostics)

completeAt :: UTCTime -> SourceSnapshot
completeAt completedAt = SourceSnapshot { completedAt, status = CompleteSuccess }

fwcCompleteAt :: UTCTime -> FwcSnapshot
fwcCompleteAt completedAt =
    FwcSnapshot (completeAt completedAt) ValidatedMapdSnapshot

dataVicCompleteAt :: Integer -> UTCTime -> DataVicSnapshot
dataVicCompleteAt targetYear completedAt =
    DataVicSnapshot targetYear (completeAt completedAt) StatewideVictoria

baselineFingerprint :: AwardFingerprint
baselineFingerprint =
    AwardFingerprint
        { documentChecksum = "sha256:reviewed"
        , documentVersion = "MA000009-2026"
        , classificationKeys = Set.fromList ["introductory", "level-1"]
        , categoryKeys = Set.fromList ["ordinary", "saturday", "sunday"]
        }

utc :: Integer -> Int -> Int -> UTCTime
utc year month day = utcSeconds year month day 0

utcSeconds :: Integer -> Int -> Int -> Integer -> UTCTime
utcSeconds year month day seconds =
    UTCTime (fromGregorian year month day) (secondsToDiffTime seconds)
