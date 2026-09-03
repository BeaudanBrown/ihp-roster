module Test.Controller.RosterWeeks.NavigationSpec where

import Application.Helper.RosterGroups (createVenueRosterGroupWithDefaults,
                                        syncStaffRosterGroupAssignments)
import Application.RosterTemplates (RosterTemplateDraft (..),
                                    rosterTemplateActor,
                                    saveRosterTemplateDraft)
import Config
import qualified Data.ByteString.Char8 as ByteString
import qualified Data.ByteString.Lazy.Char8 as LByteString
import Data.Maybe (fromJust)
import qualified Data.Text as Text
import Data.Time.Calendar (addDays)
import Data.Time.LocalTime (TimeOfDay (..))
import Generated.Types
import IHP.ControllerPrelude
import IHP.FrameworkConfig
import IHP.HaskellSupport
import IHP.Prelude
import IHP.Test.Mocking
import Network.HTTP.Types.Status
import Network.Wai
import Test.Hspec
import Test.Support
import Web.Controller.RosterWeeks ()
import Web.FrontController ()
import Web.RosterWeeks.Dom (rosterContentFragmentId, rosterDaySectionDomId,
                            rosterRowDomIdText, rosterStaffPanelFragmentId)
import Web.RosterWeeks.TemplateDesigner (startBlankRosterTemplateDesignerDraft)
import Web.Routes
import Web.Types

tests :: Spec
tests = aroundAll withDatabaseTestContext do
    describe "RosterWeeksController" do
        it "redirects unauthenticated users through shared controller middleware" $ withContext do
            actionResponsesShouldHaveStatus status302
                [ ("index", callAction RosterWeeksAction)
                , ("show week", callAction (ShowRosterWindowAction (tshow (testAnchorForOffset 0))))
                , ("content fragment", callAction (ShowRosterWeekContentFragmentAction (tshow (testAnchorForOffset 0))))
                , ("staff panel fragment", callAction (ShowRosterWeekStaffPanelFragmentAction (tshow (testAnchorForOffset 0))))
                , ("row fragment", callAction (ShowRosterWeekRowFragmentAction (tshow (testAnchorForOffset 0)) "11111111-1111-1111-1111-111111111111" 0))
                , ("create week", callActionWithParams CreateRosterWeekAction (rosterMutationParams 0))
                , ("copy week", callActionWithParams CopyRosterWeekAction (rosterCopyParams 0 1))
                , ("notification confirmation", callAction (ShowRosterNotificationConfirmationAction))
                , ("create notification run", callAction (CreateRosterNotificationRunAction))
                , ("toggle day", callActionWithParams (ToggleRosterDayClosedAction "11111111-1111-1111-1111-111111111111") (rosterMutationParams 0))
                , ("add row", callAction (AddRosterRowAction "11111111-1111-1111-1111-111111111111"))
                , ("remove row", callActionWithParams (RemoveRosterRowAction "11111111-1111-1111-1111-111111111111") (rosterMutationParams 0))
                , ("update slot", callActionWithParams (UpdateRosterSlotAction "22222222-2222-2222-2222-222222222222") (rosterMutationParams 0))
                , ("create slot", callActionWithParams (CreateRosterSlotAction "11111111-1111-1111-1111-111111111111" "22222222-2222-2222-2222-222222222222" 0) (rosterMutationParams 0))
                ]

        it "redirects venue-less super-admins from roster weeks to support" $ withContext do
            withCleanDb do
                user <- createUserRecordWithPlatformRole "roster-bootstrap-super-admin@example.com" "staff" (Just SuperAdmin) True

                response <- withUser user do
                    callAction RosterWeeksAction

                response `responseStatusShouldBe` status302
                responseHeaders response `shouldContain` [("Location", "http://localhost/Support")]

        it "redirects venue members without a completed staff profile to edit profile" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                user <- createUserRecord "roster-needs-profile@example.com" "staff" False
                _ <- createVenueMembershipRecord venue user Worker

                response <- withUserAndCurrentVenue user venue.id do
                    callAction RosterWeeksAction

                response `responseStatusShouldBe` status302
                responseHeaders response `shouldContain` [("Location", "http://localhost/EditProfile")]

        it "resolves an anchor-date bookmark to the configured window containing that date" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                user <- createUserRecord "roster-anchor-bookmark@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user Worker
                response <- withUserAndCurrentVenue user venue.id do
                    callAction (ShowRosterWindowAction (tshow (addDays 3 defaultWeekEpoch)))
                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Mon 06/01"
                response `responseBodyShouldContain` "Sun 12/01"

        it "rejects a malformed roster group bookmark without raising a server error" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                user <- createUserRecord "roster-malformed-group@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user Worker

                response <- withUserAndCurrentVenue user venue.id do
                    callActionWithParams (ShowRosterWindowAction (tshow (testAnchorForOffset 0)))
                        [ ("anchorDate", cs (show (testAnchorForOffset 0)))
                        , ("rosterGroupId", "e3179940-4716-405e-b433-70aaa33a4f7")
                        ]

                response `responseStatusShouldBe` status400
                response `responseBodyShouldContain` "Invalid roster group parameter."

        it "visiting a sparse window does not materialize dated days" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                user <- createUserRecord "roster-auto-create@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user Worker

                response <- withUserAndCurrentVenue user venue.id do
                    callAction (ShowRosterWindowAction (tshow (testAnchorForOffset 0)))

                response `responseStatusShouldBe` status200
                datedDays <- query @RosterDay
                    |> filterWhere (#venueId, unpackId venue.id)
                    |> fetch
                datedDays `shouldBe` []

        it "staff cannot see draft weeks but still gets the hidden roster shell" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                user <- createUserRecord "roster-staff-draft@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user Worker
                slotName <- fetchSlotNameRecord venue "Early"
                staffMember <- createStaffRecord venue (Just user) "Alpha" "Crew"
                rosterWeek <- createRosterWeekRecord venue 0 False
                rosterDay <- createRosterDayRecord rosterWeek 0
                _ <- updateRecord (rosterDay |> set #isClosed True)
                _ <- createRosterSlotRecord rosterDay slotName (Just staffMember) 0

                response <- withUser user do
                    callAction (ShowRosterWindowAction (tshow (testAnchorForOffset 0)))

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "roster-hidden-draft-grid"
                response `responseBodyShouldContain` "This roster is still Draft."
                response `responseBodyShouldNotContain` "Crew, Alpha"
                response `responseBodyShouldNotContain` "roster-day-closed-label"
                response `responseBodyShouldNotContain` "slot-closed-cell"
                response `responseBodyShouldNotContain` "roster-grid-header-row-subheads"

        it "empty roster pages still expose FrontendSurface live metadata" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                user <- createUserRecord "roster-empty-live-scope@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user Worker
                _ <- createStaffRecord venue (Just user) "Empty" "Scope"
                _ <- fetchSlotNameRecord venue "Early"

                response <- withUserAndCurrentVenue user venue.id do
                    callAction (ShowRosterWindowAction (tshow (testAnchorForOffset 0)))

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "data-bepis-surface=\"roster\""
                response `responseBodyShouldContain` "data-bepis-surface-config=\""
                response `responseBodyShouldContain` "roster:"
                response `responseBodyShouldContain` "rosterGroupId"
                response `responseBodyShouldContain` "windowStartDate"
                response `responseBodyShouldNotContain` "/helpers.js"

        it "staff on hidden draft pages still expose FrontendSurface live metadata" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                user <- createUserRecord "roster-hidden-draft-live-scope@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user Worker
                _ <- createStaffRecord venue (Just user) "Hidden" "Scope"
                _ <- createRosterWeekRecord venue 0 False

                response <- withUserAndCurrentVenue user venue.id do
                    callAction (ShowRosterWindowAction (tshow (testAnchorForOffset 0)))

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "data-bepis-surface=\"roster\""
                response `responseBodyShouldContain` "data-bepis-surface-config=\""
                response `responseBodyShouldContain` "roster:"
                response `responseBodyShouldContain` "rosterGroupId"
                response `responseBodyShouldContain` "windowStartDate"

        it "staff roster quick timesheet card subscribes to the operational timesheet day" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                user <- createUserRecord "roster-staff-timesheet-live-scope@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user Worker
                _ <- createStaffRecord venue (Just user) "Tess" "Roster"
                _ <- fetchSlotNameRecord venue "Early"
                payLevel <- createPayLevelRecord venue "Level 1"
                _ <- createShiftTypeRecord venue payLevel "Ordinary"

                response <- withUserAndCurrentVenue user venue.id do
                    callAction (ShowRosterWindowAction (tshow (testAnchorForOffset 0)))

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "id=\"roster-staff-self-service-timesheet-live-surface\""
                response `responseBodyShouldContain` "data-bepis-surface=\"timesheets\""
                response `responseBodyShouldContain` "data-bepis-surface-config=\""
                response `responseBodyShouldContain` "timesheets:"
                response `responseBodyShouldContain` "timesheet-day-section"
                response `responseBodyShouldContain` "data-bepis-surface=\"self-service-leave\""
                response `responseBodyShouldContain` "data-bepis-surface-action=\"create-self-service-leave-request\""
                response `responseBodyShouldNotContain` "data-live-update-surface"

                body <- responseBody response
                let bodyText = cs (LByteString.unpack body)
                Text.count "data-bepis-surface-config" bodyText `shouldBe` 3

        it "shows an empty non-mutating state when staff have no roster groups" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                user <- createUserRecord "roster-no-groups@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user Worker
                staff <- createStaffRecord venue (Just user) "No" "Groups"
                syncStaffRosterGroupAssignments staff []

                response <- withUserAndCurrentVenue user venue.id do
                    callAction (ShowRosterWindowAction (tshow (testAnchorForOffset 0)))

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "You aren't assigned to a roster group yet."
                response `responseBodyShouldNotContain` "data-bepis-surface=\"roster\""
                activeAssignments <- query @StaffRosterGroup
                    |> filterWhere (#staffId, unpackId staff.id)
                    |> filterWhere (#deletedAt, Nothing)
                    |> fetchCount
                activeAssignments `shouldBe` 0
                query @RosterDay
                    |> filterWhere (#venueId, unpackId venue.id)
                    |> fetchCount
                    >>= (`shouldBe` 0)

        it "limits staff roster reads to their assigned group" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                user <- createUserRecord "roster-group-b-only@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user Worker
                groupA <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                groupB <- createVenueRosterGroupWithDefaults venue "Group B" 2 True
                groupAStaff <- createStaffRecord venue Nothing "GroupAOnly" "Crew"
                viewerStaff <- createStaffRecord venue (Just user) "Viewer" "Crew"
                syncStaffRosterGroupAssignments viewerStaff [groupB.id]
                groupASlotName <- fetchSlotNameRecordForRosterGroup groupA "Early"
                groupBSlotName <- fetchSlotNameRecordForRosterGroup groupB "Early"
                groupAWeek <- createRosterWeekRecordForRosterGroup venue groupA 0 True
                groupBWeek <- createRosterWeekRecordForRosterGroup venue groupB 0 True
                groupADay <- createRosterDayRecord groupAWeek 0
                groupBDay <- createRosterDayRecord groupBWeek 0
                _ <- createRosterSlotRecord groupADay groupASlotName (Just groupAStaff) 0
                _ <- createRosterSlotRecord groupBDay groupBSlotName (Just viewerStaff) 0

                assignedResponse <- withUserAndCurrentVenue user venue.id do
                    callActionWithParams (ShowRosterWindowAction (tshow (testAnchorForOffset 0)))
                        [ ("anchorDate", cs (show (testAnchorForOffset 0)))
                        , ("rosterGroupId", idToParam groupB.id)
                        ]
                redirectedResponse <- withUserAndCurrentVenue user venue.id do
                    callActionWithParams (ShowRosterWindowAction (tshow (testAnchorForOffset 0)))
                        [ ("anchorDate", cs (show (testAnchorForOffset 0)))
                        , ("rosterGroupId", idToParam groupA.id)
                        ]

                assignedResponse `responseStatusShouldBe` status200
                assignedResponse `responseBodyShouldContain` ">Viewer</div>"
                assignedResponse `responseBodyShouldNotContain` "GroupAOnly"
                assignedResponse `responseBodyShouldNotContain` "id=\"roster-group-switch\""
                redirectedResponse `responseStatusShouldBe` status302
                lookup "Location" (responseHeaders redirectedResponse)
                    `shouldSatisfy` maybe False (ByteString.isInfixOf (cs (tshow groupB.id)))

        it "lets staff switch between each assigned roster group" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                user <- createUserRecord "roster-multiple-groups@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user Worker
                groupA <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                groupB <- createVenueRosterGroupWithDefaults venue "Group B" 2 True
                viewerStaff <- createStaffRecord venue (Just user) "Multi" "Group"
                syncStaffRosterGroupAssignments viewerStaff [groupA.id, groupB.id]

                groupAResponse <- withUserAndCurrentVenue user venue.id do
                    callActionWithParams (ShowRosterWindowAction (tshow (testAnchorForOffset 0)))
                        [ ("anchorDate", cs (show (testAnchorForOffset 0)))
                        , ("rosterGroupId", idToParam groupA.id)
                        ]
                groupBResponse <- withUserAndCurrentVenue user venue.id do
                    callActionWithParams (ShowRosterWindowAction (tshow (testAnchorForOffset 0)))
                        [ ("anchorDate", cs (show (testAnchorForOffset 0)))
                        , ("rosterGroupId", idToParam groupB.id)
                        ]

                forM_ [groupAResponse, groupBResponse] \response -> do
                    response `responseStatusShouldBe` status200
                    response `responseBodyShouldContain` "id=\"roster-group-switch\""
                    response `responseBodyShouldContain` ("value=\"" <> cs (tshow groupA.id) <> "\"")
                    response `responseBodyShouldContain` ("value=\"" <> cs (tshow groupB.id) <> "\"")
                    response `responseBodyShouldContain` "type=\"hidden\" name=\"anchorDate\" value=\"2025-01-06\""
                groupAResponse `responseBodyShouldContain` ("value=\"" <> cs (tshow groupA.id) <> "\" selected=\"selected\"")
                groupBResponse `responseBodyShouldContain` ("value=\"" <> cs (tshow groupB.id) <> "\" selected=\"selected\"")

        it "manager can see draft weeks" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-draft@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                slotName <- fetchSlotNameRecord venue "Early"
                staffMember <- createStaffRecord venue Nothing "Alpha" "Crew"
                rosterWeek <- createRosterWeekRecord venue 0 False
                rosterDay <- createRosterDayRecord rosterWeek 0
                _ <- createRosterSlotRecord rosterDay slotName (Just staffMember) 0

                response <- withUser manager do
                    callAction (ShowRosterWindowAction (tshow (testAnchorForOffset 0)))

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` ">Alpha</div>"
                response `responseBodyShouldContain` "hx-get=\"/EditRosterSlotDialog?rosterSlotId="
                response `responseBodyShouldContain` "hx-post=\"/ToggleRosterWeekLiveStatus?anchorDate=2025-01-06&amp;rosterGroupId="
                response `responseBodyShouldContain` "name=\"rosterCalendarRevision\" value=\"1\""
                response `responseBodyShouldContain` ">Published</span></label>"

        it "does not render conflict highlights on Published roster windows" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-live-no-conflicts@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                slotName <- fetchSlotNameRecord venue "Early"
                staffMember <- createStaffRecord venue Nothing "Alpha" "Crew"
                rosterWeek <- createRosterWeekRecord venue 0 True
                rosterDay <- createRosterDayRecord rosterWeek 0
                _ <-
                    createRosterSlotRecord rosterDay slotName (Just staffMember) 0
                        >>= updateRecord . setTestStartTime (Just (TimeOfDay 8 0 0))
                _ <- createLeaveRequestRecord venue staffMember defaultWeekEpoch (addDays 1 defaultWeekEpoch) LeaveRequestStatusEnumApproved

                response <- withUserAndCurrentVenue manager venue.id do
                    callAction (ShowRosterWindowAction (tshow (testAnchorForOffset 0)))

                response `responseStatusShouldBe` status200
                response `responseBodyShouldNotContain` "conflict-critical"
                response `responseBodyShouldNotContain` "Staff member has an approved unavailable period."

        it "manager roster pages render reusable week controls and visible staff panel settings" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-empty-create@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                panelStaff <- createStaffRecord venue Nothing "Alpha" "Crew"
                _ <- fetchSlotNameRecord venue "Early"
                _ <- createVenueRosterGroupWithDefaults venue "Back of House" 1 True

                response <- withUserAndCurrentVenue manager venue.id do
                    callAction (ShowRosterWindowAction (tshow (testAnchorForOffset 0)))

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "data-week-toolbar=\"roster\""
                response `responseBodyShouldContain` "data-week-toolbar-section=\"quick\""
                response `responseBodyShouldContain` "data-week-toolbar-section=\"navigation\""
                response `responseBodyShouldContain` "data-week-toolbar-section=\"settings\""
                response `responseBodyShouldContain` "href=\"/RosterWeeks\""
                response `responseBodyShouldContain` "This week</a>"
                response `responseBodyShouldContain` "btn btn-outline-secondary app-week-nav-button"
                response `responseBodyShouldNotContain` "data-roster-week-controls=\"manager-actions\""
                response `responseBodyShouldContain` "data-bepis-roster-staff-panel-tab=\"staff\""
                response `responseBodyShouldContain` "data-bepis-roster-staff-panel-tab=\"settings\""
                response `responseBodyShouldNotContain` "data-bepis-roster-staff-panel-tab=\"templates\""
                response `responseBodyShouldNotContain` "data-bepis-roster-template-card=\"true\""
                response `responseBodyShouldNotContain` "data-bepis-source-ref=\"day-template-drag-source\""
                response `responseBodyShouldNotContain` "data-bepis-source-ref=\"week-template-drag-source\""
                response `responseBodyShouldContain` "data-bepis-roster-staff-panel-sort-root=\"true\""
                response `responseBodyShouldContain` "data-bepis-roster-staff-panel-sort-control=\"name\""
                response `responseBodyShouldContain` "data-bepis-roster-staff-panel-sort-control=\"role\""
                response `responseBodyShouldContain` "data-bepis-roster-staff-panel-sort-control=\"shifts\""
                response `responseBodyShouldContain` "data-bepis-roster-staff-panel-sort-row=\"{&quot;assignedShifts&quot;:0,&quot;idealShifts&quot;:0,&quot;staffName&quot;:&quot;Alpha&quot;,&quot;staffRole&quot;:&quot;TRIAL&quot;,&quot;staffRowKey&quot;:&quot;staff:"
                response `responseBodyShouldNotContain` "data-roster-staff-"
                response `responseBodyShouldContain` "roster-grid-header app-side-panel-header"
                response `responseBodyShouldContain` "data-bepis-roster-side-panel-root=\"true\""
                response `responseBodyShouldContain` "data-bepis-roster-side-panel=\"collapsed\""
                response `responseBodyShouldContain` "data-bepis-roster-side-panel-main=\"true\""
                response `responseBodyShouldContain` "data-bepis-roster-side-panel-panel=\"true\""
                response `responseBodyShouldContain` "data-bepis-roster-side-panel-toggle=\"true\""
                response `responseBodyShouldContain` "data-bepis-roster-side-panel-label=\"true\""
                response `responseBodyShouldContain` "data-bepis-roster-column-editor=\"true\""
                response `responseBodyShouldContain` "data-roster-day-add=\"true\""
                response `responseBodyShouldContain` "data-bepis-roster-column-editing=\"inactive\""
                response `responseBodyShouldContain` "data-bepis-roster-column-edit-start=\"true\""
                response `responseBodyShouldContain` "data-bepis-roster-column-edit-done=\"true\""
                response `responseBodyShouldNotContain` "data-roster-column-"
                response `responseBodyShouldContain` "id=\"roster-staff-panel-settings-pane\""
                response `responseBodyShouldContain` ("data-bepis-roster-staff-highlight-source=\"staff:" <> cs (tshow panelStaff.id) <> "\"")
                response `responseBodyShouldContain` ("data-bepis-roster-staff-highlight-pin=\"staff:" <> cs (tshow panelStaff.id) <> "\"")
                response `responseBodyShouldContain` "Week actions"
                response `responseBodyShouldContain` "hx-post=\"/CopyRosterWeek?"
                response `responseBodyShouldContain` "hx-confirm=\"This will overwrite the current week with the previous week&#39;s roster. Continue?\""
                response `responseBodyShouldContain` "Sort shifts"
                response `responseBodyShouldContain` "hx-post=\"/SortRosterWeek?anchorDate=2025-01-06&amp;rosterGroupId="
                response `responseBodyShouldNotContain` "Roster columns"
                response `responseBodyShouldNotContain` "data-disable-javascript-submission"
                response `responseBodyShouldContain` "roster-live-toggle-"
                response `responseBodyShouldContain` "btn btn-outline-success app-toggle-button"
                response `responseBodyShouldContain` "data-bepis-toggle-transport=\"toggle-transport:roster-live-toggle-"
                response `responseBodyShouldContain` "data-bepis-toggle-config=\""
                response `responseBodyShouldContain` "aria-pressed=\"false\""
                response `responseBodyShouldContain` "role=\"switch\" aria-checked=\"false\""
                response `responseBodyShouldContain` "data-bepis-surface-action=\"navigate-roster-week\""
                response `responseBodyShouldContain` "data-bepis-surface-action=\"toggle-roster-week-live-status\""
                response `responseBodyShouldContain` "anchorDate=2025-01-06&amp;rosterGroupId="
                response `responseBodyShouldContain` "data-bepis-surface-action=\"toggle-roster-staff-scope\""
                response `responseBodyShouldContain` "hx-target=\"#roster-staff-panel-fragment\""
                response `responseBodyShouldNotContain` "hx-target=\"#roster-staff-panel\""
                response `responseBodyShouldContain` "data-bepis-surface-action=\"toggle-roster-warnings\""
                response `responseBodyShouldContain` "data-bepis-surface-action=\"toggle-roster-assignment-filters\""
                response `responseBodyShouldContain` "data-bepis-surface-action=\"sort-roster-week\""
                response `responseBodyShouldContain` "data-bepis-surface-action=\"copy-roster-week\""

        it "keeps templates and application targets hidden on Published rosters" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Live template target"
                manager <- createUserRecord "live-template-target@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                let templateActor = rosterTemplateActor manager venue True
                Right dayDraft <- startBlankRosterTemplateDesignerDraft templateActor rosterGroup Day "Lunch service"
                Right _ <- saveRosterTemplateDraft templateActor dayDraft.draftDesign.id
                rosterWeek <- createRosterWeekRecordForRosterGroup venue rosterGroup 0 True
                _ <- forM [0 .. 6] (createRosterDayRecord rosterWeek)

                response <- withUserAndCurrentVenue manager venue.id do
                    callAction (ShowRosterWindowAction (tshow (testAnchorForOffset 0)))

                response `responseStatusShouldBe` status200
                response `responseBodyShouldNotContain` "data-bepis-roster-staff-panel-tab=\"templates\""
                response `responseBodyShouldNotContain` "roster-template-library-mount-"
                response `responseBodyShouldNotContain` "Templates cannot be applied to a Published roster"
                response `responseBodyShouldNotContain` "aria-label=\"Apply Lunch service\""
                response `responseBodyShouldNotContain` "data-bepis-source-ref=\"day-template-drag-source\""
                response `responseBodyShouldNotContain` "data-bepis-dropzone-ref=\"day-template-dropzone\""
                response `responseBodyShouldNotContain` "data-bepis-dropzone-ref=\"week-template-dropzone\""

        it "keeps staff requiring pay remediation visible and editable in the roster staff panel" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Roster Staff Remediation Venue"
                manager <- createUserRecord "roster-staff-remediation-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                unresolvedStaff <- createStaffRecord venue Nothing "Unresolved" "Crew"
                    >>= updateRecord . set #payAssignmentMode LegacyUnresolved
                _ <- fetchSlotNameRecord venue "Early"

                response <- withUserAndCurrentVenue manager venue.id do
                    callAction (ShowRosterWindowAction (tshow (testAnchorForOffset 0)))

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Unresolved"
                response `responseBodyShouldContain` ("hx-get=\"/EditStaff?staffId=" <> cs (tshow unresolvedStaff.id))
                response `responseBodyShouldContain` "Pay configuration required"
                response `responseBodyShouldContain` "data-bepis-source-ref=\"staff-drag-source\""
                response `responseBodyShouldContain` ("data-bepis-source-key=\"staff:" <> cs (tshow unresolvedStaff.id) <> "\"")

        it "hides copy previous week controls from staff users" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                worker <- createUserRecord "roster-worker-copy-hidden@example.com" "staff" True
                _ <- createVenueMembershipRecord venue worker Worker
                _ <- fetchSlotNameRecord venue "Early"

                response <- withUserAndCurrentVenue worker venue.id do
                    callAction (ShowRosterWindowAction (tshow (testAnchorForOffset 0)))

                response `responseStatusShouldBe` status200
                response `responseBodyShouldNotContain` "Copy Previous Week"
                response `responseBodyShouldNotContain` "hx-post=\"/CopyRosterWeek"
                response `responseBodyShouldNotContain` "Sort shifts"

        it "roster group switcher preserves anchorDate in the submitted form for multi-group venues" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-group-switcher@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                _ <- newRecord @RosterGroup
                    |> set #venueId (unpackId venue.id)
                    |> set #name ("Second group" :: Text)
                    |> set #sortOrder 2
                    |> createRecord

                response <- withUserAndCurrentVenue manager venue.id do
                    callAction (ShowRosterWindowAction (tshow (testAnchorForOffset 3)))

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "action=\"/ShowRosterWindow?anchorDate=2025-01-27\""
                response `responseBodyShouldContain` "type=\"hidden\" name=\"anchorDate\" value=\"2025-01-27\""
                response `responseBodyShouldContain` "name=\"rosterGroupId\""
