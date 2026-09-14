module Test.PaySpec where

import Application.Helper.Pay
import Application.PayAssignment
import Data.Time.Calendar (fromGregorian)
import qualified Data.UUID as UUID
import Generated.Types
import IHP.ModelSupport (Id)
import IHP.ModelSupport.Types (Id' (Id))
import IHP.Prelude
import Test.Hspec

-- Non-calculation pay-version/date helpers remain here. Wage arithmetic and
-- approved-ledger contracts live in the focused WageEngine/export suites.
tests :: Spec
tests = do
    describe "Pay helper orchestration" do
        it "derives venue-effective award dates from the next venue week boundary" do
            venueEffectiveRateDate 1 (fromGregorian 2026 7 1) `shouldBe` fromGregorian 2026 7 6
            venueEffectiveRateDate 1 (fromGregorian 2026 7 6) `shouldBe` fromGregorian 2026 7 6
            venueEffectiveRateEndDate 1 (Just (fromGregorian 2026 6 30)) `shouldBe` Just (fromGregorian 2026 7 5)

        it "collapses deterministic pay-version manifests" do
            collapsePayVersionManifests [] `shouldBe` Nothing
            collapsePayVersionManifests ["staff:a;shift:b"] `shouldBe` Just "staff:a;shift:b"
            collapsePayVersionManifests ["staff:b;shift:c", "staff:a;shift:b"]
                `shouldBe` Just "staff:b;shift:c | staff:a;shift:b"

    describe "pay assignment resolver" do
        it "makes staff roster-only absolute" do
            resolvePayAssignment
                (staffAssignment RosterOnly Nothing Nothing)
                (shiftAssignment AwardRate (Just testAwardLevelId) Nothing)
                `shouldBe` EffectiveRosterOnly

        it "applies shift roster-only before rate overrides" do
            resolvePayAssignment
                (staffAssignment AwardRate (Just testAwardLevelId) Nothing)
                (shiftAssignment RosterOnly Nothing Nothing)
                `shouldBe` EffectiveRosterOnly

        it "classifies selector suppression across every selectable mode" do
            let staffAssignments =
                    [ staffAssignment AwardRate (Just testAwardLevelId) Nothing
                    , staffAssignment XeroRate Nothing (Just importedPayItemId)
                    , staffAssignment RosterOnly Nothing Nothing
                    ]
                shiftAssignments =
                    [ shiftAssignment StaffDefault Nothing Nothing
                    , shiftAssignment AwardRate (Just testAwardLevelId) Nothing
                    , shiftAssignment XeroRate Nothing (Just importedPayItemId)
                    , shiftAssignment RosterOnly Nothing Nothing
                    ]
            map staffAssignmentAllowsTimesheets staffAssignments
                `shouldBe` [True, True, False]
            map staffAssignmentSuppressesTimesheets staffAssignments
                `shouldBe` [False, False, True]
            map shiftAssignmentAllowsTimesheets shiftAssignments
                `shouldBe` [True, True, True, False]
            map shiftAssignmentSuppressesTimesheets shiftAssignments
                `shouldBe` [False, False, False, True]
            let actual =
                    [ resolvePayAssignment staff shift == EffectiveRosterOnly
                    | staff <- staffAssignments
                    , shift <- shiftAssignments
                    ]
                expected =
                    [ staffAssignmentSuppressesTimesheets staff || shiftAssignmentSuppressesTimesheets shift
                    | staff <- staffAssignments
                    , shift <- shiftAssignments
                    ]
            actual `shouldBe` expected

        it "prefers a valid shift override to the staff default" do
            resolvePayAssignment
                (staffAssignment AwardRate (Just testAwardLevelId) Nothing)
                (shiftAssignment XeroRate Nothing (Just importedPayItemId))
                `shouldBe` EffectiveXeroRate importedPayItemId

        it "uses the staff rate for staff-default shift types" do
            resolvePayAssignment
                (staffAssignment AwardRate (Just testAwardLevelId) Nothing)
                (shiftAssignment StaffDefault Nothing Nothing)
                `shouldBe` EffectiveAwardRate testAwardLevelId

        it "flags unresolved and unavailable assignments for management remediation" do
            staffPayAssignmentRequiresRemediation [] [] (staffAssignment LegacyUnresolved Nothing Nothing) `shouldBe` True
            staffPayAssignmentRequiresRemediation [testAwardLevelId] [] (staffAssignment AwardRate (Just testAwardLevelId) Nothing) `shouldBe` False
            staffPayAssignmentRequiresRemediation [] [] (staffAssignment AwardRate (Just testAwardLevelId) Nothing) `shouldBe` True
            shiftPayAssignmentRequiresRemediation [] [] (shiftAssignment StaffDefault Nothing Nothing) `shouldBe` False
            shiftPayAssignmentRequiresRemediation [] [] (shiftAssignment XeroRate Nothing (Just importedPayItemId)) `shouldBe` True

        it "keeps reference remediation separate from shape validation across the complete mode universe" do
            let modes = [minBound .. maxBound] :: [PayAssignmentModeEnum]
            modes `shouldBe` [AwardRate, XeroRate, RosterOnly, StaffDefault, LegacyUnresolved]
            forM_
                [ (Nothing, Nothing, [True, True, False, True, True], [True, True, False, False, True])
                , (Just testAwardLevelId, Nothing, [False, True, False, True, True], [False, True, False, False, True])
                , (Nothing, Just importedPayItemId, [True, False, False, True, True], [True, False, False, False, True])
                , (Just testAwardLevelId, Just importedPayItemId, [False, False, False, True, True], [False, False, False, False, True])
                ] \(award, imported, staffExpected, shiftExpected) -> do
                    map (\mode -> staffPayAssignmentRequiresRemediation [testAwardLevelId] [importedPayItemId] (staffAssignment mode award imported)) modes `shouldBe` staffExpected
                    map (\mode -> shiftPayAssignmentRequiresRemediation [testAwardLevelId] [importedPayItemId] (shiftAssignment mode award imported)) modes `shouldBe` shiftExpected

        it "supplies typed database eligibility modes from the same reference policy" do
            payAssignmentModesRequiring StaffPayScope NoPayReference `shouldBe` [RosterOnly]
            payAssignmentModesRequiring ShiftTypePayScope NoPayReference `shouldBe` [RosterOnly, StaffDefault]
            forM_ [StaffPayScope, ShiftTypePayScope] \scope -> do
                payAssignmentModesRequiring scope ActiveAwardReference `shouldBe` [AwardRate]
                payAssignmentModesRequiring scope AvailableXeroReference `shouldBe` [XeroRate]
            payAssignmentModesRequiring StaffPayScope UnselectableAssignment `shouldBe` [StaffDefault, LegacyUnresolved]
            payAssignmentModesRequiring ShiftTypePayScope UnselectableAssignment `shouldBe` [LegacyUnresolved]

        it "surfaces migration-only and malformed configurations" do
            resolvePayAssignment
                (staffAssignment LegacyUnresolved Nothing Nothing)
                (shiftAssignment StaffDefault Nothing Nothing)
                `shouldSatisfy` isInvalidPayAssignment
            resolvePayAssignment
                (staffAssignment AwardRate Nothing Nothing)
                (shiftAssignment StaffDefault Nothing Nothing)
                `shouldSatisfy` isInvalidPayAssignment
            resolvePayAssignment
                (staffAssignment XeroRate Nothing (Just importedPayItemId))
                (shiftAssignment AwardRate (Just testAwardLevelId) (Just importedPayItemId))
                `shouldSatisfy` isInvalidPayAssignment

staffAssignment :: PayAssignmentModeEnum -> Maybe (Id AwardLevel) -> Maybe (Id XeroImportedPayItem) -> StaffPayAssignment
staffAssignment = StaffPayAssignment

shiftAssignment :: PayAssignmentModeEnum -> Maybe (Id AwardLevel) -> Maybe (Id XeroImportedPayItem) -> ShiftPayAssignment
shiftAssignment = ShiftPayAssignment

testAwardLevelId :: Id AwardLevel
testAwardLevelId = Id (fromMaybe UUID.nil (UUID.fromText "10000000-0000-0000-0000-000000000001"))

importedPayItemId :: Id XeroImportedPayItem
importedPayItemId = Id (fromMaybe UUID.nil (UUID.fromText "20000000-0000-0000-0000-000000000001"))

isInvalidPayAssignment :: EffectivePayAssignment -> Bool
isInvalidPayAssignment InvalidPayAssignment {} = True
isInvalidPayAssignment _                       = False
