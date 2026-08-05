module Test.Controller.RosterTemplatesSpec where

import Application.Helper.WeekBoundaries (venueWeekStartDate)
import Application.RosterTemplates (RosterTemplateDraft (..),
                                    RosterTemplateSave (..),
                                    fetchPrivateRosterTemplateDraft,
                                    rosterTemplateActor,
                                    saveRosterTemplateDraft,
                                    startRosterTemplateEditDraft)
import qualified Data.ByteString.Char8 as ByteString
import qualified Data.Text as Text
import Data.Time.LocalTime (TimeOfDay (..))
import Generated.Types
import IHP.ControllerPrelude
import IHP.Test.Mocking
import Network.HTTP.Types.Status
import Network.Wai (Response, responseHeaders, responseStatus)
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

        it "rerenders controlled creation validation for malformed scale and invalid names" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Template input validation"
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                manager <- createUserRecord "template-input-validation@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                let submit params = withUserAndCurrentVenue manager venue.id do
                        callActionWithParams CreateRosterTemplateDraftAction { rosterGroupId = rosterGroup.id } params

                malformedScale <- submit [("name", "Valid name"), ("scale", "century"), ("startingPoint", "blank")]
                whitespaceName <- submit [("name", "   "), ("scale", "day"), ("startingPoint", "blank")]
                oversizedName <- submit [("name", ByteString.replicate 121 'x'), ("scale", "day"), ("startingPoint", "blank")]
                draftCount <- query @RosterTemplateDesign |> fetchCount

                malformedScale `responseStatusShouldBe` status200
                malformedScale `responseBodyShouldContain` "Choose Day or Week"
                whitespaceName `responseStatusShouldBe` status200
                whitespaceName `responseBodyShouldContain` "Template names must contain"
                oversizedName `responseStatusShouldBe` status200
                oversizedName `responseBodyShouldContain` "Template names must contain"
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

        it "does not mark an incomplete Week reference as compatible or selectable" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Incomplete reference controller"
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                manager <- createUserRecord "template-incomplete-reference@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                sourceWeek <- createRosterWeekRecordForRosterGroup venue rosterGroup 0 False
                _ <- createRosterDayRecord sourceWeek 0

                response <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams ShowRosterTemplateReferenceAction
                        { rosterGroupId = rosterGroup.id, weekOffset = 0 }
                        [("name", "Incomplete week"), ("scale", "week")]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "This roster week is incomplete"
                response `responseBodyShouldNotContain` "data-bepis-roster-template-designer-template-reference-compatibility"
                response `responseBodyShouldNotContain` "Use this week as template reference"

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

                bypassed <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams CreateRosterTemplateFromReferenceAction
                        { rosterGroupId = rosterGroup.id, weekOffset = 0 }
                        [("name", "Tuesday plan"), ("scale", "day"), ("dayOffset", "1")]
                bypassDraft <- fetchPrivateRosterTemplateDraft (rosterTemplateActor manager venue True)
                (confirmation, tampered, created) <- withUserAndCurrentVenue manager venue.id do
                    confirmation <- callActionWithParams ConfirmRosterTemplateReferenceAction
                        { rosterGroupId = rosterGroup.id, weekOffset = 0 }
                        [("name", "Tuesday plan"), ("scale", "day"), ("dayOffset", "1")]
                    confirmationToken <- hiddenInputValue "confirmationToken" confirmation
                    tampered <- callActionWithParams CreateRosterTemplateFromReferenceAction
                        { rosterGroupId = rosterGroup.id, weekOffset = 0 }
                        [("name", "Changed after confirmation"), ("scale", "day"), ("dayOffset", "1"), ("confirmationToken", cs confirmationToken)]
                    created <- callActionWithParams CreateRosterTemplateFromReferenceAction
                        { rosterGroupId = rosterGroup.id, weekOffset = 0 }
                        [("name", "Tuesday plan"), ("scale", "day"), ("dayOffset", "1"), ("confirmationToken", cs confirmationToken)]
                    pure (confirmation, tampered, created)
                persistedSource <- fetch sourceSlot.id

                bypassed `responseStatusShouldBe` status302
                bypassDraft `shouldBe` Nothing
                confirmation `responseStatusShouldBe` status200
                confirmation `responseBodyShouldContain` "Confirm reference"
                confirmation `responseBodyShouldContain` "Tuesday"
                confirmation `responseBodyShouldContain` "No roster data will be changed"
                tampered `responseStatusShouldBe` status302
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

        it "rejects malformed shift integers, UUIDs, assignments, and day states without mutation" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Template mutation validation"
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                manager <- createUserRecord "template-mutation-validation@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                shiftType <- ensureVenueDefaultShiftType venue
                let actor = rosterTemplateActor manager venue True
                Right draft <- startBlankRosterTemplateDesignerDraft actor rosterGroup Day "Validation day"
                let designId = draft.draftDesign.id
                let validParams =
                        [ ("dayIndex", "0")
                        , ("columnSortOrder", "0")
                        , ("rowIndex", "0")
                        , ("startTime", "09:00")
                        , ("endTime", "17:00")
                        , ("assignment", "open")
                        , ("shiftTypeId", cs (tshow shiftType.id))
                        ]
                let submitShift params = withUserAndCurrentVenue manager venue.id do
                        callActionWithParams UpsertRosterTemplateShiftAction { rosterTemplateDesignId = designId } params

                malformedRow <- submitShift (("rowIndex", "NaN") : filter ((/= "rowIndex") . fst) validParams)
                malformedShiftType <- submitShift (("shiftTypeId", "not-a-uuid") : filter ((/= "shiftTypeId") . fst) validParams)
                malformedAssignment <- submitShift (("assignment", "not-a-uuid") : filter ((/= "assignment") . fst) validParams)
                malformedDay <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams UpdateRosterTemplateDayAction { rosterTemplateDesignId = designId, dayIndex = 0 }
                        [("state", "<script>"), ("rowCount", "1")]
                persisted <- fetchPrivateRosterTemplateDraft actor

                map (\response -> responseStatus response) [malformedRow, malformedShiftType, malformedAssignment, malformedDay]
                    `shouldBe` replicate 4 status302
                fmap (.draftShifts) persisted `shouldBe` Just []
                fmap (map (.isClosed) . (.draftDays)) persisted `shouldBe` Just [False]

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

        it "preserves occupied work when a confirmed reference disappears before discard" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Template disappearing reference"
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                manager <- createUserRecord "template-disappearing-reference@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                sourceWeek <- createRosterWeekRecordForRosterGroup venue rosterGroup 0 False
                sourceDay <- createRosterDayRecord sourceWeek 0
                let actor = rosterTemplateActor manager venue True
                Right existing <- startBlankRosterTemplateDesignerDraft actor rosterGroup Day "Keep me"
                response <- withUserAndCurrentVenue manager venue.id do
                    confirmation <- callActionWithParams ConfirmRosterTemplateReferenceAction
                        { rosterGroupId = rosterGroup.id, weekOffset = 0 }
                        [("name", "Replacement reference"), ("scale", "day"), ("dayOffset", "0")]
                    confirmationToken <- hiddenInputValue "confirmationToken" confirmation
                    now <- getCurrentTime
                    _ <- sourceWeek |> set #archivedAt (Just now) |> updateRecord
                    callActionWithParams DiscardAndRestartRosterTemplateDraftAction
                        { rosterGroupId = rosterGroup.id, rosterTemplateDesignId = existing.draftDesign.id }
                        [ ("name", "Replacement reference")
                        , ("scale", "day")
                        , ("startingPoint", "reference")
                        , ("weekOffset", "0")
                        , ("dayOffset", "0")
                        , ("confirmationToken", cs confirmationToken)
                        ]
                retained <- fetchPrivateRosterTemplateDraft actor

                response `responseStatusShouldBe` status302
                fmap (.draftName) retained `shouldBe` Just "Keep me"

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

hiddenInputValue :: Text -> Response -> IO Text
hiddenInputValue name response = do
    bodyBytes <- responseBody response
    let body = cs bodyBytes :: Text
    let marker = "name=\"" <> name <> "\" value=\""
    let suffix = Text.drop (Text.length marker) (snd (Text.breakOn marker body))
    pure (Text.takeWhile (/= '"') suffix)
