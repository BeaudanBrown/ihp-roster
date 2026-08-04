module Test.AuditSpec where

import qualified Data.Aeson as Aeson
import Generated.Types
import IHP.ControllerPrelude
import IHP.Test.Mocking (withContext)
import Test.Hspec

import Application.Helper.Audit
import Application.Helper.ControllerContext (ImpersonationRequestContext (..))
import Application.Helper.Impersonation
import Test.Support

tests :: Spec
tests = aroundAll withDatabaseTestContext do
    describe "current-user audit context" do
        it "persists founder support mode while retaining the authenticated actor and caller payload" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Support Audit Venue"
                superAdmin <- createUserRecordWithPlatformRole "support-audit@example.com" "staff" (Just SuperAdmin) True

                _ <- withUserAndCurrentVenue superAdmin venue.id do
                    withCurrentControllerContext do
                        recordCurrentUserAuditEvent
                            SupportAccessGrantedAudit
                            "venues"
                            (unpackId venue.id)
                            (Aeson.object ["reason" Aeson..= ("diagnostic" :: Text)])

                auditEvent <- query @AuditEvent |> fetchOne
                auditEvent.actorUserId `shouldBe` unpackId superAdmin.id
                auditEvent.payload `shouldBe`
                    Aeson.object
                        [ "reason" Aeson..= ("diagnostic" :: Text)
                        , "requestContext" Aeson..= Aeson.object
                            ["accessMode" Aeson..= ("support" :: Text)]
                        ]

        it "persists founder support mode in dedicated timesheet and leave audit records" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Dedicated Support Audit Venue"
                superAdmin <- createUserRecordWithPlatformRole "dedicated-support-audit@example.com" "staff" (Just SuperAdmin) True
                staff <- createStaffRecord venue Nothing "Support" "Target"
                timesheetEntry <- createTimesheetEntryRecord venue staff (fromGregorian 2026 8 3)
                leaveRequest <- createLeaveRequestRecord venue staff (fromGregorian 2026 8 4) (fromGregorian 2026 8 5) LeaveRequestStatusEnumPending

                _ <- withUserAndCurrentVenue superAdmin venue.id do
                    withCurrentControllerContext do
                        _ <- recordCurrentUserTimesheetEntryVersion
                            EntryVersionActionEnumCreated
                            timesheetEntry
                            (Aeson.object ["reason" Aeson..= ("diagnostic" :: Text)])
                        recordCurrentUserLeaveRequestEvent
                            leaveRequest
                            LeaveRequestEventTypeEnumCreated
                            Nothing
                            (Just LeaveRequestStatusEnumPending)
                            Aeson.Null

                timesheetVersion <- query @TimesheetEntryVersion |> fetchOne
                timesheetVersion.actorUserId `shouldBe` unpackId superAdmin.id
                timesheetVersion.payload `shouldBe`
                    Aeson.object
                        [ "reason" Aeson..= ("diagnostic" :: Text)
                        , "requestContext" Aeson..= Aeson.object
                            ["accessMode" Aeson..= ("support" :: Text)]
                        ]

                leaveEvent <- query @LeaveRequestEvent |> fetchOne
                leaveEvent.actorUserId `shouldBe` unpackId superAdmin.id
                leaveEvent.payload `shouldBe`
                    Aeson.object
                        [ "payload" Aeson..= Aeson.Null
                        , "requestContext" Aeson..= Aeson.object
                            ["accessMode" Aeson..= ("support" :: Text)]
                        ]

        it "persists founder support mode in current-user venue role audit records" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Role Support Audit Venue"
                superAdmin <- createUserRecordWithPlatformRole "role-support-audit@example.com" "staff" (Just SuperAdmin) True
                targetUser <- createUserRecord "role-support-target@example.com" "staff" True
                membership <- createVenueMembershipRecord venue targetUser Manager
                let details = Aeson.object ["staffId" Aeson..= ("staff-123" :: Text)]

                updatedMembership <- withUserAndCurrentVenue superAdmin venue.id do
                    withCurrentControllerContext do
                        updateCurrentUserVenueMembershipRoleWithAuditInCurrentTransaction
                            WebAuditSource
                            membership
                            VenueAdmin
                            details

                updatedMembership.venueRole `shouldBe` VenueAdmin

                auditEvent <- query @AuditEvent |> fetchOne
                auditEvent.actorUserId `shouldBe` unpackId superAdmin.id
                auditEvent.payload `shouldBe`
                    Aeson.object
                        [ "previousRole" Aeson..= ("manager" :: Text)
                        , "newRole" Aeson..= ("venue_admin" :: Text)
                        , "details" Aeson..= details
                        , "requestContext" Aeson..= Aeson.object
                            ["accessMode" Aeson..= ("support" :: Text)]
                        ]

                roleEvent <- query @VenueMembershipRoleEvent |> fetchOne
                roleEvent.actorUserId `shouldBe` unpackId superAdmin.id
                roleEvent.payload `shouldBe`
                    Aeson.object
                        [ "staffId" Aeson..= ("staff-123" :: Text)
                        , "requestContext" Aeson..= Aeson.object
                            ["accessMode" Aeson..= ("support" :: Text)]
                        ]

        it "persists actual actor and effective impersonation provenance on mutations" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Impersonation Mutation Audit Venue"
                superAdmin <- createUserRecordWithPlatformRole "impersonation-mutation-audit@example.com" "staff" (Just SuperAdmin) True
                targetUser <- createUserRecord "impersonation-mutation-target@example.com" "staff" True
                _ <- createVenueMembershipRecord venue targetUser Manager

                mutationEvent <- withUserAndCurrentVenue superAdmin venue.id do
                    withCurrentControllerContext do
                        Just impersonationContext <- enterCurrentVenueImpersonation targetUser.id
                        event <- recordCurrentUserAuditEvent
                            ExportGeneratedAudit
                            "export_jobs"
                            (unpackId targetUser.id)
                            (Aeson.object ["format" Aeson..= ("csv" :: Text)])
                        event.payload `shouldBe`
                            Aeson.object
                                [ "format" Aeson..= ("csv" :: Text)
                                , "requestContext" Aeson..= Aeson.object
                                    [ "accessMode" Aeson..= ("impersonation" :: Text)
                                    , "effectiveUserId" Aeson..= targetUser.id
                                    , "impersonationSessionId" Aeson..= impersonationContext.impersonationSessionId
                                    ]
                                ]
                        pure event

                mutationEvent.actorUserId `shouldBe` unpackId superAdmin.id

        it "leaves ordinary venue-member audit payloads unchanged" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Member Audit Venue"
                manager <- createUserRecord "member-audit@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                let payload = Aeson.object ["reason" Aeson..= ("routine" :: Text)]

                _ <- withUserAndCurrentVenue manager venue.id do
                    withCurrentControllerContext do
                        recordCurrentUserAuditEvent
                            VenueRoleChangedAudit
                            "venues"
                            (unpackId venue.id)
                            payload

                auditEvent <- query @AuditEvent |> fetchOne
                auditEvent.actorUserId `shouldBe` unpackId manager.id
                auditEvent.payload `shouldBe` payload
