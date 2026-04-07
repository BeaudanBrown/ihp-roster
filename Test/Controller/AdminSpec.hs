module Test.Controller.AdminSpec where

import Application.Helper.RosterGroups (createVenueRosterGroupWithDefaults,
                                        fetchActiveRosterGroupSlotNames)
import Config
import qualified Data.Aeson as Aeson
import Data.Time.Clock (diffUTCTime, getCurrentTime)
import Generated.Types
import IHP.ControllerPrelude
import IHP.FrameworkConfig
import IHP.HaskellSupport
import IHP.Prelude
import IHP.Test.Mocking
import Network.HTTP.Types.Status
import Test.Hspec
import Test.Support
import Web.Controller.Admin ()
import Web.FrontController ()
import Web.Routes
import Web.Types

tests :: Spec
tests = beforeAll testContext do
    describe "AdminController" do
        it "redirects unauthenticated users from admin page" $ withContext do
            response <- callAction AdminAction
            response `responseStatusShouldBe` status302

        it "shows config-table sections and only current-venue config rows" $ withContext do
            withCleanDb do
                venueA <- createVenueWithConfig "Venue A"
                venueB <- createVenueWithConfig "Venue B"
                admin <- createUserRecord "admin-page@example.com" "staff" True
                _ <- createVenueMembershipRecord venueA admin "venue_admin"
                _ <- createVenueMembershipRecord venueB admin "venue_admin"

                payLevelA <- createPayLevelRecord venueA "Level A"
                dayNameA <- fetchDayNameRecord venueA 1
                shiftTypeA <- createShiftTypeRecord venueA payLevelA "Kitchen"
                _ <- createPayLevelDayRuleRecord shiftTypeA dayNameA payLevelA
                _ <- createSlotNameRecord venueA "Default Only"
                venueAGroupB <- createVenueRosterGroupWithDefaults venueA "Back of House" 10 True
                _ <- newRecord @SlotName
                    |> set #venueId (unpackId venueA.id)
                    |> set #rosterGroupId (unpackId venueAGroupB.id)
                    |> set #name "Pass"
                    |> set #sortOrder 3
                    |> set #isActive True
                    |> createRecord
                _ <- createPayConfigSnapshotRecord venueA admin 1 (Aeson.object [])
                _ <- createPayConfigSnapshotRecord venueA admin 2 (Aeson.object [])

                payLevelB <- createPayLevelRecord venueB "Level B"
                dayNameB <- fetchDayNameRecord venueB 2
                    >>= updateRecord . set #name "Venue B Tuesday"
                shiftTypeB <- createShiftTypeRecord venueB payLevelB "Bar"
                _ <- createPayLevelDayRuleRecord shiftTypeB dayNameB payLevelB
                _ <- createSlotNameRecord venueB "Graveyard"

                response <- withUserAndCurrentVenue admin venueA.id do
                    callActionWithParams AdminAction [("rosterGroupId", idToParam venueAGroupB.id)]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Roster Groups"
                response `responseBodyShouldContain` "Pay Levels"
                response `responseBodyShouldContain` "Pay Level Day Rules"
                response `responseBodyShouldContain` "Shift Types"
                response `responseBodyShouldContain` "Slot Names"
                response `responseBodyShouldContain` "Invites"
                response `responseBodyShouldContain` "Send Invite Email"
                response `responseBodyShouldContain` "Exports"
                response `responseBodyShouldContain` "Generate Staff Pay CSV"
                response `responseBodyShouldContain` "Generate Hourly Breakdown ZIP"
                response `responseBodyShouldContain` "Export History"
                response `responseBodyShouldContain` "data-live-update-feature=\"admin-slot-names\""
                response `responseBodyShouldContain` "admin-slot-names-fragment"
                response `responseBodyShouldContain` "admin-invites-fragment"
                response `responseBodyShouldNotContain` "/helpers.js"
                response `responseBodyShouldNotContain` "/ihp-auto-refresh.js"
                response `responseBodyShouldNotContain` "ihp-auto-refresh-id"
                response `responseBodyShouldContain` "Level A"
                response `responseBodyShouldContain` "Kitchen -&gt; Level A on Monday"
                response `responseBodyShouldContain` "Kitchen"
                response `responseBodyShouldContain` "Back of House"
                response `responseBodyShouldContain` "Pass"
                response `responseBodyShouldContain` "Monday"
                response `responseBodyShouldContain` "data-disable-javascript-submission=\"true\""
                response `responseBodyShouldNotContain` "Config Table Overview"
                response `responseBodyShouldNotContain` "Pay/Config Snapshots"
                response `responseBodyShouldNotContain` "Save Snapshot"
                response `responseBodyShouldNotContain` "new-invite-role"
                response `responseBodyShouldNotContain` "Invite link created"
                response `responseBodyShouldNotContain` "<th>Link</th>"
                response `responseBodyShouldContain` "hx-post=\"/CreateVenueInvitation"
                response `responseBodyShouldContain` "hx-target=\"#admin-invites-fragment\""
                response `responseBodyShouldNotContain` "Level B"
                response `responseBodyShouldNotContain` "Bar -&gt; Level B on Tuesday"
                response `responseBodyShouldNotContain` "Bar"
                response `responseBodyShouldNotContain` "Graveyard"
                response `responseBodyShouldNotContain` "Venue B Tuesday"
                response `responseBodyShouldNotContain` "Default Only"

        it "rejects non-admin venue members from admin screens" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "manager-admin@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"

                response <- withUserAndCurrentVenue manager venue.id do
                    callAction AdminAction

                response `responseStatusShouldBe` status403

        it "allows venue owners to access admin config screens" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                owner <- createUserRecord "owner-admin@example.com" "staff" True
                _ <- createVenueMembershipRecord venue owner "venue_owner"

                response <- withUserAndCurrentVenue owner venue.id do
                    callAction AdminAction

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Roster Groups"
                response `responseBodyShouldContain` "Exports"

        it "creates venue-scoped config table rows from the admin page" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Admin Venue"
                admin <- createUserRecord "admin-create@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin "venue_admin"
                dayName <- fetchDayNameRecord venue 1
                inviteNow <- getCurrentTime

                rosterGroupResponse <- withUserAndCurrentVenue admin venue.id do
                    callActionWithParams CreateRosterGroupAction
                        [ ("name", "Back of House")
                        , ("sortOrder", "7")
                        , ("isActive", "true")
                        ]
                rosterGroupResponse `responseStatusShouldBe` status302

                createdRosterGroup <- query @RosterGroup |> filterWhere (#name, "Back of House") |> fetchOne

                payLevelResponse <- withUserAndCurrentVenue admin venue.id do
                    callActionWithParams CreatePayLevelAction
                        [ ("name", "Level 2")
                        , ("isActive", "false")
                        ]
                payLevelResponse `responseStatusShouldBe` status302

                payLevel <- query @PayLevel |> fetchOne
                slotResponse <- withUserAndCurrentVenue admin venue.id do
                    callActionWithParams CreateSlotNameAction
                        [ ("name", "Swing")
                        , ("rosterGroupId", idToParam createdRosterGroup.id)
                        ]
                slotResponse `responseStatusShouldBe` status302

                shiftTypeResponse <- withUserAndCurrentVenue admin venue.id do
                    callActionWithParams CreateShiftTypeAction
                        [ ("name", "Supervisor")
                        , ("defaultPayLevelId", idToParam payLevel.id)
                        , ("isActive", "true")
                        ]
                shiftTypeResponse `responseStatusShouldBe` status302
                createdShiftType <- query @ShiftType |> filterWhere (#name, "Supervisor") |> fetchOne

                inviteResponse <- withUserAndCurrentVenue admin venue.id do
                    callActionWithParams CreateVenueInvitationAction
                        [ ("email", "new-worker@example.com")
                        , ("rosterGroupId", idToParam createdRosterGroup.id)
                        ]
                inviteResponse `responseStatusShouldBe` status302

                dayRuleResponse <- withUserAndCurrentVenue admin venue.id do
                    callActionWithParams CreatePayLevelDayRuleAction
                        [ ("shiftTypeId", idToParam createdShiftType.id)
                        , ("dayNameId", idToParam dayName.id)
                        , ("payLevelId", idToParam payLevel.id)
                        ]
                dayRuleResponse `responseStatusShouldBe` status302

                createdPayLevel <- query @PayLevel |> filterWhere (#name, "Level 2") |> fetchOne
                createdPayLevelDayRule <- query @PayLevelDayRule |> fetchOne
                createdSlotName <- query @SlotName |> filterWhere (#name, "Swing") |> fetchOne
                createdInvitation <- query @VenueInvitation |> filterWhere (#email, "new-worker@example.com") |> fetchOne
                let inviteExpiryDeltaSeconds = diffUTCTime (fromMaybe inviteNow createdInvitation.expiresAt) inviteNow

                createdRosterGroup.venueId `shouldBe` unpackId venue.id
                createdRosterGroup.sortOrder `shouldBe` 7
                createdRosterGroup.isActive `shouldBe` True
                createdPayLevel.venueId `shouldBe` unpackId venue.id
                createdPayLevel.name `shouldBe` "Level 2"
                createdPayLevel.isActive `shouldBe` False
                createdSlotName.name `shouldBe` "Swing"
                createdSlotName.rosterGroupId `shouldBe` unpackId createdRosterGroup.id
                createdSlotName.isActive `shouldBe` True
                createdSlotName.sortOrder `shouldBe` 3
                createdPayLevelDayRule.shiftTypeId `shouldBe` unpackId createdShiftType.id
                createdPayLevelDayRule.payLevelId `shouldBe` unpackId createdPayLevel.id
                createdPayLevelDayRule.dayNameId `shouldBe` unpackId dayName.id
                createdShiftType.name `shouldBe` "Supervisor"
                createdShiftType.defaultPayLevelId `shouldBe` unpackId createdPayLevel.id
                createdShiftType.isActive `shouldBe` True
                createdInvitation.venueId `shouldBe` unpackId venue.id
                createdInvitation.invitedByUserId `shouldBe` Just (unpackId admin.id)
                createdInvitation.acceptedAt `shouldBe` Nothing
                inputValue createdInvitation.inviteRole `shouldBe` "worker"
                inputValue createdInvitation.status `shouldBe` "pending"
                inviteExpiryDeltaSeconds `shouldSatisfy` (\seconds -> seconds > 86000 && seconds < 87000)

        it "redeems an admin-created invitation through the signup flow" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Admin Invite Venue"
                admin <- createUserRecord "admin-invite@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin "venue_admin"

                response <- withUserAndCurrentVenue admin venue.id do
                    callActionWithParams CreateVenueInvitationAction
                        [ ("email", "redeem-me@example.com")
                        ]

                response `responseStatusShouldBe` status302

                invitation <- query @VenueInvitation |> filterWhere (#email, "redeem-me@example.com") |> fetchOne

                showResponse <- callActionWithParams NewUserAction [("invitationId", idToParam invitation.id)]
                showResponse `responseStatusShouldBe` status200
                showResponse `responseBodyShouldContain` "Accept Invitation"
                showResponse `responseBodyShouldContain` "redeem-me@example.com"

                createResponse <- callActionWithParams CreateUserAction
                    [ ("invitationId", idToParam invitation.id)
                    , ("passwordHash", "test-password-123")
                    , ("passwordConfirmation", "test-password-123")
                    ]

                createResponse `responseStatusShouldBe` status200
                createResponse `responseBodyShouldContain` "Verify Your Email"

                createdUser <- query @User |> filterWhere (#email, "redeem-me@example.com") |> fetchOne
                membership <- query @VenueMembership |> filterWhere (#userId, unpackId createdUser.id) |> fetchOne
                updatedInvitation <- fetch invitation.id

                membership.venueId `shouldBe` unpackId venue.id
                inputValue membership.venueRole `shouldBe` "worker"
                inputValue updatedInvitation.status `shouldBe` "accepted"
                updatedInvitation.acceptedByUserId `shouldBe` Just (unpackId createdUser.id)

        it "ignores any submitted inviteRole and always creates worker invitations" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Admin Venue"
                admin <- createUserRecord "admin-invite-owner@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin "venue_admin"

                response <- withUserAndCurrentVenue admin venue.id do
                    callActionWithParams CreateVenueInvitationAction
                        [ ("email", "blocked-owner@example.com")
                        , ("inviteRole", "venue_owner")
                        ]

                response `responseStatusShouldBe` status302
                invitation <- query @VenueInvitation |> filterWhere (#email, "blocked-owner@example.com") |> fetchOne
                inputValue invitation.inviteRole `shouldBe` "worker"

        it "returns the updated invites fragment for HTMX invite creation" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Admin Venue"
                admin <- createUserRecord "admin-invite-fragment@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin "venue_admin"
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> filterWhere (#isDefault, True) |> fetchOne

                response <- withUserAndCurrentVenue admin venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams CreateVenueInvitationAction
                            [ ("email", "htmx-invite@example.com")
                            , ("rosterGroupId", idToParam rosterGroup.id)
                            ]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "admin-invites-fragment"
                response `responseBodyShouldContain` "htmx-invite@example.com"
                response `responseBodyShouldContain` "Worker"
                response `responseBodyShouldContain` "hx-target=\"#admin-invites-fragment\""
                response `responseBodyShouldContain` "hx-post=\"/CreateVenueInvitation"

        it "updates config table rows from the admin page" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Admin Venue"
                admin <- createUserRecord "admin-update@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin "venue_admin"

                oldPayLevel <- createPayLevelRecord venue "Level 1"
                newPayLevel <- createPayLevelRecord venue "Level 2"
                shiftType <- createShiftTypeRecord venue oldPayLevel "Kitchen"
                slotName <- fetchSlotNameRecord venue "Early"
                middleSlotName <- fetchSlotNameRecord venue "Mid"
                lastSlotName <- fetchSlotNameRecord venue "Late"
                dayName <- fetchDayNameRecord venue 1
                nextDayName <- fetchDayNameRecord venue 5
                payLevelDayRule <- createPayLevelDayRuleRecord shiftType dayName oldPayLevel
                rosterGroup <- createVenueRosterGroupWithDefaults venue "Back of House" 5 True

                payLevelResponse <- withUserAndCurrentVenue admin venue.id do
                    callActionWithParams (UpdatePayLevelAction oldPayLevel.id)
                        [ ("name", "Level 1 Updated")
                        , ("isActive", "false")
                        ]
                payLevelResponse `responseStatusShouldBe` status302

                makeDefaultResponse <- withUserAndCurrentVenue admin venue.id do
                    callAction (MakeDefaultRosterGroupAction rosterGroup.id)
                makeDefaultResponse `responseStatusShouldBe` status302

                rosterGroupResponse <- withUserAndCurrentVenue admin venue.id do
                    callActionWithParams (UpdateRosterGroupAction rosterGroup.id)
                        [ ("name", "Back of House Updated")
                        , ("sortOrder", "8")
                        , ("isActive", "true")
                        ]
                rosterGroupResponse `responseStatusShouldBe` status302

                shiftTypeResponse <- withUserAndCurrentVenue admin venue.id do
                    callActionWithParams (UpdateShiftTypeAction shiftType.id)
                        [ ("name", "Kitchen Updated")
                        , ("defaultPayLevelId", idToParam newPayLevel.id)
                        , ("isActive", "false")
                        ]
                shiftTypeResponse `responseStatusShouldBe` status302

                slotResponse <- withUserAndCurrentVenue admin venue.id do
                    callActionWithParams (UpdateSlotNameAction slotName.id)
                        [ ("name", "Early Updated")
                        ]
                slotResponse `responseStatusShouldBe` status302

                moveDownResponse <- withUserAndCurrentVenue admin venue.id do
                    callAction (MoveSlotNameDownAction slotName.id)
                moveDownResponse `responseStatusShouldBe` status302

                moveUpResponse <- withUserAndCurrentVenue admin venue.id do
                    callAction (MoveSlotNameUpAction lastSlotName.id)
                moveUpResponse `responseStatusShouldBe` status302

                deleteSlotResponse <- withUserAndCurrentVenue admin venue.id do
                    callAction (DeleteSlotNameAction middleSlotName.id)
                deleteSlotResponse `responseStatusShouldBe` status302

                dayRuleResponse <- withUserAndCurrentVenue admin venue.id do
                    callActionWithParams (UpdatePayLevelDayRuleAction payLevelDayRule.id)
                        [ ("shiftTypeId", idToParam shiftType.id)
                        , ("dayNameId", idToParam nextDayName.id)
                        , ("payLevelId", idToParam newPayLevel.id)
                        ]
                dayRuleResponse `responseStatusShouldBe` status302

                updatedPayLevel <- fetch oldPayLevel.id
                updatedShiftType <- fetch shiftType.id
                updatedSlotName <- fetch slotName.id
                updatedPayLevelDayRule <- fetch payLevelDayRule.id
                updatedRosterGroup <- fetch rosterGroup.id
                defaultRosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> filterWhere (#isDefault, True) |> fetchOne

                updatedPayLevel.name `shouldBe` "Level 1 Updated"
                updatedPayLevel.isActive `shouldBe` False
                updatedRosterGroup.name `shouldBe` "Back of House Updated"
                updatedRosterGroup.sortOrder `shouldBe` 8
                updatedRosterGroup.isActive `shouldBe` True
                get #id defaultRosterGroup `shouldBe` get #id updatedRosterGroup
                updatedShiftType.name `shouldBe` "Kitchen Updated"
                updatedShiftType.defaultPayLevelId `shouldBe` unpackId newPayLevel.id
                updatedShiftType.isActive `shouldBe` False
                updatedSlotName.name `shouldBe` "Early Updated"
                updatedSlotName.isActive `shouldBe` True
                updatedSlotName.sortOrder `shouldBe` 2
                (fmap (get #isActive) (fetch middleSlotName.id)) `shouldReturn` False
                (fmap (get #sortOrder) (fetch lastSlotName.id)) `shouldReturn` 1
                (fmap (map (.name)) (fetchActiveRosterGroupSlotNames (Id updatedSlotName.rosterGroupId :: Id RosterGroup))) `shouldReturn` ["Late", "Early Updated"]
                updatedPayLevelDayRule.shiftTypeId `shouldBe` unpackId shiftType.id
                updatedPayLevelDayRule.payLevelId `shouldBe` unpackId newPayLevel.id
                updatedPayLevelDayRule.dayNameId `shouldBe` unpackId nextDayName.id

        it "allows recreating a deleted slot name with the same name" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Admin Venue"
                admin <- createUserRecord "admin-slot-recreate@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin "venue_admin"

                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> filterWhere (#isDefault, True) |> fetchOne
                slotName <- fetchSlotNameRecord venue "Early"

                deleteResponse <- withUserAndCurrentVenue admin venue.id do
                    callAction (DeleteSlotNameAction slotName.id)
                deleteResponse `responseStatusShouldBe` status302

                createResponse <- withUserAndCurrentVenue admin venue.id do
                    callActionWithParams CreateSlotNameAction
                        [ ("name", "Early")
                        , ("rosterGroupId", idToParam rosterGroup.id)
                        ]
                createResponse `responseStatusShouldBe` status302

                activeEarlySlots <-
                    query @SlotName
                        |> filterWhere (#rosterGroupId, unpackId rosterGroup.id)
                        |> filterWhere (#name, "Early")
                        |> filterWhere (#isActive, True)
                        |> fetch
                inactiveEarlySlots <-
                    query @SlotName
                        |> filterWhere (#rosterGroupId, unpackId rosterGroup.id)
                        |> filterWhere (#name, "Early")
                        |> filterWhere (#isActive, False)
                        |> fetch

                length activeEarlySlots `shouldBe` 1
                length inactiveEarlySlots `shouldBe` 1

        it "does not backfill existing roster rows when creating a new slot name" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Admin Venue"
                admin <- createUserRecord "admin-slot-backfill@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin "venue_admin"

                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> filterWhere (#isDefault, True) |> fetchOne
                early <- fetchSlotNameRecordForRosterGroup rosterGroup "Early"
                rosterWeek <- createRosterWeekRecordForRosterGroup venue rosterGroup 0 False
                rosterDay <- createRosterDayRecord rosterWeek 0
                _ <- createRosterSlotRecord rosterDay early Nothing 0
                _ <- createRosterSlotRecord rosterDay early Nothing 1

                response <- withUserAndCurrentVenue admin venue.id do
                    callActionWithParams CreateSlotNameAction
                        [ ("name", "Graveyard")
                        , ("rosterGroupId", idToParam rosterGroup.id)
                        ]

                response `responseStatusShouldBe` status302

                graveyard <- fetchSlotNameRecordForRosterGroup rosterGroup "Graveyard"
                graveyardSlots <-
                    query @RosterSlot
                        |> filterWhere (#rosterDayId, unpackId rosterDay.id)
                        |> filterWhere (#slotNameId, unpackId graveyard.id)
                        |> orderByAsc #rowIndex
                        |> fetch

                graveyardSlots `shouldBe` []

        it "returns the slot-names fragment for HTMX slot move actions" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Admin Venue"
                admin <- createUserRecord "admin-slot-fragment@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin "venue_admin"
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> filterWhere (#isDefault, True) |> fetchOne
                slotName <- fetchSlotNameRecord venue "Early"

                response <- withUserAndCurrentVenue admin venue.id do
                    withRequestHeaders [("HX-Request", "true"), ("X-Live-Update-Client-Id", "admin-slot-client")] do
                        callAction (MoveSlotNameDownAction slotName.id)

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "admin-slot-names-fragment"
                response `responseBodyShouldContain` "Delete"
                response `responseBodyShouldContain` "hx-target=\"#admin-slot-names-fragment\""
                response `responseBodyShouldContain` cs (idToParam rosterGroup.id)

        it "returns the updated slot-names fragment for HTMX slot deletes" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Admin Venue"
                admin <- createUserRecord "admin-slot-delete-fragment@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin "venue_admin"
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> filterWhere (#isDefault, True) |> fetchOne
                slotName <- fetchSlotNameRecord venue "Mid"

                response <- withUserAndCurrentVenue admin venue.id do
                    withRequestHeaders [("HX-Request", "true"), ("X-Live-Update-Client-Id", "admin-slot-client")] do
                        callAction (DeleteSlotNameAction slotName.id)

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "admin-slot-names-fragment"
                response `responseBodyShouldContain` "Early"
                response `responseBodyShouldContain` "Late"
                response `responseBodyShouldNotContain` "Mid"
                response `responseBodyShouldContain` "hx-delete=\"/DeleteSlotName"
                response `responseBodyShouldContain` cs (idToParam rosterGroup.id)

        it "rejects updates to config rows outside the current venue" $ withContext do
            withCleanDb do
                venueA <- createVenueWithConfig "Venue A"
                venueB <- createVenueWithConfig "Venue B"
                admin <- createUserRecord "admin-scope@example.com" "staff" True
                _ <- createVenueMembershipRecord venueA admin "venue_admin"
                _ <- createVenueMembershipRecord venueB admin "venue_admin"
                foreignPayLevel <- createPayLevelRecord venueB "Foreign Level"

                response <- withUserAndCurrentVenue admin venueA.id do
                    callActionWithParams (UpdatePayLevelAction foreignPayLevel.id)
                        [ ("name", "Should Not Work")
                        , ("isActive", "false")
                        ]

                response `responseStatusShouldBe` status403

                unchangedPayLevel <- fetch foreignPayLevel.id
                unchangedPayLevel.name `shouldBe` "Foreign Level"
                unchangedPayLevel.isActive `shouldBe` True

        it "rejects pay level day rules that reference another venue or duplicate an existing weekday rule" $ withContext do
            withCleanDb do
                venueA <- createVenueWithConfig "Venue A"
                venueB <- createVenueWithConfig "Venue B"
                admin <- createUserRecord "admin-day-rule@example.com" "staff" True
                _ <- createVenueMembershipRecord venueA admin "venue_admin"
                _ <- createVenueMembershipRecord venueB admin "venue_admin"

                payLevelA <- createPayLevelRecord venueA "Level A"
                shiftTypeA <- createShiftTypeRecord venueA payLevelA "Kitchen"
                dayNameA <- fetchDayNameRecord venueA 1
                existingRule <- createPayLevelDayRuleRecord shiftTypeA dayNameA payLevelA

                payLevelB <- createPayLevelRecord venueB "Level B"
                shiftTypeB <- createShiftTypeRecord venueB payLevelB "Bar"
                dayNameB <- fetchDayNameRecord venueB 2

                crossVenueResponse <- withUserAndCurrentVenue admin venueA.id do
                    callActionWithParams CreatePayLevelDayRuleAction
                        [ ("shiftTypeId", idToParam shiftTypeB.id)
                        , ("dayNameId", idToParam dayNameA.id)
                        , ("payLevelId", idToParam payLevelB.id)
                        ]
                crossVenueResponse `responseStatusShouldBe` status302

                duplicateResponse <- withUserAndCurrentVenue admin venueA.id do
                    callActionWithParams CreatePayLevelDayRuleAction
                        [ ("shiftTypeId", idToParam shiftTypeA.id)
                        , ("dayNameId", idToParam dayNameA.id)
                        , ("payLevelId", idToParam payLevelA.id)
                        ]
                duplicateResponse `responseStatusShouldBe` status302

                updateForeignRuleResponse <- withUserAndCurrentVenue admin venueA.id do
                    callActionWithParams (UpdatePayLevelDayRuleAction existingRule.id)
                        [ ("shiftTypeId", idToParam shiftTypeA.id)
                        , ("dayNameId", idToParam dayNameB.id)
                        , ("payLevelId", idToParam payLevelA.id)
                        ]
                updateForeignRuleResponse `responseStatusShouldBe` status302

                payLevelDayRules <- query @PayLevelDayRule |> fetch
                length payLevelDayRules `shouldBe` 1

                unchangedRule <- fetch existingRule.id
                unchangedRule.shiftTypeId `shouldBe` unpackId shiftTypeA.id
                unchangedRule.payLevelId `shouldBe` unpackId payLevelA.id
                unchangedRule.dayNameId `shouldBe` unpackId dayNameA.id

        it "automatically snapshots payroll-relevant admin config changes while skipping roster-only edits" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Admin Venue"
                admin <- createUserRecord "admin-save@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin "venue_admin"
                dayName <- fetchDayNameRecord venue 1

                rosterGroupResponse <- withUserAndCurrentVenue admin venue.id do
                    callActionWithParams CreateRosterGroupAction
                        [ ("name", "Back of House")
                        , ("sortOrder", "7")
                        , ("isActive", "true")
                        ]
                rosterGroupResponse `responseStatusShouldBe` status302
                query @PayConfigSnapshot |> fetch `shouldReturn` []

                createdRosterGroup <- query @RosterGroup |> filterWhere (#name, "Back of House") |> fetchOne

                payLevelResponse <- withUserAndCurrentVenue admin venue.id do
                    callActionWithParams CreatePayLevelAction
                        [ ("name", "Level 2")
                        , ("baseRate", "31.50")
                        , ("isActive", "true")
                        ]
                payLevelResponse `responseStatusShouldBe` status302
                (query @PayConfigSnapshot |> orderByDesc #versionNumber |> fetch >>= pure . map (.versionLabel)) `shouldReturn` ["v1"]

                payLevel <- query @PayLevel |> filterWhere (#name, "Level 2") |> fetchOne

                shiftTypeResponse <- withUserAndCurrentVenue admin venue.id do
                    callActionWithParams CreateShiftTypeAction
                        [ ("name", "Supervisor")
                        , ("defaultPayLevelId", idToParam payLevel.id)
                        , ("isActive", "true")
                        ]
                shiftTypeResponse `responseStatusShouldBe` status302
                (query @PayConfigSnapshot |> orderByDesc #versionNumber |> fetch >>= pure . map (.versionLabel)) `shouldReturn` ["v2", "v1"]

                shiftType <- query @ShiftType |> filterWhere (#name, "Supervisor") |> fetchOne

                dayRuleResponse <- withUserAndCurrentVenue admin venue.id do
                    callActionWithParams CreatePayLevelDayRuleAction
                        [ ("shiftTypeId", idToParam shiftType.id)
                        , ("dayNameId", idToParam dayName.id)
                        , ("payLevelId", idToParam payLevel.id)
                        ]
                dayRuleResponse `responseStatusShouldBe` status302
                (query @PayConfigSnapshot |> orderByDesc #versionNumber |> fetch >>= pure . map (.versionLabel)) `shouldReturn` ["v3", "v2", "v1"]

                slotResponse <- withUserAndCurrentVenue admin venue.id do
                    callActionWithParams CreateSlotNameAction
                        [ ("name", "Swing")
                        , ("rosterGroupId", idToParam createdRosterGroup.id)
                        ]
                slotResponse `responseStatusShouldBe` status302
                (query @PayConfigSnapshot |> orderByDesc #versionNumber |> fetch >>= pure . map (.versionLabel)) `shouldReturn` ["v3", "v2", "v1"]

                slotName <- query @SlotName |> filterWhere (#name, "Swing") |> fetchOne
                payLevelDayRule <- query @PayLevelDayRule |> fetchOne

                updatePayLevelResponse <- withUserAndCurrentVenue admin venue.id do
                    callActionWithParams (UpdatePayLevelAction payLevel.id)
                        [ ("name", "Level 2 Updated")
                        , ("baseRate", "33.00")
                        , ("isActive", "true")
                        ]
                updatePayLevelResponse `responseStatusShouldBe` status302

                updateShiftTypeResponse <- withUserAndCurrentVenue admin venue.id do
                    callActionWithParams (UpdateShiftTypeAction shiftType.id)
                        [ ("name", "Supervisor Updated")
                        , ("defaultPayLevelId", idToParam payLevel.id)
                        , ("isActive", "false")
                        ]
                updateShiftTypeResponse `responseStatusShouldBe` status302

                updateDayRuleResponse <- withUserAndCurrentVenue admin venue.id do
                    callActionWithParams (UpdatePayLevelDayRuleAction payLevelDayRule.id)
                        [ ("shiftTypeId", idToParam shiftType.id)
                        , ("dayNameId", idToParam dayName.id)
                        , ("payLevelId", idToParam payLevel.id)
                        ]
                updateDayRuleResponse `responseStatusShouldBe` status302

                (query @PayConfigSnapshot |> orderByDesc #versionNumber |> fetch >>= pure . map (.versionLabel)) `shouldReturn` ["v5", "v4", "v3", "v2", "v1"]

                updateSlotResponse <- withUserAndCurrentVenue admin venue.id do
                    callActionWithParams (UpdateSlotNameAction slotName.id)
                        [ ("name", "Swing Updated") ]
                updateSlotResponse `responseStatusShouldBe` status302

                updateRosterGroupResponse <- withUserAndCurrentVenue admin venue.id do
                    callActionWithParams (UpdateRosterGroupAction createdRosterGroup.id)
                        [ ("name", "Back of House Updated")
                        , ("sortOrder", "8")
                        , ("isActive", "true")
                        ]
                updateRosterGroupResponse `responseStatusShouldBe` status302

                snapshots <- query @PayConfigSnapshot |> orderByDesc #versionNumber |> fetch
                map (.versionLabel) snapshots `shouldBe` ["v5", "v4", "v3", "v2", "v1"]
                map (.createdByUserId) snapshots `shouldBe` replicate 5 (unpackId admin.id)

        it "does not create a new snapshot when a payroll config update leaves the snapshot payload unchanged" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Admin Venue"
                admin <- createUserRecord "admin-no-churn@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin "venue_admin"

                createResponse <- withUserAndCurrentVenue admin venue.id do
                    callActionWithParams CreatePayLevelAction
                        [ ("name", "Level 2")
                        , ("baseRate", "31.50")
                        , ("isActive", "true")
                        ]
                createResponse `responseStatusShouldBe` status302

                payLevel <- query @PayLevel |> filterWhere (#name, "Level 2") |> fetchOne

                unchangedUpdateResponse <- withUserAndCurrentVenue admin venue.id do
                    callActionWithParams (UpdatePayLevelAction payLevel.id)
                        [ ("name", "Level 2")
                        , ("baseRate", "31.50")
                        , ("eveningPenalty", "0")
                        , ("after12Penalty", "0")
                        , ("weekdayMultiplier", "1")
                        , ("saturdayMultiplier", "1")
                        , ("sundayMultiplier", "1")
                        , ("isActive", "true")
                        ]
                unchangedUpdateResponse `responseStatusShouldBe` status302

                snapshots <- query @PayConfigSnapshot |> orderByDesc #versionNumber |> fetch
                map (.versionLabel) snapshots `shouldBe` ["v1"]
