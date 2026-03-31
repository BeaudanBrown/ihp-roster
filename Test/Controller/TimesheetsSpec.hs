module Test.Controller.TimesheetsSpec where

import Application.Helper.Controller (parseTimeParam)
import Application.Helper.LiveUpdate (LiveUpdateScope (..),
                                      currentLiveUpdateVersion)
import Config
import Data.Time.Calendar (fromGregorian)
import Generated.Types
import IHP.ControllerPrelude
import IHP.FrameworkConfig
import IHP.HaskellSupport
import IHP.ModelSupport (inputValue)
import IHP.Prelude
import IHP.Test.Mocking
import Network.HTTP.Types.Status
import Network.Wai
import Test.Hspec
import Test.Support
import Web.Controller.Timesheets ()
import Web.FrontController ()
import Web.Routes
import Web.Types

tests :: Spec
tests = beforeAll testContext do
    describe "TimesheetsController" do
        it "redirects unauthenticated users from timesheets page" $ withContext do
            response <- callAction TimesheetsAction
            response `responseStatusShouldBe` status302

        it "redirects unauthenticated users from weekly timesheets page" $ withContext do
            response <- callAction ShowTimesheetWeekAction { weekOffset = 0 }
            response `responseStatusShouldBe` status302

        it "redirects unauthenticated users from day-section fragment action" $ withContext do
            response <- callAction ShowTimesheetDaySectionFragmentAction { weekOffset = 0, dayOffset = 0 }
            response `responseStatusShouldBe` status302

        it "redirects unauthenticated users from new timesheet entry" $ withContext do
            response <- callAction NewTimesheetEntryAction
            response `responseStatusShouldBe` status302

        it "redirects unauthenticated users from create timesheet entry" $ withContext do
            response <- callAction CreateTimesheetEntryAction
            response `responseStatusShouldBe` status302

        it "redirects unauthenticated users from approve action" $ withContext do
            let entryId = Id "00000000-0000-0000-0000-000000000000"
            response <- callAction ApproveTimesheetEntryAction { timesheetEntryId = entryId }
            response `responseStatusShouldBe` status302

        it "redirects unauthenticated users from unapprove action" $ withContext do
            let entryId = Id "00000000-0000-0000-0000-000000000000"
            response <- callAction UnapproveTimesheetEntryAction { timesheetEntryId = entryId }
            response `responseStatusShouldBe` status302

        it "renders a subscribed timesheet shell for authenticated viewers" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Venue"
                user <- createUserRecord "timesheet-shell@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user "worker"
                _ <- createStaffRecord venue (Just user) "Tess" "Viewer"

                response <- withUserAndCurrentVenue user venue.id do
                    callAction ShowTimesheetWeekAction { weekOffset = 0 }

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "data-live-update-feature=\"timesheets\""
                response `responseBodyShouldContain` "data-live-update-client-enabled=\"true\""
                response `responseBodyShouldContain` "data-live-update-scope-kind=\"timesheet_week\""
                response `responseBodyShouldContain` "data-timesheet-day-offset=\"0\""

        it "renders HTMX timesheet forms with javascript submission disabled" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Venue"
                user <- createUserRecord "timesheet-form@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user "worker"
                _ <- createStaffRecord venue (Just user) "Tess" "Form"
                payLevel <- createPayLevelRecord venue "Level 1"
                _ <- createShiftTypeRecord venue payLevel "Ordinary"

                response <- withUserAndCurrentVenue user venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams NewTimesheetEntryAction
                            [ ("weekOffset", "0")
                            , ("workedOn", "2025-01-07")
                            ]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "data-disable-javascript-submission=\"true\""

        it "renders explicit delete forms instead of js-delete links on timesheet cards" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Venue"
                user <- createUserRecord "timesheet-delete-form@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user "manager"
                staff <- createStaffRecord venue Nothing "Tess" "Delete"
                entry <- createTimesheetEntryRecord venue staff (fromGregorian 2025 1 7)

                response <- withUserAndCurrentVenue user venue.id do
                    callAction ShowTimesheetWeekAction { weekOffset = 0 }

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` cs (pathTo (DeleteTimesheetEntryAction entry.id))
                response `responseBodyShouldContain` "name=\"_method\" value=\"DELETE\""
                response `responseBodyShouldNotContain` "js-delete"

        it "scopes timesheet day fragments to the current viewer visibility" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Venue"
                manager <- createUserRecord "timesheet-fragment-manager@example.com" "staff" True
                workerAUser <- createUserRecord "timesheet-fragment-worker-a@example.com" "staff" True
                workerBUser <- createUserRecord "timesheet-fragment-worker-b@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                _ <- createVenueMembershipRecord venue workerAUser "worker"
                _ <- createVenueMembershipRecord venue workerBUser "worker"
                workerA <- createStaffRecord venue (Just workerAUser) "Ava" "Hours"
                workerB <- createStaffRecord venue (Just workerBUser) "Bea" "Hours"
                _ <- createTimesheetEntryRecord venue workerA (fromGregorian 2025 1 7)
                _ <- createTimesheetEntryRecord venue workerB (fromGregorian 2025 1 7)

                managerResponse <- withUserAndCurrentVenue manager venue.id do
                    callAction ShowTimesheetDaySectionFragmentAction { weekOffset = 0, dayOffset = 1 }
                workerResponse <- withUserAndCurrentVenue workerAUser venue.id do
                    callAction ShowTimesheetDaySectionFragmentAction { weekOffset = 0, dayOffset = 1 }

                managerResponse `responseStatusShouldBe` status200
                managerResponse `responseBodyShouldContain` "Ava Hours"
                managerResponse `responseBodyShouldContain` "Bea Hours"
                workerResponse `responseStatusShouldBe` status200
                workerResponse `responseBodyShouldContain` "Ava Hours"
                workerResponse `responseBodyShouldNotContain` "Bea Hours"

        it "creating timesheets via HTMX updates the actor fragment and bumps the week scope version" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Venue"
                user <- createUserRecord "timesheet-htmx-create@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user "worker"
                staff <- createStaffRecord venue (Just user) "Tess" "Create"
                payLevel <- createPayLevelRecord venue "Level 1"
                shiftType <- createShiftTypeRecord venue payLevel "Ordinary"

                versionBefore <- currentLiveUpdateVersion TimesheetWeekScope { venueId = unpackId venue.id, weekOffset = 0 }

                response <- withUserAndCurrentVenue user venue.id do
                    withRequestHeaders
                        [ ("HX-Request", "true")
                        , ("X-Live-Update-Client-Id", "timesheet-create-client")
                        ] do
                            callActionWithParams CreateTimesheetEntryAction
                                [ ("weekOffset", "0")
                                , ("staffId", idToParam staff.id)
                                , ("shiftTypeId", idToParam shiftType.id)
                                , ("workedOn", "2025-01-07")
                                , ("startTime", "09:15")
                                , ("endTime", "17:15")
                                ]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "id=\"timesheet-day-section-1\""
                response `responseBodyShouldContain` "Timesheet entry created"
                response `responseBodyShouldContain` "hx-swap-oob=\"outerHTML\""

                versionAfter <- currentLiveUpdateVersion TimesheetWeekScope { venueId = unpackId venue.id, weekOffset = 0 }
                versionAfter `shouldBe` versionBefore + 1

        it "manager review actions bump the timesheet week scope version" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Venue"
                manager <- createUserRecord "timesheet-live-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                staff <- createStaffRecord venue Nothing "Tia" "Shift"
                entry <- createTimesheetEntryRecord venue staff (fromGregorian 2025 1 7)

                versionBefore <- currentLiveUpdateVersion TimesheetWeekScope { venueId = unpackId venue.id, weekOffset = 0 }

                response <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true"), ("X-Live-Update-Client-Id", "timesheet-approve-client")] do
                        callAction ApproveTimesheetEntryAction { timesheetEntryId = entry.id }

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "id=\"timesheet-day-section-1\""
                response `responseBodyShouldNotContain` "id=\"timesheet-day-section-1\" hx-swap-oob="
                versionAfter <- currentLiveUpdateVersion TimesheetWeekScope { venueId = unpackId venue.id, weekOffset = 0 }
                versionAfter `shouldBe` versionBefore + 1

        it "writes an audit event when approving a timesheet entry" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Venue"
                manager <- createUserRecord "timesheet-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                staff <- createStaffRecord venue Nothing "Tia" "Shift"
                entry <- createTimesheetEntryRecord venue staff (fromGregorian 2025 1 7)

                response <- withUserAndCurrentVenue manager venue.id do
                    callAction ApproveTimesheetEntryAction { timesheetEntryId = entry.id }

                response `responseStatusShouldBe` status302

                updatedEntry <- fetch entry.id
                updatedEntry.isApproved `shouldBe` True
                updatedEntry.approvedByUserId `shouldBe` Just (unpackId manager.id)
                updatedEntry.payConfigSnapshotId `shouldSatisfy` isJust

                version <- query @TimesheetEntryVersion |> fetchOne
                inputValue version.versionAction `shouldBe` "approved"
                version.timesheetEntryId `shouldBe` unpackId entry.id
                version.actorUserId `shouldBe` unpackId manager.id

                snapshot <- query @PayConfigSnapshot |> fetchOne
                updatedEntry.payConfigSnapshotId `shouldBe` Just (unpackId snapshot.id)
                snapshot.versionLabel `shouldBe` "v1"

                auditEvent <- query @AuditEvent |> fetchOne
                auditEvent.venueId `shouldBe` unpackId venue.id
                auditEvent.actorUserId `shouldBe` unpackId manager.id
                auditEvent.eventType `shouldBe` "timesheet_approved"
                auditEvent.targetTable `shouldBe` "timesheet_entries"
                auditEvent.targetId `shouldBe` unpackId entry.id
                auditEvent.sourceChannel `shouldBe` "web"

        it "writes an audit event when unapproving a timesheet entry" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Venue"
                manager <- createUserRecord "timesheet-unapprove@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                staff <- createStaffRecord venue Nothing "Una" "Shift"
                entry <- createTimesheetEntryRecord venue staff (fromGregorian 2025 1 8)
                    >>= updateRecord
                        . set #isApproved True
                        . set #approvedByUserId (Just (unpackId manager.id))

                response <- withUserAndCurrentVenue manager venue.id do
                    callAction UnapproveTimesheetEntryAction { timesheetEntryId = entry.id }

                response `responseStatusShouldBe` status302

                updatedEntry <- fetch entry.id
                updatedEntry.isApproved `shouldBe` False
                updatedEntry.approvedByUserId `shouldBe` Nothing
                updatedEntry.payConfigSnapshotId `shouldBe` Nothing

                version <- query @TimesheetEntryVersion |> fetchOne
                inputValue version.versionAction `shouldBe` "unapproved"
                version.timesheetEntryId `shouldBe` unpackId entry.id

                auditEvent <- query @AuditEvent |> fetchOne
                auditEvent.eventType `shouldBe` "timesheet_unapproved"
                auditEvent.targetId `shouldBe` unpackId entry.id

        it "writes an audit event when editing resets a prior approval" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Venue"
                manager <- createUserRecord "timesheet-reset@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                staff <- createStaffRecord venue Nothing "Ria" "Shift"
                payLevel <- createPayLevelRecord venue "Level 1"
                shiftType <- createShiftTypeRecord venue payLevel "Ordinary"
                entry <- createTimesheetEntryRecord venue staff (fromGregorian 2025 1 9)
                    >>= updateRecord
                        . set #isApproved True
                        . set #approvedByUserId (Just (unpackId manager.id))

                response <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams (UpdateTimesheetEntryAction entry.id)
                        [ ("staffId", idToParam staff.id)
                        , ("shiftTypeId", idToParam shiftType.id)
                        , ("workedOn", "2025-01-09")
                        , ("startTime", "09:15")
                        , ("endTime", "17:15")
                        ]

                response `responseStatusShouldBe` status302

                updatedEntry <- fetch entry.id
                updatedEntry.isApproved `shouldBe` False
                parseTimeParam "09:15" `shouldBe` Just updatedEntry.startTime
                parseTimeParam "17:15" `shouldBe` Just updatedEntry.endTime

                version <- query @TimesheetEntryVersion |> fetchOne
                inputValue version.versionAction `shouldBe` "approval_reset"
                version.timesheetEntryId `shouldBe` unpackId entry.id

                auditEvent <- query @AuditEvent |> fetchOne
                auditEvent.eventType `shouldBe` "timesheet_approval_reset"
                auditEvent.targetId `shouldBe` unpackId entry.id

        it "records a version row before deleting an unapproved timesheet entry" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Venue"
                manager <- createUserRecord "timesheet-delete@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                staff <- createStaffRecord venue Nothing "Del" "Shift"
                entry <- createTimesheetEntryRecord venue staff (fromGregorian 2025 1 10)

                response <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams (DeleteTimesheetEntryAction entry.id)
                        [("weekOffset", "0")]

                response `responseStatusShouldBe` status302

                remainingEntries <- query @TimesheetEntry |> fetchCount
                remainingEntries `shouldBe` 0

                version <- query @TimesheetEntryVersion |> fetchOne
                inputValue version.versionAction `shouldBe` "deleted"
                version.timesheetEntryId `shouldBe` unpackId entry.id

        it "blocks deleting an approved timesheet entry" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Venue"
                manager <- createUserRecord "timesheet-protected-delete@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                staff <- createStaffRecord venue Nothing "Ada" "Shift"
                entry <- createTimesheetEntryRecord venue staff (fromGregorian 2025 1 11)
                    >>= updateRecord
                        . set #isApproved True
                        . set #approvedByUserId (Just (unpackId manager.id))

                response <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams (DeleteTimesheetEntryAction entry.id)
                        [("weekOffset", "0")]

                response `responseStatusShouldBe` status302

                remainingEntries <- query @TimesheetEntry |> fetchCount
                remainingEntries `shouldBe` 1

                versionCount <- query @TimesheetEntryVersion |> fetchCount
                versionCount `shouldBe` 0
