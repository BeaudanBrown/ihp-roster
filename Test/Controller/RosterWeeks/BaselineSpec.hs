module Test.Controller.RosterWeeks.BaselineSpec where

import Application.Helper.RosterGroups (ensureVenueDefaultRosterGroup)
import Control.Exception (bracket)
import qualified Data.ByteString.Char8 as ByteString
import qualified Data.ByteString.Lazy.Char8 as LByteString
import Data.Maybe (fromJust)
import qualified Data.Text as Text
import Data.Time.Calendar (addDays)
import Data.Time.LocalTime (TimeOfDay (..))
import Generated.Types
import IHP.ControllerPrelude
import IHP.FrameworkConfig
import IHP.Prelude
import IHP.Test.Mocking
import Network.HTTP.Types.Status
import Network.Wai
import qualified System.Environment as Environment
import Test.Hspec
import Test.Support
import Web.Controller.RosterWeeks ()
import Web.FrontController ()
import Web.Routes
import Web.Types

-- These tests pin the active roster read-model path at a high level.
tests :: Spec
tests = aroundAll withDatabaseTestContext do
    describe "RosterWeeksController direct read-model integration" do
        it "renders full-page and fragment roster reads through the direct read model" $ withContext do
            withEnv "IHP_ROSTER_PROFILING" (Just "1") do
                withCleanDb do
                    BaselineRoster { brVenue, brManager, brRosterDay } <- createBaselineRoster

                    coldPage <- withUserAndCurrentVenue brManager brVenue.id do
                        callAction (ShowRosterWindowAction (tshow (testAnchorForOffset 0)))
                    warmPage <- withUserAndCurrentVenue brManager brVenue.id do
                        callAction (ShowRosterWindowAction (tshow (testAnchorForOffset 0)))
                    contentFragment <- withUserAndCurrentVenue brManager brVenue.id do
                        callAction (ShowRosterWeekContentFragmentAction (tshow (testAnchorForOffset 0)))
                    rowFragment <- withUserAndCurrentVenue brManager brVenue.id do
                        callAction (ShowRosterWeekRowFragmentAction (tshow (testAnchorForOffset 0)) brRosterDay.id 0)
                    dayFragment <- withUserAndCurrentVenue brManager brVenue.id do
                        callAction (ShowRosterWeekDaySectionFragmentAction (tshow (testAnchorForOffset 0)) brRosterDay.id)
                    staffPanel <- withUserAndCurrentVenue brManager brVenue.id do
                        callAction (ShowRosterWeekStaffPanelFragmentAction (tshow (testAnchorForOffset 0)))

                    coldPage `responseStatusShouldBe` status200
                    warmPage `responseStatusShouldBe` status200
                    contentFragment `responseStatusShouldBe` status200
                    rowFragment `responseStatusShouldBe` status200
                    dayFragment `responseStatusShouldBe` status200
                    staffPanel `responseStatusShouldBe` status200

                    serverTiming coldPage `shouldContainBS` "roster_direct_fetch_dated_slots;dur="
                    serverTiming rowFragment `shouldContainBS` "roster_direct_build_slot_conflicts;dur="
                    serverTiming dayFragment `shouldContainBS` "roster_direct_build_slot_conflicts;dur="
                    serverTiming staffPanel `shouldNotContainBS` "roster_direct_build_staff_option_states;dur="
                    serverTiming staffPanel `shouldNotContainBS` "roster_direct_build_slot_conflicts;dur="

                    dumpBaselineTimings
                        [ ("cold-page", coldPage)
                        , ("warm-page", warmPage)
                        , ("content-fragment", contentFragment)
                        , ("row-fragment", rowFragment)
                        , ("day-fragment", dayFragment)
                        , ("staff-panel", staffPanel)
                        ]

                    bodyText <- cs . LByteString.unpack <$> responseBody contentFragment
                    bodyText `shouldContain` "data-roster-row"

        it "keeps reads and lane mutations on the anchor-date window" $ withContext do
            withCleanDb do
                BaselineRoster { brVenue, brManager, brRosterDay } <- createBaselineRoster
                venueConfig <- query @VenueConfig
                    |> filterWhere (#venueId, unpackId brVenue.id)
                    |> fetchOne
                fullPage <- withUserAndCurrentVenue brManager brVenue.id do
                    callAction (ShowRosterWindowAction (tshow (testAnchorForOffset 0)))
                contentFragment <- withUserAndCurrentVenue brManager brVenue.id do
                    callAction (ShowRosterWeekContentFragmentAction (tshow (testAnchorForOffset 0)))
                rowFragment <- withUserAndCurrentVenue brManager brVenue.id do
                    callAction (ShowRosterWeekRowFragmentAction (tshow (testAnchorForOffset 0)) brRosterDay.id 0)
                dayFragment <- withUserAndCurrentVenue brManager brVenue.id do
                    callAction (ShowRosterWeekDaySectionFragmentAction (tshow (testAnchorForOffset 0)) brRosterDay.id)
                timelineFragment <- withUserAndCurrentVenue brManager brVenue.id do
                    callAction (ShowRosterDayTimelineContentFragmentAction (tshow (testAnchorForOffset 0)) brRosterDay.id)
                staffPanel <- withUserAndCurrentVenue brManager brVenue.id do
                    callAction (ShowRosterWeekStaffPanelFragmentAction (tshow (testAnchorForOffset 0)))

                forM_ [fullPage, contentFragment, rowFragment, dayFragment, timelineFragment, staffPanel] \response ->
                    response `responseStatusShouldBe` status200
                fullPage `responseBodyShouldContain` "Mon 06/01"
                fullPage `responseBodyShouldContain` "Sun 12/01"
                fullPage `responseBodyShouldContain` "&quot;windowStartDate&quot;:&quot;2025-01-06&quot;"
                fullPage `responseBodyShouldContain` "&quot;windowEndDate&quot;:&quot;2025-01-13&quot;"
                contentFragment `responseBodyShouldContain` "Mon 06/01"
                contentFragment `responseBodyShouldContain` "Sun 12/01"
                timelineFragment `responseBodyShouldContain` "data-roster-day-timeline=\"true\""

                mutationResponse <- withPasskeyVerifiedUserAndCurrentVenue brManager brVenue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams
                            CreateRosterWeekSlotDefinitionAction
                            [ ("anchorDate", cs (show (testAnchorForOffset 0)))
                            , ("rosterGroupId", cs (show brRosterDay.rosterGroupId))
                            , ("rosterCalendarRevision", cs (show venueConfig.rosterCalendarRevision))
                            , ("name", "Explicit window lane")
                            ]
                mutationResponse `responseStatusShouldBe` status200
                let triggerHeader = cs <$> lookup "HX-Trigger" (responseHeaders mutationResponse)
                triggerHeader `shouldSatisfy` maybe False (Text.isInfixOf "\"windowStartDate\":\"2025-01-06\"")
                triggerHeader `shouldSatisfy` maybe True (not . Text.isInfixOf "2024-12-31")
                mutatedDays <- query @RosterDay
                    |> filterWhere (#venueId, unpackId brVenue.id)
                    |> filterWhere (#rosterGroupId, brRosterDay.rosterGroupId)
                    |> orderByAsc #operationalDate
                    |> fetch
                map (.operationalDate) mutatedDays `shouldBe` map (\dayIndex -> addDays dayIndex (testAnchorForOffset 0)) [0 .. 6]
                explicitLanes <- query @RosterLane
                    |> filterWhereIn (#rosterDayId, map (unpackId . (.id)) mutatedDays)
                    |> filterWhere (#name, "Explicit window lane")
                    |> filterWhere (#deletedAt, Nothing)
                    |> fetch
                length explicitLanes `shouldBe` 7

        it "keeps slot mutation actor refresh separate from passive direct refetch" $ withContext do
            withEnv "IHP_ROSTER_PROFILING" (Just "1") do
                withCleanDb do
                    BaselineRoster { brVenue, brManager, brRosterDay, brMutableSlot, brAlternateStaff } <- createBaselineRoster
                    shiftType <- ensureVenueDefaultShiftType brVenue

                    mutationResponse <- withUserAndCurrentVenue brManager brVenue.id do
                        withRequestHeaders [("HX-Request", "true")] do
                            callRosterSlotActionWithParams
                                (UpdateRosterSlotAction brMutableSlot.id)
                                [ ("staffId", idToParam brAlternateStaff.id)
                                , ("startTime", "08:00")
                                , ("shiftTypeId", idToParam shiftType.id)
                                ]
                    passiveRefetch <- withUserAndCurrentVenue brManager brVenue.id do
                        callAction (ShowRosterWeekRowFragmentAction (tshow (testAnchorForOffset 0)) brRosterDay.id 0)

                    mutationResponse `responseStatusShouldBe` status200
                    passiveRefetch `responseStatusShouldBe` status200

                    forM_ (lookup "HX-Trigger" (responseHeaders mutationResponse)) \triggerHeader ->
                        triggerHeader `shouldContainBS` "bepis:live-fragments-refresh"
                    serverTiming mutationResponse `shouldContainBS` "app_total;dur="
                    serverTiming passiveRefetch `shouldContainBS` "roster_direct_build_slot_conflicts;dur="
                    dumpBaselineTimings [("slot-mutation", mutationResponse), ("passive-row-refetch", passiveRefetch)]

data BaselineRoster = BaselineRoster
    { brVenue          :: Venue
    , brManager        :: User
    , brRosterDay      :: RosterDay
    , brMutableSlot    :: RosterSlot
    , brAlternateStaff :: Staff
    }

createBaselineRoster :: (?modelContext :: ModelContext) => IO BaselineRoster
createBaselineRoster = do
    venue <- createVenueWithConfig "Roster Baseline Venue"
    manager <- createUserRecord "roster-baseline-manager@example.com" "staff" True
    _ <- createVenueMembershipRecord venue manager Manager
    rosterGroup <- ensureVenueDefaultRosterGroup venue
    earlySlotName <- fetchSlotNameRecordForRosterGroup rosterGroup "Early"
    lateSlotName <- fetchSlotNameRecordForRosterGroup rosterGroup "Late"
    awardLevel <- createPayLevelRecord venue "Baseline Level"
    shiftType <- createShiftTypeRecord venue awardLevel "Baseline Shift"
    staffMembers <- forM [1 :: Int .. 6] \index -> do
        user <- createUserRecord ("roster-baseline-staff-" <> tshow index <> "@example.com") "staff" True
        _ <- createVenueMembershipRecord venue user Worker
        staff <- createStaffRecord venue (Just user) ("Staff" <> tshow index) "Baseline"
        staff
            |> set #idealShiftsPerWeek 5
            |> updateRecord
    rosterWeek <- createRosterWeekRecordForRosterGroup venue rosterGroup 0 False
    rosterDays <- forM [0 :: Int .. 6] \dayOffset -> do
        day <- createRosterDayRecord rosterWeek dayOffset
        day |> set #rowCount 2 |> updateRecord
    createdSlots <- forM (zip [0 :: Int ..] rosterDays) \(dayIndex, day) -> do
        forM [0 :: Int, 1] \rowIndex -> do
            earlySlot <- createRosterSlotRecord day earlySlotName (Just (staffMembers !! ((dayIndex + rowIndex) `mod` length staffMembers))) rowIndex
            lateSlot <- createRosterSlotRecord day lateSlotName (Just (staffMembers !! ((dayIndex + rowIndex + 2) `mod` length staffMembers))) rowIndex
            mapM_ (\slot -> slot |> setTestStartTime (Just (TimeOfDay (8 + rowIndex) 0 0)) |> setTestEndTime (Just (TimeOfDay (12 + rowIndex) 0 0)) |> set #shiftTypeId (Just (unpackId shiftType.id)) |> updateRecord) [earlySlot, lateSlot]
            pure (earlySlot, lateSlot)
    let firstDay = fromJust (head rosterDays)
    let firstSlotPair = fromJust (head (fromJust (head createdSlots)))
    let primaryStaff = fromJust (head staffMembers)
    mutableSlot <- fst firstSlotPair |> set #staffId (Just (unpackId primaryStaff.id)) |> updateRecord
    _ <- snd firstSlotPair |> set #staffId (Just (unpackId primaryStaff.id)) |> updateRecord
    pure BaselineRoster { brVenue = venue, brManager = manager, brRosterDay = firstDay, brMutableSlot = mutableSlot, brAlternateStaff = staffMembers !! 1 }

serverTiming :: Response -> ByteString.ByteString
serverTiming response =
    fromMaybe "" (lookup "Server-Timing" (responseHeaders response))

shouldContainBS :: HasCallStack => ByteString.ByteString -> ByteString.ByteString -> Expectation
shouldContainBS haystack needle =
    haystack `shouldSatisfy` ByteString.isInfixOf needle

shouldNotContainBS :: HasCallStack => ByteString.ByteString -> ByteString.ByteString -> Expectation
shouldNotContainBS haystack needle =
    haystack `shouldNotSatisfy` ByteString.isInfixOf needle

dumpBaselineTimings :: [(String, Response)] -> IO ()
callRosterSlotActionWithParams action params =
    callActionWithParams action (params <> rosterMutationParams 0)

dumpBaselineTimings responses = do
    shouldPrint <- Environment.lookupEnv "IHP_ROSTER_BASELINE_PRINT"
    when (shouldPrint == Just "1") do
        forM_ responses \(label, response) ->
            putStrLn (cs label <> ": " <> cs (ByteString.unpack (serverTiming response)))

withEnv :: String -> Maybe String -> IO a -> IO a
withEnv name value action =
    bracket setup restore (const action)
    where
        setup = do
            previous <- Environment.lookupEnv name
            apply value
            pure previous

        restore previous =
            apply previous

        apply Nothing         = Environment.unsetEnv name
        apply (Just envValue) = Environment.setEnv name envValue
