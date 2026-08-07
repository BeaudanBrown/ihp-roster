module Test.XeroTimesheetReconciliationSpec where

import Application.Helper.Xero.Types (XeroTimesheetRef (..))
import Application.Xero.Timesheets.Reconciliation
import qualified Data.Aeson as Aeson
import Data.Time.Calendar (fromGregorian)
import Generated.Types
import IHP.Prelude
import Test.Hspec

tests :: Spec
tests =
    describe "Xero timesheet reconciliation" do
        it "classifies the complete local-status and remote-state matrix" do
            forM_ terminalLocalStates \(_label, local, emptyDecision) -> do
                reconcileXeroTimesheet local [] `shouldBe` emptyDecision
                reconcileXeroTimesheet local [remote "draft-id" (Just "DRAFT")] `shouldBe` UpdateXeroDraft "draft-id"
                forM_ knownNonDraftStatuses \status ->
                    reconcileXeroTimesheet local [remote "non-draft-id" (Just status)]
                        `shouldBe` BlockXeroNonDraft "non-draft-id" status
                reconcileXeroTimesheet local [remote "unknown-id" (Just "FUTURE_PROVIDER_STATUS")]
                    `shouldBe` BlockUnknownXeroStatus "unknown-id" (Just "FUTURE_PROVIDER_STATUS")
                reconcileXeroTimesheet local [remote "missing-status-id" Nothing]
                    `shouldBe` BlockUnknownXeroStatus "missing-status-id" Nothing
                reconcileXeroTimesheet local [remote "same-id" (Just "draft"), remote "same-id" (Just "draft")]
                    `shouldBe` UpdateXeroDraft "same-id"
                reconcileXeroTimesheet local [remote "first-id" (Just "DRAFT"), remote "second-id" (Just "DRAFT")]
                    `shouldBe` BlockDistinctXeroTimesheets ["first-id", "second-id"]

        it "reports every pending local submission as in progress across the remote-state matrix" do
            let pending = localSubmission XeroTimesheetSubmissionStatusEnumPending Nothing
                remoteStates =
                    [ []
                    , [remote "draft-id" (Just "DRAFT")]
                    , [remote "same-id" (Just "draft"), remote "same-id" (Just "DRAFT")]
                    , [remote "unknown-id" (Just "NEW_STATUS")]
                    , [remote "missing-status-id" Nothing]
                    , [remote "first-id" (Just "DRAFT"), remote "second-id" (Just "DRAFT")]
                    ]
                        <> map (\status -> [remote "non-draft-id" (Just status)]) knownNonDraftStatuses
            forM_ remoteStates \remotes ->
                reconcileXeroTimesheet (Just pending) remotes `shouldBe` XeroSubmissionInProgress

        it "treats DRAFT case-insensitively and no other provider status as mutable" do
            forM_ ["DRAFT", "draft", "Draft", "dRaFt"] \status ->
                reconcileXeroTimesheet Nothing [remote "draft-id" (Just status)]
                    `shouldBe` UpdateXeroDraft "draft-id"
            reconcileXeroTimesheet Nothing [remote "draft-id" (Just "DRAFT"), remote "draft-id" (Just "draft")]
                `shouldBe` UpdateXeroDraft "draft-id"
            reconcileXeroTimesheet Nothing [remote "draft-id" (Just " DRAFT ")]
                `shouldBe` BlockUnknownXeroStatus "draft-id" (Just " DRAFT ")

        it "preserves unknown provider status text exactly" do
            let providerStatus = "Awaiting Employer Review v2"
            reconcileXeroTimesheet Nothing [remote "unknown-id" (Just providerStatus)]
                `shouldBe` BlockUnknownXeroStatus "unknown-id" (Just providerStatus)

        it "deduplicates conflicting copies of one remote id to the safest deterministic status" do
            reconcileXeroTimesheet
                Nothing
                [remote "same-id" (Just "DRAFT"), remote "same-id" (Just "APPROVED")]
                `shouldBe` BlockXeroNonDraft "same-id" "APPROVED"
            reconcileXeroTimesheet
                Nothing
                [remote "same-id" (Just "PROCESSED"), remote "same-id" (Just "APPROVED")]
                `shouldBe` reconcileXeroTimesheet
                    Nothing
                    [remote "same-id" (Just "APPROVED"), remote "same-id" (Just "PROCESSED")]
            reconcileXeroTimesheet
                Nothing
                [remote "same-id" (Just "DRAFT"), remote "same-id" (Just "FUTURE_STATUS")]
                `shouldBe` BlockUnknownXeroStatus "same-id" (Just "FUTURE_STATUS")
            reconcileXeroTimesheet
                Nothing
                [remote "same-id" Nothing, remote "same-id" (Just "FUTURE_STATUS")]
                `shouldBe` BlockUnknownXeroStatus "same-id" (Just "FUTURE_STATUS")
            reconcileXeroTimesheet
                Nothing
                [remote "same-id" (Just "Z_STATUS"), remote "same-id" (Just "A_STATUS")]
                `shouldBe` reconcileXeroTimesheet
                    Nothing
                    [remote "same-id" (Just "A_STATUS"), remote "same-id" (Just "Z_STATUS")]

        it "replaces only a confirmed-missing prior draft" do
            forM_ knownNonDraftStatuses \status ->
                reconcileXeroTimesheet (Just (submittedSubmission (Just status))) []
                    `shouldBe` BlockXeroNonDraft "prior-id" status
            reconcileXeroTimesheet (Just (submittedSubmission (Just "FUTURE_STATUS"))) []
                `shouldBe` BlockUnknownXeroStatus "prior-id" (Just "FUTURE_STATUS")
            reconcileXeroTimesheet (Just (submittedSubmission Nothing)) []
                `shouldBe` BlockUnknownXeroStatus "prior-id" Nothing
            reconcileXeroTimesheet
                (Just (ExistingXeroTimesheetSubmission XeroTimesheetSubmissionStatusEnumSubmitted Nothing (Just "DRAFT")))
                []
                `shouldBe` BlockMissingXeroTimesheetId (Just "DRAFT")

        it "blocks a remote reference without a TimesheetID" do
            reconcileXeroTimesheet Nothing [remoteWithTimesheetId Nothing (Just "DRAFT")]
                `shouldBe` BlockMissingXeroTimesheetId (Just "DRAFT")
  where
    terminalLocalStates =
        [ ("no local submission", Nothing, CreateXeroTimesheet)
        , ("blocked", Just (localSubmission XeroTimesheetSubmissionStatusEnumBlocked Nothing), CreateXeroTimesheet)
        , ("submitted", Just (submittedSubmission (Just "draft")), ReplaceMissingXeroDraft "prior-id")
        , ("failed", Just (localSubmission XeroTimesheetSubmissionStatusEnumFailed Nothing), CreateXeroTimesheet)
        , ("skipped", Just (localSubmission Skipped Nothing), CreateXeroTimesheet)
        , ("superseded", Just (localSubmission XeroTimesheetSubmissionStatusEnumSuperseded Nothing), CreateXeroTimesheet)
        ]
    knownNonDraftStatuses = ["APPROVED", "PROCESSED", "REJECTED", "REQUESTED"]

localSubmission :: XeroTimesheetSubmissionStatusEnum -> Maybe Text -> ExistingXeroTimesheetSubmission
localSubmission status timesheetId =
    ExistingXeroTimesheetSubmission
        { existingSubmissionStatus = status
        , existingSubmissionTimesheetId = timesheetId
        , existingSubmissionTimesheetStatus = Nothing
        }

submittedSubmission :: Maybe Text -> ExistingXeroTimesheetSubmission
submittedSubmission providerStatus =
    ExistingXeroTimesheetSubmission
        { existingSubmissionStatus = XeroTimesheetSubmissionStatusEnumSubmitted
        , existingSubmissionTimesheetId = Just "prior-id"
        , existingSubmissionTimesheetStatus = providerStatus
        }

remote :: Text -> Maybe Text -> XeroTimesheetRef
remote timesheetId = remoteWithTimesheetId (Just timesheetId)

remoteWithTimesheetId :: Maybe Text -> Maybe Text -> XeroTimesheetRef
remoteWithTimesheetId timesheetId status =
    XeroTimesheetRef
        { xeroTimesheetId = timesheetId
        , xeroTimesheetEmployeeId = "employee-id"
        , xeroTimesheetStartDate = fromGregorian 2026 8 3
        , xeroTimesheetEndDate = fromGregorian 2026 8 9
        , xeroTimesheetStatus = status
        , xeroTimesheetHours = Nothing
        , xeroTimesheetLines = []
        , xeroTimesheetRaw = Aeson.Null
        }
