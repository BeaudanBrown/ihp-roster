module Test.RecipientGroupsSpec where

import Application.RecipientGroups
import qualified Application.RecipientGroups as Groups
import Application.PayrollReports.Generation (generatePayrollReportSnapshot)
import Application.PayrollReports.Settings (payrollReportRunIsCurrent)
import Application.Helper.Export.PayrollWorkbookConfiguration (createStandardPayrollWorkbookConfigurationInCurrentTransaction, SavedPayrollWorkbookConfiguration (..))
import Application.Helper.ControllerContext (currentVenueMembershipOrNothing, currentVenueSessionKey)
import Application.EmailDelivery.Group
import Control.Concurrent.Async (concurrently)
import Control.Monad (void)
import Data.Either (isLeft)
import Data.IORef
import qualified Data.Text as Text
import Generated.Types
import IHP.ControllerPrelude
import IHP.Test.Mocking (withContext, withUser)
import Test.Hspec
import Test.Support
import Test.PayrollWorkbookConfigurationSpec (asCurrentVenueUser, expectRight)

input :: RecipientGroupInput
input = RecipientGroupInput
    { name = " Payroll   contacts "
    , recipients = [" Accountant@Example.com ", "accountant@example.com"]
    , expectedRevision = Nothing
    }

tests :: Spec
tests = aroundAll withDatabaseTestContext do
    describe "Recipient groups" do
        it "normalizes names and addresses, rejects invalid lists, and enforces the group bounds" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Groups"
                admin <- createUserRecord "groups-admin@example.com" "admin" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin
                asCurrentVenueUser admin venue.id do
                    saved <- saveRecipientGroup Nothing input >>= expectRight
                    saved.name `shouldBe` "Payroll contacts"
                    saved.recipients `shouldBe` ["accountant@example.com"]
                    saved.createdByUserId `shouldBe` unpackId admin.id
                    saved.updatedByUserId `shouldBe` unpackId admin.id
                    saved.revision `shouldBe` 0
                    fetchRecipientGroup saved.id `shouldReturn` Right saved
                    listRecipientGroups `shouldReturn` Right [saved]
                    forM_ [[], [""], ["not-an-email"], ["x@example.com\r\nBcc: y@example.com"], ["Name <x@example.com>"], replicate 51 "x@example.com"] \addresses ->
                        saveRecipientGroup Nothing (input { Groups.recipients = addresses }) >>= (`shouldSatisfy` isLeft)
                    forM_ ["  ", Text.replicate 101 "x"] \name ->
                        saveRecipientGroup Nothing (input { Groups.name = name }) >>= (`shouldSatisfy` isLeft)
                    let fifty = ["person" <> tshow index <> "@example.com" | index <- [1..50 :: Int]]
                    full <- saveRecipientGroup Nothing (input { Groups.name = "Fifty", Groups.recipients = fifty }) >>= expectRight
                    length full.recipients `shouldBe` 50
                    query @RecipientGroup |> fetchCount `shouldReturn` 2

        it "rejects duplicate names and stale edits, and permits name reuse after logical deletion" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Groups"
                admin <- createUserRecord "groups-admin@example.com" "admin" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin
                asCurrentVenueUser admin venue.id do
                    saved <- saveRecipientGroup Nothing input >>= expectRight
                    saveRecipientGroup Nothing (input { Groups.name = "PAYROLL contacts" }) `shouldReturn` Left RecipientGroupNameConflict
                    saveRecipientGroup Nothing (input { Groups.name = "New", Groups.expectedRevision = Just 0 }) `shouldReturn` Left RecipientGroupStale
                    updated <- saveRecipientGroup (Just saved.id) (input { Groups.name = "Renamed", Groups.expectedRevision = Just 0 }) >>= expectRight
                    updated.revision `shouldBe` 1
                    updated.createdAt `shouldBe` saved.createdAt
                    saveRecipientGroup (Just saved.id) (input { Groups.expectedRevision = Just 0 }) `shouldReturn` Left RecipientGroupStale
                    deleteRecipientGroup saved.id 0 True `shouldReturn` Left RecipientGroupStale
                    deleteRecipientGroup saved.id 1 False `shouldReturn` Right ()
                    listRecipientGroups `shouldReturn` Right []
                    fetchRecipientGroup saved.id `shouldReturn` Left RecipientGroupNotFound
                    saveRecipientGroup (Just saved.id) (input { Groups.expectedRevision = Just 2 }) `shouldReturn` Left RecipientGroupNotFound
                    archived <- fetch saved.id
                    archived.archivedAt `shouldSatisfy` isJust
                    archived.recipients `shouldBe` saved.recipients
                    archived.revision `shouldBe` 2
                    _ <- saveRecipientGroup Nothing (input { Groups.name = "Renamed" }) >>= expectRight
                    query @RecipientGroup |> fetchCount `shouldReturn` 2

        it "serializes simultaneous same-name creation without duplicate records or raw constraint errors" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Concurrent groups"
                admin <- createUserRecord "groups-admin@example.com" "admin" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin
                (first, second) <- concurrently
                    (asCurrentVenueUser admin venue.id (saveRecipientGroup Nothing input))
                    (asCurrentVenueUser admin venue.id (saveRecipientGroup Nothing input))
                let successCount = length [() | Right _ <- [first, second]]
                successCount `shouldBe` 1
                [failure | Left failure <- [first, second]] `shouldBe` [RecipientGroupNameConflict]
                query @RecipientGroup |> fetchCount `shouldReturn` 1

        it "allows owners/admins and venue-scoped support without granting group members app authority" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Group authority"
                owner <- createUserRecord "groups-owner@example.com" "admin" True
                manager <- createUserRecord "accountant@example.com" "manager" True
                staff <- createUserRecord "groups-staff@example.com" "staff" True
                founder <- createUserRecordWithPlatformRole "groups-founder@example.com" "staff" (Just SuperAdmin) True
                _ <- createVenueMembershipRecord venue owner VenueOwner
                _ <- createVenueMembershipRecord venue manager Manager
                _ <- createVenueMembershipRecord venue staff Worker
                saved <- asCurrentVenueUser owner venue.id (saveRecipientGroup Nothing input) >>= expectRight
                forM_ [manager, staff] \user -> asCurrentVenueUser user venue.id do
                    listRecipientGroups `shouldReturn` Left RecipientGroupAccessDenied
                    fetchRecipientGroup saved.id `shouldReturn` Left RecipientGroupAccessDenied
                    saveRecipientGroup Nothing input `shouldReturn` Left RecipientGroupAccessDenied
                    saveRecipientGroup (Just saved.id) (input { Groups.expectedRevision = Just 0 }) `shouldReturn` Left RecipientGroupAccessDenied
                    deleteRecipientGroup saved.id 0 True `shouldReturn` Left RecipientGroupAccessDenied
                withUser founder do
                    withSessionValues [(currentVenueSessionKey, "")] do
                        withCurrentControllerContext listRecipientGroups `shouldReturn` Left RecipientGroupAccessDenied
                asCurrentVenueUser founder venue.id do
                    currentVenueMembershipOrNothing `shouldBe` Nothing
                    listRecipientGroups `shouldReturn` Right [saved]
                    updated <- saveRecipientGroup (Just saved.id) (input { Groups.expectedRevision = Just 0 }) >>= expectRight
                    updated.updatedByUserId `shouldBe` unpackId founder.id
                    deleteRecipientGroup updated.id updated.revision False `shouldReturn` Right ()

        it "rejects foreign group IDs and permits the same name in different venues" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "First"
                other <- createVenueWithConfig "Other"
                admin <- createUserRecord "groups-admin@example.com" "admin" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin
                _ <- createVenueMembershipRecord other admin VenueAdmin
                foreignGroup :: RecipientGroup <- asCurrentVenueUser admin other.id (saveRecipientGroup Nothing input) >>= expectRight
                asCurrentVenueUser admin venue.id do
                    listRecipientGroups `shouldReturn` Right []
                    fetchRecipientGroup foreignGroup.id `shouldReturn` Left RecipientGroupNotFound
                    saveRecipientGroup (Just foreignGroup.id) (input { Groups.expectedRevision = Just 0 }) `shouldReturn` Left RecipientGroupNotFound
                    deleteRecipientGroup foreignGroup.id 0 True `shouldReturn` Left RecipientGroupNotFound
                    _ <- saveRecipientGroup Nothing input >>= expectRight
                    pure ()
                fetch foreignGroup.id `shouldReturn` foreignGroup

        it "preserves prepared snapshots on edits and only cancels automatic work on confirmed linked deletion" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Snapshot groups"
                admin <- createUserRecord "groups-admin@example.com" "admin" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin
                group <- asCurrentVenueUser admin venue.id (saveRecipientGroup Nothing input) >>= expectRight
                template <- createStandardPayrollWorkbookConfigurationInCurrentTransaction venue admin
                setting <- newRecord @PayrollReportSetting
                    |> set #venueId (unpackId venue.id)
                    |> set #configurationId (Just (unpackId template.savedPayrollWorkbookConfigurationRecord.id))
                    |> set #recipientGroupId (Just (unpackId group.id))
                    |> set #recipients group.recipients
                    |> set #enabled True
                    |> set #scheduleActivatedAt (UTCTime (fromGregorian 2024 12 1) 0)
                    |> set #updatedByUserId (unpackId admin.id) |> createRecord
                let due = UTCTime (fromGregorian 2025 1 13) (22 * 3600)
                let now = addUTCTime 60 due
                let week = fromGregorian 2025 1 6
                automatic <- generatePayrollReportSnapshot venue.id (unpackId admin.id) PayrollReportScheduled (Just due) week now >>= expectRight
                manual <- generatePayrollReportSnapshot venue.id (unpackId admin.id) PayrollReportManual Nothing week now >>= expectRight
                updatedSend <- generatePayrollReportSnapshot venue.id (unpackId admin.id) PayrollReportUpdated Nothing week now >>= expectRight
                terminalRuns <- forM (zip [1, 2 :: Int] [PayrollReportAccepted, PayrollReportAmbiguous]) \(offset, status) -> do
                    let earlier = addUTCTime (fromIntegral (-604800 * offset))
                    run <- generatePayrollReportSnapshot venue.id (unpackId admin.id) PayrollReportScheduled
                        (Just (earlier due)) (addDays (fromIntegral (-7 * offset)) week) (earlier now) >>= expectRight
                    run |> set #status status |> updateRecord
                enqueuePayrollReportOutcome manual
                queuedManual <- fetch manual.id
                group <- asCurrentVenueUser admin venue.id (saveRecipientGroup (Just group.id) (input { Groups.recipients = ["new@example.com"], Groups.expectedRevision = Just 0 })) >>= expectRight
                fetch setting.id `shouldReturn` setting
                fetch automatic.id `shouldReturn` automatic
                fetch manual.id `shouldReturn` queuedManual
                fetch updatedSend.id `shouldReturn` updatedSend
                asCurrentVenueUser admin venue.id do
                    deleteRecipientGroup group.id group.revision False `shouldReturn` Left RecipientGroupScheduleConfirmationRequired
                    fetch setting.id `shouldReturn` setting
                    fetchRecipientGroup group.id `shouldReturn` Right group
                    deleteRecipientGroup group.id group.revision True `shouldReturn` Right ()
                current <- fetch setting.id
                current.enabled `shouldBe` False
                current.recipientGroupId `shouldBe` Nothing
                current.recipients `shouldBe` setting.recipients
                current.configurationId `shouldBe` setting.configurationId
                current.minuteOfDay `shouldBe` setting.minuteOfDay
                current.revision `shouldBe` (setting.revision + 1)
                current.deliveryRevision `shouldBe` setting.deliveryRevision
                cancelled <- fetch automatic.id
                cancelled.status `shouldBe` PayrollReportCancelled
                cancelled.recipients `shouldBe` automatic.recipients
                fetch manual.id `shouldReturn` queuedManual
                fetch updatedSend.id `shouldReturn` updatedSend
                forM_ terminalRuns \run -> fetch run.id `shouldReturn` run
                payrollReportRunIsCurrent current manual `shouldBe` True
                payrollReportRunIsCurrent current updatedSend `shouldBe` True
                sent <- newIORef (0 :: Int)
                job <- query @AppJob |> filterWhere (#relatedId, Just (unpackId manual.id)) |> filterWhere (#payloadSchemaVersion, 2) |> fetchOne
                performGroupEmailDeliveryWith (GroupDeliveryRuntime (pure False) (\_ -> modifyIORef' sent (+ 1))) job
                readIORef sent `shouldReturn` 1
                void (fetch group.id)
