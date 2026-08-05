module Test.Controller.RosterTemplatesSpec where

import Application.Helper.WeekBoundaries (venueWeekStartDate)
import Application.RosterTemplates (RosterTemplateDraft (..),
                                    RosterTemplateSave (..),
                                    fetchPrivateRosterTemplateDraft,
                                    rosterTemplateActor,
                                    saveRosterTemplateDraft,
                                    startRosterTemplateEditDraft)
import qualified Data.ByteString.Char8 as ByteString
import Data.Time.LocalTime (TimeOfDay (..))
import Generated.Types
import IHP.ControllerPrelude
import IHP.Test.Mocking
import Network.HTTP.Types.Status
import Network.Wai (responseHeaders)
import Test.Hspec
import Test.Support
import Web.Controller.RosterTemplates ()
import Web.FrontController ()
import Web.RosterWeeks.TemplateDesigner (startBlankRosterTemplateDesignerDraft)
import Web.Types

tests :: Spec
tests = aroundAll withDatabaseTestContext do
    describe "RosterTemplatesController" do
        it "rejects cross-venue template routes without creating a draft" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Template authorized venue"
                foreignVenue <- createVenueWithConfig "Template foreign venue"
                foreignGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId foreignVenue.id) |> fetchOne
                manager <- createUserRecord "template-cross-venue@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager

                response <- withUserAndCurrentVenue manager venue.id do
                    callAction NewRosterTemplateAction { rosterGroupId = foreignGroup.id }
                draftCount <- query @RosterTemplateDesign |> fetchCount

                response `responseStatusShouldBe` status403
                draftCount `shouldBe` 0

        it "renders template creation in the roster-content card for an authorized manager" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Template controller"
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                manager <- createUserRecord "template-controller@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager

                response <- withUserAndCurrentVenue manager venue.id do
                    callAction NewRosterTemplateAction { rosterGroupId = rosterGroup.id }

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Create roster template"
                response `responseBodyShouldContain` "Start from a blank design"
                response `responseBodyShouldContain` "Use a roster as reference"
                response `responseBodyShouldContain` "roster-main-panel"

        it "renders read-only reference selection without materializing or mutating rosters" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Template reference controller"
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                manager <- createUserRecord "template-reference-controller@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                sourceWeek <- createRosterWeekRecordForRosterGroup venue rosterGroup 0 True
                _ <- forM [0 .. 6] (createRosterDayRecord sourceWeek)
                beforeCount <- query @RosterWeek |> fetchCount

                response <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams ShowRosterTemplateReferenceAction
                        { rosterGroupId = rosterGroup.id, weekOffset = 0 }
                        [("name", "Reference day"), ("scale", "day")]
                afterCount <- query @RosterWeek |> fetchCount

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Select a reference day"
                response `responseBodyShouldContain` "Previous week"
                response `responseBodyShouldContain` "Next week"
                response `responseBodyShouldContain` "Use Tuesday"
                response `responseBodyShouldNotContain` "ToggleRosterDayClosed"
                afterCount `shouldBe` beforeCount

        it "confirms a Day reference before creating an isolated prefilled draft" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Template reference confirmation"
                venueConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                manager <- createUserRecord "template-confirm-controller@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                staff <- createStaffRecord venue Nothing "Confirm" "Worker"
                slotName <- fetchSlotNameRecordForRosterGroup rosterGroup "Early"
                sourceWeek <- createRosterWeekRecordForRosterGroup venue rosterGroup 0 False
                sourceDay <- createRosterDayRecord sourceWeek 1
                sourceSlot <- createCompleteRosterSlotRecord sourceDay slotName staff 0
                    >>= updateRecord
                        . setTestRosterSlotBoundaries
                            (addDays 1 (venueWeekStartDate venueConfig 0))
                            (TimeOfDay 9 0 0)
                            (TimeOfDay 17 0 0)

                confirmation <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams ConfirmRosterTemplateReferenceAction
                        { rosterGroupId = rosterGroup.id, weekOffset = 0 }
                        [("name", "Tuesday plan"), ("scale", "day"), ("dayOffset", "1")]
                beforeConfirmDraft <- fetchPrivateRosterTemplateDraft (rosterTemplateActor manager venue True)
                created <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams CreateRosterTemplateFromReferenceAction
                        { rosterGroupId = rosterGroup.id, weekOffset = 0 }
                        [("name", "Tuesday plan"), ("scale", "day"), ("dayOffset", "1")]
                persistedSource <- fetch sourceSlot.id

                confirmation `responseStatusShouldBe` status200
                confirmation `responseBodyShouldContain` "Confirm reference"
                confirmation `responseBodyShouldContain` "Tuesday"
                confirmation `responseBodyShouldContain` "No roster data will be changed"
                beforeConfirmDraft `shouldBe` Nothing
                created `responseStatusShouldBe` status303
                lookup "Location" (responseHeaders created)
                    `shouldSatisfy` maybe False (ByteString.isInfixOf "/ShowRosterTemplateDesigner")
                persistedSource `shouldBe` sourceSlot

        it "renders isolated Day/Week editing controls that autosave complete mutations" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Template designer controls"
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                manager <- createUserRecord "template-controls-controller@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                let actor = rosterTemplateActor manager venue True
                Right draft <- startBlankRosterTemplateDesignerDraft actor rosterGroup Day "Service day"

                let designId = (draft.draftDesign :: RosterTemplateDesign).id
                response <- withUserAndCurrentVenue manager venue.id do
                    callAction ShowRosterTemplateDesignerAction
                        { rosterTemplateDesignId = designId }

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Template design"
                response `responseBodyShouldContain` "Autosaved"
                response `responseBodyShouldContain` "Add shift"
                response `responseBodyShouldContain` "Add column"
                response `responseBodyShouldContain` "Save template"
                response `responseBodyShouldNotContain` "ToggleRosterWeekLiveStatus"

        it "never persists incomplete shift submissions and autosaves a complete shift" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Template shift controller"
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                manager <- createUserRecord "template-shift-controller@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                shiftType <- ensureVenueDefaultShiftType venue
                let actor = rosterTemplateActor manager venue True
                Right draft <- startBlankRosterTemplateDesignerDraft actor rosterGroup Day "Shift day"
                let designId = draft.draftDesign.id
                let completeParams =
                        [ ("dayIndex", "0")
                        , ("columnSortOrder", "0")
                        , ("rowIndex", "0")
                        , ("startTime", "09:00")
                        , ("endTime", "17:00")
                        , ("assignment", "open")
                        , ("shiftTypeId", cs (tshow shiftType.id))
                        ]

                incomplete <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams UpsertRosterTemplateShiftAction { rosterTemplateDesignId = designId }
                        (filter ((/= "endTime") . fst) completeParams)
                afterIncomplete <- fetchPrivateRosterTemplateDraft actor
                complete <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams UpsertRosterTemplateShiftAction { rosterTemplateDesignId = designId } completeParams
                afterComplete <- fetchPrivateRosterTemplateDraft actor

                incomplete `responseStatusShouldBe` status302
                fmap (.draftShifts) afterIncomplete `shouldBe` Just []
                complete `responseStatusShouldBe` status302
                fmap (map (.assignmentState) . (.draftShifts)) afterComplete `shouldBe` Just ["open"]

        it "renders immutable edit conflict recovery actions for saved templates" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Template edit controls"
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                manager <- createUserRecord "template-edit-controller@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                let actor = rosterTemplateActor manager venue True
                Right initial <- startBlankRosterTemplateDesignerDraft actor rosterGroup Day "Saved day"
                Right saved <- saveRosterTemplateDraft actor initial.draftDesign.id
                Right editDraft <- startRosterTemplateEditDraft actor saved.savedTemplate.id

                response <- withUserAndCurrentVenue manager venue.id do
                    callAction ShowRosterTemplateDesignerAction
                        { rosterTemplateDesignId = editDraft.draftDesign.id }

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Reload latest"
                response `responseBodyShouldContain` "Save as new"

        it "offers Continue, Discard and start new, or Cancel for an occupied draft slot" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Template occupied controller"
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                manager <- createUserRecord "template-occupied-controller@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                let actor = rosterTemplateActor manager venue True
                Right _ <- startBlankRosterTemplateDesignerDraft actor rosterGroup Day "Existing private work"

                response <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams CreateRosterTemplateDraftAction { rosterGroupId = rosterGroup.id }
                        [ ("name", "Replacement week")
                        , ("scale", "week")
                        , ("startingPoint", "blank")
                        ]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "A template draft is already in progress"
                response `responseBodyShouldContain` "Continue draft"
                response `responseBodyShouldContain` "Discard and start new"
                response `responseBodyShouldContain` "Cancel"

        it "discards occupied work and starts the explicitly requested replacement" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Template discard controller"
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                manager <- createUserRecord "template-discard-controller@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                let actor = rosterTemplateActor manager venue True
                Right existing <- startBlankRosterTemplateDesignerDraft actor rosterGroup Day "Discard me"

                response <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams DiscardAndRestartRosterTemplateDraftAction
                        { rosterGroupId = rosterGroup.id, rosterTemplateDesignId = existing.draftDesign.id }
                        [("name", "Replacement week"), ("scale", "week"), ("startingPoint", "blank")]
                replacement <- fetchPrivateRosterTemplateDraft actor

                response `responseStatusShouldBe` status303
                fmap (.draftName) replacement `shouldBe` Just "Replacement week"
                fmap ((.scale) . (.draftDesign)) replacement `shouldBe` Just Week

        it "starts a blank private draft and redirects to the isolated designer" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Template blank controller"
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                manager <- createUserRecord "template-blank-controller@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager

                response <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams CreateRosterTemplateDraftAction { rosterGroupId = rosterGroup.id }
                        [ ("name", "Standard week")
                        , ("scale", "week")
                        , ("startingPoint", "blank")
                        ]

                response `responseStatusShouldBe` status303
                lookup "Location" (responseHeaders response)
                    `shouldSatisfy` maybe False (ByteString.isInfixOf "/ShowRosterTemplateDesigner")
