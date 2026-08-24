module Test.Controller.RosterTemplatesSpec where

import qualified Application.Helper.FrontendContract.Surface.Roster as Surface
import qualified Application.Helper.FrontendContract.Surface.Roster.Action as RosterAction
import Application.Helper.FrontendContract.Surface.Values (surfaceFieldNameFrom)
import Application.RosterShiftAssignment (RosterShiftAssignment (..),
                                          applyRosterShiftAssignment)
import qualified Data.Text as Text
import Data.Time.Calendar (addDays, fromGregorian)
import Data.Time.LocalTime (TimeOfDay (..))
import Generated.Types
import IHP.ControllerPrelude
import IHP.Test.Mocking
import Network.HTTP.Types.Status
import Network.Wai (Response)
import Test.Hspec
import Test.Support
import Web.Controller.RosterTemplates ()
import Web.FrontController ()
import Web.Types

capturePreviewTransportFields = RosterAction.previewRosterTemplateCaptureActionFields "" Surface.KeepValidStaffAssignments Nothing Nothing
captureCreateTransportFields = RosterAction.createRosterTemplateCaptureActionFields "" Surface.KeepValidStaffAssignments Nothing Nothing "" 0 False

templateNameParam, captureAssignmentModeParam, staleShiftTypeIdsParam, mappedShiftTypeIdsParam, expectedSourceRevisionParam, rosterCalendarRevisionParam, warningsConfirmedParam :: ByteString
templateNameParam = cs (surfaceFieldNameFrom @Surface.TemplateName capturePreviewTransportFields)
captureAssignmentModeParam = cs (surfaceFieldNameFrom @Surface.CaptureAssignmentMode capturePreviewTransportFields)
staleShiftTypeIdsParam = cs (surfaceFieldNameFrom @Surface.StaleShiftTypeIds capturePreviewTransportFields)
mappedShiftTypeIdsParam = cs (surfaceFieldNameFrom @Surface.MappedShiftTypeIds capturePreviewTransportFields)
expectedSourceRevisionParam = cs (surfaceFieldNameFrom @Surface.ExpectedSourceRevision captureCreateTransportFields)
rosterCalendarRevisionParam = cs (surfaceFieldNameFrom @Surface.RosterCalendarRevision captureCreateTransportFields)
warningsConfirmedParam = cs (surfaceFieldNameFrom @Surface.WarningsConfirmed captureCreateTransportFields)

tests :: Spec
tests = aroundAll withDatabaseTestContext do
    describe "RosterTemplatesController date-native capture" do
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
                previewResponse `responseBodyShouldContain` "Draft/Published status is not saved"
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
