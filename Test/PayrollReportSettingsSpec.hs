module Test.PayrollReportSettingsSpec where

import Application.PayrollReports.Settings
import Application.PayrollReports.Manual (requestManualPayrollReport, completedPayrollReportWeeks)
import qualified Application.PayrollReports.Settings as Settings
import qualified Application.RecipientGroups as Groups
import Application.Helper.Export.PayrollWorkbookConfiguration
import qualified Data.Aeson as Aeson
import Data.Either (isLeft)
import Generated.Types
import IHP.ControllerPrelude
import IHP.Test.Mocking (withContext)
import Test.Hspec
import Test.Support
import Test.PayrollWorkbookConfigurationSpec (asCurrentVenueUser, expectRight, newConfiguration)

input :: PayrollReportSettingsInput
input = PayrollReportSettingsInput
    { configurationId = Nothing, recipientGroupId = Nothing, enabled = False, expectedRevision = Nothing }

-- Shared fixture for scheduler/generation tests; create real authorised groups
-- and selections, then optionally disable without discarding those selections.
saveSettingsForTemplate :: (?context :: ControllerContext, ?modelContext :: ModelContext) => UUID -> Bool -> IO (Either PayrollReportSettingsError PayrollReportSetting)
saveSettingsForTemplate templateId automatic = do
    group <- Groups.saveRecipientGroup Nothing (Groups.RecipientGroupInput "Payroll recipients" ["payroll@example.com"] Nothing) >>= expectRight
    outcome <- savePayrollReportSettings (input
        { Settings.configurationId = Just templateId, Settings.recipientGroupId = Just (unpackId group.id), Settings.enabled = True })
    case outcome of
        Right saved | not automatic -> savePayrollReportSettings (input { expectedRevision = Just saved.revision })
        _ -> pure outcome

tests :: Spec
tests = aroundAll withDatabaseTestContext do
    describe "Payroll report settings" do
        it "offers completed calendar weeks newest first, including empty weeks and year boundaries" $ withContext do
            completedPayrollReportWeeks 3 (fromGregorian 2025 1 15) (fromGregorian 2024 12 26)
                `shouldBe` [fromGregorian 2025 1 8, fromGregorian 2025 1 1, fromGregorian 2024 12 25]
            completedPayrollReportWeeks 0 (fromGregorian 2025 1 18) (fromGregorian 2025 1 18)
                `shouldBe` [fromGregorian 2025 1 5]

        it "normalizes recipients and rejects injection, malformed addresses and excessive lists" $ withContext do
            validatePayrollReportRecipients [" Payroll@Example.com ", "payroll@example.com"] `shouldBe` Right ["payroll@example.com"]
            mapM_ (\addresses -> validatePayrollReportRecipients addresses `shouldSatisfy` isLeft)
                [["missing-at"], ["x@example.com\r\nBcc: other@example.com"], ["Person <x@example.com>"], replicate 51 "x@example.com"]

        it "saves disabled empty settings at 06:00 and rejects stale edits" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Reports"
                admin <- createUserRecord "reports-admin@example.com" "admin" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin
                asCurrentVenueUser admin venue.id do
                    saved <- savePayrollReportSettings input >>= expectRight
                    saved.enabled `shouldBe` False
                    saved.recipients `shouldBe` []
                    saved.configurationId `shouldBe` Nothing
                    saved.recipientGroupId `shouldBe` Nothing
                    saved.minuteOfDay `shouldBe` 360
                    savePayrollReportSettings input `shouldReturn` Left PayrollReportStaleSettings
                    updated <- savePayrollReportSettings (input { expectedRevision = Just saved.revision }) >>= expectRight
                    updated.revision `shouldBe` saved.revision + 1
                    updated.deliveryRevision `shouldBe` saved.deliveryRevision
                    query @PayrollReportSetting |> fetchCount `shouldReturn` 1

        it "requires active venue-owned template/group selections and derives the day from the venue calendar" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Reports"
                other <- createVenueWithConfig "Other"
                admin <- createUserRecord "reports-admin@example.com" "admin" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin
                _ <- createVenueMembershipRecord other admin VenueAdmin
                foreignTemplate <- asCurrentVenueUser admin other.id (createSavedPayrollWorkbookConfiguration (newConfiguration "Foreign" 1 ["summary"])) >>= expectRight
                foreignGroup <- asCurrentVenueUser admin other.id (Groups.saveRecipientGroup Nothing (Groups.RecipientGroupInput "Other group" ["other@example.com"] Nothing)) >>= expectRight
                asCurrentVenueUser admin venue.id do
                    savePayrollReportSettings (input { Settings.enabled = True }) `shouldReturn` Left PayrollReportTemplateUnavailable
                    savePayrollReportSettings (input { Settings.enabled = True, Settings.configurationId = Just (unpackId foreignTemplate.savedPayrollWorkbookConfigurationRecord.id) })
                        `shouldReturn` Left PayrollReportTemplateUnavailable
                    template <- createSavedPayrollWorkbookConfiguration (newConfiguration "Local" 1 ["summary"]) >>= expectRight
                    let enabledInput = input { Settings.enabled = True, Settings.configurationId = Just (unpackId template.savedPayrollWorkbookConfigurationRecord.id) }
                    savePayrollReportSettings enabledInput `shouldReturn` Left PayrollReportRecipientGroupUnavailable
                    savePayrollReportSettings (enabledInput { Settings.recipientGroupId = Just (unpackId foreignGroup.id) }) `shouldReturn` Left PayrollReportRecipientGroupUnavailable
                    group <- Groups.saveRecipientGroup Nothing (Groups.RecipientGroupInput "Local group" ["payroll@example.com"] Nothing) >>= expectRight
                    config <- query @VenueConfig |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                    _ <- config |> set #rosterWeekStartsOn 3 |> updateRecord
                    saved <- savePayrollReportSettings (enabledInput { Settings.recipientGroupId = Just (unpackId group.id) }) >>= expectRight
                    saved.enabled `shouldBe` True
                    saved.weekday `shouldBe` 3
                    saved.minuteOfDay `shouldBe` 360
                    Groups.deleteRecipientGroup group.id group.revision True `shouldReturn` Right ()
                    disabled <- fetch saved.id
                    savePayrollReportSettings (enabledInput { Settings.recipientGroupId = Just (unpackId group.id), expectedRevision = Just disabled.revision })
                        `shouldReturn` Left PayrollReportRecipientGroupUnavailable

        it "preserves disabled selections and non-default existing time without revoking prepared explicit sends" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Preserved schedule"
                admin <- createUserRecord "schedule-preserve@example.com" "admin" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin
                asCurrentVenueUser admin venue.id do
                    template <- createSavedPayrollWorkbookConfiguration (newConfiguration "Payroll" 1 ["summary"]) >>= expectRight
                    saved <- saveSettingsForTemplate (unpackId template.savedPayrollWorkbookConfigurationRecord.id) True >>= expectRight
                    saved <- saved |> set #minuteOfDay 570 |> updateRecord
                    runs <- forM [PayrollReportScheduled, PayrollReportManual, PayrollReportUpdated] \origin ->
                        newRecord @PayrollReportRun |> set #venueId (unpackId venue.id) |> set #settingsId (Just (unpackId saved.id))
                            |> set #reportingWeek (fromGregorian 2025 1 6) |> set #rangeEnd (fromGregorian 2025 1 12)
                            |> set #origin origin |> set #status PayrollReportQueued |> set #recipients ["frozen@example.com"]
                            |> set #templateSnapshot (Aeson.object []) |> set #deliveryRevision saved.deliveryRevision
                            |> set #scheduleActivatedAt saved.scheduleActivatedAt |> set #scheduledAt (Just saved.scheduleActivatedAt)
                            |> set #requestedByUserId (unpackId admin.id) |> createRecord
                    disabled <- savePayrollReportSettings (input { expectedRevision = Just saved.revision }) >>= expectRight
                    disabled.enabled `shouldBe` False
                    disabled.configurationId `shouldBe` saved.configurationId
                    disabled.recipientGroupId `shouldBe` saved.recipientGroupId
                    disabled.recipients `shouldBe` saved.recipients
                    disabled.minuteOfDay `shouldBe` 570
                    disabled.deliveryRevision `shouldBe` saved.deliveryRevision
                    forM_ runs \run -> do
                        retained <- fetch run.id
                        retained.status `shouldBe` (if run.origin == PayrollReportScheduled then PayrollReportCancelled else PayrollReportQueued)
                        retained.recipients `shouldBe` run.recipients
                    enabled <- savePayrollReportSettings (input { Settings.enabled = True, Settings.configurationId = saved.configurationId
                        , Settings.recipientGroupId = saved.recipientGroupId, expectedRevision = Just disabled.revision }) >>= expectRight
                    enabled.minuteOfDay `shouldBe` 570
                    enabled.scheduleActivatedAt `shouldSatisfy` (>= disabled.scheduleActivatedAt)

        it "denies managers and keeps settings venue-scoped" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Reports"
                other <- createVenueWithConfig "Other"
                manager <- createUserRecord "reports-manager@example.com" "manager" True
                _ <- createVenueMembershipRecord venue manager Manager
                asCurrentVenueUser manager venue.id do
                    savePayrollReportSettings input `shouldReturn` Left PayrollReportAccessDenied
                    fetchPayrollReportSettings `shouldReturn` Left PayrollReportAccessDenied
                    requestManualPayrollReport "22222222-2222-4222-8222-222222222224" 0 (fromGregorian 2025 1 6) Nothing
                        `shouldReturn` Left "Payroll report access denied."
                admin <- createUserRecord "reports-admin@example.com" "admin" True
                _ <- createVenueMembershipRecord venue admin VenueOwner
                _ <- createVenueMembershipRecord other admin VenueAdmin
                _ <- asCurrentVenueUser admin venue.id (savePayrollReportSettings input) >>= expectRight
                asCurrentVenueUser admin other.id fetchPayrollReportSettings `shouldReturn` Right Nothing

        it "requires deletion confirmation and disables the selected template without revoking explicit snapshots" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Reports"
                admin <- createUserRecord "reports-admin@example.com" "admin" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin
                asCurrentVenueUser admin venue.id do
                    template <- createSavedPayrollWorkbookConfiguration (newConfiguration "Payroll" 1 ["summary"]) >>= expectRight
                    let templateId = template.savedPayrollWorkbookConfigurationRecord.id
                    saved <- saveSettingsForTemplate (unpackId templateId) True >>= expectRight
                    deleteSavedPayrollWorkbookConfiguration templateId `shouldReturn` Left PayrollWorkbookConfigurationScheduleConfirmationRequired
                    deleteSavedPayrollWorkbookConfigurationConfirmingScheduleDisable True templateId `shouldReturn` Right ()
                    updated <- fetch saved.id
                    updated.enabled `shouldBe` False
                    updated.configurationId `shouldBe` Nothing
                    updated.recipientGroupId `shouldBe` saved.recipientGroupId
                    updated.recipients `shouldBe` saved.recipients
                    updated.weekday `shouldBe` saved.weekday
                    updated.deliveryRevision `shouldBe` saved.deliveryRevision
