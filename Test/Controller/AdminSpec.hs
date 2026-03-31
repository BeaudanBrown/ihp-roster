module Test.Controller.AdminSpec where

import Application.Helper.RosterGroups (createVenueRosterGroupWithDefaults)
import Config
import qualified Data.Aeson as Aeson
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
                response `responseBodyShouldContain` "Day Names"
                response `responseBodyShouldContain` "Config Table Overview"
                response `responseBodyShouldContain` "Edits change the current venue draft state only until you save a new pay/config snapshot."
                response `responseBodyShouldContain` "Draft edits on this page do not rewrite historical approvals or exports."
                response `responseBodyShouldNotContain` "/helpers.js"
                response `responseBodyShouldNotContain` "/ihp-auto-refresh.js"
                response `responseBodyShouldNotContain` "ihp-auto-refresh-id"
                response `responseBodyShouldContain` "Level A"
                response `responseBodyShouldContain` "Kitchen -&gt; Level A on Monday (Monday)"
                response `responseBodyShouldContain` "Kitchen"
                response `responseBodyShouldContain` "Back of House"
                response `responseBodyShouldContain` "Pass"
                response `responseBodyShouldContain` "Monday"
                response `responseBodyShouldContain` "Active snapshot: v2"
                response `responseBodyShouldContain` "data-disable-javascript-submission=\"true\""
                response `responseBodyShouldNotContain` "Level B"
                response `responseBodyShouldNotContain` "Bar -&gt; Level B on Venue B Tuesday (Tuesday)"
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
                response `responseBodyShouldContain` "Config Table Overview"
                response `responseBodyShouldContain` "Pay/Config Snapshots"

        it "creates venue-scoped config table rows from the admin page" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Admin Venue"
                admin <- createUserRecord "admin-create@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin "venue_admin"
                dayName <- fetchDayNameRecord venue 1

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
                        , ("isActive", "true")
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

                createdRosterGroup.venueId `shouldBe` unpackId venue.id
                createdRosterGroup.sortOrder `shouldBe` 7
                createdRosterGroup.isActive `shouldBe` True
                createdPayLevel.venueId `shouldBe` unpackId venue.id
                createdPayLevel.name `shouldBe` "Level 2"
                createdPayLevel.isActive `shouldBe` False
                createdSlotName.name `shouldBe` "Swing"
                createdSlotName.rosterGroupId `shouldBe` unpackId createdRosterGroup.id
                createdSlotName.isActive `shouldBe` True
                createdPayLevelDayRule.shiftTypeId `shouldBe` unpackId createdShiftType.id
                createdPayLevelDayRule.payLevelId `shouldBe` unpackId createdPayLevel.id
                createdPayLevelDayRule.dayNameId `shouldBe` unpackId dayName.id
                createdShiftType.name `shouldBe` "Supervisor"
                createdShiftType.defaultPayLevelId `shouldBe` unpackId createdPayLevel.id
                createdShiftType.isActive `shouldBe` True

        it "updates config table rows from the admin page" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Admin Venue"
                admin <- createUserRecord "admin-update@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin "venue_admin"

                oldPayLevel <- createPayLevelRecord venue "Level 1"
                newPayLevel <- createPayLevelRecord venue "Level 2"
                shiftType <- createShiftTypeRecord venue oldPayLevel "Kitchen"
                slotName <- fetchSlotNameRecord venue "Early"
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
                        , ("isActive", "false")
                        ]
                slotResponse `responseStatusShouldBe` status302

                dayResponse <- withUserAndCurrentVenue admin venue.id do
                    callActionWithParams (UpdateDayNameAction dayName.id)
                        [ ("weekdayIndex", "1")
                        , ("name", "Thursday Updated")
                        , ("isActive", "false")
                        ]
                dayResponse `responseStatusShouldBe` status302

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
                updatedDayName <- fetch dayName.id
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
                updatedSlotName.isActive `shouldBe` False
                updatedDayName.weekdayIndex `shouldBe` 1
                updatedDayName.name `shouldBe` "Thursday Updated"
                updatedDayName.isActive `shouldBe` False
                updatedPayLevelDayRule.shiftTypeId `shouldBe` unpackId shiftType.id
                updatedPayLevelDayRule.payLevelId `shouldBe` unpackId newPayLevel.id
                updatedPayLevelDayRule.dayNameId `shouldBe` unpackId nextDayName.id

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

        it "creates a new pay/config snapshot version from the admin page" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Admin Venue"
                admin <- createUserRecord "admin-save@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin "venue_admin"

                response <- withUserAndCurrentVenue admin venue.id do
                    callAction CreatePayConfigSnapshotAction

                response `responseStatusShouldBe` status302

                snapshot <- query @PayConfigSnapshot |> fetchOne
                snapshot.versionNumber `shouldBe` 1
                snapshot.versionLabel `shouldBe` "v1"
                snapshot.createdByUserId `shouldBe` unpackId admin.id
