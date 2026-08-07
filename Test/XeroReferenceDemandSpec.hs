module Test.XeroReferenceDemandSpec where

import Application.Xero.ReferenceDemand
import Application.Xero.ReferenceTrust
import Data.Time.Clock (addUTCTime)
import Data.Time.LocalTime (TimeOfDay (..))
import Generated.Types
import IHP.ControllerPrelude
import IHP.Prelude
import IHP.Test.Mocking
import Test.Hspec
import Test.Support
import qualified Test.XeroTimesheetPreviewSpec as Preview
import Web.FrontController ()
import Web.Routes
import Web.Types

tests :: Spec
tests = aroundAll withDatabaseTestContext do
    describe "Xero reference demand" do
        it "uses approval-pinned pay versions and excludes roster-only work without approved payroll entries" $ withContext do
            withCleanDb do
                fixture <- Preview.createPreviewFixture "weekly" [Preview.EntrySpec 0 Preview.fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 13 0 0)]
                entry <- maybe (error "Expected approved fixture entry") pure (listToMaybe fixture.entries)
                mapping <- query @XeroStaffMapping |> filterWhere (#staffId, entry.staffId) |> fetchOne
                _ <- mapping
                    |> set #mappingStatus XeroStaffMappingStatusEnumStale
                    |> set #xeroEmployeeId Nothing
                    |> set #updatedByUserId Nothing
                    |> updateRecord
                staff <- fetch (Id entry.staffId :: Id Staff)
                _ <- staff
                    |> set #payAssignmentMode RosterOnly
                    |> set #defaultAwardLevelId Nothing
                    |> set #importedXeroPayItemId Nothing
                    |> updateRecord

                pinnedDemand <- fetchXeroMissingReferenceDemand fixture.connection
                pinnedDemand `shouldBe` MissingPayrollEligibleStaffReference
                eligibleStaffIds <- fetchXeroPayrollEligibleApprovedStaffIds fixture.connection
                eligibleStaffIds `shouldBe` [entry.staffId]

                refreshedAt <- getCurrentTime
                _ <- mapping |> set #referenceRefreshedAt (Just refreshedAt) |> updateRecord
                _ <- staff |> set #firstName "Ada updated after approval" |> updateRecord
                fetchXeroMissingReferenceDemand fixture.connection `shouldReturn` NoMissingPayrollReferenceDemand

                approvedAfterRefresh <- entry |> set #approvedAt (Just (addUTCTime 1 refreshedAt)) |> updateRecord
                fetchXeroMissingReferenceDemand fixture.connection `shouldReturn` MissingPayrollEligibleStaffReference
                _ <- mapping |> set #referenceRefreshedAt (Just (addUTCTime 2 refreshedAt)) |> updateRecord
                fetchXeroMissingReferenceDemand fixture.connection `shouldReturn` NoMissingPayrollReferenceDemand

                _ <- approvedAfterRefresh
                    |> set #isApproved False
                    |> set #activePayCalculationId Nothing
                    |> set #legacyPayBackfillPending False
                    |> set #staffPayVersionId Nothing
                    |> set #shiftTypePayVersionId Nothing
                    |> set #approvedAt Nothing
                    |> set #approvedByUserId Nothing
                    |> updateRecord

                rosterOnlyDemand <- fetchXeroMissingReferenceDemand fixture.connection
                rosterOnlyDemand `shouldBe` NoMissingPayrollReferenceDemand
                fetchXeroPayrollEligibleApprovedStaffIds fixture.connection `shouldReturn` []
