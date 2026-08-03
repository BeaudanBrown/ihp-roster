module Test.XeroReferenceTrustSpec where

import Application.Xero.ReferenceTrust
import Data.Time.Calendar (fromGregorian)
import Data.Time.Clock (UTCTime (..), addUTCTime, secondsToDiffTime)
import IHP.Prelude
import Test.Hspec

tests :: Spec
tests = do
    describe "Xero reference trust policy" do
        it "uses a fresh snapshot even while its six-day maintenance refresh is active" do
            decideXeroReferenceTrust now "active" (Just (addUTCTime (negate (6.5 * oneDay)) now)) NoMissingPayrollReferenceDemand XeroReferenceSyncRunning
                `shouldBe` UseTrustedXeroReferenceSnapshot

        it "starts or joins sync for missing, stale, or payroll-eligible missing-mapping demand" do
            decideXeroReferenceTrust now "active" Nothing NoMissingPayrollReferenceDemand XeroReferenceSyncIdle
                `shouldBe` StartOrJoinXeroReferenceSync
            decideXeroReferenceTrust now "active" (Just (addUTCTime (negate (8 * oneDay)) now)) NoMissingPayrollReferenceDemand XeroReferenceSyncRunning
                `shouldBe` WaitForTrustedXeroReferenceSnapshot XeroReferenceSyncRunning
            decideXeroReferenceTrust now "active" (Just (addUTCTime (negate oneDay) now)) MissingPayrollEligibleStaffReference XeroReferenceSyncIdle
                `shouldBe` StartOrJoinXeroReferenceSync

        it "uses a fresh snapshot for missing-staff mapping while a provider retry is waiting" do
            let retryAt = addUTCTime (16 * 60 * 60) now
            decideXeroReferenceTrust now "active" (Just (addUTCTime (negate oneDay) now)) MissingPayrollEligibleStaffReference (XeroReferenceSyncRetryWaiting retryAt)
                `shouldBe` UseTrustedXeroReferenceSnapshot
            decideXeroReferenceTrust now "active" (Just (addUTCTime (negate (8 * oneDay)) now)) MissingPayrollEligibleStaffReference (XeroReferenceSyncRetryWaiting retryAt)
                `shouldBe` WaitForTrustedXeroReferenceSnapshot (XeroReferenceSyncRetryWaiting retryAt)

        it "does not refresh fresh reference data for effective roster-only work" do
            decideXeroReferenceTrust now "active" (Just (addUTCTime (negate oneDay) now)) MissingRosterOnlyStaffReference XeroReferenceSyncIdle
                `shouldBe` UseTrustedXeroReferenceSnapshot

        it "prioritizes reconnect and blocks exhausted stale snapshots safely" do
            decideXeroReferenceTrust now "reauthorization_required" Nothing NoMissingPayrollReferenceDemand (XeroReferenceSyncFailed "safe failure")
                `shouldBe` ReconnectXeroForReferenceData
            decideXeroReferenceTrust now "active" (Just (addUTCTime (negate (8 * oneDay)) now)) NoMissingPayrollReferenceDemand (XeroReferenceSyncFailed "safe failure")
                `shouldBe` BlockStaleXeroReferenceData "safe failure"

now :: UTCTime
now = UTCTime (fromGregorian 2026 7 30) (secondsToDiffTime 0)

oneDay :: NominalDiffTime
oneDay = 24 * 60 * 60
