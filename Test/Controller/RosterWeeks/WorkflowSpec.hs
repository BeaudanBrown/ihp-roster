module Test.Controller.RosterWeeks.WorkflowSpec where

import Application.Helper.Controller (PlatformRole (SuperAdminRole),
                                      venueWeekStartDate)
import Application.Helper.FrontendContract.Surface.Roster.Resource
import Application.Helper.FrontendContract.Surface.Timesheets.Resource (timesheetWeekResource)
import Application.Helper.RosterGroups (createVenueRosterGroupWithDefaults,
                                        syncStaffRosterGroupAssignments)
import Application.Helper.SurfaceResource
import Application.Helper.UserPreferences
import Application.VenueTime (RepeatedTimeOccurrence (..))
import Application.VenueTime.Model (rosterSlotElapsedSeconds,
                                    rosterSlotEndOccurrence,
                                    rosterSlotStartOccurrence,
                                    storedInstantLocalTime,
                                    storedInstantOccurrence)
import Config
import qualified Data.ByteString.Char8 as ByteString
import Data.Coerce (coerce)
import Data.List (sortOn)
import Data.Maybe (fromJust)
import qualified Data.Set as Set
import qualified Data.Text as Text
import Data.Time.Calendar (addDays, fromGregorian)
import Data.Time.LocalTime (TimeOfDay (..))
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
import Web.Controller.RosterWeeks ()
import Web.FrontController ()
import Web.RosterWeeks.Dom (rosterContentFragmentId, rosterDayColumnsFragmentId,
                            rosterDaySectionDomId, rosterGridFrameFragmentId,
                            rosterRowDomIdText, rosterStaffPanelFragmentId)
import Web.RosterWeeks.Mutations (rosterDayTouchedResources,
                                  rosterSlotMutationTouchedResources,
                                  rosterSlotTouchedResources,
                                  rosterSlotsStructureTouchedResources,
                                  rosterWeekLiveStatusTouchedResources,
                                  rosterWeekStructuralTouchedResources,
                                  rosterWeekTouchedResources)
import Web.RosterWeeks.Service (rosterSlotHasValidStartEnd)
import Web.Routes
import Web.Types

tests :: Spec
tests = aroundAll withDatabaseTestContext do
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
                        [ rosterWeekResource (unpackId rosterGroupId) rosterWeek.weekOffset
                        , rosterDayResource (unpackId rosterDay.id)

                        ]
                rosterWeekTouchedResources rosterGroupId rosterWeek.weekOffset
                    `shouldBe` [rosterWeekResource (unpackId rosterGroupId) rosterWeek.weekOffset]
                Set.fromList (rosterWeekStructuralTouchedResources rosterGroupId rosterWeek.weekOffset)
                    `shouldBe` Set.fromList
                        [ rosterWeekResource (unpackId rosterGroupId) rosterWeek.weekOffset
                        , rosterWeekStructureResource (unpackId rosterGroupId) rosterWeek.weekOffset
                        ]
                Set.fromList (rosterSlotsStructureTouchedResources rosterGroupId rosterWeek.weekOffset)
                    `shouldBe` Set.fromList
                        [ rosterWeekResource (unpackId rosterGroupId) rosterWeek.weekOffset
                        , rosterSlotsStructureResource (unpackId rosterGroupId) rosterWeek.weekOffset
                        ]
                Set.fromList (rosterWeekLiveStatusTouchedResources rosterGroupId rosterWeek)
                    `shouldBe` Set.fromList
                        [ rosterWeekResource (unpackId rosterGroupId) rosterWeek.weekOffset
                        , rosterWeekStructureResource (unpackId rosterGroupId) rosterWeek.weekOffset
                        , timesheetWeekResource rosterWeek.venueId rosterWeek.weekOffset
                        ]
                Set.fromList (rosterSlotMutationTouchedResources rosterGroupId rosterWeek rosterDay (Just rosterSlot))
                    `shouldBe` Set.fromList
                        [ rosterWeekResource (unpackId rosterGroupId) rosterWeek.weekOffset
                        , rosterDayResource (unpackId rosterDay.id)
                        , timesheetWeekResource rosterWeek.venueId rosterWeek.weekOffset
                        ]
                rosterDayTouchedResources rosterGroupId rosterWeek.weekOffset rosterDay
                    `shouldBe`
                        [ rosterWeekResource (unpackId rosterGroupId) rosterWeek.weekOffset
                        , rosterDayResource (unpackId rosterDay.id)
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
                _ <- updateRecord (slot |> setTestStartTime (Just (timeOfDay 9 0)))

                response <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callAction (ToggleRosterDayClosedAction rosterDay.id)

                response `responseStatusShouldBe` status200
                body <- responseBody response
                let bodyText = cs body :: String
                lookup "HX-Reswap" (responseHeaders response) `shouldBe` Just "none"
                bodyText `shouldContain` "id=\"dialog-overlay-mount\""
                bodyText `shouldNotContain` ("id=\"" <> cs rosterDayColumnsFragmentId <> "\"" :: String)
                bodyText `shouldNotContain` ("id=\"" <> cs rosterGridFrameFragmentId <> "\"" :: String)
                bodyText `shouldNotContain` ("id=\"" <> cs rosterStaffPanelFragmentId <> "\"" :: String)
                bodyText `shouldNotContain` "hx-swap-oob=\"outerHTML\""
                let rosterActorTriggerHeader = cs <$> lookup "HX-Trigger" (responseHeaders response)
                rosterActorTriggerHeader `shouldSatisfy` maybe False (Text.isInfixOf (cs rosterDayColumnsFragmentId))
                rosterActorTriggerHeader `shouldSatisfy` maybe False (Text.isInfixOf "\"kind\":\"roster-staff-panel\"")

                updatedDay <- fetch rosterDay.id
                updatedDay.isClosed `shouldBe` True
                unchangedSlot <- fetch slot.id
                unchangedSlot.staffId `shouldBe` Just (unpackId staffMember.id)
                testStartTime unchangedSlot `shouldBe` Just (timeOfDay 9 0)

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
                lookup "HX-Reswap" (responseHeaders response) `shouldBe` Just "none"
                response `responseBodyShouldNotContain` cs rosterContentFragmentId
                response `responseBodyShouldContain` "Roster week created successfully"
                let createWeekTriggerHeader = cs <$> lookup "HX-Trigger" (responseHeaders response)
                createWeekTriggerHeader `shouldSatisfy` maybe False (Text.isInfixOf (cs rosterContentFragmentId))

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
                lookup "HX-Reswap" (responseHeaders response) `shouldBe` Just "none"
                bodyText `shouldContain` "id=\"dialog-overlay-mount\""
                bodyText `shouldNotContain` ("id=\"" <> cs rosterDayColumnsFragmentId <> "\"" :: String)
                bodyText `shouldNotContain` ("id=\"" <> cs rosterGridFrameFragmentId <> "\"" :: String)
                bodyText `shouldNotContain` ("id=\"" <> cs rosterStaffPanelFragmentId <> "\"" :: String)
                bodyText `shouldNotContain` "hx-swap-oob=\"outerHTML\""
                let rosterActorTriggerHeader = cs <$> lookup "HX-Trigger" (responseHeaders response)
                rosterActorTriggerHeader `shouldSatisfy` maybe False (Text.isInfixOf (cs rosterDayColumnsFragmentId))
                rosterActorTriggerHeader `shouldSatisfy` maybe False (Text.isInfixOf "\"kind\":\"roster-staff-panel\"")

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
                lookup "HX-Reswap" (responseHeaders response) `shouldBe` Just "none"
                bodyText `shouldContain` "id=\"dialog-overlay-mount\""
                bodyText `shouldNotContain` ("id=\"" <> cs rosterDayColumnsFragmentId <> "\"" :: String)
                bodyText `shouldNotContain` ("id=\"" <> cs rosterGridFrameFragmentId <> "\"" :: String)
                bodyText `shouldNotContain` ("id=\"" <> cs rosterStaffPanelFragmentId <> "\"" :: String)
                bodyText `shouldNotContain` "hx-swap-oob=\"outerHTML\""
                let rosterActorTriggerHeader = cs <$> lookup "HX-Trigger" (responseHeaders response)
                rosterActorTriggerHeader `shouldSatisfy` maybe False (Text.isInfixOf (cs rosterDayColumnsFragmentId))
                rosterActorTriggerHeader `shouldSatisfy` maybe False (Text.isInfixOf "\"kind\":\"roster-staff-panel\"")

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
                _ <- updateRecord (row0 |> setTestStartTime (Just (timeOfDay 8 0)))
                _ <- updateRecord (row2 |> setTestStartTime (Just (timeOfDay 10 0)))
                _ <- updateRecord (row3 |> setTestStartTime (Just (timeOfDay 12 0)))

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
                map testStartTime packedDataSlots `shouldBe` map (Just . uncurry timeOfDay) [(8, 0), (10, 0), (12, 0)]
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
                _ <- updateRecord (early0 |> setTestStartTime (Just (timeOfDay 8 0)))
                _ <- updateRecord (early1 |> setTestStartTime (Just (timeOfDay 9 0)))
                _ <- updateRecord (late0 |> setTestStartTime (Just (timeOfDay 10 0)))
                _ <- updateRecord (early2 |> setTestStartTime (Just (timeOfDay 11 0)))
                _ <- updateRecord (late2 |> setTestStartTime (Just (timeOfDay 12 0)))

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
                _ <- updateRecord (earlySlot |> setTestStartTime (Just (timeOfDay 9 0)))

                createResponse <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams (CreateRosterWeekSlotDefinitionAction rosterWeek.id)
                            []
                createResponse `responseStatusShouldBe` status200
                let createTriggerHeader = cs <$> lookup "HX-Trigger" (responseHeaders createResponse)
                createTriggerHeader `shouldSatisfy` maybe False (Text.isInfixOf "\"kind\":\"roster-slots-grid\"")
                createTriggerHeader `shouldSatisfy` maybe False (Text.isInfixOf "\"kind\":\"roster-day-rail\"")
                createTriggerHeader `shouldSatisfy` maybe False (not . Text.isInfixOf "\"kind\":\"roster-grid-frame\"")

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
                let deleteTriggerHeader = cs <$> lookup "HX-Trigger" (responseHeaders deleteResponse)
                deleteTriggerHeader `shouldSatisfy` maybe False (Text.isInfixOf "\"kind\":\"roster-slots-grid\"")
                deleteTriggerHeader `shouldSatisfy` maybe False (not . Text.isInfixOf "\"kind\":\"roster-grid-frame\"")
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
                _ <- updateRecord (charlieSlot |> setTestStartTime (Just (timeOfDay 11 0)))
                _ <- updateRecord (alphaSlot |> setTestStartTime (Just (timeOfDay 9 0)))
                _ <- updateRecord (bravoSlot |> setTestStartTime (Just (timeOfDay 9 0)))

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
                _ <- updateRecord (bravoSlot |> setTestStartTime (Just (timeOfDay 10 0)))
                _ <- updateRecord (charlieSlot |> setTestStartTime (Just (timeOfDay 11 0)))
                _ <- updateRecord (alphaSlot |> setTestStartTime (Just (timeOfDay 9 0)))
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
                map testStartTime packedDataSlots `shouldBe` map (Just . uncurry timeOfDay) [(9, 0), (10, 0), (11, 0)]

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
                        |> setTestStartTime (Just (timeOfDay 9 0))
                        |> setTestEndTime (Just (timeOfDay 17 0))
                        |> set #shiftTypeId (Just (unpackId shiftType.id))
                    )

                response <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams
                            (ToggleRosterWeekLiveStatusAction rosterWeek.id)
                            [("isLive", "on")]

                response `responseStatusShouldBe` status200
                lookup "HX-Reswap" (responseHeaders response) `shouldBe` Just "none"
                response `responseBodyShouldNotContain` cs rosterContentFragmentId
                response `responseBodyShouldContain` "Roster week is now live."
                let publishTriggerHeader = cs <$> lookup "HX-Trigger" (responseHeaders response)
                publishTriggerHeader `shouldSatisfy` maybe False (Text.isInfixOf (cs rosterContentFragmentId))

                contentResponse <- withUserAndCurrentVenue manager venue.id do
                    callAction (ShowRosterWeekContentFragmentAction 0)
                contentResponse `responseBodyShouldContain` ">Alpha<"
                contentResponse `responseBodyShouldContain` "9:00 AM"
                contentResponse `responseBodyShouldContain` ">Floor<"
                contentResponse `responseBodyShouldNotContain` "data-roster-day-add=\"true\""
                contentResponse `responseBodyShouldNotContain` "data-roster-day-remove=\"true\""
                contentResponse `responseBodyShouldNotContain` "name=\"staffId\""
                contentResponse `responseBodyShouldNotContain` "data-bepis-time-picker-trigger"

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
                        |> setTestStartTime (Just (timeOfDay 9 0))
                        |> setTestEndTime (Just (timeOfDay 17 0))
                        |> set #shiftTypeId (Just (unpackId shiftType.id))
                        |> setTestDurationMinutes (Just 480)
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
                testStartTime unchangedSlot `shouldBe` Just (timeOfDay 9 0)
                testEndTime unchangedSlot `shouldBe` Just (timeOfDay 17 0)
                testDurationMinutes unchangedSlot `shouldBe` Just 480

        it "rejects tampered dialog assignments with unresolved pay configuration" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Roster Pay Validation Venue"
                manager <- createUserRecord "roster-pay-validation-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                unresolvedStaff <- createStaffRecord venue Nothing "Unresolved" "Crew"
                    >>= updateRecord . set #payAssignmentMode LegacyUnresolved
                level <- createPayLevelRecord venue "Level 1"
                shiftType <- createShiftTypeRecord venue level "Floor"
                rosterWeek <- createRosterWeekRecord venue 0 False
                rosterDay <- createRosterDayRecord rosterWeek 0
                slotName <- fetchSlotNameRecord venue "Early"
                slotDefinition <- ensureRosterWeekSlotDefinitionForSlotName rosterDay slotName

                response <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams
                            (CreateRosterSlotAction rosterDay.id slotDefinition.id 0)
                            [ ("staffId", idToParam unresolvedStaff.id)
                            , ("startTime", "09:00")
                            , ("endTime", "17:00")
                            , ("shiftTypeId", idToParam shiftType.id)
                            ]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Resolve pay configuration for the selected staff member or shift type before saving this roster shift."
                query @RosterSlot |> fetchCount >>= (`shouldBe` 0)

        it "rejects unavailable and cross-venue pay assignments submitted outside roster selectors" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Roster Tampered Pay Venue"
                otherVenue <- createVenueWithConfig "Other Roster Tampered Pay Venue"
                manager <- createUserRecord "roster-tampered-pay-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                staffMember <- createStaffRecord venue Nothing "Current" "Crew"
                foreignStaff <- createStaffRecord otherVenue Nothing "Foreign" "Crew"
                level <- createPayLevelRecord venue "Inactive Level"
                inactiveShift <- createShiftTypeRecord venue level "Inactive Pay Reference"
                _ <- updateRecord (level |> set #isActive False)
                foreignLevel <- createPayLevelRecord otherVenue "Foreign Level"
                foreignShift <- createShiftTypeRecord otherVenue foreignLevel "Foreign Shift"
                rosterWeek <- createRosterWeekRecord venue 0 False
                rosterDay <- createRosterDayRecord rosterWeek 0
                slotName <- fetchSlotNameRecord venue "Early"
                slotDefinition <- ensureRosterWeekSlotDefinitionForSlotName rosterDay slotName
                let submit rowIndex staffId shiftTypeId =
                        withUserAndCurrentVenue manager venue.id do
                            withRequestHeaders [("HX-Request", "true")] do
                                callActionWithParams
                                    (CreateRosterSlotAction rosterDay.id slotDefinition.id rowIndex)
                                    [ ("staffId", idToParam staffId)
                                    , ("startTime", "09:00")
                                    , ("endTime", "17:00")
                                    , ("shiftTypeId", idToParam shiftTypeId)
                                    ]

                unavailableResponse <- submit 0 staffMember.id inactiveShift.id
                unavailableResponse `responseBodyShouldContain` "Resolve pay configuration for the selected staff member or shift type before saving this roster shift."
                foreignStaffResponse <- submit 1 foreignStaff.id inactiveShift.id
                foreignStaffResponse `responseBodyShouldContain` "Choose a staff member for this venue."
                foreignShiftResponse <- submit 2 staffMember.id foreignShift.id
                foreignShiftResponse `responseBodyShouldContain` "Choose a shift type for this venue."
                query @RosterSlot |> fetchCount >>= (`shouldBe` 0)

        it "allows roster-only shifts outside Award projected-duration limits" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Roster Only Duration Venue"
                manager <- createUserRecord "roster-only-duration-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                partTimeStaff <- createStaffRecord venue Nothing "Roster Only" "Crew" >>= updateRecord . set #employmentBasis Permanent
                rateProducingStaff <- createStaffRecord venue Nothing "Rate Producing" "Crew" >>= updateRecord . set #employmentBasis Permanent
                level <- createPayLevelRecord venue "Level 1"
                rateProducingStaff <- updateRecord (rateProducingStaff |> set #payAssignmentMode AwardRate |> set #defaultAwardLevelId (Just level.id))
                shiftType <- createShiftTypeRecord venue level "Floor"
                rosterOnlyShiftType <- createShiftTypeRecord venue level "Roster only shift"
                    >>= updateRecord
                        . set #payAssignmentMode RosterOnly
                        . set #overrideAwardLevelId Nothing
                rosterWeek <- createRosterWeekRecord venue 0 False
                rosterDay <- createRosterDayRecord rosterWeek 0
                slotName <- fetchSlotNameRecord venue "Early"
                slotDefinition <- ensureRosterWeekSlotDefinitionForSlotName rosterDay slotName

                response <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams
                            (CreateRosterSlotAction rosterDay.id slotDefinition.id 0)
                            [ ("staffId", idToParam partTimeStaff.id)
                            , ("startTime", "17:30")
                            , ("endTime", "05:45")
                            , ("shiftTypeId", idToParam shiftType.id)
                            ]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldNotContain` "Part-time roster shifts must project"

                shiftRosterOnlyResponse <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams
                            (CreateRosterSlotAction rosterDay.id slotDefinition.id 1)
                            [ ("staffId", idToParam rateProducingStaff.id)
                            , ("startTime", "17:30")
                            , ("endTime", "05:45")
                            , ("shiftTypeId", idToParam rosterOnlyShiftType.id)
                            ]
                shiftRosterOnlyResponse `responseBodyShouldNotContain` "Part-time roster shifts must project"
                query @RosterSlot |> fetchCount >>= (`shouldBe` 2)

        it "wires roster duration validation into shift creation" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Roster Award Duration Venue"
                manager <- createUserRecord "roster-award-duration-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                partTimeStaff <- createStaffRecord venue Nothing "Part-time" "Crew" >>= updateRecord . set #employmentBasis Permanent
                level <- createPayLevelRecord venue "Level 1"
                _ <- updateRecord (partTimeStaff |> set #payAssignmentMode AwardRate |> set #defaultAwardLevelId (Just level.id))
                shiftType <- createShiftTypeRecord venue level "Floor"
                rosterWeek <- createRosterWeekRecord venue 0 False
                rosterDay <- createRosterDayRecord rosterWeek 0
                slotName <- fetchSlotNameRecord venue "Early"
                slotDefinition <- ensureRosterWeekSlotDefinitionForSlotName rosterDay slotName

                response <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams
                            (CreateRosterSlotAction rosterDay.id slotDefinition.id 0)
                            [ ("staffId", idToParam partTimeStaff.id)
                            , ("startTime", "09:00")
                            , ("endTime", "11:45")
                            , ("shiftTypeId", idToParam shiftType.id)
                            ]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Part-time roster shifts must project between 3 and 11.5 working hours after the automatic unpaid meal break."
                query @RosterSlot |> fetchCount >>= (`shouldBe` 0)

        it "wires roster duration validation into shift updates" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Roster Award Edit Venue"
                manager <- createUserRecord "roster-award-edit-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                partTimeStaff <- createStaffRecord venue Nothing "Part-time" "Edit" >>= updateRecord . set #employmentBasis Permanent
                level <- createPayLevelRecord venue "Level 1"
                _ <- updateRecord (partTimeStaff |> set #payAssignmentMode AwardRate |> set #defaultAwardLevelId (Just level.id))
                shiftType <- createShiftTypeRecord venue level "Floor"
                rosterWeek <- createRosterWeekRecord venue 0 False
                rosterDay <- createRosterDayRecord rosterWeek 0
                slotName <- fetchSlotNameRecord venue "Early"
                slot <- createRosterSlotRecord rosterDay slotName (Just partTimeStaff) 0
                    >>= updateRecord
                        . set #shiftTypeId (Just (unpackId shiftType.id))
                        . setTestRosterSlotBoundaries (fromGregorian 2025 1 6) (timeOfDay 9 0) (timeOfDay 12 0)

                response <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams
                            (UpdateRosterSlotAction slot.id)
                            [ ("staffId", idToParam partTimeStaff.id)
                            , ("startTime", "09:00")
                            , ("endTime", "11:45")
                            , ("shiftTypeId", idToParam shiftType.id)
                            ]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Part-time roster shifts must project between 3 and 11.5 working hours after the automatic unpaid meal break."
                unchangedSlot <- fetch slot.id
                testDurationMinutes unchangedSlot `shouldBe` Just 180

        it "wires roster duration validation into publication" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Roster Award Publish Venue"
                manager <- createUserRecord "roster-award-publish-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                partTimeStaff <- createStaffRecord venue Nothing "Part-time" "Crew" >>= updateRecord . set #employmentBasis Permanent
                level <- createPayLevelRecord venue "Level 1"
                _ <- updateRecord (partTimeStaff |> set #payAssignmentMode AwardRate |> set #defaultAwardLevelId (Just level.id))
                shiftType <- createShiftTypeRecord venue level "Floor"
                rosterWeek <- createRosterWeekRecord venue 0 False
                rosterDay <- createRosterDayRecord rosterWeek 0
                slotName <- fetchSlotNameRecord venue "Early"
                partTimeSlot <- createRosterSlotRecord rosterDay slotName (Just partTimeStaff) 0
                    >>= updateRecord
                        . set #shiftTypeId (Just (unpackId shiftType.id))
                        . setTestRosterSlotBoundaries (fromGregorian 2025 1 6) (timeOfDay 17 30) (timeOfDay 5 45)
                let publish =
                        withUserAndCurrentVenue manager venue.id do
                            withRequestHeaders [("HX-Request", "true")] do
                                callActionWithParams
                                    (ToggleRosterWeekLiveStatusAction rosterWeek.id)
                                    [("isLive", "on")]

                blocked <- publish
                blocked `responseStatusShouldBe` status200
                blocked `responseBodyShouldContain` "Part-time roster shifts must project between 3 and 11.5 working hours after the automatic unpaid meal break."
                fetch rosterWeek.id >>= (\week -> week.isLive `shouldBe` False)

                _ <- updateRecord
                    (partTimeSlot |> setTestRosterSlotBoundaries (fromGregorian 2025 1 6) (timeOfDay 9 0) (timeOfDay 12 0))
                published <- publish
                published `responseStatusShouldBe` status200
                fetch rosterWeek.id >>= (\week -> week.isLive `shouldBe` True)

        it "blocks publishing legacy-unresolved staff even with a roster-only shift type" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Roster Pay Publish Venue"
                manager <- createUserRecord "roster-pay-publish-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                unresolvedStaff <- createStaffRecord venue Nothing "Unresolved" "Publish"
                    >>= updateRecord . set #payAssignmentMode LegacyUnresolved
                level <- createPayLevelRecord venue "Publish Level"
                rosterOnlyShift <- createShiftTypeRecord venue level "Roster only"
                    >>= updateRecord
                        . set #payAssignmentMode RosterOnly
                        . set #overrideAwardLevelId Nothing
                rosterWeek <- createRosterWeekRecord venue 0 False
                rosterDay <- createRosterDayRecord rosterWeek 0
                slotName <- fetchSlotNameRecord venue "Early"
                _ <- createRosterSlotRecord rosterDay slotName (Just unresolvedStaff) 0
                    >>= updateRecord
                        . set #shiftTypeId (Just (unpackId rosterOnlyShift.id))
                        . setTestRosterSlotBoundaries (fromGregorian 2025 1 6) (timeOfDay 9 0) (timeOfDay 17 0)

                response <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams (ToggleRosterWeekLiveStatusAction rosterWeek.id) [("isLive", "on")]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Resolve pay configuration for the selected staff member or shift type before saving this roster shift."
                fetch rosterWeek.id >>= (\week -> week.isLive `shouldBe` False)

        it "rejects copying unresolved pay configuration without replacing existing target data" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Roster Pay Copy Venue"
                manager <- createUserRecord "roster-pay-copy-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                unresolvedStaff <- createStaffRecord venue Nothing "Unresolved" "Copy"
                    >>= updateRecord . set #payAssignmentMode LegacyUnresolved
                level <- createPayLevelRecord venue "Copy Pay Level"
                shiftType <- createShiftTypeRecord venue level "Copy Shift"
                slotName <- fetchSlotNameRecord venue "Early"
                sourceWeek <- createRosterWeekRecord venue 0 False
                sourceDay <- createRosterDayRecord sourceWeek 0
                _ <- createRosterSlotRecord sourceDay slotName (Just unresolvedStaff) 0
                    >>= updateRecord
                        . set #shiftTypeId (Just (unpackId shiftType.id))
                        . setTestRosterSlotBoundaries (fromGregorian 2025 1 6) (timeOfDay 9 0) (timeOfDay 17 0)
                targetWeek <- createRosterWeekRecord venue 1 False
                targetDay <- createRosterDayRecord targetWeek 0
                targetStaff <- createStaffRecord venue Nothing "Existing" "Target"
                targetSlot <- createRosterSlotRecord targetDay slotName (Just targetStaff) 0

                response <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callAction (CopyRosterWeekAction 0 1)

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Resolve pay configuration for the selected staff member or shift type before saving this roster shift."
                persistedTarget <- fetch targetSlot.id
                persistedTarget.deletedAt `shouldBe` Nothing
                persistedTarget.staffId `shouldBe` Just (unpackId targetStaff.id)

        it "requires an occurrence for an ambiguous after-midnight roster boundary" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Roster Autumn Boundary Venue"
                manager <- createUserRecord "roster-autumn-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                staffMember <- createStaffRecord venue Nothing "Autumn" "Crew"
                level <- createPayLevelRecord venue "Level 1"
                shiftType <- createShiftTypeRecord venue level "Floor"
                rosterWeek <- createRosterWeekRecord venue 64 False
                rosterDay <- createRosterDayRecord rosterWeek 5
                slotName <- fetchSlotNameRecord venue "Early"
                slotDefinition <- ensureRosterWeekSlotDefinitionForSlotName rosterDay slotName
                let baseParams =
                        [ ("staffId", idToParam staffMember.id)
                        , ("startTime", "02:30")
                        , ("endTime", "04:00")
                        , ("shiftTypeId", idToParam shiftType.id)
                        ]

                missingOccurrenceResponse <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams (CreateRosterSlotAction rosterDay.id slotDefinition.id 0) baseParams

                missingOccurrenceResponse `responseStatusShouldBe` status200
                missingOccurrenceResponse `responseBodyShouldContain` "Choose whether this is the first or second occurrence."
                missingOccurrenceResponse `responseBodyShouldContain` "data-time-occurrence-chooser=\"startOccurrence\""
                missingOccurrenceResponse `responseBodyShouldNotContain` "data-time-occurrence-chooser=\"endOccurrence\""
                query @RosterSlot |> fetchCount >>= (`shouldBe` 0)

                createdResponse <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams
                            (CreateRosterSlotAction rosterDay.id slotDefinition.id 0)
                            (baseParams <> [("startOccurrence", "second")])

                createdResponse `responseStatusShouldBe` status200
                slot <- query @RosterSlot |> fetchOne
                startsAt <- maybe (expectationFailure "Expected roster start instant" >> error "unreachable") pure slot.startsAt
                storedInstantOccurrence slot.timezone startsAt `shouldBe` Just SecondOccurrence
                (storedInstantLocalTime slot.timezone startsAt).localDay `shouldBe` fromGregorian 2026 4 5
                rosterSlotElapsedSeconds slot `shouldBe` Just (90 * 60)

        it "creates a positive repeated-hour roster shift with equal local clocks" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Roster Equal Autumn Boundary Venue"
                manager <- createUserRecord "roster-equal-autumn-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                staffMember <- createStaffRecord venue Nothing "Equal Autumn" "Crew"
                level <- createPayLevelRecord venue "Level 1"
                shiftType <- createShiftTypeRecord venue level "Floor"
                rosterWeek <- createRosterWeekRecord venue 64 False
                rosterDay <- createRosterDayRecord rosterWeek 5
                slotName <- fetchSlotNameRecord venue "Early"
                slotDefinition <- ensureRosterWeekSlotDefinitionForSlotName rosterDay slotName
                let baseParams =
                        [ ("staffId", idToParam staffMember.id)
                        , ("startTime", "02:30")
                        , ("endTime", "02:30")
                        , ("shiftTypeId", idToParam shiftType.id)
                        ]

                missingOccurrenceResponse <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams (CreateRosterSlotAction rosterDay.id slotDefinition.id 0) baseParams

                missingOccurrenceResponse `responseStatusShouldBe` status200
                missingOccurrenceResponse `responseBodyShouldContain` "data-time-occurrence-chooser=\"startOccurrence\""
                missingOccurrenceResponse `responseBodyShouldContain` "data-time-occurrence-chooser=\"endOccurrence\""
                query @RosterSlot |> fetchCount >>= (`shouldBe` 0)

                createdResponse <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams
                            (CreateRosterSlotAction rosterDay.id slotDefinition.id 0)
                            (baseParams <> [("startOccurrence", "first"), ("endOccurrence", "second")])

                createdResponse `responseStatusShouldBe` status200
                slot <- query @RosterSlot |> fetchOne
                rosterSlotStartOccurrence slot `shouldBe` Just FirstOccurrence
                rosterSlotEndOccurrence slot `shouldBe` Just SecondOccurrence
                rosterSlotElapsedSeconds slot `shouldBe` Just (60 * 60)
                rosterSlotHasValidStartEnd slot `shouldBe` True

        it "rejects a nonexistent after-midnight spring roster boundary" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Roster Spring Boundary Venue"
                manager <- createUserRecord "roster-spring-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                staffMember <- createStaffRecord venue Nothing "Spring" "Crew"
                level <- createPayLevelRecord venue "Level 1"
                shiftType <- createShiftTypeRecord venue level "Floor"
                rosterWeek <- createRosterWeekRecord venue 90 False
                rosterDay <- createRosterDayRecord rosterWeek 5
                slotName <- fetchSlotNameRecord venue "Early"
                slotDefinition <- ensureRosterWeekSlotDefinitionForSlotName rosterDay slotName

                response <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams
                            (CreateRosterSlotAction rosterDay.id slotDefinition.id 0)
                            [ ("staffId", idToParam staffMember.id)
                            , ("startTime", "02:30")
                            , ("endTime", "04:00")
                            , ("shiftTypeId", idToParam shiftType.id)
                            ]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "This local time does not exist because clocks move forward."
                response `responseBodyShouldNotContain` "data-time-occurrence-chooser=\"startOccurrence\""
                query @RosterSlot |> fetchCount >>= (`shouldBe` 0)

        it "blocks publishing staffed shifts with invalid timing" $ withContext do
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
                        |> setTestStartTime (Just (timeOfDay 9 0))
                        |> setTestEndTime (Just (timeOfDay 8 0))
                        |> set #shiftTypeId (Just (unpackId shiftType.id))
                        |> setTestDurationMinutes (Just 1380)
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

        it "allows valid overnight staffed shifts to go live" $ withContext do
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
                        |> setTestStartTime (Just (timeOfDay 22 0))
                        |> setTestEndTime (Just (timeOfDay 2 0))
                        |> set #shiftTypeId (Just (unpackId shiftType.id))
                        |> setTestDurationMinutes (Just 240)
                    )

                response <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams
                            (ToggleRosterWeekLiveStatusAction rosterWeek.id)
                            [("isLive", "on")]

                response `responseStatusShouldBe` status200
                lookup "HX-Reswap" (responseHeaders response) `shouldBe` Just "none"
                response `responseBodyShouldContain` "Roster week is now live."
                response `responseBodyShouldNotContain` cs rosterContentFragmentId
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
                staffMember <- createStaffRecord venue (Just user) "Alpha" "Crew"
                rosterWeek <- createRosterWeekRecord venue 0 True
                rosterDay <- createRosterDayRecord rosterWeek 0
                _ <- createRosterSlotRecord rosterDay slotName (Just staffMember) 0

                response <- withUser user do
                    callAction (ShowRosterWeekAction 0)

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` ">Alpha<"
                response `responseBodyShouldContain` "name=\"responseContext\" value=\"self-service\""
                response `responseBodyShouldContain` "data-bepis-surface=\"self-service-leave\""
                response `responseBodyShouldContain` "data-bepis-surface-action=\"create-self-service-leave-request\""
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

        it "shows roster JPG export only to managers on live row-grid weeks" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-export-live-only@example.com" "staff" True
                worker <- createUserRecord "roster-worker-export-hidden@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                _ <- createVenueMembershipRecord venue worker "worker"
                slotName <- fetchSlotNameRecord venue "Early"
                draftWeek <- createRosterWeekRecord venue 0 False
                rosterDay <- createRosterDayRecord draftWeek 0
                _ <- createRosterSlotRecord rosterDay slotName Nothing 0

                draftManagerResponse <- withUserAndCurrentVenue manager venue.id do
                    callAction (ShowRosterWeekAction 0)
                draftManagerResponse `responseStatusShouldBe` status200
                draftManagerResponse `responseBodyShouldNotContain` "Export JPG"
                draftManagerResponse `responseBodyShouldContain` "roster-shift-create-grid"
                draftManagerResponse `responseBodyShouldContain` "class=\"roster-shift-unit-cell slot-empty-cell\" data-bepis-roster-image-export-cell=\"{&quot;imageExportText&quot;:&quot;&quot;}\""

                _ <- updateRecord (draftWeek |> set #isLive True)

                liveManagerResponse <- withUserAndCurrentVenue manager venue.id do
                    callAction (ShowRosterWeekAction 0)
                liveManagerResponse `responseStatusShouldBe` status200
                liveManagerResponse `responseBodyShouldContain` "Export JPG"
                liveManagerResponse `responseBodyShouldContain` "data-bepis-roster-image-export-trigger=\"true\""
                liveManagerResponse `responseBodyShouldContain` "data-bepis-roster-image-export-format=\"jpg\""
                liveManagerResponse `responseBodyShouldContain` "data-bepis-roster-image-export-config="
                liveManagerResponse `responseBodyShouldContain` "&quot;imageExportFilename&quot;:&quot;roster-"
                liveManagerResponse `responseBodyShouldContain` "data-bepis-roster-image-export-projection=\"true\""
                liveManagerResponse `responseBodyShouldContain` "data-bepis-roster-image-export-cell="
                liveManagerResponse `responseBodyShouldContain` "class=\"roster-subhead roster-col-time\" data-bepis-roster-image-export-cell=\"{&quot;imageExportText&quot;:&quot;Start&quot;}\">Start</div>"

                _ <- withPasskeyVerifiedUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams
                            (UpdateRosterLayoutPreferenceAction 0)
                            [("rosterLayoutMode", "day_columns")]

                dayColumnsManagerResponse <- withUserAndCurrentVenue manager venue.id do
                    callAction (ShowRosterWeekAction 0)
                dayColumnsManagerResponse `responseStatusShouldBe` status200
                dayColumnsManagerResponse `responseBodyShouldContain` "data-roster-layout=\"day_columns\""
                dayColumnsManagerResponse `responseBodyShouldNotContain` "data-bepis-roster-image-export-trigger"

                timelineManagerResponse <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams
                        (ShowRosterWeekAction 0)
                        [ ("rosterView", "timeline")
                        , ("dayOffset", "0")
                        ]
                timelineManagerResponse `responseStatusShouldBe` status200
                timelineManagerResponse `responseBodyShouldContain` "data-roster-layout=\"timeline\""
                timelineManagerResponse `responseBodyShouldNotContain` "data-bepis-roster-image-export-trigger"

                workerResponse <- withUserAndCurrentVenue worker venue.id do
                    callAction (ShowRosterWeekAction 0)
                workerResponse `responseStatusShouldBe` status200
                workerResponse `responseBodyShouldNotContain` "Export JPG"

        it "shows week wage estimates to admins only" $ withContext do
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
                _ <- updateRecord (staffMember |> set #payAssignmentMode AwardRate |> set #defaultAwardLevelId (Just level.id))
                shiftType <- createShiftTypeRecord venue level "Floor"
                rosterOnlyStaff <- createStaffRecord venue Nothing "Roster-only" "Staff"
                rosterOnlyShiftType <- createShiftTypeRecord venue level "Roster-only shift"
                _ <- updateRecord (rosterOnlyShiftType |> set #payAssignmentMode RosterOnly |> set #overrideAwardLevelId Nothing)
                rosterWeek <- createRosterWeekRecord venue 0 True
                rosterDay <- createRosterDayRecord rosterWeek 0
                slot <- createRosterSlotRecord rosterDay slotName (Just staffMember) 0
                _ <- updateRecord
                    ( slot
                        |> setTestStartTime (Just (timeOfDay 9 0))
                        |> setTestEndTime (Just (timeOfDay 17 0))
                        |> set #shiftTypeId (Just (unpackId shiftType.id))
                        |> setTestDurationMinutes (Just 480)
                    )
                rosterOnlyStaffSlot <- createRosterSlotRecord rosterDay slotName (Just rosterOnlyStaff) 4
                _ <- updateRecord
                    ( rosterOnlyStaffSlot
                        |> setTestStartTime (Just (timeOfDay 9 0))
                        |> setTestEndTime (Just (timeOfDay 17 0))
                        |> set #shiftTypeId (Just (unpackId shiftType.id))
                        |> setTestDurationMinutes (Just 480)
                    )
                rosterOnlyShiftSlot <- createRosterSlotRecord rosterDay slotName (Just staffMember) 5
                _ <- updateRecord
                    ( rosterOnlyShiftSlot
                        |> setTestStartTime (Just (timeOfDay 9 0))
                        |> setTestEndTime (Just (timeOfDay 17 0))
                        |> set #shiftTypeId (Just (unpackId rosterOnlyShiftType.id))
                        |> setTestDurationMinutes (Just 480)
                    )
                incompleteSlot <- createRosterSlotRecord rosterDay slotName (Just staffMember) 1
                _ <- updateRecord (incompleteSlot |> setTestStartTime (Just (timeOfDay 9 0)))
                invalidTimingSlot <- createRosterSlotRecord rosterDay slotName (Just staffMember) 2
                _ <- updateRecord
                    ( invalidTimingSlot
                        |> setTestStartTime (Just (timeOfDay 9 0))
                        |> setTestEndTime (Just (timeOfDay 8 0))
                        |> set #shiftTypeId (Just (unpackId shiftType.id))
                        |> setTestDurationMinutes (Just 1380)
                    )
                importedPayItem <- createImportedXeroPayItemRecord venue admin "Unavailable imported rate" "unavailable-rate" 25
                now <- getCurrentTime
                _ <- updateRecord (importedPayItem |> set #archivedAt (Just now) |> set #archivedByUserId (Just (unpackId admin.id)))
                uncalculableShiftType <- newRecord @ShiftType
                    |> set #venueId (unpackId venue.id)
                    |> set #name "Unavailable pay context"
                    |> set #sortOrder 99
                    |> set #payAssignmentMode XeroRate
                    |> set #importedXeroPayItemId (Just importedPayItem.id)
                    |> set #isActive True
                    |> createRecord
                uncalculableSlot <- createRosterSlotRecord rosterDay slotName (Just staffMember) 3
                _ <- updateRecord
                    ( uncalculableSlot
                        |> setTestStartTime (Just (timeOfDay 10 0))
                        |> setTestEndTime (Just (timeOfDay 14 0))
                        |> set #shiftTypeId (Just (unpackId uncalculableShiftType.id))
                        |> setTestDurationMinutes (Just 240)
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
                adminResponse `responseBodyShouldContain` "1 wage estimate error"
                adminResponse `responseBodyShouldContain` "Wage source warning"
                adminResponse `responseBodyShouldNotContain` "draft shift excluded"
                adminResponse `responseBodyShouldNotContain` "roster-only excluded"
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
                lookup "HX-Reswap" (responseHeaders dayColumnsResponse) `shouldBe` Just "none"
                dayColumnsResponse `responseBodyShouldNotContain` "data-roster-layout=\"day_columns\""
                let dayColumnsTriggerHeader = cs <$> lookup "HX-Trigger" (responseHeaders dayColumnsResponse)
                dayColumnsTriggerHeader `shouldSatisfy` maybe False (Text.isInfixOf (cs rosterGridFrameFragmentId))

                dayColumnsFrameResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callAction (ShowRosterWeekContentFragmentAction 0)
                dayColumnsFrameResponse `responseBodyShouldContain` "data-roster-layout=\"day_columns\""
                dayColumnsFrameResponse `responseBodyShouldContain` "Wages:"
                dayColumnsFrameResponse `responseBodyShouldContain` "roster-wage-summary-total"
                dayColumnsFrameResponse `responseBodyShouldContain` "roster-day-wage-total-labeled"
                dayColumnsFrameResponse `responseBodyShouldContain` "Wages"
                dayColumnsFrameResponse `responseBodyShouldContain` "aria-label=\"Wages for day\""
                dayColumnsFrameResponse `responseBodyShouldNotContain` "roster-wage-prediction"

                hiddenWagesResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams
                            (UpdateRosterWageEstimatePreferenceAction 0)
                            [("showWageEstimates", "false")]

                hiddenWagesResponse `responseStatusShouldBe` status200
                lookup "HX-Reswap" (responseHeaders hiddenWagesResponse) `shouldBe` Just "none"
                hiddenWagesResponse `responseBodyShouldNotContain` "data-roster-wages=\"hidden\""
                let hiddenWagesTriggerHeader = cs <$> lookup "HX-Trigger" (responseHeaders hiddenWagesResponse)
                hiddenWagesTriggerHeader `shouldSatisfy` maybe False (Text.isInfixOf (cs rosterGridFrameFragmentId))

                hiddenWagesFrameResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callAction (ShowRosterWeekContentFragmentAction 0)
                hiddenWagesFrameResponse `responseBodyShouldContain` "data-roster-wages=\"hidden\""
                hiddenWagesFrameResponse `responseBodyShouldNotContain` "Wages disabled"
                hiddenWagesFrameResponse `responseBodyShouldNotContain` "Wages:"
                hiddenWagesPanelResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams
                        (ShowRosterWeekStaffPanelFragmentAction 0)
                        [("rosterGroupId", cs (tshow rosterWeek.rosterGroupId))]
                hiddenWagesPanelResponse `responseBodyShouldContain` "Wages disabled"
                hiddenWagesFrameResponse `responseBodyShouldNotContain` "roster-wage-summary"
                hiddenWagesFrameResponse `responseBodyShouldNotContain` "roster-day-wage-total"
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

        it "allows wage estimates when roster end times are hidden" $ withContext do
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
                _ <- updateRecord (staffMember |> set #payAssignmentMode AwardRate |> set #defaultAwardLevelId (Just level.id))
                shiftType <- createShiftTypeRecord venue level "Floor"
                rosterWeek <- createRosterWeekRecord venue 0 True
                rosterDay <- createRosterDayRecord rosterWeek 0
                slot <- createRosterSlotRecord rosterDay slotName (Just staffMember) 0
                _ <- updateRecord
                    ( slot
                        |> setTestStartTime (Just (timeOfDay 9 0))
                        |> setTestEndTime (Just (timeOfDay 17 0))
                        |> set #shiftTypeId (Just (unpackId shiftType.id))
                        |> setTestDurationMinutes (Just 480)
                    )

                adminResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callAction (ShowRosterWeekAction 0)

                adminResponse `responseStatusShouldBe` status200
                adminResponse `responseBodyShouldContain` "data-roster-end-times=\"false\""
                adminResponse `responseBodyShouldContain` "data-roster-wages=\"hidden\""
                adminResponse `responseBodyShouldContain` "Wages disabled"
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
                lookup "HX-Reswap" (responseHeaders toggleResponse) `shouldBe` Just "none"
                toggleResponse `responseBodyShouldNotContain` "data-roster-end-times=\"false\""
                let shownWagesTriggerHeader = cs <$> lookup "HX-Trigger" (responseHeaders toggleResponse)
                shownWagesTriggerHeader `shouldSatisfy` maybe False (Text.isInfixOf (cs rosterGridFrameFragmentId))

                shownWagesFrameResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callAction (ShowRosterWeekContentFragmentAction 0)
                shownWagesFrameResponse `responseBodyShouldContain` "data-roster-end-times=\"false\""
                shownWagesFrameResponse `responseBodyShouldNotContain` "Wages enabled"
                shownWagesFrameResponse `responseBodyShouldContain` "Wages:"
                shownWagesPanelResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams
                        (ShowRosterWeekStaffPanelFragmentAction 0)
                        [("rosterGroupId", cs (tshow rosterWeek.rosterGroupId))]
                shownWagesPanelResponse `responseBodyShouldContain` "Wages enabled"
                shownWagesFrameResponse `responseBodyShouldContain` "$150.00"
                shownWagesFrameResponse `responseBodyShouldContain` "roster-wage-summary"
                shownWagesFrameResponse `responseBodyShouldContain` "roster-day-wage-total"
                shownWagesFrameResponse `responseBodyShouldNotContain` ">5:00 PM<"
                shownPreferences <- query @UserPreference
                    |> filterWhere (#userId, unpackId admin.id)
                    |> fetchOne
                shownPreferences.showWageEstimates `shouldBe` True

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

        it "publishes roster suggestions immediately without queueing or creating timesheets" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-publish-suggestions@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                venueConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                _ <- updateRecord (venueConfig |> set #autoTimesheetCreationEnabled True)
                slotName <- fetchSlotNameRecord venue "Late"
                staffMember <- createStaffRecord venue (Just manager) "Alpha" "Crew"
                level <- createPayLevelRecord venue "Level 1"
                _ <- updateRecord (staffMember |> set #payAssignmentMode AwardRate |> set #defaultAwardLevelId (Just level.id))
                shiftType <- createShiftTypeRecord venue level "Bar"
                rosterWeek <- createRosterWeekRecord venue 0 False
                rosterDay <- createRosterDayRecord rosterWeek 0
                slot <- createRosterSlotRecord rosterDay slotName (Just staffMember) 0
                slot <- updateRecord
                    ( slot
                        |> setTestStartTime (Just (timeOfDay 22 0))
                        |> setTestEndTime (Just (timeOfDay 2 0))
                        |> set #shiftTypeId (Just (unpackId shiftType.id))
                        |> setTestDurationMinutes (Just 240)
                    )

                response <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams
                            (ToggleRosterWeekLiveStatusAction rosterWeek.id)
                            [("isLive", "on")]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldNotContain` "Pending timesheet jobs queued"
                query @AppJob |> fetchCount >>= (`shouldBe` 0)
                query @TimesheetEntry |> fetchCount >>= (`shouldBe` 0)

                timesheetsResponse <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams ShowTimesheetWeekAction { weekOffset = 0 }
                        [("weekOffset", "0"), ("showApproved", "false"), ("showAllStaff", "true"), ("showSuggestions", "true")]
                timesheetsResponse `responseBodyShouldContain` cs ("data-timesheet-suggestion-id=\"" <> tshow slot.id <> "\"")

        it "hides draft-roster suggestions while preserving materialized timesheet snapshots" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-draft-suggestions@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                staffMember <- createStaffRecord venue (Just manager) "Alpha" "Crew"
                level <- createPayLevelRecord venue "Level 1"
                _ <- updateRecord (staffMember |> set #payAssignmentMode AwardRate |> set #defaultAwardLevelId (Just level.id))
                shiftType <- createShiftTypeRecord venue level "Bar"
                slotName <- fetchSlotNameRecord venue "Late"
                rosterWeek <- createRosterWeekRecord venue 0 True
                rosterDay <- createRosterDayRecord rosterWeek 0
                sourceSlot <- createRosterSlotRecord rosterDay slotName (Just staffMember) 0
                pendingSlot <- createRosterSlotRecord rosterDay slotName (Just staffMember) 1
                sourceSlot <- updateRecord
                    ( sourceSlot
                        |> setTestStartTime (Just (timeOfDay 9 0))
                        |> setTestEndTime (Just (timeOfDay 17 0))
                        |> set #shiftTypeId (Just (unpackId shiftType.id))
                        |> setTestDurationMinutes (Just 480)
                    )
                pendingSlot <- updateRecord
                    ( pendingSlot
                        |> setTestStartTime (Just (timeOfDay 18 0))
                        |> setTestEndTime (Just (timeOfDay 23 0))
                        |> set #shiftTypeId (Just (unpackId shiftType.id))
                        |> setTestDurationMinutes (Just 300)
                    )

                liveResponse <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams ShowTimesheetWeekAction { weekOffset = 0 }
                        [("weekOffset", "0"), ("showApproved", "false"), ("showAllStaff", "true"), ("showSuggestions", "true")]
                liveResponse `responseBodyShouldContain` cs ("data-timesheet-suggestion-id=\"" <> tshow sourceSlot.id <> "\"")
                liveResponse `responseBodyShouldContain` cs ("data-timesheet-suggestion-id=\"" <> tshow pendingSlot.id <> "\"")

                createResponse <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams CreateTimesheetEntryFromSuggestionAction { rosterSlotId = sourceSlot.id }
                        [("weekOffset", "0"), ("showApproved", "false"), ("showAllStaff", "true"), ("showSuggestions", "true")]
                createResponse `responseStatusShouldBe` status302
                materializedEntry <- query @TimesheetEntry |> fetchOne

                draftResponse <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams (ToggleRosterWeekLiveStatusAction rosterWeek.id) [("isLive", "false")]
                draftResponse `responseStatusShouldBe` status200

                timesheetsResponse <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams ShowTimesheetWeekAction { weekOffset = 0 }
                        [("weekOffset", "0"), ("showApproved", "false"), ("showAllStaff", "true"), ("showSuggestions", "true")]
                timesheetsResponse `responseBodyShouldNotContain` cs ("data-timesheet-suggestion-id=\"" <> tshow pendingSlot.id <> "\"")
                timesheetsResponse `responseBodyShouldContain` cs (pathTo EditTimesheetEntryAction { timesheetEntryId = materializedEntry.id })
                unchangedEntry <- fetch materializedEntry.id
                unchangedEntry.sourceRosterSlotId `shouldBe` Just (unpackId sourceSlot.id)
                testStartTime unchangedEntry `shouldBe` timeOfDay 9 0
                testEndTime unchangedEntry `shouldBe` timeOfDay 17 0

        it "warns and leaves a materialized timesheet snapshot unchanged when its roster source is edited" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-timesheet-snapshot-warning@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                alpha <- createStaffRecord venue (Just manager) "Alpha" "Crew"
                bravoUser <- createUserRecord "roster-timesheet-snapshot-bravo@example.com" "staff" True
                _ <- createVenueMembershipRecord venue bravoUser "worker"
                bravo <- createStaffRecord venue (Just bravoUser) "Bravo" "Crew"
                level <- createPayLevelRecord venue "Level 1"
                _ <- updateRecord (alpha |> set #payAssignmentMode AwardRate |> set #defaultAwardLevelId (Just level.id))
                _ <- updateRecord (bravo |> set #payAssignmentMode AwardRate |> set #defaultAwardLevelId (Just level.id))
                shiftType <- createShiftTypeRecord venue level "Bar"
                slotName <- fetchSlotNameRecord venue "Late"
                rosterWeek <- createRosterWeekRecord venue 0 True
                rosterDay <- createRosterDayRecord rosterWeek 0
                slot <- createRosterSlotRecord rosterDay slotName (Just alpha) 0
                completeSlot <- updateRecord
                    ( slot
                        |> setTestStartTime (Just (timeOfDay 22 0))
                        |> setTestEndTime (Just (timeOfDay 2 0))
                        |> set #shiftTypeId (Just (unpackId shiftType.id))
                        |> setTestDurationMinutes (Just 240)
                    )

                createResponse <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams CreateTimesheetEntryFromSuggestionAction { rosterSlotId = completeSlot.id }
                        [("weekOffset", "0"), ("showApproved", "false"), ("showAllStaff", "true"), ("showSuggestions", "true")]
                createResponse `responseStatusShouldBe` status302
                entry <- query @TimesheetEntry |> fetchOne

                _ <- updateRecord (rosterWeek |> set #isLive False)
                response <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams
                            (UpdateRosterSlotAction completeSlot.id)
                            [ ("staffId", idToParam bravo.id)
                            , ("startTime", "23:00")
                            , ("endTime", "03:00")
                            , ("shiftTypeId", idToParam shiftType.id)
                            ]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "A timesheet entry was already created from this roster shift. The timesheet snapshot was not changed."
                unchangedEntry <- fetch entry.id
                unchangedEntry.staffId `shouldBe` unpackId alpha.id
                testStartTime unchangedEntry `shouldBe` timeOfDay 22 0
                testEndTime unchangedEntry `shouldBe` timeOfDay 2 0
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
                _ <- updateRecord (slot |> setTestStartTime (Just (timeOfDay 9 0)) |> set #shiftTypeId Nothing)

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
                        |> setTestRosterSlotBoundaries (fromGregorian 2025 1 6) (timeOfDay 9 0) (timeOfDay 17 0)
                        |> set #shiftTypeId (Just (unpackId shiftType.id))
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

        it "blocks publishing staffed shifts missing end times or shift types when end times are hidden" $ withContext do
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
                _ <- updateRecord (slot |> setTestStartTime (Just (timeOfDay 9 0)) |> set #shiftTypeId Nothing)

                blockedResponse <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams
                            (ToggleRosterWeekLiveStatusAction rosterWeek.id)
                            [("isLive", "on")]

                blockedResponse `responseStatusShouldBe` status200
                blockedResponse `responseBodyShouldContain` "Roster week cannot go live until every staffed shift has a start time, valid end time, and shift type."
                blockedWeek <- fetch rosterWeek.id
                blockedWeek.isLive `shouldBe` False

                _ <- updateRecord (slot |> set #shiftTypeId (Just (unpackId shiftType.id)))

                stillBlockedResponse <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams
                            (ToggleRosterWeekLiveStatusAction rosterWeek.id)
                            [("isLive", "on")]

                stillBlockedResponse `responseStatusShouldBe` status200
                stillBlockedResponse `responseBodyShouldContain` "Roster week cannot go live until every staffed shift has a start time, valid end time, and shift type."
                stillBlockedWeek <- fetch rosterWeek.id
                stillBlockedWeek.isLive `shouldBe` False

                _ <- updateRecord (slot |> setTestRosterSlotBoundaries (fromGregorian 2025 1 6) (timeOfDay 9 0) (timeOfDay 17 0))

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
                testStartTime updatedSlot `shouldBe` Just (timeOfDay 22 0)
                testEndTime updatedSlot `shouldBe` Just (timeOfDay 2 0)
                updatedSlot.shiftTypeId `shouldBe` Just (unpackId shiftType.id)
                testDurationMinutes updatedSlot `shouldBe` Just 240

        it "manager slot edits save end times when roster end times are hidden" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-hidden-end-time-save@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                venueConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                _ <- updateRecord (venueConfig |> set #rosterEndTimesEnabled False)
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
                response `responseBodyShouldNotContain` "roster-col-time\">End"
                response `responseBodyShouldNotContain` ">2:00 AM<"
                updatedSlot <- fetch slot.id
                testStartTime updatedSlot `shouldBe` Just (timeOfDay 22 0)
                testEndTime updatedSlot `shouldBe` Just (timeOfDay 2 0)
                updatedSlot.shiftTypeId `shouldBe` Just (unpackId shiftType.id)
                testDurationMinutes updatedSlot `shouldBe` Just 240

        it "manager can toggle a live week back to draft" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-draft-toggle@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                rosterWeek <- createRosterWeekRecord venue 0 True

                response <- withUser manager do
                    callActionWithParams (ToggleRosterWeekLiveStatusAction rosterWeek.id) [("isLive", "false")]

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
                lookup "HX-Reswap" (responseHeaders response) `shouldBe` Just "none"
                response `responseBodyShouldNotContain` "data-roster-layout=\"day_columns\""
                response `responseBodyShouldNotContain` "roster-day-columns"
                let layoutTriggerHeader = cs <$> lookup "HX-Trigger" (responseHeaders response)
                layoutTriggerHeader `shouldSatisfy` maybe False (Text.isInfixOf (cs rosterGridFrameFragmentId))

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
                response `responseBodyShouldContain` "&quot;staffName&quot;:&quot;Alpha&quot;"
                response `responseBodyShouldContain` "&quot;assignedShifts&quot;:1"

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
                response `responseBodyShouldContain` "&quot;staffName&quot;:&quot;Alpha&quot;"
                response `responseBodyShouldContain` "&quot;staffName&quot;:&quot;Trial&quot;"
                response `responseBodyShouldContain` "&quot;staffRole&quot;:&quot;TRIAL&quot;"
                response `responseBodyShouldContain` "class=\"btn btn-sm btn-outline-secondary app-icon-button roster-staff-invite-button\""
                response `responseBodyShouldContain` "class=\"bi bi-envelope\""
                response `responseBodyShouldContain` "aria-label=\"Invite Trial\""
                response `responseBodyShouldContain` "hx-trigger=\"click consume\""
                response `responseBodyShouldContain` "hx-get=\"/NewTrialStaffInvitation?staffId="
                response `responseBodyShouldNotContain` "aria-label=\"Invite Alpha\""
                response `responseBodyShouldNotContain` "&quot;staffName&quot;:&quot;Bravo&quot;"
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
                response `responseBodyShouldContain` "&quot;staffName&quot;:&quot;Solo&quot;"
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
                response `responseBodyShouldContain` "&quot;staffName&quot;:&quot;Alpha&quot;"
                response `responseBodyShouldContain` "&quot;staffName&quot;:&quot;Bravo&quot;"
                response `responseBodyShouldContain` "&quot;staffName&quot;:&quot;Trial&quot;"
                response `responseBodyShouldNotContain` "&quot;staffName&quot;:&quot;Other&quot;"
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
                sourceSlot <- createCompleteRosterSlotRecord sourceDay slotName staffMember 0
                let sourceSlotWithFields =
                        sourceSlot
                            |> setTestStartTime (Just (timeOfDay 9 0))
                            |> setTestDurationMinutes (Just 480)
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
                testStartTime copiedSlot `shouldBe` Just (timeOfDay 9 0)
                testDurationMinutes copiedSlot `shouldBe` Just 480

        it "rejects copies whose target-date DST elapsed duration breaches Part-time limits" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Roster Award Copy Venue"
                manager <- createUserRecord "roster-award-copy-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                staffMember <- createStaffRecord venue Nothing "Part-time" "Copy" >>= updateRecord . set #employmentBasis Permanent
                level <- createPayLevelRecord venue "Copy Level"
                staffMemberWithRate <- updateRecord (staffMember |> set #payAssignmentMode AwardRate |> set #defaultAwardLevelId (Just level.id))
                shiftType <- createShiftTypeRecord venue level "Copy Shift"
                slotName <- fetchSlotNameRecord venue "Early"
                sourceWeek <- createRosterWeekRecord venue 63 False
                sourceDay <- createRosterDayRecord sourceWeek 5
                sourceSlot <- createRosterSlotRecord sourceDay slotName (Just staffMemberWithRate) 0
                _ <- updateRecord
                    (sourceSlot |> set #shiftTypeId (Just (unpackId shiftType.id)) |> setTestRosterSlotBoundaries (fromGregorian 2026 3 28) (timeOfDay 17 45) (timeOfDay 5 45))

                response <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callAction (CopyRosterWeekAction 63 64)

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Part-time roster shifts must project between 3 and 11.5 working hours after the automatic unpaid meal break."
                query @RosterWeek
                    |> filterWhere (#venueId, unpackId venue.id)
                    |> filterWhere (#weekOffset, 64)
                    |> fetchOneOrNothing
                    >>= (`shouldBe` Nothing)

        it "rejects copies whose target-date DST elapsed duration breaches Casual limits" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Roster Award Casual Copy Venue"
                manager <- createUserRecord "roster-award-casual-copy-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                staffMember <- createStaffRecord venue Nothing "Casual" "Copy" >>= updateRecord . set #employmentBasis Casual
                level <- createPayLevelRecord venue "Copy Level"
                staffMemberWithRate <- updateRecord (staffMember |> set #payAssignmentMode AwardRate |> set #defaultAwardLevelId (Just level.id))
                shiftType <- createShiftTypeRecord venue level "Copy Shift"
                slotName <- fetchSlotNameRecord venue "Early"
                sourceWeek <- createRosterWeekRecord venue 63 False
                sourceDay <- createRosterDayRecord sourceWeek 5
                sourceSlot <- createRosterSlotRecord sourceDay slotName (Just staffMemberWithRate) 0
                _ <- updateRecord
                    (sourceSlot |> set #shiftTypeId (Just (unpackId shiftType.id)) |> setTestRosterSlotBoundaries (fromGregorian 2026 3 28) (timeOfDay 17 15) (timeOfDay 5 45))

                response <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callAction (CopyRosterWeekAction 63 64)

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Casual roster shifts must project no more than 12 working hours after the automatic unpaid meal break."
                query @RosterWeek
                    |> filterWhere (#venueId, unpackId venue.id)
                    |> filterWhere (#weekOffset, 64)
                    |> fetchOneOrNothing
                    >>= (`shouldBe` Nothing)

        it "copies roster clocks across autumn only after choosing the repeated occurrence" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Roster Copy Autumn Venue"
                manager <- createUserRecord "roster-copy-autumn-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                slotName <- fetchSlotNameRecord venue "Early"
                staffMember <- createStaffRecord venue Nothing "Copy" "Crew"
                sourceWeek <- createRosterWeekRecord venue 63 True
                sourceDay <- createRosterDayRecord sourceWeek 5
                sourceSlot <- createCompleteRosterSlotRecord sourceDay slotName staffMember 0
                _ <- sourceSlot
                    |> setTestRosterSlotBoundaries (fromGregorian 2026 3 28) (timeOfDay 2 30) (timeOfDay 4 0)
                    |> updateRecord
                ordinarySourceSlot <- createCompleteRosterSlotRecord sourceDay slotName staffMember 1
                _ <- ordinarySourceSlot
                    |> setTestRosterSlotBoundaries (fromGregorian 2026 3 28) (timeOfDay 9 0) (timeOfDay 17 0)
                    |> updateRecord

                chooserResponse <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callAction (CopyRosterWeekAction 63 64)

                chooserResponse `responseStatusShouldBe` status200
                chooserResponse `responseBodyShouldContain` "data-bepis-surface-action=\"copy-roster-week\""
                chooserResponse `responseBodyShouldContain` "hx-target=\"#roster-content\""
                chooserResponse `responseBodyShouldContain` "data-time-occurrence-chooser=\"copyStartOccurrence\""
                chooserResponse `responseBodyShouldNotContain` "data-time-occurrence-chooser=\"copyEndOccurrence\""
                query @RosterWeek
                    |> filterWhere (#venueId, unpackId venue.id)
                    |> filterWhere (#weekOffset, 64)
                    |> fetchCount
                    >>= (`shouldBe` 0)

                copiedResponse <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams
                            (CopyRosterWeekAction 63 64)
                            [("copyStartOccurrence", "second")]

                copiedResponse `responseStatusShouldBe` status200
                copiedWeek <- query @RosterWeek
                    |> filterWhere (#venueId, unpackId venue.id)
                    |> filterWhere (#weekOffset, 64)
                    |> fetchOne
                copiedDay <- query @RosterDay
                    |> filterWhere (#rosterWeekId, unpackId copiedWeek.id)
                    |> filterWhere (#dayOffset, 5)
                    |> fetchOne
                copiedSlot <- query @RosterSlot
                    |> filterWhere (#rosterDayId, unpackId copiedDay.id)
                    |> filterWhere (#rowIndex, 0)
                    |> filterWhere (#deletedAt, Nothing)
                    |> fetchOne
                ordinaryCopiedSlot <- query @RosterSlot
                    |> filterWhere (#rosterDayId, unpackId copiedDay.id)
                    |> filterWhere (#rowIndex, 1)
                    |> filterWhere (#deletedAt, Nothing)
                    |> fetchOne
                copiedStartsAt <- maybe (expectationFailure "Expected copied roster start" >> error "unreachable") pure copiedSlot.startsAt
                storedInstantOccurrence copiedSlot.timezone copiedStartsAt `shouldBe` Just SecondOccurrence
                (storedInstantLocalTime copiedSlot.timezone copiedStartsAt).localDay `shouldBe` fromGregorian 2026 4 5
                testStartTime copiedSlot `shouldBe` Just (timeOfDay 2 30)
                testEndTime copiedSlot `shouldBe` Just (timeOfDay 4 0)
                testDurationMinutes copiedSlot `shouldBe` Just 90
                testStartTime ordinaryCopiedSlot `shouldBe` Just (timeOfDay 9 0)
                testEndTime ordinaryCopiedSlot `shouldBe` Just (timeOfDay 17 0)
                rosterSlotStartOccurrence ordinaryCopiedSlot `shouldBe` Nothing

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
                sourceSlot <- createCompleteRosterSlotRecord sourceDay early alpha 0
                _ <- updateRecord
                    ( sourceSlot
                        |> setTestStartTime (Just (timeOfDay 8 0))
                        |> setTestDurationMinutes (Just 300)
                    )

                targetWeek <- createRosterWeekRecord venue 1 False
                targetDay <- createRosterDayRecord targetWeek 0
                targetSlot <- createRosterSlotRecord targetDay late (Just bravo) 0
                _ <- updateRecord
                    ( targetSlot
                        |> setTestStartTime (Just (timeOfDay 14 0))
                        |> setTestDurationMinutes (Just 180)
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
                testStartTime copiedSlot `shouldBe` Just (timeOfDay 8 0)
                testDurationMinutes copiedSlot `shouldBe` Just 300

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
                sourceSlot <- createCompleteRosterSlotRecord sourceDay early alpha 0
                _ <- updateRecord
                    ( sourceSlot
                        |> setTestStartTime (Just (timeOfDay 8 0))
                        |> setTestDurationMinutes (Just 300)
                    )

                targetWeek <- createRosterWeekRecord venue 1 True
                targetDay <- createRosterDayRecord targetWeek 0
                targetSlot <- createRosterSlotRecord targetDay late (Just bravo) 0
                _ <- updateRecord
                    ( targetSlot
                        |> setTestStartTime (Just (timeOfDay 14 0))
                        |> setTestDurationMinutes (Just 180)
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
                testStartTime copiedSlot `shouldBe` Just (timeOfDay 8 0)
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
                frontSourceSlot <- createCompleteRosterSlotRecord frontSourceDay frontSlotName alpha 0
                _ <- updateRecord (frontSourceSlot |> setTestStartTime (Just (timeOfDay 8 0)))

                backSourceWeek <- createRosterWeekRecordForRosterGroup venue backOfHouse 0 True
                backSourceDay <- createRosterDayRecord backSourceWeek 0
                backSourceSlot <- createRosterSlotRecord backSourceDay backSlotName (Just bravo) 0
                _ <- updateRecord (backSourceSlot |> setTestStartTime (Just (timeOfDay 12 0)))

                frontTargetWeek <- createRosterWeekRecordForRosterGroup venue frontOfHouse 1 False
                _ <- createRosterDayRecord frontTargetWeek 0
                backTargetWeek <- createRosterWeekRecordForRosterGroup venue backOfHouse 1 False
                backTargetDay <- createRosterDayRecord backTargetWeek 0
                backTargetSlot <- createRosterSlotRecord backTargetDay backSlotName (Just bravo) 0
                _ <- updateRecord (backTargetSlot |> setTestStartTime (Just (timeOfDay 15 0)))

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
                testStartTime frontCopiedSlot `shouldBe` Just (timeOfDay 8 0)

                backUnchangedSlot <- fetch backTargetSlot.id
                backUnchangedSlot.deletedAt `shouldBe` Nothing
                backUnchangedSlot.staffId `shouldBe` Just (unpackId bravo.id)
                testStartTime backUnchangedSlot `shouldBe` Just (timeOfDay 15 0)
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

timeOfDay :: Int -> Int -> TimeOfDay
timeOfDay hour minute = TimeOfDay hour minute 0


