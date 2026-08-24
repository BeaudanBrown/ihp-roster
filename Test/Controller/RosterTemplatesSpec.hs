module Test.Controller.RosterTemplatesSpec where

import qualified Application.Helper.FrontendContract.Surface.Roster as Surface
import qualified Application.Helper.FrontendContract.Surface.Roster.Action as RosterAction
import Application.Helper.FrontendContract.Surface.Values (surfaceFieldNameFrom)
import Application.Helper.RosterGroups (createVenueRosterGroupWithDefaults)
import Application.RosterShiftAssignment (RosterShiftAssignment (..),
                                          applyRosterShiftAssignment)
import Application.RosterTemplates
import Data.Either (isRight)
import qualified Data.Map.Strict as Map
import qualified Data.Text as Text
import Data.Time.Calendar (addDays, fromGregorian)
import Data.Time.LocalTime (TimeOfDay (..))
import qualified Data.UUID as UUID
import Generated.Types hiding (createRosterTemplate)
import IHP.ControllerPrelude
import IHP.Test.Mocking
import Network.HTTP.Types.Status
import Network.Wai (Response, responseHeaders)
import Test.Hspec
import Test.Support
import Web.Controller.RosterTemplates ()
import Web.FrontController ()
import Web.RosterWeeks.TemplateApplication
import Web.Types

capturePreviewTransportFields = RosterAction.previewRosterTemplateCaptureActionFields "" Surface.KeepValidStaffAssignments Nothing Nothing
captureCreateTransportFields = RosterAction.createRosterTemplateCaptureActionFields "" Surface.KeepValidStaffAssignments Nothing Nothing "" 0 False
applicationPreviewTransportFields = RosterAction.previewRosterTemplateApplicationActionFields UUID.nil (fromGregorian 2026 1 1) 0 Nothing Nothing
applicationApplyTransportFields = RosterAction.applyRosterTemplateApplicationActionFields UUID.nil (fromGregorian 2026 1 1) "" 0 Nothing Nothing

templateNameParam, captureAssignmentModeParam, staleShiftTypeIdsParam, mappedShiftTypeIdsParam, expectedSourceRevisionParam, rosterCalendarRevisionParam, warningsConfirmedParam :: ByteString
templateNameParam = cs (surfaceFieldNameFrom @Surface.TemplateName capturePreviewTransportFields)
captureAssignmentModeParam = cs (surfaceFieldNameFrom @Surface.CaptureAssignmentMode capturePreviewTransportFields)
staleShiftTypeIdsParam = cs (surfaceFieldNameFrom @Surface.StaleShiftTypeIds capturePreviewTransportFields)
mappedShiftTypeIdsParam = cs (surfaceFieldNameFrom @Surface.MappedShiftTypeIds capturePreviewTransportFields)
expectedSourceRevisionParam = cs (surfaceFieldNameFrom @Surface.ExpectedSourceRevision captureCreateTransportFields)
rosterCalendarRevisionParam = cs (surfaceFieldNameFrom @Surface.RosterCalendarRevision captureCreateTransportFields)
warningsConfirmedParam = cs (surfaceFieldNameFrom @Surface.WarningsConfirmed captureCreateTransportFields)
applicationAnchorDateParam = cs (surfaceFieldNameFrom @Surface.AnchorDate applicationPreviewTransportFields)
applicationTemplateIdParam = cs (surfaceFieldNameFrom @Surface.TemplateId applicationApplyTransportFields)
expectedTargetRevisionParam = cs (surfaceFieldNameFrom @Surface.ExpectedTargetRevision applicationApplyTransportFields)
deleteRosterGroupIdParam = "rosterGroupId"

tests :: Spec
tests = aroundAll withDatabaseTestContext do
    describe "RosterTemplatesController date-native capture" do
        it "opens an empty modal with assignment mode unselected" $ withContext do
            withCleanDb do
                fixture <- controllerCaptureFixture "Controller capture launcher"
                response <- withUserAndCurrentVenue fixture.manager fixture.venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams PreviewRosterTemplateCaptureAction { rosterGroupId = fixture.rosterGroup.id }
                            [("anchorDate", cs (tshow fixture.windowStart))]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Save current week as template"
                response `responseBodyShouldContain` "value=\"\""
                response `responseBodyShouldNotContain` "checked=\"checked\""
                response `responseBodyShouldNotContain` "alert alert-warning"

        it "renders one alphabetical Week-template library and disables Apply for any Published target day" $ withContext do
            withCleanDb do
                fixture <- controllerCaptureFixture "Controller template library"
                let actor = rosterTemplateActor fixture.manager fixture.venue True
                    content = RosterTemplateContent
                        { contentDays = [RosterTemplateDayInput dayIndex (Just dayIndex) False 1 | dayIndex <- [0 .. 6]]
                        , contentColumns = [RosterTemplateColumnInput "Only" 0]
                        , contentShifts = [RosterTemplateShiftInput 0 0 0 540 1020 fixture.shiftType.id OpenAssignment]
                        }
                Right _ <- createRosterTemplate actor fixture.rosterGroup Week "Zulu" content
                Right _ <- createRosterTemplate actor fixture.rosterGroup Week "alpha" content
                _ <- fixture.days !! 3 |> set #publicationState Published |> updateRecord
                response <- withUserAndCurrentVenue fixture.manager fixture.venue.id do
                    callActionWithParams ShowRosterTemplateLibraryFragmentAction { rosterGroupId = fixture.rosterGroup.id }
                        [("anchorDate", cs (tshow fixture.windowStart))]
                body <- responseBody response
                let html = cs body :: String
                    htmlText = cs body :: Text

                response `responseStatusShouldBe` status200
                html `shouldContain` "Save current week as template"
                html `shouldNotContain` "No templates are saved."
                html `shouldContain` "1 shift(s)"
                html `shouldContain` "at least one day in the viewed window is Published"
                html `shouldContain` "disabled"
                html `shouldNotContain` "Week snapshot"
                html `shouldNotContain` "assignment mode"
                Text.breakOn "alpha" htmlText `shouldSatisfy` (\(_, suffix) -> "Zulu" `Text.isInfixOf` suffix)

        it "deletes through the modal workflow and refreshes the library in place" $ withContext do
            withCleanDb do
                fixture <- controllerCaptureFixture "Controller template delete"
                let actor = rosterTemplateActor fixture.manager fixture.venue True
                    content = RosterTemplateContent
                        { contentDays = [RosterTemplateDayInput dayIndex (Just dayIndex) False 1 | dayIndex <- [0 .. 6]]
                        , contentColumns = [RosterTemplateColumnInput "Only" 0]
                        , contentShifts = []
                        }
                Right snapshot <- createRosterTemplate actor fixture.rosterGroup Week "Delete me" content
                response <- withUserAndCurrentVenue fixture.manager fixture.venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams DeleteRosterTemplateAction { rosterTemplateId = snapshot.snapshotTemplate.id }
                            [ (applicationTemplateIdParam, cs (tshow snapshot.snapshotTemplate.id))
                            , (applicationAnchorDateParam, cs (tshow fixture.windowStart))
                            , (deleteRosterGroupIdParam, cs (tshow fixture.rosterGroup.id))
                            ]
                deleted <- fetch snapshot.snapshotTemplate.id
                let triggerHeader = cs <$> lookup "HX-Trigger" (responseHeaders response)

                response `responseStatusShouldBe` status200
                deleted.deletedAt `shouldSatisfy` isJust
                response `responseBodyShouldContain` "Template deleted."
                response `responseBodyShouldContain` "id=\"dialog-overlay-mount\""
                triggerHeader `shouldSatisfy` maybe False (Text.isInfixOf "roster-template-library")

        it "rejects deletion when submitted roster-group context does not own the template" $ withContext do
            withCleanDb do
                fixture <- controllerCaptureFixture "Controller cross-group delete"
                otherGroup <- createVenueRosterGroupWithDefaults fixture.venue "Other group" 2 True
                let actor = rosterTemplateActor fixture.manager fixture.venue True
                    content = RosterTemplateContent
                        { contentDays = [RosterTemplateDayInput dayIndex (Just dayIndex) False 1 | dayIndex <- [0 .. 6]]
                        , contentColumns = [RosterTemplateColumnInput "Only" 0]
                        , contentShifts = []
                        }
                Right snapshot <- createRosterTemplate actor otherGroup Week "Other group template" content
                response <- withUserAndCurrentVenue fixture.manager fixture.venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams DeleteRosterTemplateAction { rosterTemplateId = snapshot.snapshotTemplate.id }
                            [ ("anchorDate", cs (tshow fixture.windowStart))
                            , ("rosterGroupId", cs (tshow fixture.rosterGroup.id))
                            ]
                retained <- fetch snapshot.snapshotTemplate.id

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "outside the current roster group"
                retained.deletedAt `shouldBe` Nothing

        it "previews and confirms capture from a mixed-publication source" $ withContext do
            withCleanDb do
                fixture <- controllerCaptureFixture "Controller capture"
                firstDay <- fixture.days !! 0 |> set #publicationState Published |> updateRecord
                previewResponse <- withUserAndCurrentVenue fixture.manager fixture.venue.id do
                    callActionWithParams PreviewRosterTemplateCaptureAction { rosterGroupId = fixture.rosterGroup.id }
                        [ ("anchorDate", cs (tshow fixture.windowStart))
                        , (templateNameParam, "Mixed source")
                        , (captureAssignmentModeParam, "open")
                        ]
                expectedSourceRevision <- hiddenInputValue (surfaceFieldNameFrom @Surface.ExpectedSourceRevision captureCreateTransportFields) previewResponse
                expectedCalendarRevision <- hiddenInputValue (surfaceFieldNameFrom @Surface.RosterCalendarRevision captureCreateTransportFields) previewResponse
                createResponse <- withUserAndCurrentVenue fixture.manager fixture.venue.id do
                    callActionWithParams CreateRosterTemplateCaptureAction { rosterGroupId = fixture.rosterGroup.id }
                        [ ("anchorDate", cs (tshow fixture.windowStart))
                        , (templateNameParam, "Mixed source")
                        , (captureAssignmentModeParam, "open")
                        , (expectedSourceRevisionParam, expectedSourceRevision)
                        , (rosterCalendarRevisionParam, expectedCalendarRevision)
                        , (warningsConfirmedParam, "true")
                        ]
                templates <- query @RosterTemplate |> fetch
                retainedFirstDay <- fetch firstDay.id
                durableEventCount :: Int <- sqlQueryScalar "SELECT COUNT(*)::INT FROM live_invalidation_events WHERE source = 'roster.template.capture'" ()

                previewResponse `responseStatusShouldBe` status200
                previewResponse `responseBodyShouldNotContain` "Draft/Published status"
                createResponse `responseStatusShouldBe` status302
                map (.name) templates `shouldBe` ["Mixed source"]
                retainedFirstDay.publicationState `shouldBe` Published
                durableEventCount `shouldBe` 1

        it "rerenders authoritative requirements when source content changes after preview" $ withContext do
            withCleanDb do
                fixture <- controllerCaptureFixture "Controller stale capture"
                previewResponse <- withUserAndCurrentVenue fixture.manager fixture.venue.id do
                    callActionWithParams PreviewRosterTemplateCaptureAction { rosterGroupId = fixture.rosterGroup.id }
                        [ ("anchorDate", cs (tshow fixture.windowStart))
                        , (templateNameParam, "Stale source")
                        , (captureAssignmentModeParam, "open")
                        ]
                expectedSourceRevision <- hiddenInputValue (surfaceFieldNameFrom @Surface.ExpectedSourceRevision captureCreateTransportFields) previewResponse
                expectedCalendarRevision <- hiddenInputValue (surfaceFieldNameFrom @Surface.RosterCalendarRevision captureCreateTransportFields) previewResponse
                _ <- fixture.days !! 2 |> set #isClosed True |> updateRecord

                staleResponse <- withUserAndCurrentVenue fixture.manager fixture.venue.id do
                    callActionWithParams CreateRosterTemplateCaptureAction { rosterGroupId = fixture.rosterGroup.id }
                        [ ("anchorDate", cs (tshow fixture.windowStart))
                        , (templateNameParam, "Stale source")
                        , (captureAssignmentModeParam, "open")
                        , (expectedSourceRevisionParam, expectedSourceRevision)
                        , (rosterCalendarRevisionParam, expectedCalendarRevision)
                        , (warningsConfirmedParam, "true")
                        ]
                templateCount <- query @RosterTemplate |> fetchCount

                staleResponse `responseStatusShouldBe` status200
                staleResponse `responseBodyShouldContain` "roster or validation requirements changed"
                staleResponse `responseBodyShouldContain` "Stale source"
                templateCount `shouldBe` 0

        it "round-trips explicit stale Shift type mappings through typed capture actions" $ withContext do
            withCleanDb do
                fixture <- controllerCaptureFixture "Controller mapping capture"
                sourceSlot <- createControllerCaptureSlot (fixture.days !! 4) fixture.shiftType
                let archivedAt = UTCTime (fromGregorian 2026 8 24) 0
                staleShiftType <- fixture.shiftType |> set #isActive False |> set #archivedAt (Just archivedAt) |> updateRecord
                replacement <- newRecord @ShiftType
                    |> set #venueId (unpackId fixture.venue.id)
                    |> set #name "Mapped replacement"
                    |> set #isActive True
                    |> set #sortOrder 20
                    |> set #payAssignmentMode RosterOnly
                    |> createRecord

                mappedPreview <- withUserAndCurrentVenue fixture.manager fixture.venue.id do
                    callActionWithParams PreviewRosterTemplateCaptureAction { rosterGroupId = fixture.rosterGroup.id }
                        [ ("anchorDate", cs (tshow fixture.windowStart))
                        , (templateNameParam, "Mapped controller source")
                        , (captureAssignmentModeParam, "keep_staff")
                        , (staleShiftTypeIdsParam, cs (tshow staleShiftType.id))
                        , (mappedShiftTypeIdsParam, cs (tshow replacement.id))
                        ]
                expectedSourceRevision <- hiddenInputValue (surfaceFieldNameFrom @Surface.ExpectedSourceRevision captureCreateTransportFields) mappedPreview
                expectedCalendarRevision <- hiddenInputValue (surfaceFieldNameFrom @Surface.RosterCalendarRevision captureCreateTransportFields) mappedPreview
                created <- withUserAndCurrentVenue fixture.manager fixture.venue.id do
                    callActionWithParams CreateRosterTemplateCaptureAction { rosterGroupId = fixture.rosterGroup.id }
                        [ ("anchorDate", cs (tshow fixture.windowStart))
                        , (templateNameParam, "Mapped controller source")
                        , (captureAssignmentModeParam, "keep_staff")
                        , (staleShiftTypeIdsParam, cs (tshow staleShiftType.id))
                        , (mappedShiftTypeIdsParam, cs (tshow replacement.id))
                        , (expectedSourceRevisionParam, expectedSourceRevision)
                        , (rosterCalendarRevisionParam, expectedCalendarRevision)
                        , (warningsConfirmedParam, "true")
                        ]
                savedShift <- query @RosterTemplateShift |> fetchOne
                retainedSource <- fetch sourceSlot.id

                mappedPreview `responseStatusShouldBe` status200
                created `responseStatusShouldBe` status302
                savedShift.shiftTypeId `shouldBe` unpackId replacement.id
                retainedSource.shiftTypeId `shouldBe` Just (unpackId staleShiftType.id)

        it "rejects missing assignment mode and cross-venue roster groups without persistence" $ withContext do
            withCleanDb do
                fixture <- controllerCaptureFixture "Controller validation"
                foreignVenue <- createVenueWithConfig "Controller foreign venue"
                foreignGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId foreignVenue.id) |> fetchOne

                (missingMode, blankName, oversizedName, malformedAnchor, malformedMapping, malformedRevision) <- withUserAndCurrentVenue fixture.manager fixture.venue.id do
                    missingMode <- callActionWithParams PreviewRosterTemplateCaptureAction { rosterGroupId = fixture.rosterGroup.id }
                        [ ("anchorDate", cs (tshow fixture.windowStart))
                        , (templateNameParam, "Missing mode")
                        ]
                    blankName <- callActionWithParams PreviewRosterTemplateCaptureAction { rosterGroupId = fixture.rosterGroup.id }
                        [("anchorDate", cs (tshow fixture.windowStart)), (templateNameParam, "   "), (captureAssignmentModeParam, "open")]
                    oversizedName <- callActionWithParams PreviewRosterTemplateCaptureAction { rosterGroupId = fixture.rosterGroup.id }
                        [("anchorDate", cs (tshow fixture.windowStart)), (templateNameParam, cs (Text.replicate 121 "x")), (captureAssignmentModeParam, "open")]
                    malformedAnchor <- callActionWithParams PreviewRosterTemplateCaptureAction { rosterGroupId = fixture.rosterGroup.id }
                        [("anchorDate", "not-a-date"), (templateNameParam, "Malformed date"), (captureAssignmentModeParam, "open")]
                    malformedMapping <- callActionWithParams PreviewRosterTemplateCaptureAction { rosterGroupId = fixture.rosterGroup.id }
                        [ ("anchorDate", cs (tshow fixture.windowStart))
                        , (templateNameParam, "Malformed mapping")
                        , (captureAssignmentModeParam, "open")
                        , (staleShiftTypeIdsParam, "not-a-uuid")
                        , (mappedShiftTypeIdsParam, "also-not-a-uuid")
                        ]
                    validPreview <- callActionWithParams PreviewRosterTemplateCaptureAction { rosterGroupId = fixture.rosterGroup.id }
                        [("anchorDate", cs (tshow fixture.windowStart)), (templateNameParam, "Malformed revision"), (captureAssignmentModeParam, "open")]
                    expectedSourceRevision <- hiddenInputValue (surfaceFieldNameFrom @Surface.ExpectedSourceRevision captureCreateTransportFields) validPreview
                    malformedRevision <- callActionWithParams CreateRosterTemplateCaptureAction { rosterGroupId = fixture.rosterGroup.id }
                        [ ("anchorDate", cs (tshow fixture.windowStart))
                        , (templateNameParam, "Malformed revision")
                        , (captureAssignmentModeParam, "open")
                        , (expectedSourceRevisionParam, expectedSourceRevision)
                        , (rosterCalendarRevisionParam, "not-an-int")
                        , (warningsConfirmedParam, "true")
                        ]
                    pure (missingMode, blankName, oversizedName, malformedAnchor, malformedMapping, malformedRevision)
                crossVenue <- withUserAndCurrentVenue fixture.manager fixture.venue.id do
                    callActionWithParams PreviewRosterTemplateCaptureAction { rosterGroupId = foreignGroup.id }
                        [ ("anchorDate", cs (tshow fixture.windowStart))
                        , (templateNameParam, "Foreign")
                        , (captureAssignmentModeParam, "open")
                        ]
                templateCount <- query @RosterTemplate |> fetchCount

                missingMode `responseStatusShouldBe` status200
                missingMode `responseBodyShouldContain` "captureAssignmentMode"
                blankName `responseStatusShouldBe` status200
                blankName `responseBodyShouldContain` "Template names must contain"
                oversizedName `responseStatusShouldBe` status200
                oversizedName `responseBodyShouldContain` "Template names must contain"
                malformedAnchor `responseStatusShouldBe` status400
                malformedMapping `responseStatusShouldBe` status200
                malformedMapping `responseBodyShouldContain` "staleShiftTypeIds"
                malformedRevision `responseStatusShouldBe` status200
                malformedRevision `responseBodyShouldContain` "rosterCalendarRevision"
                crossVenue `responseStatusShouldBe` status403
                templateCount `shouldBe` 0

    describe "RosterTemplatesController date-native application" do
        it "previews and applies a Week template through typed button transport" $ withContext do
            withCleanDb do
                fixture <- controllerCaptureFixture "Controller application"
                let actor = rosterTemplateActor fixture.manager fixture.venue True
                    content = RosterTemplateContent
                        { contentDays = [RosterTemplateDayInput dayIndex (Just dayIndex) False 1 | dayIndex <- [0 .. 6]]
                        , contentColumns = [RosterTemplateColumnInput "Only" 0]
                        , contentShifts = [RosterTemplateShiftInput 0 0 0 540 1020 fixture.shiftType.id OpenAssignment]
                        }
                Right snapshot <- createRosterTemplate actor fixture.rosterGroup Week "Controller week" content
                venueConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId fixture.venue.id) |> fetchOne
                let directRequest = RosterTemplateApplicationRequest
                        { applicationTemplateId = snapshot.snapshotTemplate.id
                        , applicationTargetRosterGroupId = fixture.rosterGroup.id
                        , applicationTargetWindowStart = fixture.windowStart
                        , applicationTargetWindowEnd = addDays 7 fixture.windowStart
                        , applicationShiftTypeMappings = Map.empty
                        }
                directPreview <- previewRosterTemplateApplication actor directRequest
                directPreview `shouldSatisfy` isRight
                preview <- withUserAndCurrentVenue fixture.manager fixture.venue.id do
                    callActionWithParams PreviewRosterTemplateApplicationAction { rosterGroupId = fixture.rosterGroup.id }
                        [ (applicationTemplateIdParam, cs (tshow snapshot.snapshotTemplate.id))
                        , (applicationAnchorDateParam, cs (tshow fixture.windowStart))
                        , (rosterCalendarRevisionParam, cs (tshow venueConfig.rosterCalendarRevision))
                        ]
                renderedAnchorDate <- hiddenInputValue (surfaceFieldNameFrom @Surface.AnchorDate applicationApplyTransportFields) preview
                expectedTargetRevision <- hiddenInputValue (surfaceFieldNameFrom @Surface.ExpectedTargetRevision applicationApplyTransportFields) preview
                expectedCalendarRevision <- hiddenInputValue (surfaceFieldNameFrom @Surface.RosterCalendarRevision applicationApplyTransportFields) preview
                applied <- withUserAndCurrentVenue fixture.manager fixture.venue.id do
                    callActionWithParams ApplyRosterTemplateAction { rosterTemplateId = snapshot.snapshotTemplate.id, rosterGroupId = fixture.rosterGroup.id }
                        [ (applicationTemplateIdParam, cs (tshow snapshot.snapshotTemplate.id))
                        , (applicationAnchorDateParam, cs (tshow fixture.windowStart))
                        , (expectedTargetRevisionParam, expectedTargetRevision)
                        , (rosterCalendarRevisionParam, expectedCalendarRevision)
                        ]
                activeSlotCount <- query @RosterSlot |> filterWhere (#deletedAt, Nothing) |> fetchCount
                durableEventCount :: Int <- sqlQueryScalar "SELECT COUNT(*)::INT FROM live_invalidation_events WHERE source = 'roster.template.apply'" ()

                preview `responseStatusShouldBe` status200
                preview `responseBodyShouldContain` "Apply Controller week"
                renderedAnchorDate `shouldBe` cs (tshow fixture.windowStart)
                applied `responseStatusShouldBe` status302
                activeSlotCount `shouldBe` 1
                durableEventCount `shouldBe` 1

        it "rerenders malformed typed application transport inside the HTMX dialog" $ withContext do
            withCleanDb do
                fixture <- controllerCaptureFixture "Controller application transport"
                venueConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId fixture.venue.id) |> fetchOne

                response <- withUserAndCurrentVenue fixture.manager fixture.venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams PreviewRosterTemplateApplicationAction { rosterGroupId = fixture.rosterGroup.id }
                            [ (applicationAnchorDateParam, cs (tshow fixture.windowStart))
                            , (rosterCalendarRevisionParam, cs (tshow venueConfig.rosterCalendarRevision))
                            ]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Review template application"
                response `responseBodyShouldContain` "templateId"

data ControllerCaptureFixture = ControllerCaptureFixture
    { venue       :: !Venue
    , rosterGroup :: !RosterGroup
    , manager     :: !User
    , shiftType   :: !ShiftType
    , windowStart :: !Day
    , days        :: ![RosterDay]
    }

controllerCaptureFixture :: (?modelContext :: ModelContext) => Text -> IO ControllerCaptureFixture
hiddenInputValue :: Text -> Response -> IO ByteString
hiddenInputValue name response = do
    bodyBytes <- responseBody response
    let body = cs bodyBytes :: Text
        marker = "name=\"" <> name <> "\" value=\""
        suffix = Text.drop (Text.length marker) (snd (Text.breakOn marker body))
    pure (cs (Text.takeWhile (/= '\"') suffix))

controllerCaptureFixture label = do
    venue <- createVenueWithConfig label
    rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
    manager <- createUserRecord ("controller-capture-" <> tshow venue.id <> "@example.com") "staff" True
    _ <- createVenueMembershipRecord venue manager Manager
    shiftType <- ensureVenueDefaultShiftType venue
    let windowStart = testAnchorForOffset 24
    days <- forM ([0 .. 6] :: [Int]) (\dayIndex -> createNativeRosterDayRecord venue rosterGroup (addDays (toInteger dayIndex) windowStart) dayIndex)
    pure ControllerCaptureFixture { .. }

createControllerCaptureSlot :: (?modelContext :: ModelContext) => RosterDay -> ShiftType -> IO RosterSlot
createControllerCaptureSlot rosterDay shiftType = do
    lane <- newRecord @RosterLane
        |> set #rosterDayId (unpackId rosterDay.id)
        |> set #name "Early"
        |> set #sortOrder 0
        |> createRecord
    newRecord @RosterSlot
        |> set #rosterDayId (unpackId rosterDay.id)
        |> set #rosterLaneId (unpackId lane.id)
        |> set #slotSortOrder 0
        |> set #rowIndex 0
        |> set #shiftTypeId (Just (unpackId shiftType.id))
        |> applyRosterShiftAssignment OpenAssignment
        |> setTestRosterSlotBoundaries rosterDay.operationalDate (TimeOfDay 9 0 0) (TimeOfDay 17 0 0)
        |> createRecord
