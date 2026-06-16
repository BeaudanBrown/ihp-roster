module Test.Controller.RosterWeeks.WorkflowSpec where

import Application.Async.Queue (EnqueueAppJobResult (..))
import Application.Helper.Controller (PlatformRole (SuperAdminRole),
                                      venueWeekStartDate)
import Application.Helper.LiveResource (LiveResource (..))
import Application.Helper.RosterGroups (createVenueRosterGroupWithDefaults,
                                        syncStaffRosterGroupAssignments)
import Application.Helper.UserPreferences
import Application.RosterTimesheets.Automation (enqueueRosterTimesheetCreationJobsForWeek,
                                                performRosterTimesheetCreationJob,
                                                rosterTimesheetCreationJobKind,
                                                rosterTimesheetRunAt)
import Config
import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Char8 as ByteString
import Data.Coerce (coerce)
import Data.List (sortOn)
import Data.Maybe (fromJust)
import qualified Data.Set as Set
import Data.Time.Calendar (addDays)
import Data.Time.LocalTime (TimeOfDay (..))
import Generated.Types
import IHP.ControllerPrelude
import IHP.FrameworkConfig
import IHP.HaskellSupport
import IHP.Job.Types
import IHP.ModelSupport (inputValue)
import IHP.Prelude
import IHP.Test.Mocking
import Network.HTTP.Types.Status
import Network.Wai
import Test.Hspec
import Test.Support
import Web.Controller.RosterWeeks ()
import Web.FrontController ()
import Web.RosterWeeks.Dom (rosterContentFragmentId, rosterDayColumnsFragmentId, rosterDaySectionDomId,
                            rosterGridFrameFragmentId, rosterRowDomIdText, rosterStaffPanelFragmentId)
import Web.RosterWeeks.Mutations (rosterDayTouchedResources,
                                  rosterSlotTouchedResources,
                                  rosterWeekTouchedResources)
import Web.Routes
import Web.Types

tests :: Spec
tests = beforeAll testContext do
    describe "RosterWeeksController" do
        it "records touched resources for roster mutations" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Roster Touched Venue"
                rosterWeek <- createRosterWeekRecord venue 0 False
                rosterDay <- createRosterDayRecord rosterWeek 0
                slotName <- fetchSlotNameRecord venue "Early"
                rosterSlot <- createRosterSlotRecord rosterDay slotName Nothing 0
                let rosterGroupId = coerce rosterWeek.rosterGroupId

                Set.fromList (rosterSlotTouchedResources rosterGroupId rosterWeek.weekOffset rosterDay (Just rosterSlot))
                    `shouldBe` Set.fromList
                        [ RosterWeekResource (unpackId rosterGroupId) rosterWeek.weekOffset
                        , RosterDayResource (unpackId rosterDay.id)
                        , RosterSlotResource (unpackId rosterSlot.id)
                        ]
                rosterWeekTouchedResources rosterGroupId rosterWeek.weekOffset
                    `shouldBe` [RosterWeekResource (unpackId rosterGroupId) rosterWeek.weekOffset]
                rosterDayTouchedResources rosterGroupId rosterWeek.weekOffset rosterDay
                    `shouldBe`
                        [ RosterWeekResource (unpackId rosterGroupId) rosterWeek.weekOffset
                        , RosterDayResource (unpackId rosterDay.id)
                        ]

        it "always renders separate day-name and date rows even when a day only has one roster row" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-day-labels@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                slotName <- fetchSlotNameRecord venue "Early"
                rosterWeek <- createRosterWeekRecord venue 0 False
                rosterDay <- createRosterDayRecord rosterWeek 0
                _ <- createRosterSlotRecord rosterDay slotName Nothing 0

                response <- withUserAndCurrentVenue manager venue.id do
                    callAction (ShowRosterWeekAction 0)

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "roster-day-label-row-primary"
                response `responseBodyShouldContain` "roster-day-label-row-controls"
                response `responseBodyShouldContain` cs (rosterRowDomIdText rosterDay.id 1)

        it "shows statewide public holiday indicators on roster day labels" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-public-holidays@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                venueConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                let weekStartDate = venueWeekStartDate venueConfig 0
                rosterWeek <- createRosterWeekRecord venue 0 False
                _ <- createRosterDayRecord rosterWeek 0
                _ <- createRosterDayRecord rosterWeek 1
                _ <-
                    newRecord @PublicHoliday
                        |> set #jurisdiction "VIC"
                        |> set #holidayDate weekStartDate
                        |> set #name "Picnic Day"
                        |> set #isRegional False
                        |> createRecord
                _ <-
                    newRecord @PublicHoliday
                        |> set #jurisdiction "VIC"
                        |> set #holidayDate (addDays 1 weekStartDate)
                        |> set #name "Regional Show Day"
                        |> set #region (Just "Regional Council")
                        |> set #isRegional True
                        |> createRecord

                response <- withUserAndCurrentVenue manager venue.id do
                    callAction (ShowRosterWeekAction 0)

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "roster-public-holiday-indicator"
                response `responseBodyShouldContain` "title=\"Picnic Day\""
                response `responseBodyShouldContain` "aria-label=\"Public holiday: Picnic Day\""
                response `responseBodyShouldNotContain` "Regional Show Day"

        it "manager can mark a draft roster day closed via HTMX without deleting existing slot content" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-close-day@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                slotName <- fetchSlotNameRecord venue "Early"
                staffMember <- createStaffRecord venue Nothing "Alpha" "Crew"
                rosterWeek <- createRosterWeekRecord venue 0 False
                rosterDay <- createRosterDayRecord rosterWeek 0
                slot <- createRosterSlotRecord rosterDay slotName (Just staffMember) 0
                _ <- updateRecord (slot |> set #startTime (Just (timeOfDay 9 0)))

                response <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callAction (ToggleRosterDayClosedAction rosterDay.id)

                response `responseStatusShouldBe` status200
                body <- responseBody response
                let bodyText = cs body :: String
                bodyText `shouldContain` "id=\"dialog-overlay-mount\""
                bodyText `shouldContain` ("id=\"" <> cs rosterDayColumnsFragmentId <> "\"" :: String)
                bodyText `shouldNotContain` ("id=\"" <> cs rosterGridFrameFragmentId <> "\"" :: String)
                bodyText `shouldContain` ("id=\"" <> cs rosterStaffPanelFragmentId <> "\"" :: String)
                bodyText `shouldContain` "hx-swap-oob=\"outerHTML\""

                updatedDay <- fetch rosterDay.id
                updatedDay.isClosed `shouldBe` True
                unchangedSlot <- fetch slot.id
                unchangedSlot.staffId `shouldBe` Just (unpackId staffMember.id)
                unchangedSlot.startTime `shouldBe` Just (timeOfDay 9 0)

        it "closed roster days stay locked at two rows and reject row additions" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-closed-day-add@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                slotName <- fetchSlotNameRecord venue "Early"
                rosterWeek <- createRosterWeekRecord venue 0 False
                rosterDay <- createRosterDayRecord rosterWeek 0
                _ <- updateRecord (rosterDay |> set #isClosed True)
                _ <- createRosterSlotRecord rosterDay slotName Nothing 0

                response <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callAction (AddRosterRowAction rosterDay.id)

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Closed days stay locked at two blank rows until reopened."

        it "manager can create a draft week via HTMX without redirecting" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-create-htmx@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                _ <- fetchSlotNameRecord venue "Early"

                response <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callAction (CreateRosterWeekAction 0)

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` cs rosterContentFragmentId
                response `responseBodyShouldContain` "Roster week created successfully"

        it "manager can add a row to an auto-created draft week" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-add-row@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                slotNames <- query @SlotName
                    |> filterWhere (#venueId, unpackId venue.id)
                    |> filterWhere (#isActive, True)
                    |> fetch

                _ <- withUserAndCurrentVenue manager venue.id do
                    callAction (ShowRosterWeekAction 0)

                rosterWeek <- query @RosterWeek
                    |> filterWhere (#venueId, unpackId venue.id)
                    |> filterWhere (#weekOffset, 0)
                    |> fetchOne
                rosterDay <- query @RosterDay
                    |> filterWhere (#rosterWeekId, unpackId rosterWeek.id)
                    |> filterWhere (#dayOffset, 0)
                    |> fetchOne

                response <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callAction (AddRosterRowAction rosterDay.id)

                response `responseStatusShouldBe` status200
                body <- responseBody response
                let bodyText = cs body :: String
                bodyText `shouldContain` "id=\"dialog-overlay-mount\""
                bodyText `shouldContain` ("id=\"" <> cs rosterDayColumnsFragmentId <> "\"" :: String)
                bodyText `shouldNotContain` ("id=\"" <> cs rosterGridFrameFragmentId <> "\"" :: String)
                bodyText `shouldContain` ("id=\"" <> cs rosterStaffPanelFragmentId <> "\"" :: String)
                bodyText `shouldContain` "hx-swap-oob=\"outerHTML\""

                slotsForDay <- query @RosterSlot
                    |> filterWhere (#rosterDayId, unpackId rosterDay.id)
                    |> orderByAsc #rowIndex
                    |> fetch
                slotsForDay `shouldBe` []
                updatedDay <- fetch rosterDay.id
                updatedDay.rowCount `shouldBe` 5

        it "manager can remove the last roster row via a day-section refresh" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-remove-row-patch@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                slotName <- fetchSlotNameRecord venue "Early"
                rosterWeek <- createRosterWeekRecord venue 0 False
                rosterDay <- createRosterDayRecord rosterWeek 0
                rosterDayWithRows <- updateRecord (rosterDay |> set #rowCount 3)

                response <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callAction (RemoveRosterRowAction rosterDayWithRows.id)

                response `responseStatusShouldBe` status200
                body <- responseBody response
                let bodyText = cs body :: String
                bodyText `shouldContain` "id=\"dialog-overlay-mount\""
                bodyText `shouldContain` ("id=\"" <> cs rosterDayColumnsFragmentId <> "\"" :: String)
                bodyText `shouldNotContain` ("id=\"" <> cs rosterGridFrameFragmentId <> "\"" :: String)
                bodyText `shouldContain` ("id=\"" <> cs rosterStaffPanelFragmentId <> "\"" :: String)
                bodyText `shouldContain` "hx-swap-oob=\"outerHTML\""

                slotsForDay <- query @RosterSlot
                    |> filterWhere (#rosterDayId, unpackId rosterDayWithRows.id)
                    |> filterWhere (#deletedAt, Nothing)
                    |> fetch
                slotsForDay `shouldBe` []
                updatedDay <- fetch rosterDayWithRows.id
                updatedDay.rowCount `shouldBe` 2

        it "removing a populated row compacts holes before appending preserved shifts at the bottom" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-remove-row-pack-hole@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                early <- fetchSlotNameRecord venue "Early"
                rosterWeek <- createRosterWeekRecord venue 0 False
                rosterDay <- createRosterDayRecord rosterWeek 0
                row0 <- createRosterSlotRecord rosterDay early Nothing 0
                row1 <- createRosterSlotRecord rosterDay early Nothing 1
                row2 <- createRosterSlotRecord rosterDay early Nothing 2
                row3 <- createRosterSlotRecord rosterDay early Nothing 3
                _ <- updateRecord (row0 |> set #startTime (Just (timeOfDay 8 0)))
                _ <- updateRecord (row2 |> set #startTime (Just (timeOfDay 10 0)))
                _ <- updateRecord (row3 |> set #startTime (Just (timeOfDay 12 0)))

                response <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callAction (RemoveRosterRowAction rosterDay.id)
                response `responseStatusShouldBe` status200

                activeDataSlots <- query @RosterSlot
                    |> filterWhere (#rosterDayId, unpackId rosterDay.id)
                    |> filterWhere (#deletedAt, Nothing)
                    |> fetch
                let packedDataSlots = sortOn (.rowIndex) (filter (\slot -> slot.id `elem` map (.id) [row0, row2, row3]) activeDataSlots)
                map (.id) packedDataSlots `shouldBe` [row0.id, row2.id, row3.id]
                map (.rowIndex) packedDataSlots `shouldBe` [0, 1, 2]
                map (.startTime) packedDataSlots `shouldBe` map (Just . uncurry timeOfDay) [(8, 0), (10, 0), (12, 0)]
                deletedHole <- fetch row1.id
                deletedHole.deletedAt `shouldSatisfy` isJust

        it "asks for confirmation before deleting overflow shifts and preserves deleted-row shifts left to right" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-remove-row-overflow@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                early <- fetchSlotNameRecord venue "Early"
                late <- fetchSlotNameRecord venue "Late"
                rosterWeek <- createRosterWeekRecord venue 0 False
                rosterDay <- createRosterDayRecord rosterWeek 0
                rosterDayWithRows <- updateRecord (rosterDay |> set #rowCount 3)
                early0 <- createRosterSlotRecord rosterDayWithRows early Nothing 0
                early1 <- createRosterSlotRecord rosterDayWithRows early Nothing 1
                early2 <- createRosterSlotRecord rosterDayWithRows early Nothing 2
                late0 <- createRosterSlotRecord rosterDayWithRows late Nothing 0
                late1 <- createRosterSlotRecord rosterDayWithRows late Nothing 1
                late2 <- createRosterSlotRecord rosterDayWithRows late Nothing 2
                _ <- updateRecord (early0 |> set #startTime (Just (timeOfDay 8 0)))
                _ <- updateRecord (early1 |> set #startTime (Just (timeOfDay 9 0)))
                _ <- updateRecord (late0 |> set #startTime (Just (timeOfDay 10 0)))
                _ <- updateRecord (early2 |> set #startTime (Just (timeOfDay 11 0)))
                _ <- updateRecord (late2 |> set #startTime (Just (timeOfDay 12 0)))

                previewResponse <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callAction (RemoveRosterRowAction rosterDayWithRows.id)
                previewResponse `responseStatusShouldBe` status200
                previewResponse `responseBodyShouldContain` "1 shift cannot be packed into another column and will be deleted."
                previewResponse `responseBodyShouldContain` "confirmDeletePopulatedRow"

                unchangedEarly <- fetch early2.id
                unchangedLate <- fetch late2.id
                unchangedEarly.deletedAt `shouldBe` Nothing
                unchangedLate.deletedAt `shouldBe` Nothing

                confirmResponse <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams
                            (RemoveRosterRowAction rosterDayWithRows.id)
                            [("confirmDeletePopulatedRow", "true")]
                confirmResponse `responseStatusShouldBe` status200

                preservedFirst <- fetch early2.id
                deletedRightmost <- fetch late2.id
                preservedFirst.deletedAt `shouldBe` Nothing
                preservedFirst.rosterWeekSlotDefinitionId `shouldBe` late1.rosterWeekSlotDefinitionId
                preservedFirst.rowIndex `shouldBe` 1
                deletedRightmost.deletedAt `shouldSatisfy` isJust

        it "manager can add and delete draft week roster spacing columns via HTMX" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-slot-columns@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                early <- fetchSlotNameRecord venue "Early"
                rosterWeek <- createRosterWeekRecord venue 0 False
                rosterDay <- createRosterDayRecord rosterWeek 0
                earlySlot <- createRosterSlotRecord rosterDay early Nothing 0
                _ <- updateRecord (earlySlot |> set #startTime (Just (timeOfDay 9 0)))

                createResponse <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams (CreateRosterWeekSlotDefinitionAction rosterWeek.id)
                            []
                createResponse `responseStatusShouldBe` status200

                newColumn <- query @RosterWeekSlotDefinition
                    |> filterWhere (#rosterWeekId, unpackId rosterWeek.id)
                    |> filterWhere (#name, "New column")
                    |> filterWhere (#deletedAt, Nothing)
                    |> fetchOne
                createdSlots <-
                    query @RosterSlot
                        |> filterWhere (#rosterDayId, unpackId rosterDay.id)
                        |> filterWhere (#rosterWeekSlotDefinitionId, unpackId newColumn.id)
                        |> filterWhere (#deletedAt, Nothing)
                        |> fetch
                createdSlots `shouldBe` []

                deleteResponse <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callAction (DeleteRosterWeekSlotDefinitionAction newColumn.id)
                deleteResponse `responseStatusShouldBe` status200
                deleted <- fetch newColumn.id
                deleted.deletedAt `shouldSatisfy` isJust
                deletedSlots <-
                    query @RosterSlot
                        |> filterWhere (#rosterWeekSlotDefinitionId, unpackId newColumn.id)
                        |> fetch
                deletedSlots `shouldSatisfy` all (isJust . (.deletedAt))

        it "manager can manually sort draft week shifts top-to-bottom then across columns" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-sort-columns@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                early <- fetchSlotNameRecord venue "Early"
                late <- fetchSlotNameRecord venue "Late"
                alpha <- createStaffRecord venue Nothing "Alpha" "Crew"
                bravo <- createStaffRecord venue Nothing "Bravo" "Crew"
                charlie <- createStaffRecord venue Nothing "Charlie" "Crew"
                rosterWeek <- createRosterWeekRecord venue 0 False
                rosterDay <- createRosterDayRecord rosterWeek 0
                charlieSlot <- createRosterSlotRecord rosterDay early (Just charlie) 0
                alphaSlot <- createRosterSlotRecord rosterDay late (Just alpha) 0
                bravoSlot <- createRosterSlotRecord rosterDay early (Just bravo) 1
                _ <- updateRecord (charlieSlot |> set #startTime (Just (timeOfDay 11 0)))
                _ <- updateRecord (alphaSlot |> set #startTime (Just (timeOfDay 9 0)))
                _ <- updateRecord (bravoSlot |> set #startTime (Just (timeOfDay 9 0)))

                response <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callAction (SortRosterWeekAction rosterWeek.id)
                response `responseStatusShouldBe` status200

                sortedAlphaSlot <- fetch alphaSlot.id
                sortedBravoSlot <- fetch bravoSlot.id
                sortedCharlieSlot <- fetch charlieSlot.id
                earlyDefinition <- query @RosterWeekSlotDefinition
                    |> filterWhere (#rosterWeekId, unpackId rosterWeek.id)
                    |> filterWhere (#name, "Early")
                    |> filterWhere (#deletedAt, Nothing)
                    |> fetchOne
                lateDefinition <- query @RosterWeekSlotDefinition
                    |> filterWhere (#rosterWeekId, unpackId rosterWeek.id)
                    |> filterWhere (#name, "Late")
                    |> filterWhere (#deletedAt, Nothing)
                    |> fetchOne

                sortedAlphaSlot.id `shouldBe` alphaSlot.id
                sortedAlphaSlot.rosterWeekSlotDefinitionId `shouldBe` unpackId earlyDefinition.id
                sortedAlphaSlot.rowIndex `shouldBe` 0
                sortedBravoSlot.id `shouldBe` bravoSlot.id
                sortedBravoSlot.rosterWeekSlotDefinitionId `shouldBe` unpackId earlyDefinition.id
                sortedBravoSlot.rowIndex `shouldBe` 1
                sortedCharlieSlot.id `shouldBe` charlieSlot.id
                sortedCharlieSlot.rosterWeekSlotDefinitionId `shouldBe` unpackId lateDefinition.id
                sortedCharlieSlot.rowIndex `shouldBe` 0

        it "deleting a populated roster column reallocates shifts into remaining columns and adds rows" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-delete-packed-column@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                early <- fetchSlotNameRecord venue "Early"
                late <- fetchSlotNameRecord venue "Late"
                alpha <- createStaffRecord venue Nothing "Alpha" "Crew"
                bravo <- createStaffRecord venue Nothing "Bravo" "Crew"
                charlie <- createStaffRecord venue Nothing "Charlie" "Crew"
                rosterWeek <- createRosterWeekRecord venue 0 False
                rosterDay <- createRosterDayRecord rosterWeek 0
                bravoSlot <- createRosterSlotRecord rosterDay early (Just bravo) 0
                charlieSlot <- createRosterSlotRecord rosterDay late (Just charlie) 0
                alphaSlot <- createRosterSlotRecord rosterDay late (Just alpha) 1
                _ <- updateRecord (bravoSlot |> set #startTime (Just (timeOfDay 10 0)))
                _ <- updateRecord (charlieSlot |> set #startTime (Just (timeOfDay 11 0)))
                _ <- updateRecord (alphaSlot |> set #startTime (Just (timeOfDay 9 0)))
                earlyDefinition <- query @RosterWeekSlotDefinition
                    |> filterWhere (#rosterWeekId, unpackId rosterWeek.id)
                    |> filterWhere (#name, "Early")
                    |> filterWhere (#deletedAt, Nothing)
                    |> fetchOne
                lateDefinition <- query @RosterWeekSlotDefinition
                    |> filterWhere (#rosterWeekId, unpackId rosterWeek.id)
                    |> filterWhere (#name, "Late")
                    |> filterWhere (#deletedAt, Nothing)
                    |> fetchOne

                response <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callAction (DeleteRosterWeekSlotDefinitionAction lateDefinition.id)
                response `responseStatusShouldBe` status200

                deletedLateDefinition <- fetch lateDefinition.id
                deletedLateDefinition.deletedAt `shouldSatisfy` isJust
                packedSlots <- query @RosterSlot
                    |> filterWhere (#rosterDayId, unpackId rosterDay.id)
                    |> filterWhere (#deletedAt, Nothing)
                    |> fetch
                let packedDataSlots = sortOn (.rowIndex) (filter (\slot -> slot.rosterWeekSlotDefinitionId == unpackId earlyDefinition.id && isJust slot.staffId) packedSlots)
                map (.id) packedDataSlots `shouldBe` [alphaSlot.id, bravoSlot.id, charlieSlot.id]
                map (.rowIndex) packedDataSlots `shouldBe` [0, 1, 2]
                map (.startTime) packedDataSlots `shouldBe` map (Just . uncurry timeOfDay) [(9, 0), (10, 0), (11, 0)]

        it "manager can toggle a draft week live via HTMX without redirecting" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-live-toggle-htmx@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                slotName <- fetchSlotNameRecord venue "Early"
                level <- createPayLevelRecord venue "Level 1"
                shiftType <- createShiftTypeRecord venue level "Floor"
                staffMember <- createStaffRecord venue Nothing "Alpha" "Crew"
                rosterWeek <- createRosterWeekRecord venue 0 False
                rosterDay <- createRosterDayRecord rosterWeek 0
                slot <- createRosterSlotRecord rosterDay slotName (Just staffMember) 0
                _ <- updateRecord
                    ( slot
                        |> set #startTime (Just (timeOfDay 9 0))
                        |> set #endTime (Just (timeOfDay 17 0))
                        |> set #shiftTypeId (Just (unpackId shiftType.id))
                    )

                response <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams
                            (ToggleRosterWeekLiveStatusAction rosterWeek.id)
                            [("isLive", "on")]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` cs rosterContentFragmentId
                response `responseBodyShouldContain` "Roster week is now live."
                response `responseBodyShouldContain` ">Alpha<"
                response `responseBodyShouldContain` "9:00 AM"
                response `responseBodyShouldContain` ">Floor<"
                response `responseBodyShouldNotContain` "data-roster-day-add=\"true\""
                response `responseBodyShouldNotContain` "data-roster-day-remove=\"true\""
                response `responseBodyShouldNotContain` "name=\"staffId\""
                response `responseBodyShouldNotContain` "js-time-picker-trigger"

        it "rejects invalid roster slot timing on create and update" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-invalid-slot-time@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                venueConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                _ <- updateRecord (venueConfig |> set #rosterEndTimesEnabled True)
                slotName <- fetchSlotNameRecord venue "Early"
                staffMember <- createStaffRecord venue Nothing "Alpha" "Crew"
                level <- createPayLevelRecord venue "Level 1"
                shiftType <- createShiftTypeRecord venue level "Floor"
                rosterWeek <- createRosterWeekRecord venue 0 False
                rosterDay <- createRosterDayRecord rosterWeek 0
                slotDefinition <- ensureRosterWeekSlotDefinitionForSlotName rosterDay slotName

                createResponse <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams
                            (CreateRosterSlotAction rosterDay.id slotDefinition.id 0)
                            [ ("staffId", idToParam staffMember.id)
                            , ("startTime", "09:00")
                            , ("endTime", "08:00")
                            , ("shiftTypeId", idToParam shiftType.id)
                            ]

                createResponse `responseStatusShouldBe` status200
                createResponse `responseBodyShouldContain` "Choose an end time after the start time within the 6:00 AM to 5:45 AM roster day."
                query @RosterSlot
                    |> filterWhere (#rosterDayId, unpackId rosterDay.id)
                    |> filterWhere (#deletedAt, Nothing)
                    |> fetchCount
                    >>= (`shouldBe` 0)

                slot <- createRosterSlotRecord rosterDay slotName (Just staffMember) 1
                completeSlot <- updateRecord
                    ( slot
                        |> set #startTime (Just (timeOfDay 9 0))
                        |> set #endTime (Just (timeOfDay 17 0))
                        |> set #shiftTypeId (Just (unpackId shiftType.id))
                        |> set #durationMinutes (Just 480)
                    )

                updateResponse <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams
                            (UpdateRosterSlotAction completeSlot.id)
                            [ ("staffId", idToParam staffMember.id)
                            , ("startTime", "09:00")
                            , ("endTime", "08:00")
                            , ("shiftTypeId", idToParam shiftType.id)
                            ]

                updateResponse `responseStatusShouldBe` status200
                updateResponse `responseBodyShouldContain` "Choose an end time after the start time within the 6:00 AM to 5:45 AM roster day."
                unchangedSlot <- fetch completeSlot.id
                unchangedSlot.startTime `shouldBe` Just (timeOfDay 9 0)
                unchangedSlot.endTime `shouldBe` Just (timeOfDay 17 0)
                unchangedSlot.durationMinutes `shouldBe` Just 480

        it "blocks publishing staffed shifts with invalid timing when end times are enabled" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-invalid-publish-time@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                venueConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                _ <- updateRecord (venueConfig |> set #rosterEndTimesEnabled True)
                slotName <- fetchSlotNameRecord venue "Early"
                staffMember <- createStaffRecord venue Nothing "Alpha" "Crew"
                level <- createPayLevelRecord venue "Level 1"
                shiftType <- createShiftTypeRecord venue level "Floor"
                rosterWeek <- createRosterWeekRecord venue 0 False
                rosterDay <- createRosterDayRecord rosterWeek 0
                slot <- createRosterSlotRecord rosterDay slotName (Just staffMember) 0
                _ <- updateRecord
                    ( slot
                        |> set #startTime (Just (timeOfDay 9 0))
                        |> set #endTime (Just (timeOfDay 8 0))
                        |> set #shiftTypeId (Just (unpackId shiftType.id))
                        |> set #durationMinutes (Just 1380)
                    )

                response <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams
                            (ToggleRosterWeekLiveStatusAction rosterWeek.id)
                            [("isLive", "on")]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "valid end time"
                updatedWeek <- fetch rosterWeek.id
                updatedWeek.isLive `shouldBe` False

        it "allows valid overnight staffed shifts to go live when end times are enabled" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-overnight-publish@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                venueConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                _ <- updateRecord (venueConfig |> set #rosterEndTimesEnabled True)
                slotName <- fetchSlotNameRecord venue "Late"
                staffMember <- createStaffRecord venue Nothing "Alpha" "Crew"
                level <- createPayLevelRecord venue "Level 1"
                shiftType <- createShiftTypeRecord venue level "Bar"
                rosterWeek <- createRosterWeekRecord venue 0 False
                rosterDay <- createRosterDayRecord rosterWeek 0
                slot <- createRosterSlotRecord rosterDay slotName (Just staffMember) 0
                _ <- updateRecord
                    ( slot
                        |> set #startTime (Just (timeOfDay 22 0))
                        |> set #endTime (Just (timeOfDay 2 0))
                        |> set #shiftTypeId (Just (unpackId shiftType.id))
                        |> set #durationMinutes (Just 240)
                    )

                response <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams
                            (ToggleRosterWeekLiveStatusAction rosterWeek.id)
                            [("isLive", "on")]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Roster week is now live."
                updatedWeek <- fetch rosterWeek.id
                updatedWeek.isLive `shouldBe` True

        it "renders live closed days as read-only closed text without the lock control" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-live-closed-day@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                _ <- fetchSlotNameRecord venue "Early"
                rosterWeek <- createRosterWeekRecord venue 0 True
                rosterDay <- createRosterDayRecord rosterWeek 0
                _ <- updateRecord (rosterDay |> set #isClosed True)

                response <- withUserAndCurrentVenue manager venue.id do
                    callAction (ShowRosterWeekAction 0)

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "roster-day-closed-label"
                response `responseBodyShouldContain` "CLOSED"
                response `responseBodyShouldNotContain` "data-roster-day-closed-toggle=\"true\""
                response `responseBodyShouldNotContain` "bi-lock-fill"
                response `responseBodyShouldNotContain` "data-roster-day-add=\"true\""
                response `responseBodyShouldNotContain` "data-roster-day-remove=\"true\""

        it "staff can see published weeks" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                user <- createUserRecord "roster-staff-live@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user "worker"
                slotName <- fetchSlotNameRecord venue "Early"
                staffMember <- createStaffRecord venue Nothing "Alpha" "Crew"
                rosterWeek <- createRosterWeekRecord venue 0 True
                rosterDay <- createRosterDayRecord rosterWeek 0
                _ <- createRosterSlotRecord rosterDay slotName (Just staffMember) 0

                response <- withUser user do
                    callAction (ShowRosterWeekAction 0)

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` ">Alpha<"
                response `responseBodyShouldNotContain` "No roster exists for this week yet."

        it "hides roster warning controls and highlights from staff" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-warnings@example.com" "staff" True
                worker <- createUserRecord "roster-worker-warnings@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                _ <- createVenueMembershipRecord venue worker "worker"
                _ <-
                    newRecord @UserPreference
                        |> set #userId (unpackId worker.id)
                        |> set #showShiftTypeHighlights False
                        |> createRecord
                _ <- fetchSlotNameRecord venue "Early"
                _ <- createRosterWeekRecord venue 0 True

                managerResponse <- withUserAndCurrentVenue manager venue.id do
                    callAction (ShowRosterWeekAction 0)

                managerResponse `responseStatusShouldBe` status200
                managerResponse `responseBodyShouldContain` "Warnings disabled"

                workerResponse <- withUserAndCurrentVenue worker venue.id do
                    callAction (ShowRosterWeekAction 0)

                workerResponse `responseStatusShouldBe` status200
                workerResponse `responseBodyShouldNotContain` "Warnings enabled"
                workerResponse `responseBodyShouldNotContain` "Warnings disabled"
                workerResponse `responseBodyShouldContain` "data-roster-warnings=\"hidden\""

        it "shows roster JPG export only to managers on live weeks" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-export-live-only@example.com" "staff" True
                worker <- createUserRecord "roster-worker-export-hidden@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                _ <- createVenueMembershipRecord venue worker "worker"
                _ <- fetchSlotNameRecord venue "Early"
                draftWeek <- createRosterWeekRecord venue 0 False

                draftManagerResponse <- withUserAndCurrentVenue manager venue.id do
                    callAction (ShowRosterWeekAction 0)
                draftManagerResponse `responseStatusShouldBe` status200
                draftManagerResponse `responseBodyShouldNotContain` "Export JPG"

                _ <- updateRecord (draftWeek |> set #isLive True)

                liveManagerResponse <- withUserAndCurrentVenue manager venue.id do
                    callAction (ShowRosterWeekAction 0)
                liveManagerResponse `responseStatusShouldBe` status200
                liveManagerResponse `responseBodyShouldContain` "Export JPG"

                workerResponse <- withUserAndCurrentVenue worker venue.id do
                    callAction (ShowRosterWeekAction 0)
                workerResponse `responseStatusShouldBe` status200
                workerResponse `responseBodyShouldNotContain` "Export JPG"

        it "shows week wage estimates to admins only when end times are enabled" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                admin <- createUserRecord "roster-admin-wage-prediction@example.com" "staff" True
                manager <- createUserRecord "roster-manager-wage-prediction@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin "venue_admin"
                _ <- createVenueMembershipRecord venue manager "manager"
                venueConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                _ <- updateRecord (venueConfig |> set #rosterEndTimesEnabled True)
                slotName <- fetchSlotNameRecord venue "Early"
                staffMember <- createStaffRecord venue Nothing "Alpha" "Crew"
                _ <- updateRecord (staffMember |> set #employmentBasis Permanent)
                level <- createPayLevelRecordWithRates venue "Level 1" 20 5 10 1 1.5 2
                shiftType <- createShiftTypeRecord venue level "Floor"
                rosterWeek <- createRosterWeekRecord venue 0 True
                rosterDay <- createRosterDayRecord rosterWeek 0
                slot <- createRosterSlotRecord rosterDay slotName (Just staffMember) 0
                _ <- updateRecord
                    ( slot
                        |> set #startTime (Just (timeOfDay 9 0))
                        |> set #endTime (Just (timeOfDay 17 0))
                        |> set #shiftTypeId (Just (unpackId shiftType.id))
                        |> set #durationMinutes (Just 480)
                    )
                incompleteSlot <- createRosterSlotRecord rosterDay slotName (Just staffMember) 1
                _ <- updateRecord (incompleteSlot |> set #startTime (Just (timeOfDay 9 0)))
                invalidTimingSlot <- createRosterSlotRecord rosterDay slotName (Just staffMember) 2
                _ <- updateRecord
                    ( invalidTimingSlot
                        |> set #startTime (Just (timeOfDay 9 0))
                        |> set #endTime (Just (timeOfDay 8 0))
                        |> set #shiftTypeId (Just (unpackId shiftType.id))
                        |> set #durationMinutes (Just 1380)
                    )
                _ <-
                    newRecord @UserPreference
                        |> set #userId (unpackId admin.id)
                        |> set #showWageEstimates True
                        |> createRecord

                adminResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callAction (ShowRosterWeekAction 0)

                adminResponse `responseStatusShouldBe` status200
                adminResponse `responseBodyShouldContain` "data-roster-layout=\"day_rows\""
                adminResponse `responseBodyShouldContain` "Wages:"
                adminResponse `responseBodyShouldContain` "$150.00"
                adminResponse `responseBodyShouldContain` "roster-wage-summary"
                adminResponse `responseBodyShouldContain` "roster-wage-summary-total"
                adminResponse `responseBodyShouldNotContain` "draft shift excluded"
                adminResponse `responseBodyShouldNotContain` "roster-wage-summary-warning"
                adminResponse `responseBodyShouldContain` "roster-wage-rail-head"
                adminResponse `responseBodyShouldContain` ">Wages<"
                adminResponse `responseBodyShouldContain` "roster-day-wage-total"
                adminResponse `responseBodyShouldContain` "aria-label=\"Wages for day\""
                adminResponse `responseBodyShouldContain` "Wages enabled"
                adminResponse `responseBodyShouldNotContain` "Admin estimate only"
                adminResponse `responseBodyShouldNotContain` "roster-wage-prediction"

                dayColumnsResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams
                            (UpdateRosterLayoutPreferenceAction 0)
                            [("rosterLayoutMode", "day_columns")]

                dayColumnsResponse `responseStatusShouldBe` status200
                dayColumnsResponse `responseBodyShouldContain` "data-roster-layout=\"day_columns\""
                dayColumnsResponse `responseBodyShouldContain` "Wages:"
                dayColumnsResponse `responseBodyShouldContain` "roster-wage-summary-total"
                dayColumnsResponse `responseBodyShouldContain` "roster-day-wage-total-labeled"
                dayColumnsResponse `responseBodyShouldContain` "Wages"
                dayColumnsResponse `responseBodyShouldContain` "aria-label=\"Wages for day\""
                dayColumnsResponse `responseBodyShouldNotContain` "roster-wage-prediction"

                hiddenWagesResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams
                            (UpdateRosterWageEstimatePreferenceAction 0)
                            []

                hiddenWagesResponse `responseStatusShouldBe` status200
                hiddenWagesResponse `responseBodyShouldContain` "data-roster-wages=\"hidden\""
                hiddenWagesResponse `responseBodyShouldContain` "Wages disabled"
                hiddenWagesResponse `responseBodyShouldNotContain` "Wages:"
                hiddenWagesResponse `responseBodyShouldNotContain` "roster-wage-summary"
                hiddenWagesResponse `responseBodyShouldNotContain` "roster-day-wage-total"
                hiddenPreferences <- query @UserPreference
                    |> filterWhere (#userId, unpackId admin.id)
                    |> fetchOne
                hiddenPreferences.showWageEstimates `shouldBe` False

                managerResponse <- withUserAndCurrentVenue manager venue.id do
                    callAction (ShowRosterWeekAction 0)

                managerResponse `responseStatusShouldBe` status200
                managerResponse `responseBodyShouldNotContain` "Week wage estimate"
                managerResponse `responseBodyShouldNotContain` "roster-wage-summary"
                managerResponse `responseBodyShouldNotContain` "roster-wage-summary-total"
                managerResponse `responseBodyShouldNotContain` "roster-day-wage-total"
                managerResponse `responseBodyShouldNotContain` "aria-label=\"Wages for day\""
                managerResponse `responseBodyShouldNotContain` "roster-wage-prediction"
                managerResponse `responseBodyShouldNotContain` "Wages disabled"

        it "hides wage estimate controls when roster end times are disabled" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                admin <- createUserRecord "roster-admin-wage-end-times-disabled@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin "venue_admin"
                venueConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                _ <- updateRecord (venueConfig |> set #rosterEndTimesEnabled False)
                slotName <- fetchSlotNameRecord venue "Early"
                staffMember <- createStaffRecord venue Nothing "Alpha" "Crew"
                _ <- updateRecord (staffMember |> set #employmentBasis Permanent)
                level <- createPayLevelRecordWithRates venue "Level 1" 20 5 10 1 1.5 2
                shiftType <- createShiftTypeRecord venue level "Floor"
                rosterWeek <- createRosterWeekRecord venue 0 True
                rosterDay <- createRosterDayRecord rosterWeek 0
                slot <- createRosterSlotRecord rosterDay slotName (Just staffMember) 0
                _ <- updateRecord
                    ( slot
                        |> set #startTime (Just (timeOfDay 9 0))
                        |> set #endTime (Just (timeOfDay 17 0))
                        |> set #shiftTypeId (Just (unpackId shiftType.id))
                        |> set #durationMinutes (Just 480)
                    )

                adminResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callAction (ShowRosterWeekAction 0)

                adminResponse `responseStatusShouldBe` status200
                adminResponse `responseBodyShouldContain` "data-roster-end-times=\"false\""
                adminResponse `responseBodyShouldContain` "data-roster-wages=\"hidden\""
                adminResponse `responseBodyShouldNotContain` "Wages disabled"
                adminResponse `responseBodyShouldNotContain` "Wages:"
                adminResponse `responseBodyShouldNotContain` "roster-wage-summary"
                adminResponse `responseBodyShouldNotContain` "roster-day-wage-total"
                adminResponse `responseBodyShouldNotContain` "roster-wage-rail-head"

                toggleResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams
                            (UpdateRosterWageEstimatePreferenceAction 0)
                            [("showWageEstimates", "true")]

                toggleResponse `responseStatusShouldBe` status200
                toggleResponse `responseBodyShouldNotContain` "Wages disabled"
                toggleResponse `responseBodyShouldNotContain` "Wages:"
                hiddenPreferences <- query @UserPreference
                    |> filterWhere (#userId, unpackId admin.id)
                    |> fetchOneOrNothing
                hiddenPreferences `shouldBe` Nothing

        it "manager can toggle a draft week live" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-publish@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                rosterWeek <- createRosterWeekRecord venue 0 False

                response <- withUser manager do
                    callActionWithParams
                        (ToggleRosterWeekLiveStatusAction rosterWeek.id)
                        [("isLive", "on")]

                response `responseStatusShouldBe` status302

                publishedWeek <- fetch rosterWeek.id
                publishedWeek.isLive `shouldBe` True

        it "queues pending timesheet jobs when an opted-in roster week is published" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-publish-auto-timesheets@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                venueConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                _ <- updateRecord (venueConfig |> set #autoTimesheetCreationEnabled True)
                slotName <- fetchSlotNameRecord venue "Late"
                staffMember <- createStaffRecord venue (Just manager) "Alpha" "Crew"
                level <- createPayLevelRecord venue "Level 1"
                shiftType <- createShiftTypeRecord venue level "Bar"
                rosterWeek <- createRosterWeekRecord venue 0 False
                rosterDay <- createRosterDayRecord rosterWeek 0
                slot <- createRosterSlotRecord rosterDay slotName (Just staffMember) 0
                _ <- updateRecord
                    ( slot
                        |> set #startTime (Just (timeOfDay 22 0))
                        |> set #endTime (Just (timeOfDay 2 0))
                        |> set #shiftTypeId (Just (unpackId shiftType.id))
                        |> set #durationMinutes (Just 240)
                    )

                response <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams
                            (ToggleRosterWeekLiveStatusAction rosterWeek.id)
                            [("isLive", "on")]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Pending timesheet jobs queued for 1 shifts."
                [job] <- query @AppJob |> fetch
                job.jobKind `shouldBe` rosterTimesheetCreationJobKind
                job.relatedTable `shouldBe` Just "roster_slots"
                job.relatedId `shouldBe` Just (unpackId slot.id)

        it "cancels not-started and retry roster-timesheet jobs when a live week returns to draft without stopping running jobs" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-draft-cancels-auto-timesheets@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                venueConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                _ <- updateRecord (venueConfig |> set #autoTimesheetCreationEnabled True)
                slotName <- fetchSlotNameRecord venue "Late"
                alpha <- createStaffRecord venue (Just manager) "Alpha" "Crew"
                bravoUser <- createUserRecord "roster-timesheet-cancel-bravo@example.com" "staff" True
                charlieUser <- createUserRecord "roster-timesheet-cancel-charlie@example.com" "staff" True
                _ <- createVenueMembershipRecord venue bravoUser "worker"
                _ <- createVenueMembershipRecord venue charlieUser "worker"
                bravo <- createStaffRecord venue (Just bravoUser) "Bravo" "Crew"
                charlie <- createStaffRecord venue (Just charlieUser) "Charlie" "Crew"
                level <- createPayLevelRecord venue "Level 1"
                shiftType <- createShiftTypeRecord venue level "Bar"
                rosterWeek <- createRosterWeekRecord venue 0 False
                rosterDay <- createRosterDayRecord rosterWeek 0
                notStartedSlot <- createRosterSlotRecord rosterDay slotName (Just alpha) 0
                retrySlot <- createRosterSlotRecord rosterDay slotName (Just bravo) 1
                runningSlot <- createRosterSlotRecord rosterDay slotName (Just charlie) 2
                forM_ [notStartedSlot, retrySlot, runningSlot] \slot ->
                    updateRecord
                        ( slot
                            |> set #startTime (Just (timeOfDay 22 0))
                            |> set #endTime (Just (timeOfDay 2 0))
                            |> set #shiftTypeId (Just (unpackId shiftType.id))
                            |> set #durationMinutes (Just 240)
                        )

                publishResponse <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams
                            (ToggleRosterWeekLiveStatusAction rosterWeek.id)
                            [("isLive", "on")]
                publishResponse `responseStatusShouldBe` status200

                notStartedJob <- fetchRosterTimesheetJobForSlot notStartedSlot
                retryJob <- fetchRosterTimesheetJobForSlot retrySlot
                runningJob <- fetchRosterTimesheetJobForSlot runningSlot
                _ <- updateRecord (retryJob |> set #status JobStatusRetry)
                _ <- updateRecord (runningJob |> set #status JobStatusRunning)

                draftResponse <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callAction (ToggleRosterWeekLiveStatusAction rosterWeek.id)

                draftResponse `responseStatusShouldBe` status200
                draftWeek <- fetch rosterWeek.id
                draftWeek.isLive `shouldBe` False
                assertRosterTimesheetJobCancelled notStartedJob
                assertRosterTimesheetJobCancelled retryJob
                stillRunningJob <- fetch runningJob.id
                stillRunningJob.status `shouldBe` JobStatusRunning

        it "republishes draft-edited roster slots with recalculated timesheet run times and preserves generated timesheets" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-republish-auto-timesheets@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                venueConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                _ <- updateRecord (venueConfig |> set #autoTimesheetCreationEnabled True |> set #rosterEndTimesEnabled True)
                slotName <- fetchSlotNameRecord venue "Late"
                staffMember <- createStaffRecord venue (Just manager) "Alpha" "Crew"
                level <- createPayLevelRecord venue "Level 1"
                shiftType <- createShiftTypeRecord venue level "Bar"
                rosterWeek <- createRosterWeekRecord venue 0 False
                rosterDay <- createRosterDayRecord rosterWeek 0
                slot <- createRosterSlotRecord rosterDay slotName (Just staffMember) 0
                completeSlot <- updateRecord
                    ( slot
                        |> set #startTime (Just (timeOfDay 22 0))
                        |> set #endTime (Just (timeOfDay 2 0))
                        |> set #shiftTypeId (Just (unpackId shiftType.id))
                        |> set #durationMinutes (Just 240)
                    )

                firstPublishResponse <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams
                            (ToggleRosterWeekLiveStatusAction rosterWeek.id)
                            [("isLive", "on")]
                firstPublishResponse `responseStatusShouldBe` status200
                firstJob <- fetchRosterTimesheetJobForSlot completeSlot
                let firstRunAt = firstJob.runAt
                performRosterTimesheetCreationJob firstJob
                [generatedEntry] <- query @TimesheetEntry |> fetch
                generatedEntry.startTime `shouldBe` timeOfDay 22 0
                generatedEntry.endTime `shouldBe` timeOfDay 2 0

                draftResponse <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callAction (ToggleRosterWeekLiveStatusAction rosterWeek.id)
                draftResponse `responseStatusShouldBe` status200

                editResponse <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams
                            (UpdateRosterSlotAction completeSlot.id)
                            [ ("staffId", idToParam staffMember.id)
                            , ("startTime", "22:00")
                            , ("endTime", "03:00")
                            , ("shiftTypeId", idToParam shiftType.id)
                            ]
                editResponse `responseStatusShouldBe` status200
                [entryAfterDraftEdit] <- query @TimesheetEntry |> fetch
                entryAfterDraftEdit.id `shouldBe` generatedEntry.id
                entryAfterDraftEdit.startTime `shouldBe` timeOfDay 22 0
                entryAfterDraftEdit.endTime `shouldBe` timeOfDay 2 0

                secondPublishResponse <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams
                            (ToggleRosterWeekLiveStatusAction rosterWeek.id)
                            [("isLive", "on")]
                secondPublishResponse `responseStatusShouldBe` status200
                secondPublishResponse `responseBodyShouldContain` "Pending timesheet jobs queued for 1 shifts."
                jobs <- fetchRosterTimesheetJobsForSlot completeSlot
                length jobs `shouldBe` 2
                let secondJob = fromJust (last jobs)
                expectedSecondRunAt <- rosterTimesheetRunAt venueConfig (addDays 0 (venueWeekStartDate venueConfig rosterWeek.weekOffset)) (timeOfDay 22 0) (timeOfDay 3 0)
                firstRunAt `shouldNotBe` expectedSecondRunAt
                secondJob.runAt `shouldBe` expectedSecondRunAt

                performRosterTimesheetCreationJob secondJob
                [entryAfterRepublishJob] <- query @TimesheetEntry |> fetch
                entryAfterRepublishJob.id `shouldBe` generatedEntry.id
                entryAfterRepublishJob.startTime `shouldBe` timeOfDay 22 0
                entryAfterRepublishJob.endTime `shouldBe` timeOfDay 2 0
                completedSecondJob <- fetch secondJob.id
                completedSecondJob.result `shouldBe` Aeson.object ["status" Aeson..= ("already_exists" :: Text), "timesheetEntryId" Aeson..= Just (tshow generatedEntry.id)]

        it "warns and leaves an auto-created timesheet unchanged when the source roster slot is edited later" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-auto-timesheet-edit-warning@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                venueConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                _ <- updateRecord (venueConfig |> set #autoTimesheetCreationEnabled True |> set #rosterEndTimesEnabled True)
                slotName <- fetchSlotNameRecord venue "Late"
                alpha <- createStaffRecord venue (Just manager) "Alpha" "Crew"
                bravoUser <- createUserRecord "roster-timesheet-warning-bravo@example.com" "staff" True
                _ <- createVenueMembershipRecord venue bravoUser "worker"
                bravo <- createStaffRecord venue (Just bravoUser) "Bravo" "Crew"
                level <- createPayLevelRecord venue "Level 1"
                shiftType <- createShiftTypeRecord venue level "Bar"
                rosterWeek <- createRosterWeekRecord venue 0 True
                rosterDay <- createRosterDayRecord rosterWeek 0
                slot <- createRosterSlotRecord rosterDay slotName (Just alpha) 0
                completeSlot <- updateRecord
                    ( slot
                        |> set #startTime (Just (timeOfDay 22 0))
                        |> set #endTime (Just (timeOfDay 2 0))
                        |> set #shiftTypeId (Just (unpackId shiftType.id))
                        |> set #durationMinutes (Just 240)
                    )
                [EnqueuedAppJob job] <- enqueueRosterTimesheetCreationJobsForWeek (Just manager.id) rosterWeek
                performRosterTimesheetCreationJob job
                [entry] <- query @TimesheetEntry |> fetch
                entry.staffId `shouldBe` unpackId alpha.id

                _ <- updateRecord (rosterWeek |> set #isLive False)
                response <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams
                            (UpdateRosterSlotAction completeSlot.id)
                            [ ("staffId", idToParam bravo.id)
                            , ("startTime", "22:00")
                            , ("endTime", "02:00")
                            , ("shiftTypeId", idToParam shiftType.id)
                            ]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "A pending timesheet already exists for this roster slot, so the timesheet was not changed. Edit the timesheet entry directly."
                [unchangedEntry] <- query @TimesheetEntry |> fetch
                unchangedEntry.id `shouldBe` entry.id
                unchangedEntry.staffId `shouldBe` unpackId alpha.id
                unchangedEntry.startTime `shouldBe` timeOfDay 22 0
                unchangedEntry.endTime `shouldBe` timeOfDay 2 0
                unchangedEntry.shiftTypeId `shouldBe` unpackId shiftType.id
                unchangedEntry.sourceRosterSlotId `shouldBe` Just (unpackId completeSlot.id)

        it "blocks publishing staffed shifts missing end times or shift types when enabled" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-publish-required-fields@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                venueConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                _ <- updateRecord (venueConfig |> set #rosterEndTimesEnabled True)
                slotName <- fetchSlotNameRecord venue "Early"
                staffMember <- createStaffRecord venue Nothing "Alpha" "Crew"
                level <- createPayLevelRecord venue "Level 1"
                shiftType <- createShiftTypeRecord venue level "Floor"
                rosterWeek <- createRosterWeekRecord venue 0 False
                rosterDay <- createRosterDayRecord rosterWeek 0
                slot <- createRosterSlotRecord rosterDay slotName (Just staffMember) 0
                _ <- updateRecord (slot |> set #startTime (Just (timeOfDay 9 0)) |> set #shiftTypeId Nothing)

                draftResponse <- withUserAndCurrentVenue manager venue.id do
                    callAction (ShowRosterWeekAction 0)
                draftResponse `responseStatusShouldBe` status200
                draftResponse `responseBodyShouldNotContain` "is-roster-shift-publish-required"
                draftResponse `responseBodyShouldNotContain` "required after failed publish"

                blockedResponse <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams
                            (ToggleRosterWeekLiveStatusAction rosterWeek.id)
                            [("isLive", "on")]

                blockedResponse `responseStatusShouldBe` status200
                blockedResponse `responseBodyShouldContain` "Roster week cannot go live until every staffed shift has a start time, valid end time, and shift type."
                blockedResponse `responseBodyShouldContain` "is-roster-shift-publish-required"
                blockedWeek <- fetch rosterWeek.id
                blockedWeek.isLive `shouldBe` False

                _ <- updateRecord
                    ( slot
                        |> set #endTime (Just (timeOfDay 17 0))
                        |> set #shiftTypeId (Just (unpackId shiftType.id))
                        |> set #durationMinutes (Just 480)
                    )

                publishedResponse <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams
                            (ToggleRosterWeekLiveStatusAction rosterWeek.id)
                            [("isLive", "on")]

                publishedResponse `responseStatusShouldBe` status200
                publishedResponse `responseBodyShouldNotContain` "is-roster-shift-publish-required"
                publishedResponse `responseBodyShouldNotContain` "required after failed publish"
                publishedWeek <- fetch rosterWeek.id
                publishedWeek.isLive `shouldBe` True

        it "blocks publishing staffed shifts missing shift type when end times are disabled" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-publish-type-required@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                venueConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                _ <- updateRecord (venueConfig |> set #rosterEndTimesEnabled False)
                slotName <- fetchSlotNameRecord venue "Early"
                staffMember <- createStaffRecord venue Nothing "Alpha" "Crew"
                level <- createPayLevelRecord venue "Level 1"
                shiftType <- createShiftTypeRecord venue level "Floor"
                rosterWeek <- createRosterWeekRecord venue 0 False
                rosterDay <- createRosterDayRecord rosterWeek 0
                slot <- createRosterSlotRecord rosterDay slotName (Just staffMember) 0
                _ <- updateRecord (slot |> set #startTime (Just (timeOfDay 9 0)) |> set #shiftTypeId Nothing)

                blockedResponse <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams
                            (ToggleRosterWeekLiveStatusAction rosterWeek.id)
                            [("isLive", "on")]

                blockedResponse `responseStatusShouldBe` status200
                blockedResponse `responseBodyShouldContain` "Roster week cannot go live until every staffed shift has a start time and shift type."
                blockedWeek <- fetch rosterWeek.id
                blockedWeek.isLive `shouldBe` False

                _ <- updateRecord (slot |> set #shiftTypeId (Just (unpackId shiftType.id)))

                publishedResponse <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams
                            (ToggleRosterWeekLiveStatusAction rosterWeek.id)
                            [("isLive", "on")]

                publishedResponse `responseStatusShouldBe` status200
                publishedWeek <- fetch rosterWeek.id
                publishedWeek.isLive `shouldBe` True

        it "manager slot edits can save end time and shift type with overnight duration" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-slot-end-type@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                venueConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                _ <- updateRecord (venueConfig |> set #rosterEndTimesEnabled True)
                slotName <- fetchSlotNameRecord venue "Late"
                staffMember <- createStaffRecord venue Nothing "Alpha" "Crew"
                level <- createPayLevelRecord venue "Level 1"
                shiftType <- createShiftTypeRecord venue level "Bar"
                rosterWeek <- createRosterWeekRecord venue 0 False
                rosterDay <- createRosterDayRecord rosterWeek 0
                slot <- createRosterSlotRecord rosterDay slotName (Just staffMember) 0

                response <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams
                            (UpdateRosterSlotAction slot.id)
                            [ ("staffId", idToParam staffMember.id)
                            , ("startTime", "22:00")
                            , ("endTime", "02:00")
                            , ("shiftTypeId", idToParam shiftType.id)
                            ]

                response `responseStatusShouldBe` status200
                updatedSlot <- fetch slot.id
                updatedSlot.startTime `shouldBe` Just (timeOfDay 22 0)
                updatedSlot.endTime `shouldBe` Just (timeOfDay 2 0)
                updatedSlot.shiftTypeId `shouldBe` Just (unpackId shiftType.id)
                updatedSlot.durationMinutes `shouldBe` Just 240

        it "manager can toggle a live week back to draft" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-draft-toggle@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                rosterWeek <- createRosterWeekRecord venue 0 True

                response <- withUser manager do
                    callAction (ToggleRosterWeekLiveStatusAction rosterWeek.id)

                response `responseStatusShouldBe` status302

                updatedWeek <- fetch rosterWeek.id
                updatedWeek.isLive `shouldBe` False

        it "manager can fetch a roster row fragment for the current venue" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-row-fragment@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                slotName <- fetchSlotNameRecord venue "Early"
                staffMember <- createStaffRecord venue Nothing "Alpha" "Crew"
                rosterWeek <- createRosterWeekRecord venue 0 False
                rosterDay <- createRosterDayRecord rosterWeek 0
                _ <- createRosterSlotRecord rosterDay slotName (Just staffMember) 0

                response <- withUserAndCurrentVenue manager venue.id do
                    callAction (ShowRosterWeekRowFragmentAction 0 rosterDay.id 0)

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` cs (rosterRowDomIdText rosterDay.id 0)
                response `responseBodyShouldContain` ">Alpha</div>"
                response `responseBodyShouldContain` "hx-get=\"/EditRosterSlotDialog?rosterSlotId="

        it "renders shift type colours without a roster highlight toggle" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-highlight-pref@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                slotName <- fetchSlotNameRecord venue "Early"
                staffMember <- createStaffRecord venue Nothing "Alpha" "Crew"
                level <- createPayLevelRecord venue "Level 1"
                shiftType <- createShiftTypeRecord venue level "Floor" >>= updateRecord . set #colourKey "palette-3"
                rosterWeek <- createRosterWeekRecord venue 0 False
                rosterDay <- createRosterDayRecord rosterWeek 0
                _ <- createRosterSlotRecord rosterDay slotName (Just staffMember) 0 >>= updateRecord . set #shiftTypeId (Just (unpackId shiftType.id))

                response <- withUserAndCurrentVenue manager venue.id do
                    callAction (ShowRosterWeekAction 0)

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "data-roster-layout=\"day_rows\""
                response `responseBodyShouldContain` "data-roster-shift-colour=\"palette-3\""
                response `responseBodyShouldNotContain` "data-roster-shift-type-highlights"
                response `responseBodyShouldNotContain` "showShiftTypeHighlights"
                response `responseBodyShouldNotContain` "roster-shift-type-highlights-toggle"

        it "persists roster layout preference and renders day columns" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-layout-pref@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                slotName <- fetchSlotNameRecord venue "Early"
                staffMember <- createStaffRecord venue Nothing "Alpha" "Crew"
                rosterWeek <- createRosterWeekRecord venue 0 False
                rosterDay <- createRosterDayRecord rosterWeek 0
                _ <- createRosterSlotRecord rosterDay slotName (Just staffMember) 0

                response <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams
                            (UpdateRosterLayoutPreferenceAction 0)
                            [("rosterLayoutMode", "day_columns")]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "data-roster-layout=\"day_columns\""
                response `responseBodyShouldContain` "hx-swap=\"none settle:0ms\""
                response `responseBodyShouldContain` "roster-day-columns"

                preferences <- query @UserPreference
                    |> filterWhere (#userId, unpackId manager.id)
                    |> fetchOne
                inputValue preferences.rosterLayoutMode `shouldBe` ("day_columns" :: Text)

                showResponse <- withUserAndCurrentVenue manager venue.id do
                    callAction (ShowRosterWeekAction 0)

                showResponse `responseStatusShouldBe` status200
                showResponse `responseBodyShouldContain` "data-roster-layout=\"day_columns\""
                showResponse `responseBodyShouldContain` "roster-day-columns"

        it "manager can fetch the roster content fragment for the current venue" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-content-fragment@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                slotName <- fetchSlotNameRecord venue "Early"
                staffMember <- createStaffRecord venue Nothing "Alpha" "Crew"
                rosterWeek <- createRosterWeekRecord venue 0 False
                rosterDay <- createRosterDayRecord rosterWeek 0
                _ <- createRosterSlotRecord rosterDay slotName (Just staffMember) 0

                response <- withUserAndCurrentVenue manager venue.id do
                    callAction (ShowRosterWeekContentFragmentAction 0)

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` cs rosterContentFragmentId
                response `responseBodyShouldNotContain` cs rosterStaffPanelFragmentId
                response `responseBodyShouldContain` ">Alpha</div>"
                response `responseBodyShouldContain` "hx-get=\"/EditRosterSlotDialog?rosterSlotId="

        it "manager can fetch the roster staff panel fragment for the current venue" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-panel-fragment@example.com" "staff" True
                linkedUser <- createUserRecord "roster-worker-panel-fragment@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                _ <- createVenueMembershipRecord venue linkedUser "worker"
                slotName <- fetchSlotNameRecord venue "Early"
                staffMember <- createStaffRecord venue (Just linkedUser) "Alpha" "Crew"
                rosterWeek <- createRosterWeekRecord venue 0 False
                rosterDay <- createRosterDayRecord rosterWeek 0
                _ <- createRosterSlotRecord rosterDay slotName (Just staffMember) 0

                response <- withUserAndCurrentVenue manager venue.id do
                    callAction (ShowRosterWeekStaffPanelFragmentAction 0)

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` cs rosterStaffPanelFragmentId
                response `responseBodyShouldContain` "data-roster-staff-name=\"Alpha\""
                response `responseBodyShouldContain` "1"

        it "manager roster staff panel fragment only shows staff applicable to the selected roster group" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-group-panel@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                alphaUser <- createUserRecord "roster-alpha-group-panel@example.com" "staff" True
                bravoUser <- createUserRecord "roster-bravo-group-panel@example.com" "staff" True
                _ <- createVenueMembershipRecord venue alphaUser "worker"
                _ <- createVenueMembershipRecord venue bravoUser "worker"
                frontOfHouse <- createVenueRosterGroupWithDefaults venue "Front of House" 1 True
                backOfHouse <- createVenueRosterGroupWithDefaults venue "Back of House" 2 True
                alpha <- createStaffRecord venue (Just alphaUser) "Alpha" "Crew"
                bravo <- createStaffRecord venue (Just bravoUser) "Bravo" "Crew"
                trial <- createStaffRecord venue Nothing "Trial" "Crew"
                syncStaffRosterGroupAssignments alpha [frontOfHouse.id]
                syncStaffRosterGroupAssignments bravo [backOfHouse.id]
                syncStaffRosterGroupAssignments trial [frontOfHouse.id]

                response <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams (ShowRosterWeekStaffPanelFragmentAction 0) [("rosterGroupId", idToParam frontOfHouse.id)]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "data-roster-staff-name=\"Alpha\""
                response `responseBodyShouldContain` "data-roster-staff-name=\"Trial\""
                response `responseBodyShouldContain` "data-roster-staff-role=\"TRIAL\""
                response `responseBodyShouldNotContain` "data-roster-staff-name=\"Bravo\""
                response `responseBodyShouldContain` "Add trial staff"
                response `responseBodyShouldContain` "hx-get=\"/NewStaff?weekOffset=0&amp;rosterGroupId="
                response `responseBodyShouldContain` "Show all staff"

        it "hides the all-staff staff panel toggle when the venue has one roster group" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-single-group-panel@example.com" "staff" True
                worker <- createUserRecord "roster-worker-single-group-panel@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                _ <- createVenueMembershipRecord venue worker "worker"
                _ <- createStaffRecord venue (Just worker) "Solo" "Crew"

                response <- withUserAndCurrentVenue manager venue.id do
                    callAction (ShowRosterWeekStaffPanelFragmentAction 0)

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "data-roster-staff-name=\"Solo\""
                response `responseBodyShouldNotContain` "Show all staff"
                response `responseBodyShouldNotContain` "name=\"staffScope\""

        it "manager can toggle the roster staff panel to all active venue staff, including unlinked staff" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                otherVenue <- createVenueWithConfig "Venue B"
                manager <- createUserRecord "roster-manager-all-panel@example.com" "staff" True
                alphaUser <- createUserRecord "roster-alpha-all-panel@example.com" "staff" True
                bravoUser <- createUserRecord "roster-bravo-all-panel@example.com" "staff" True
                otherUser <- createUserRecord "roster-other-all-panel@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                _ <- createVenueMembershipRecord venue alphaUser "worker"
                _ <- createVenueMembershipRecord venue bravoUser "worker"
                _ <- createVenueMembershipRecord otherVenue otherUser "worker"
                frontOfHouse <- createVenueRosterGroupWithDefaults venue "Front of House" 1 True
                backOfHouse <- createVenueRosterGroupWithDefaults venue "Back of House" 2 True
                alpha <- createStaffRecord venue (Just alphaUser) "Alpha" "Crew"
                bravo <- createStaffRecord venue (Just bravoUser) "Bravo" "Crew"
                trial <- createStaffRecord venue Nothing "Trial" "Crew"
                _ <- createStaffRecord otherVenue (Just otherUser) "Other" "Crew"
                syncStaffRosterGroupAssignments alpha [frontOfHouse.id]
                syncStaffRosterGroupAssignments bravo [backOfHouse.id]
                syncStaffRosterGroupAssignments trial [backOfHouse.id]

                response <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams (ShowRosterWeekStaffPanelFragmentAction 0)
                        [ ("rosterGroupId", idToParam frontOfHouse.id)
                        , ("staffScope", "all")
                        ]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "data-roster-staff-name=\"Alpha\""
                response `responseBodyShouldContain` "data-roster-staff-name=\"Bravo\""
                response `responseBodyShouldContain` "data-roster-staff-name=\"Trial\""
                response `responseBodyShouldNotContain` "data-roster-staff-name=\"Other\""
                response `responseBodyShouldNotContain` "active staff"

        it "staff row fragment fetch returns no roster row for a draft week" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                staffUser <- createUserRecord "roster-staff-row-fragment@example.com" "staff" True
                _ <- createVenueMembershipRecord venue staffUser "worker"
                slotName <- fetchSlotNameRecord venue "Early"
                staffMember <- createStaffRecord venue Nothing "Alpha" "Crew"
                rosterWeek <- createRosterWeekRecord venue 0 False
                rosterDay <- createRosterDayRecord rosterWeek 0
                _ <- createRosterSlotRecord rosterDay slotName (Just staffMember) 0

                response <- withUserAndCurrentVenue staffUser venue.id do
                    callAction (ShowRosterWeekRowFragmentAction 0 rosterDay.id 0)

                response `responseStatusShouldBe` status200
                body <- responseBody response
                let bodyText = cs body :: String
                let rowId = cs (rosterRowDomIdText rosterDay.id 0) :: String
                bodyText `shouldNotContain` rowId
                bodyText `shouldNotContain` "Crew, Alpha"

        it "manager can copy a week and it is created as draft with copied slots" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-copy@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                slotName <- fetchSlotNameRecord venue "Early"
                staffMember <- createStaffRecord venue Nothing "Alpha" "Crew"
                sourceWeek <- createRosterWeekRecord venue 0 True
                sourceDay <- createRosterDayRecord sourceWeek 0
                sourceSlot <- createRosterSlotRecord sourceDay slotName (Just staffMember) 0
                let sourceSlotWithFields =
                        sourceSlot
                            |> set #startTime (Just (timeOfDay 9 0))
                            |> set #durationMinutes (Just 480)
                _ <- updateRecord sourceSlotWithFields

                response <- withUser manager do
                    callAction (CopyRosterWeekAction 0 1)

                response `responseStatusShouldBe` status302

                copiedWeek <- query @RosterWeek
                    |> filterWhere (#venueId, unpackId venue.id)
                    |> filterWhere (#weekOffset, 1)
                    |> fetchOne
                copiedWeek.isLive `shouldBe` False

                copiedDays <- query @RosterDay
                    |> filterWhere (#rosterWeekId, unpackId copiedWeek.id)
                    |> fetch
                length copiedDays `shouldBe` 7

                copiedDay <- query @RosterDay
                    |> filterWhere (#rosterWeekId, unpackId copiedWeek.id)
                    |> filterWhere (#dayOffset, 0)
                    |> fetchOne
                copiedSlots <- query @RosterSlot
                    |> filterWhere (#rosterDayId, unpackId copiedDay.id)
                    |> filterWhere (#deletedAt, Nothing)
                    |> fetch
                length copiedSlots `shouldBe` 1

                let copiedSlot = fromJust (head copiedSlots)
                copiedSlotDefinition <- fetch (Id copiedSlot.rosterWeekSlotDefinitionId :: Id RosterWeekSlotDefinition)
                copiedSlot.staffId `shouldBe` Just (unpackId staffMember.id)
                copiedSlotDefinition.name `shouldBe` slotName.name
                copiedSlot.rowIndex `shouldBe` 0
                copiedSlot.startTime `shouldBe` Just (timeOfDay 9 0)
                copiedSlot.durationMinutes `shouldBe` Just 480

        it "manager can overwrite an existing target week with the previous roster" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-copy-overwrite@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                early <- fetchSlotNameRecord venue "Early"
                late <- fetchSlotNameRecord venue "Late"
                alpha <- createStaffRecord venue Nothing "Alpha" "Crew"
                bravo <- createStaffRecord venue Nothing "Bravo" "Crew"

                sourceWeek <- createRosterWeekRecord venue 0 True
                sourceDay <- createRosterDayRecord sourceWeek 0
                sourceSlot <- createRosterSlotRecord sourceDay early (Just alpha) 0
                _ <- updateRecord
                    ( sourceSlot
                        |> set #startTime (Just (timeOfDay 8 0))
                        |> set #durationMinutes (Just 300)
                    )

                targetWeek <- createRosterWeekRecord venue 1 False
                targetDay <- createRosterDayRecord targetWeek 0
                targetSlot <- createRosterSlotRecord targetDay late (Just bravo) 0
                _ <- updateRecord
                    ( targetSlot
                        |> set #startTime (Just (timeOfDay 14 0))
                        |> set #durationMinutes (Just 180)
                    )

                response <- withUserAndCurrentVenue manager venue.id do
                    callAction (CopyRosterWeekAction 0 1)

                response `responseStatusShouldBe` status302

                targetWeeks <- query @RosterWeek
                    |> filterWhere (#venueId, unpackId venue.id)
                    |> filterWhere (#weekOffset, 1)
                    |> fetch
                length targetWeeks `shouldBe` 1

                copiedWeek <- query @RosterWeek
                    |> filterWhere (#venueId, unpackId venue.id)
                    |> filterWhere (#weekOffset, 1)
                    |> fetchOne
                copiedDay <- query @RosterDay
                    |> filterWhere (#rosterWeekId, unpackId copiedWeek.id)
                    |> filterWhere (#dayOffset, 0)
                    |> fetchOne
                copiedSlots <- query @RosterSlot
                    |> filterWhere (#rosterDayId, unpackId copiedDay.id)
                    |> filterWhere (#deletedAt, Nothing)
                    |> fetch

                length copiedSlots `shouldBe` 1
                let copiedSlot = fromJust (head copiedSlots)
                copiedSlotDefinition <- fetch (Id copiedSlot.rosterWeekSlotDefinitionId :: Id RosterWeekSlotDefinition)
                copiedSlot.staffId `shouldBe` Just (unpackId alpha.id)
                copiedSlotDefinition.name `shouldBe` early.name
                copiedSlot.startTime `shouldBe` Just (timeOfDay 8 0)
                copiedSlot.durationMinutes `shouldBe` Just 300

        it "copying over a live target week explicitly replaces it as a draft" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-copy-live-target@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                early <- fetchSlotNameRecord venue "Early"
                late <- fetchSlotNameRecord venue "Late"
                alpha <- createStaffRecord venue Nothing "Alpha" "Crew"
                bravo <- createStaffRecord venue Nothing "Bravo" "Crew"

                sourceWeek <- createRosterWeekRecord venue 0 True
                sourceDay <- createRosterDayRecord sourceWeek 0
                sourceSlot <- createRosterSlotRecord sourceDay early (Just alpha) 0
                _ <- updateRecord
                    ( sourceSlot
                        |> set #startTime (Just (timeOfDay 8 0))
                        |> set #durationMinutes (Just 300)
                    )

                targetWeek <- createRosterWeekRecord venue 1 True
                targetDay <- createRosterDayRecord targetWeek 0
                targetSlot <- createRosterSlotRecord targetDay late (Just bravo) 0
                _ <- updateRecord
                    ( targetSlot
                        |> set #startTime (Just (timeOfDay 14 0))
                        |> set #durationMinutes (Just 180)
                    )

                response <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callAction (CopyRosterWeekAction 0 1)

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Roster week copied from the previous week."

                copiedWeek <- fetch targetWeek.id
                copiedWeek.isLive `shouldBe` False
                copiedDay <- query @RosterDay
                    |> filterWhere (#rosterWeekId, unpackId copiedWeek.id)
                    |> filterWhere (#dayOffset, 0)
                    |> fetchOne
                activeSlots <- query @RosterSlot
                    |> filterWhere (#rosterDayId, unpackId copiedDay.id)
                    |> filterWhere (#deletedAt, Nothing)
                    |> fetch

                length activeSlots `shouldBe` 1
                let copiedSlot = fromJust (head activeSlots)
                copiedSlotDefinition <- fetch (Id copiedSlot.rosterWeekSlotDefinitionId :: Id RosterWeekSlotDefinition)
                copiedSlot.staffId `shouldBe` Just (unpackId alpha.id)
                copiedSlotDefinition.name `shouldBe` early.name
                copiedSlot.startTime `shouldBe` Just (timeOfDay 8 0)
                replacedTargetSlot <- fetch targetSlot.id
                replacedTargetSlot.deletedAt `shouldSatisfy` isJust

        it "copies only within the selected roster group scope" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-copy-group-scope@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                frontOfHouse <- createVenueRosterGroupWithDefaults venue "Front of House" 1 True
                backOfHouse <- createVenueRosterGroupWithDefaults venue "Back of House" 2 True
                frontSlotName <- fetchSlotNameRecordForRosterGroup frontOfHouse "Early"
                backSlotName <- fetchSlotNameRecordForRosterGroup backOfHouse "Early"
                alpha <- createStaffRecord venue Nothing "Alpha" "Crew"
                bravo <- createStaffRecord venue Nothing "Bravo" "Crew"

                frontSourceWeek <- createRosterWeekRecordForRosterGroup venue frontOfHouse 0 True
                frontSourceDay <- createRosterDayRecord frontSourceWeek 0
                frontSourceSlot <- createRosterSlotRecord frontSourceDay frontSlotName (Just alpha) 0
                _ <- updateRecord (frontSourceSlot |> set #startTime (Just (timeOfDay 8 0)))

                backSourceWeek <- createRosterWeekRecordForRosterGroup venue backOfHouse 0 True
                backSourceDay <- createRosterDayRecord backSourceWeek 0
                backSourceSlot <- createRosterSlotRecord backSourceDay backSlotName (Just bravo) 0
                _ <- updateRecord (backSourceSlot |> set #startTime (Just (timeOfDay 12 0)))

                frontTargetWeek <- createRosterWeekRecordForRosterGroup venue frontOfHouse 1 False
                _ <- createRosterDayRecord frontTargetWeek 0
                backTargetWeek <- createRosterWeekRecordForRosterGroup venue backOfHouse 1 False
                backTargetDay <- createRosterDayRecord backTargetWeek 0
                backTargetSlot <- createRosterSlotRecord backTargetDay backSlotName (Just bravo) 0
                _ <- updateRecord (backTargetSlot |> set #startTime (Just (timeOfDay 15 0)))

                response <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams
                        (CopyRosterWeekAction 0 1)
                        [("rosterGroupId", ByteString.pack (cs (tshow frontOfHouse.id)))]

                response `responseStatusShouldBe` status302

                frontCopiedDay <- query @RosterDay
                    |> filterWhere (#rosterWeekId, unpackId frontTargetWeek.id)
                    |> filterWhere (#dayOffset, 0)
                    |> fetchOne
                frontCopiedSlots <- query @RosterSlot
                    |> filterWhere (#rosterDayId, unpackId frontCopiedDay.id)
                    |> filterWhere (#deletedAt, Nothing)
                    |> fetch
                length frontCopiedSlots `shouldBe` 1
                let frontCopiedSlot = fromJust (head frontCopiedSlots)
                frontCopiedSlot.staffId `shouldBe` Just (unpackId alpha.id)
                frontCopiedSlot.startTime `shouldBe` Just (timeOfDay 8 0)

                backUnchangedSlot <- fetch backTargetSlot.id
                backUnchangedSlot.deletedAt `shouldBe` Nothing
                backUnchangedSlot.staffId `shouldBe` Just (unpackId bravo.id)
                backUnchangedSlot.startTime `shouldBe` Just (timeOfDay 15 0)
                backActiveSlots <- query @RosterSlot
                    |> filterWhere (#rosterDayId, unpackId backTargetDay.id)
                    |> filterWhere (#deletedAt, Nothing)
                    |> fetch
                length backActiveSlots `shouldBe` 1

        it "rejects copying a roster week onto itself via HTMX" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-copy-self-htmx@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                originalWeek <- createRosterWeekRecord venue 0 False

                response <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callAction (CopyRosterWeekAction 0 0)

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Cannot copy a roster week onto itself."

                persistedWeeks <- query @RosterWeek
                    |> filterWhere (#venueId, unpackId venue.id)
                    |> filterWhere (#weekOffset, 0)
                    |> fetch
                length persistedWeeks `shouldBe` 1
                map (.id) persistedWeeks `shouldBe` [originalWeek.id]

        it "rejects copying from a missing source week via HTMX without creating the target week" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-copy-missing-source-htmx@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"

                response <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callAction (CopyRosterWeekAction 7 8)

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Source week not found. Cannot copy."

                targetWeek <- query @RosterWeek
                    |> filterWhere (#venueId, unpackId venue.id)
                    |> filterWhere (#weekOffset, 8)
                    |> fetchOneOrNothing
                targetWeek `shouldBe` Nothing


fetchRosterTimesheetJobForSlot :: (?modelContext :: ModelContext) => RosterSlot -> IO AppJob
fetchRosterTimesheetJobForSlot rosterSlot = do
    jobs <- fetchRosterTimesheetJobsForSlot rosterSlot
    case jobs of
        [job] -> pure job
        _ -> do
            expectationFailure ("Expected one roster timesheet job for slot, got " <> cs (tshow (length jobs)))
            error "unreachable"

fetchRosterTimesheetJobsForSlot :: (?modelContext :: ModelContext) => RosterSlot -> IO [AppJob]
fetchRosterTimesheetJobsForSlot rosterSlot =
    query @AppJob
        |> filterWhere (#jobKind, rosterTimesheetCreationJobKind)
        |> filterWhere (#relatedTable, Just "roster_slots")
        |> filterWhere (#relatedId, Just (unpackId rosterSlot.id))
        |> orderByAsc #createdAt
        |> fetch

assertRosterTimesheetJobCancelled :: (?modelContext :: ModelContext) => AppJob -> IO ()
assertRosterTimesheetJobCancelled job = do
    updatedJob <- fetch job.id
    updatedJob.status `shouldBe` JobStatusSucceeded
    updatedJob.result
        `shouldBe` Aeson.object
            [ "status" Aeson..= ("cancelled" :: Text)
            , "reason" Aeson..= ("roster_week_moved_to_draft" :: Text)
            ]

timeOfDay :: Int -> Int -> TimeOfDay
timeOfDay hour minute = TimeOfDay hour minute 0
