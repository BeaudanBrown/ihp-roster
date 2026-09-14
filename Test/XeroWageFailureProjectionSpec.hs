module Test.XeroWageFailureProjectionSpec where

import Application.Helper.XeroTimesheetReadiness
import Application.WageEngine (AwardClassification (HospitalityLevel1),
                               BaseRateKind (OrdinaryRate),
                               EmploymentBasis (PermanentPartTime),
                               ValidatedRateKey (ClassificationRate),
                               WageCalculationError (MissingValidatedRate))
import Application.WageEvaluation (WageEvaluationError (WageSubjectCalculationFailed),
                                   WageSubjectKey (TimesheetSubject),
                                   renderWageEvaluationError)
import Application.WageSourceEnforcement (WageEntryFailure (WageCalculationFailed))
import qualified Data.Text as Text
import qualified Data.UUID as UUID
import IHP.Prelude
import Test.Hspec

tests :: Spec
tests =
    describe "Xero wage failure blockers" do
        it "projects a missing validated rate into a deterministic entry-local readiness blocker" do
            let entryId = UUID.nil
                key = ClassificationRate HospitalityLevel1 PermanentPartTime OrdinaryRate
                message =
                    renderWageEvaluationError
                        (WageSubjectCalculationFailed (TimesheetSubject entryId) (MissingValidatedRate key))
                blockers = xeroWageFailureBlockers (Left [WageCalculationFailed entryId message] :: Either [WageEntryFailure] [()])

            case blockers of
                [blocker] -> do
                    blocker.xeroBlockerCode `shouldBe` "wage_source_policy"
                    blocker.xeroBlockerTimesheetEntryId `shouldBe` Just entryId
                    blocker.xeroBlockerMessage `shouldSatisfy` Text.isInfixOf "validated wage rate is unavailable"
                    blocker.xeroBlockerActionHint `shouldBe` Just "Refresh authoritative wage sources or correct the entry before payroll."
                _ -> expectationFailure (cs ("Expected one wage blocker, got " <> tshow blockers))
