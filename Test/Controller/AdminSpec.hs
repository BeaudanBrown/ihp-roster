module Test.Controller.AdminSpec where

import Application.Helper.RosterGroups (createVenueRosterGroupWithDefaults,
                                        fetchActiveRosterGroupSlotNames)
import Application.Helper.WeekBoundaries (defaultWeekOffsetEpochForStartDay)
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

        it "shows current-venue admin sections with FWC-backed award level data" $ withContext do
            withCleanDb do
                venueA <- createVenueWithConfig "Venue A"
                venueB <- createVenueWithConfig "Venue B"
                admin <- createUserRecord "admin-page@example.com" "staff" True
                _ <- createVenueMembershipRecord venueA admin "venue_admin"
                _ <- createVenueMembershipRecord venueB admin "venue_admin"

                levelA <- createPayLevelRecordWithRates venueA "Level A" 31.50 3.15 6.30 1 1.25 1.50
                _ <- createShiftTypeRecord venueA levelA "Kitchen"
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

                levelB <- createPayLevelRecord venueB "Level B"
                _ <- createShiftTypeRecord venueB levelB "Bar"
                _ <- createSlotNameRecord venueB "Graveyard"

                response <- withUserAndCurrentVenue admin venueA.id do
                    callActionWithParams AdminAction [("rosterGroupId", idToParam venueAGroupB.id)]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Roster Groups"
                response `responseBodyShouldContain` "Shift Types"
                response `responseBodyShouldContain` "Slot Names"
                response `responseBodyShouldContain` "Invites"
                response `responseBodyShouldContain` "Exports"
                response `responseBodyShouldContain` "Generate Staff Pay CSV"
                response `responseBodyShouldContain` "Generate Hourly Breakdown ZIP"
                response `responseBodyShouldContain` "Generate Payroll Earnings CSV"
                response `responseBodyShouldContain` "admin-slot-names-fragment"
                response `responseBodyShouldContain` "admin-invites-fragment"
                response `responseBodyShouldNotContain` "Venue Config"
                response `responseBodyShouldNotContain` "Award Levels"
                response `responseBodyShouldNotContain` "Pay Levels"
                response `responseBodyShouldNotContain` "Pay Level Day Rules"
                response `responseBodyShouldNotContain` "/helpers.js"
                response `responseBodyShouldNotContain` "/ihp-auto-refresh.js"
                response `responseBodyShouldContain` "Kitchen"
                response `responseBodyShouldContain` "Level A"
                response `responseBodyShouldContain` "Level A (perm $31.50/hr)"
                response `responseBodyShouldContain` "Use staff default award level"
                response `responseBodyShouldContain` "Back of House"
                response `responseBodyShouldContain` "Pass"
                response `responseBodyShouldNotContain` "Bar"
                response `responseBodyShouldNotContain` "Graveyard"
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
                response `responseBodyShouldNotContain` "Venue Config"

        it "creates venue-scoped non-pay config rows from the admin page" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Admin Venue"
                admin <- createUserRecord "admin-create@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin "venue_admin"
                inviteNow <- getCurrentTime

                rosterGroupResponse <- withUserAndCurrentVenue admin venue.id do
                    callActionWithParams CreateRosterGroupAction
                        [ ("name", "Back of House")
                        , ("isActive", "true")
                        ]
                rosterGroupResponse `responseStatusShouldBe` status302
                createdRosterGroup <- query @RosterGroup |> filterWhere (#name, "Back of House") |> fetchOne

                slotResponse <- withUserAndCurrentVenue admin venue.id do
                    callActionWithParams CreateSlotNameAction
                        [ ("name", "Swing")
                        , ("rosterGroupId", idToParam createdRosterGroup.id)
                        ]
                slotResponse `responseStatusShouldBe` status302

                shiftTypeResponse <- withUserAndCurrentVenue admin venue.id do
                    callActionWithParams CreateShiftTypeAction
                        [ ("name", "Supervisor")
                        , ("isActive", "true")
                        , ("overrideAwardLevelId", "")
                        ]
                shiftTypeResponse `responseStatusShouldBe` status302

                inviteResponse <- withUserAndCurrentVenue admin venue.id do
                    callActionWithParams CreateVenueInvitationAction
                        [ ("email", "new-worker@example.com")
                        , ("rosterGroupId", idToParam createdRosterGroup.id)
                        ]
                inviteResponse `responseStatusShouldBe` status302

                createdSlotName <- query @SlotName |> filterWhere (#name, "Swing") |> fetchOne
                createdShiftType <- query @ShiftType |> filterWhere (#name, "Supervisor") |> fetchOne
                createdInvitation <- query @VenueInvitation |> filterWhere (#email, "new-worker@example.com") |> fetchOne
                let inviteExpiryDeltaSeconds = diffUTCTime (fromMaybe inviteNow createdInvitation.expiresAt) inviteNow

                createdRosterGroup.venueId `shouldBe` unpackId venue.id
                createdRosterGroup.sortOrder `shouldBe` 1
                createdRosterGroup.isActive `shouldBe` True
                createdSlotName.name `shouldBe` "Swing"
                createdSlotName.rosterGroupId `shouldBe` unpackId createdRosterGroup.id
                createdSlotName.isActive `shouldBe` True
                createdSlotName.sortOrder `shouldBe` 3
                createdShiftType.name `shouldBe` "Supervisor"
                createdShiftType.overrideAwardLevelId `shouldBe` Nothing
                createdShiftType.isActive `shouldBe` True
                createdInvitation.venueId `shouldBe` unpackId venue.id
                createdInvitation.invitedByUserId `shouldBe` Just (unpackId admin.id)
                createdInvitation.acceptedAt `shouldBe` Nothing
                inputValue createdInvitation.inviteRole `shouldBe` "worker"
                inputValue createdInvitation.status `shouldBe` "pending"
                inputValue createdInvitation.deliveryStatus `shouldSatisfy` (`elem` ["queued", "sent", "failed"])
                inviteExpiryDeltaSeconds `shouldSatisfy` (\seconds -> seconds > 86000 && seconds < 87000)

        it "updates non-pay config rows from the admin page" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Admin Venue"
                admin <- createUserRecord "admin-update@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin "venue_admin"
                level <- createPayLevelRecord venue "Level 1"
                shiftType <- createShiftTypeRecord venue level "Kitchen"
                overrideLevel <- createPayLevelRecord venue "Level 2"
                slotName <- fetchSlotNameRecord venue "Early"
                middleSlotName <- fetchSlotNameRecord venue "Mid"
                lastSlotName <- fetchSlotNameRecord venue "Late"
                rosterGroup <- createVenueRosterGroupWithDefaults venue "Back of House" 5 True

                moveGroupUpResponse <- withUserAndCurrentVenue admin venue.id do
                    callAction (MoveRosterGroupUpAction rosterGroup.id)
                moveGroupUpResponse `responseStatusShouldBe` status302

                rosterGroupResponse <- withUserAndCurrentVenue admin venue.id do
                    callActionWithParams (UpdateRosterGroupAction rosterGroup.id)
                        [ ("name", "Back of House Updated")
                        , ("isActive", "true")
                        ]
                rosterGroupResponse `responseStatusShouldBe` status302

                shiftTypeResponse <- withUserAndCurrentVenue admin venue.id do
                    callActionWithParams (UpdateShiftTypeAction shiftType.id)
                        [ ("name", "Kitchen Updated")
                        , ("isActive", "false")
                        , ("overrideAwardLevelId", idToParam overrideLevel.id)
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

                updatedShiftType <- fetch shiftType.id
                updatedSlotName <- fetch slotName.id
                updatedRosterGroup <- fetch rosterGroup.id
                defaultRosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> filterWhere (#isDefault, True) |> fetchOne

                updatedRosterGroup.name `shouldBe` "Back of House Updated"
                updatedRosterGroup.sortOrder `shouldBe` 0
                updatedRosterGroup.isActive `shouldBe` True
                get #id defaultRosterGroup `shouldBe` get #id updatedRosterGroup
                updatedShiftType.name `shouldBe` "Kitchen Updated"
                updatedShiftType.overrideAwardLevelId `shouldBe` Just overrideLevel.id
                updatedShiftType.isActive `shouldBe` False
                updatedSlotName.name `shouldBe` "Early Updated"
                updatedSlotName.isActive `shouldBe` True
                updatedSlotName.sortOrder `shouldBe` 2
                (fmap (get #isActive) (fetch middleSlotName.id)) `shouldReturn` False
                (fmap (get #sortOrder) (fetch lastSlotName.id)) `shouldReturn` 1
                (fmap (map (.name)) (fetchActiveRosterGroupSlotNames (Id updatedSlotName.rosterGroupId :: Id RosterGroup))) `shouldReturn` ["Late", "Early Updated"]

        it "updates the roster week start before venue history exists and snapshots the new setting" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Admin Venue"
                admin <- createUserRecord "admin-week-start@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin "venue_admin"

                response <- withUserAndCurrentVenue admin venue.id do
                    callActionWithParams UpdateVenueConfigAction
                        [("rosterWeekStartsOn", "2")]

                response `responseStatusShouldBe` status302

                venueConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                snapshots <- query @PayConfigSnapshot |> orderByDesc #versionNumber |> fetch

                venueConfig.rosterWeekStartsOn `shouldBe` 2
                venueConfig.weekOffsetEpoch `shouldBe` defaultWeekOffsetEpochForStartDay 2
                map (.versionLabel) snapshots `shouldBe` ["v1"]

        it "rejects updates to config rows outside the current venue" $ withContext do
            withCleanDb do
                venueA <- createVenueWithConfig "Venue A"
                venueB <- createVenueWithConfig "Venue B"
                admin <- createUserRecord "admin-scope@example.com" "staff" True
                _ <- createVenueMembershipRecord venueA admin "venue_admin"
                _ <- createVenueMembershipRecord venueB admin "venue_admin"
                foreignLevel <- createPayLevelRecord venueB "Foreign Level"
                foreignShiftType <- createShiftTypeRecord venueB foreignLevel "Foreign Shift"

                response <- withUserAndCurrentVenue admin venueA.id do
                    callActionWithParams (UpdateShiftTypeAction foreignShiftType.id)
                        [ ("name", "Should Not Work")
                        , ("isActive", "false")
                        , ("overrideAwardLevelId", "")
                        ]

                response `responseStatusShouldBe` status403

                unchangedShiftType <- fetch foreignShiftType.id
                unchangedShiftType.name `shouldBe` "Foreign Shift"
                unchangedShiftType.isActive `shouldBe` True

        it "snapshots payroll-relevant FWC-backed config changes while skipping roster-only edits" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Admin Venue"
                admin <- createUserRecord "admin-save@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin "venue_admin"

                rosterGroupResponse <- withUserAndCurrentVenue admin venue.id do
                    callActionWithParams CreateRosterGroupAction
                        [ ("name", "Back of House")
                        , ("isActive", "true")
                        ]
                rosterGroupResponse `responseStatusShouldBe` status302
                query @PayConfigSnapshot |> fetch `shouldReturn` []

                _ <- createPayLevelRecordWithRates venue "Level 2" 31.50 3.15 6.30 1 1.25 1.50

                shiftTypeResponse <- withUserAndCurrentVenue admin venue.id do
                    callActionWithParams CreateShiftTypeAction
                        [ ("name", "Supervisor")
                        , ("isActive", "true")
                        , ("overrideAwardLevelId", "")
                        ]
                shiftTypeResponse `responseStatusShouldBe` status302
                (query @PayConfigSnapshot |> orderByDesc #versionNumber |> fetch >>= pure . map (.versionLabel)) `shouldReturn` ["v1"]

                createdRosterGroup <- query @RosterGroup |> filterWhere (#name, "Back of House") |> fetchOne
                slotResponse <- withUserAndCurrentVenue admin venue.id do
                    callActionWithParams CreateSlotNameAction
                        [ ("name", "Swing")
                        , ("rosterGroupId", idToParam createdRosterGroup.id)
                        ]
                slotResponse `responseStatusShouldBe` status302
                (query @PayConfigSnapshot |> orderByDesc #versionNumber |> fetch >>= pure . map (.versionLabel)) `shouldReturn` ["v1"]

                snapshots <- query @PayConfigSnapshot |> orderByDesc #versionNumber |> fetch
                map (.createdByUserId) snapshots `shouldBe` [unpackId admin.id]
