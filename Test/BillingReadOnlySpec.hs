module Test.BillingReadOnlySpec where

import qualified Data.Text as Text
import Generated.Types
import IHP.ControllerPrelude
import IHP.Test.Mocking
import Network.HTTP.Types.Status
import Network.Wai (responseHeaders)
import Test.Hspec
import Test.Support
import Web.Controller.Admin ()
import Web.Controller.Billing ()
import Web.Controller.LeaveRequests ()
import Web.Controller.RosterWeeks ()
import Web.Controller.Timesheets ()
import Web.FrontController ()
import Web.Routes
import Web.Types

tests :: Spec
tests = aroundAll withDatabaseTestContext do
    describe "Billing manual read-only enforcement" do
        it "keeps venue read pages available" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Read Only Read Venue"
                manager <- createUserRecord "readonly-read-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                superAdmin <- createUserRecordWithPlatformRole "readonly-read-support@example.com" "staff" (Just SuperAdmin) True
                _ <- markVenueReadOnly venue superAdmin

                response <- withUserAndCurrentVenue manager venue.id do
                    callAction RosterWeeksAction

                response `responseStatusShouldBe` status302
                fmap cs (lookup "Location" (responseHeaders response))
                    `shouldSatisfy` maybe False (Text.isPrefixOf "http://localhost/ShowRosterWindow?anchorDate=")

        it "keeps owner billing recovery available" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Read Only Billing Venue"
                owner <- createUserRecord "readonly-billing-owner@example.com" "staff" True
                _ <- createVenueMembershipRecord venue owner VenueOwner
                superAdmin <- createUserRecordWithPlatformRole "readonly-billing-support@example.com" "staff" (Just SuperAdmin) True
                _ <- markVenueReadOnly venue superAdmin

                response <- withPasskeyVerifiedUserAndCurrentVenue owner venue.id do
                    callAction BillingAction

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Billing"
                response `responseBodyShouldContain` "Start Subscription"

        it "blocks representative roster writes" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Read Only Roster Venue"
                manager <- createUserRecord "readonly-roster-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                superAdmin <- createUserRecordWithPlatformRole "readonly-roster-support@example.com" "staff" (Just SuperAdmin) True
                _ <- markVenueReadOnly venue superAdmin

                response <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams CreateRosterWeekAction (rosterMutationParams 0)

                response `responseStatusShouldBe` status302
                lookup "Location" (responseHeaders response) `shouldBe` Just "http://localhost/RosterWeeks"

        it "blocks representative timesheet writes" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Read Only Timesheet Venue"
                manager <- createUserRecord "readonly-timesheet-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                _ <- ensureProfileCompleteStaffRecord venue manager
                superAdmin <- createUserRecordWithPlatformRole "readonly-timesheet-support@example.com" "staff" (Just SuperAdmin) True
                _ <- markVenueReadOnly venue superAdmin

                response <- withUserAndCurrentVenue manager venue.id do
                    callAction CreateTimesheetEntryAction

                response `responseStatusShouldBe` status302
                lookup "Location" (responseHeaders response) `shouldBe` Just "http://localhost/RosterWeeks"

        it "blocks representative unavailability writes" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Read Only Leave Venue"
                manager <- createUserRecord "readonly-leave-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                _ <- ensureProfileCompleteStaffRecord venue manager
                superAdmin <- createUserRecordWithPlatformRole "readonly-leave-support@example.com" "staff" (Just SuperAdmin) True
                _ <- markVenueReadOnly venue superAdmin

                response <- withUserAndCurrentVenue manager venue.id do
                    callAction (ApproveLeaveRequestAction "11111111-1111-1111-1111-111111111111")

                response `responseStatusShouldBe` status302
                lookup "Location" (responseHeaders response) `shouldBe` Just "http://localhost/RosterWeeks"

        it "blocks representative admin writes" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Read Only Admin Venue"
                admin <- createUserRecord "readonly-admin@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin
                _ <- ensureProfileCompleteStaffRecord venue admin
                superAdmin <- createUserRecordWithPlatformRole "readonly-admin-support@example.com" "staff" (Just SuperAdmin) True
                _ <- markVenueReadOnly venue superAdmin

                response <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams CreateRosterGroupAction [("name", "Patio"), ("isActive", "on")]

                response `responseStatusShouldBe` status302
                lookup "Location" (responseHeaders response) `shouldBe` Just "http://localhost/RosterWeeks"
                rosterGroupCount <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> fetchCount
                rosterGroupCount `shouldBe` 1

        it "keeps support manual billing controls available" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Read Only Support Toggle Venue"
                superAdmin <- createUserRecordWithPlatformRole "readonly-toggle-support@example.com" "staff" (Just SuperAdmin) True
                _ <- markVenueReadOnly venue superAdmin

                response <- withPasskeyVerifiedUserAndCurrentVenue superAdmin venue.id do
                    callActionWithParams
                        UpdateVenueBillingControlAction
                        [ ("manualReadOnly", "false")
                        , ("manualReadOnlyReason", "")
                        ]

                response `responseStatusShouldBe` status302
                control <- query @VenueBillingControl |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                control.manualReadOnly `shouldBe` False

markVenueReadOnly :: (?modelContext :: ModelContext) => Venue -> User -> IO VenueBillingControl
markVenueReadOnly venue superAdmin = do
    now <- getCurrentTime
    newRecord @VenueBillingControl
        |> set #venueId (unpackId venue.id)
        |> set #manualReadOnly True
        |> set #manualReadOnlyReason (Just "Payment follow-up")
        |> set #setByUserId (Just (unpackId superAdmin.id))
        |> set #setAt (Just now)
        |> createRecord
