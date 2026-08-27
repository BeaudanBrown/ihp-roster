module Test.Controller.Admin.AccessSpec where

import Application.Helper.LiveUpdate
import Application.Helper.RosterGroups (createVenueRosterGroupWithDefaults,
                                        fetchActiveRosterGroupSlotNames)
import Application.Helper.Xero
import Config
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as AesonKey
import qualified Data.Aeson.KeyMap as AesonKeyMap
import qualified Data.Aeson.Types as AesonTypes
import qualified Data.ByteString.Lazy.Char8 as LByteString
import qualified Data.IORef as IORef
import qualified Data.List as List
import Data.Scientific (Scientific)
import qualified Data.Text as Text
import Data.Time.Calendar (fromGregorian)
import Data.Time.Clock (NominalDiffTime, addUTCTime, diffUTCTime,
                        getCurrentTime)
import Generated.Types
import IHP.ControllerPrelude
import IHP.FrameworkConfig
import IHP.HaskellSupport
import IHP.Prelude
import IHP.Test.Mocking
import Network.HTTP.Types.Status
import Network.Wai (responseHeaders)
import Test.Hspec
import Test.Support
import qualified Test.XeroMock as XeroMock
import Web.Controller.Admin ()
import Web.FrontController ()
import Web.Routes
import Web.Types

tests :: Spec
tests = aroundAll withDatabaseTestContext do
    describe "AdminController" do
        it "redirects unauthenticated users from admin page" $ withContext do
            response <- callAction AdminAction
            response `responseStatusShouldBe` status302

        it "redirects venue-less super-admins from admin to support" $ withContext do
            withCleanDb do
                user <- createUserRecordWithPlatformRole "admin-bootstrap-super-admin@example.com" "staff" (Just SuperAdmin) True

                response <- withUser user do
                    callAction AdminAction

                response `responseStatusShouldBe` status302
                responseHeaders response `shouldContain` [("Location", "http://localhost/Support")]

        it "shows current-venue admin sections with FWC-backed award level data" $ withContext do
            withCleanDb do
                venueA <- createVenueWithConfig "Venue A"
                venueB <- createVenueWithConfig "Venue B"
                admin <- createUserRecord "admin-page@example.com" "staff" True
                _ <- createVenueMembershipRecord venueA admin VenueAdmin
                _ <- createVenueMembershipRecord venueB admin VenueAdmin

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
                levelB <- createPayLevelRecord venueB "Level B"
                _ <- createShiftTypeRecord venueB levelB "Bar"
                _ <- createSlotNameRecord venueB "Graveyard"

                response <- withPasskeyVerifiedUserAndCurrentVenue admin venueA.id do
                    callActionWithParams AdminAction [("rosterGroupId", idToParam venueAGroupB.id)]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Roster Groups"
                response `responseBodyShouldContain` "Shift Types"
                response `responseBodyShouldContain` "Invites"
                response `responseBodyShouldContain` "Exports"
                response `responseBodyShouldContain` "Payroll Workbook"
                response `responseBodyShouldContain` "Download workbook"
                response `responseBodyShouldContain` "Payroll Earnings CSV"
                response `responseBodyShouldContain` "Recent Exports"
                response `responseBodyShouldNotContain` "Staff Hours CSV"
                response `responseBodyShouldNotContain` "Hourly Breakdown ZIP"
                response `responseBodyShouldNotContain` "admin-slot-names-fragment"
                response `responseBodyShouldContain` "admin-invites-fragment"
                response `responseBodyShouldContain` "data-bepis-surface-action=\"create-venue-invitation\""
                body <- responseBody response
                (cs body :: String) `shouldContainInOrder` ["Invites", "Exports", "Shift Types", "Roster Groups"]
                response `responseBodyShouldNotContain` "Compliance"
                response `responseBodyShouldNotContain` "Venue Config"
                response `responseBodyShouldNotContain` "Award Levels"
                response `responseBodyShouldNotContain` "Pay Levels"
                response `responseBodyShouldNotContain` "Pay Level Day Rules"
                response `responseBodyShouldNotContain` "slot-names-heading"
                response `responseBodyShouldNotContain` "/helpers.js"
                response `responseBodyShouldContain` "Kitchen"
                response `responseBodyShouldContain` "Level A"
                response `responseBodyShouldContain` "Award rates"
                response `responseBodyShouldContain` "Level A (Part-time $31.50/hr, casual $39.38/hr)"
                response `responseBodyShouldContain` "Use staff default pay rate"
                response `responseBodyShouldContain` "No Timesheets (roster only)"
                response `responseBodyShouldContain` "Back of House"
                response `responseBodyShouldNotContain` "Pass"
                response `responseBodyShouldNotContain` "Default Only"
                response `responseBodyShouldNotContain` "Bar"
                response `responseBodyShouldNotContain` "Graveyard"

        it "scopes slot names to the roster group card and fragment target" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Admin Slot Group Venue"
                admin <- createUserRecord "admin-slot-groups@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin
                firstGroup <- createVenueRosterGroupWithDefaults venue "Front Lane" 10 True
                secondGroup <- createVenueRosterGroupWithDefaults venue "Back Lane" 20 True
                _ <- newRecord @SlotName
                    |> set #venueId (unpackId venue.id)
                    |> set #rosterGroupId (unpackId firstGroup.id)
                    |> set #name "Front Register"
                    |> set #sortOrder 0
                    |> set #isActive True
                    |> createRecord
                _ <- newRecord @SlotName
                    |> set #venueId (unpackId venue.id)
                    |> set #rosterGroupId (unpackId secondGroup.id)
                    |> set #name "Back Pass"
                    |> set #sortOrder 0
                    |> set #isActive True
                    |> createRecord

                pageResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callAction AdminAction
                pageResponse `responseStatusShouldBe` status200
                pageResponse `responseBodyShouldContain` "Front Lane"
                pageResponse `responseBodyShouldContain` "Back Lane"
                pageResponse `responseBodyShouldNotContain` "Front Register"
                pageResponse `responseBodyShouldNotContain` "Back Pass"
                pageResponse `responseBodyShouldContain` "data-bepis-surface=\""
                pageResponse `responseBodyShouldNotContain` "admin_slot_names"

        it "rejects non-admin venue members from admin screens" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "manager-admin@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager

                response <- withUserAndCurrentVenue manager venue.id do
                    callAction AdminAction

                response `responseStatusShouldBe` status302
                lookup "Location" (responseHeaders response) `shouldBe` Just "http://localhost/RosterWeeks"


shouldContainInOrder :: String -> [String] -> Expectation
shouldContainInOrder haystack needles =
    case mapM markerPosition needles of
        Nothing -> expectationFailure ("Expected body to contain all markers in order: " ++ cs (show needles))
        Just positions -> positions `shouldSatisfy` ordered
    where
        markerPosition marker = List.findIndex (List.isPrefixOf marker) (List.tails haystack)
        ordered positions = positions == List.sort positions
