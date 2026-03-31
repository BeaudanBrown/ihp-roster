module Test.PaySpec where

import Application.Helper.Pay
import Config
import qualified Data.Map.Strict as Map
import qualified Data.Text as Text
import Data.Time.Calendar (fromGregorian)
import Generated.Types
import IHP.ControllerPrelude
import IHP.FrameworkConfig
import IHP.HaskellSupport
import IHP.Prelude
import IHP.Test.Mocking
import Test.Hspec
import Test.Support
import Web.Controller.Admin ()
import Web.FrontController ()
import Web.Routes
import Web.Types

tests :: Spec
tests = do
    describe "Pay helper orchestration" do
        it "decodes single-entry pay payloads" do
            let payload = "{\"entryId\":\"11111111-1111-1111-1111-111111111111\",\"shiftTypeName\":\"Ordinary\",\"payLevelName\":\"Level 1\",\"payConfigSnapshotVersion\":\"v1\",\"segments\":[{\"segment\":\"ordinary\",\"minutes\":480,\"shiftTypeName\":\"Ordinary\",\"payLevelName\":\"Level 1\",\"dayRuleMultiplier\":1.25,\"weekendMultiplier\":1.5,\"multiplier\":1.875,\"baseRate\":0,\"amount\":0}],\"totals\":{\"paidMinutes\":480,\"totalAmount\":0}}"
            case decodeTimesheetPayResult payload of
                Left err -> expectationFailure ("Expected decode success, got: " <> Text.unpack err)
                Right result -> do
                    result.entryId `shouldBe` "11111111-1111-1111-1111-111111111111"
                    result.shiftTypeName `shouldBe` Just "Ordinary"
                    result.payLevelName `shouldBe` Just "Level 1"
                    result.payConfigSnapshotVersion `shouldBe` Just "v1"
                    result.totals.paidMinutes `shouldBe` 480
                    fmap (.segment) result.segments `shouldBe` ["ordinary"]

        it "builds summary flags for weekend and stacked multipliers" do
            let result = TimesheetPayResult
                    { entryId = "11111111-1111-1111-1111-111111111111"
                    , shiftTypeId = Nothing
                    , shiftTypeName = Just "Ordinary"
                    , payLevelId = Nothing
                    , payLevelName = Just "Level 1"
                    , payConfigSnapshotId = Nothing
                    , payConfigSnapshotVersion = Nothing
                    , segments =
                        [ PaySegment
                            { segment = "evening"
                            , minutes = 120
                            , shiftTypeId = Nothing
                            , shiftTypeName = Just "Ordinary"
                            , payLevelId = Nothing
                            , payLevelName = Just "Level 1"
                            , multiplier = 1.875
                            , dayRuleMultiplier = Just 1.25
                            , weekendMultiplier = Just 1.5
                            , baseRate = 30
                            , amount = 75
                            }
                        ]
                    , totals = PayTotals { paidMinutes = 120, totalAmount = 0 }
                    }
                summary = buildTimesheetPaySummary result
            summary.paidMinutes `shouldBe` 120
            summary.segmentCount `shouldBe` 1
            summary.weekendApplied `shouldBe` True
            summary.hasStackedMultiplier `shouldBe` True
            summary.totalAmount `shouldBe` 0

        it "decodes range payload arrays and indexes summaries by entry id" do
            let payload = "[{\"entryId\":\"a\",\"segments\":[{\"segment\":\"ordinary\",\"minutes\":60,\"dayRuleMultiplier\":1.0,\"weekendMultiplier\":1.0,\"multiplier\":1.0,\"baseRate\":0,\"amount\":0}],\"totals\":{\"paidMinutes\":60,\"totalAmount\":0}},{\"entryId\":\"b\",\"segments\":[{\"segment\":\"evening\",\"minutes\":30,\"dayRuleMultiplier\":1.0,\"weekendMultiplier\":1.5,\"multiplier\":1.5,\"baseRate\":0,\"amount\":0}],\"totals\":{\"paidMinutes\":30,\"totalAmount\":0}}]"
            case decodeTimesheetPayResults payload of
                Left err -> expectationFailure ("Expected decode success, got: " <> Text.unpack err)
                Right results -> do
                    length results `shouldBe` 2
                    let summaries = buildTimesheetPaySummariesByEntryId results
                    fmap (.weekendApplied) (Map.lookup "a" summaries) `shouldBe` Just False
                    fmap (.weekendApplied) (Map.lookup "b" summaries) `shouldBe` Just True

    beforeAll testContext do
        describe "Historical pay snapshots" do
            it "keeps approved timesheet pay stable after later config changes" $ withContext do
                withCleanDb do
                    venue <- createVenueWithConfig "Pay Snapshot Venue"
                    admin <- createUserRecord "pay-admin@example.com" "staff" True
                    _ <- createVenueMembershipRecord venue admin "venue_admin"
                    staff <- createStaffRecord venue Nothing "Pat" "Rate"
                    payLevel <- createPayLevelRecord venue "Level 1"
                    shiftType <- createShiftTypeRecord venue payLevel "Ordinary"
                    friday <- fetchDayNameRecord venue 5
                    overrideLevel <- createPayLevelRecord venue "Friday Level"
                    _ <- createPayLevelDayRuleRecord shiftType friday overrideLevel
                    entry <- createTimesheetEntryRecord venue staff (fromGregorian 2025 1 10)
                        >>= updateRecord . set #shiftTypeId (unpackId shiftType.id)

                    _ <- withUserAndCurrentVenue admin venue.id do
                        callAction CreatePayConfigSnapshotAction

                    _ <- withUserAndCurrentVenue admin venue.id do
                        callAction (ApproveTimesheetEntryAction entry.id)

                    _ <- shiftType
                        |> set #defaultPayLevelId (unpackId (get #id payLevel))
                        |> updateRecord
                    _ <- query @PayLevelDayRule
                        |> filterWhere (#shiftTypeId, unpackId (get #id shiftType))
                        |> fetchOne
                        >>= updateRecord . set #payLevelId (unpackId (get #id payLevel))

                    payResult <- fetchTimesheetPay entry.id

                    case payResult of
                        Left err -> expectationFailure ("Expected pay result, got: " <> Text.unpack err)
                        Right result -> do
                            result.payConfigSnapshotVersion `shouldBe` Just "v1"
                            result.shiftTypeName `shouldBe` Just "Ordinary"
                            result.payLevelName `shouldBe` Just "Friday Level"
                            fmap (.payLevelName) result.segments `shouldBe` [Just "Friday Level"]
