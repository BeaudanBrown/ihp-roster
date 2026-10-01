module Test.Controller.RecipientGroupsSpec where

import Application.Helper.Export.PayrollWorkbookConfiguration (createStandardPayrollWorkbookConfigurationInCurrentTransaction, SavedPayrollWorkbookConfiguration (..))
import Config
import qualified Data.Text as Text
import Generated.Types
import IHP.ControllerPrelude
import IHP.FrameworkConfig
import IHP.HaskellSupport
import IHP.Hspec
import IHP.Prelude
import IHP.Test.Mocking
import Network.HTTP.Types.Status
import Test.Hspec
import Test.Support
import Web.Controller.RecipientGroups ()
import Web.FrontController ()
import Web.Routes ()
import Web.Types

-- HTTP adapters exercise the same domain authority as scheduled/manual sends.
tests :: Spec
tests = aroundAll withDatabaseTestContext do
    describe "RecipientGroupsController" do
        it "keeps Add/Remove drafts server-rendered and rejects malformed entries without saving" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Groups UI"
                admin <- createUserRecord "group-ui@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin
                withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        opened <- callAction NewRecipientGroupAction
                        opened `responseBodyShouldContain` "type=\"email\""
                        opened `responseBodyShouldContain` "autofocus"
                        let fields = [("recipientGroupName", "Accounts"), ("recipientGroupAddresses", "first@example.com")]
                        invalid <- callActionWithParams SaveRecipientGroupAction (fields <> [("recipientGroupEntry", "not-an-email"), ("recipientGroupAdd", "true")])
                        invalid `responseBodyShouldContain` "Enter valid email addresses"
                        invalid `responseBodyShouldContain` "Accounts"
                        invalid `responseBodyShouldContain` "first@example.com"
                        invalid `responseBodyShouldContain` "not-an-email"
                        added <- callActionWithParams SaveRecipientGroupAction (fields <> [("recipientGroupEntry", " SECOND@example.com "), ("recipientGroupAdd", "true")])
                        added `responseBodyShouldContain` "Remove second@example.com"
                        removed <- callActionWithParams SaveRecipientGroupAction (fields <> [("recipientGroupEntry", "invalid-pending"), ("recipientGroupRemove", "first@example.com")])
                        removed `responseBodyShouldNotContain` "Remove first@example.com"
                        removed `responseBodyShouldContain` "invalid-pending"
                query @RecipientGroup |> fetchCount `shouldReturn` 0

        it "saves an empty pending field, rejects duplicate names and stale edits, and preserves rejected values" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Groups save"
                admin <- createUserRecord "group-save@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin
                withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    let fields = [("recipientGroupName", "Accounts"), ("recipientGroupAddresses", "FIRST@example.com\nfirst@example.com"), ("recipientGroupEntry", "")]
                    saved <- callActionWithParams SaveRecipientGroupAction fields
                    saved `responseStatusShouldBe` status302
                    group <- query @RecipientGroup |> fetchOne
                    group.recipients `shouldBe` ["first@example.com"]
                    withRequestHeaders [("HX-Request", "true")] do
                        duplicate <- callActionWithParams SaveRecipientGroupAction fields
                        duplicate `responseBodyShouldContain` "with that name already exists"
                        let editFields = [("recipientGroupId", cs (tshow group.id)), ("recipientGroupRevision", "0"), ("recipientGroupName", "Updated Accounts"), ("recipientGroupAddresses", "next@example.com")]
                        updated <- callActionWithParams SaveRecipientGroupAction editFields
                        updated `responseBodyShouldContain` "Recipient group saved"
                        stale <- callActionWithParams SaveRecipientGroupAction editFields
                        stale `responseBodyShouldContain` "changed while the dialog was open"
                        stale `responseBodyShouldContain` "Updated Accounts"
                        stale `responseBodyShouldContain` "next@example.com"
                    current <- fetch group.id
                    current.revision `shouldBe` 1
                query @RecipientGroup |> fetchCount `shouldReturn` 1
                query @LiveInvalidationEvent |> fetchCount `shouldReturn` 2

        it "rejects zero and more than fifty addresses, including requests bypassing browser validation" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Groups bounds"
                admin <- createUserRecord "group-bounds@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin
                withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        forM_ ["", Text.intercalate "\n" ["recipient" <> tshow n <> "@example.com" | n <- [1 .. 51 :: Int]]] \addresses -> do
                            rejected <- callActionWithParams SaveRecipientGroupAction [("recipientGroupName", "Bounded"), ("recipientGroupAddresses", cs addresses)]
                            rejected `responseBodyShouldContain` "Bounded"
                            rejected `responseBodyShouldNotContain` "Recipient group saved"
                query @RecipientGroup |> fetchCount `shouldReturn` 0

        it "denies managers every endpoint before parsing and never reveals a foreign venue group" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Groups authority"
                other <- createVenueWithConfig "Foreign groups"
                manager <- createUserRecord "group-manager@example.com" "staff" True
                admin <- createUserRecord "group-admin@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                _ <- createVenueMembershipRecord venue admin VenueAdmin
                foreignGroup <- newRecord @RecipientGroup |> set #venueId (unpackId other.id) |> set #name "Private foreign name"
                    |> set #recipients ["private-foreign@example.com"] |> set #createdByUserId (unpackId admin.id) |> set #updatedByUserId (unpackId admin.id) |> createRecord
                forM_ [NewRecipientGroupAction, EditRecipientGroupAction foreignGroup.id, SaveRecipientGroupAction, ConfirmDeleteRecipientGroupAction foreignGroup.id, DeleteRecipientGroupAction foreignGroup.id, ShowadminRecipientGroupsFragmentAction] \action -> do
                    response <- withPasskeyVerifiedUserAndCurrentVenue manager venue.id (callAction action)
                    response `responseStatusShouldBe` status302
                    response `responseBodyShouldNotContain` "private-foreign@example.com"
                withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        forM_ [EditRecipientGroupAction foreignGroup.id, ConfirmDeleteRecipientGroupAction foreignGroup.id] \action -> do
                            response <- callAction action
                            response `responseBodyShouldContain` "no longer available"
                            response `responseBodyShouldNotContain` "private-foreign@example.com"
                        rejected <- callActionWithParams SaveRecipientGroupAction
                            [("recipientGroupId", cs (tshow foreignGroup.id)), ("recipientGroupRevision", "0"), ("recipientGroupName", "Attack"), ("recipientGroupAddresses", "changed@example.com")]
                        rejected `responseBodyShouldContain` "no longer available"
                        rejectedDelete <- callActionWithParams (DeleteRecipientGroupAction foreignGroup.id) [("recipientGroupRevision", "0"), ("recipientGroupDisableSchedule", "true")]
                        rejectedDelete `responseBodyShouldContain` "no longer available"
                fetch foreignGroup.id `shouldReturn` foreignGroup

        it "requires an explicit linked-schedule delete confirmation and preserves internal records" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Groups delete"
                admin <- createUserRecord "group-delete@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin VenueOwner
                withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    _ <- callActionWithParams SaveRecipientGroupAction [("recipientGroupName", "Payroll recipients"), ("recipientGroupAddresses", "accounts@example.com")]
                    group <- query @RecipientGroup |> fetchOne
                    template <- createStandardPayrollWorkbookConfigurationInCurrentTransaction venue admin
                    settings <- newRecord @PayrollReportSetting |> set #venueId (unpackId venue.id)
                        |> set #configurationId (Just (unpackId template.savedPayrollWorkbookConfigurationRecord.id))
                        |> set #recipientGroupId (Just (unpackId group.id)) |> set #enabled True
                        |> set #recipients ["legacy@example.com"] |> set #updatedByUserId (unpackId admin.id) |> createRecord
                    withRequestHeaders [("HX-Request", "true")] do
                        preview <- callAction (ConfirmDeleteRecipientGroupAction group.id)
                        preview `responseBodyShouldContain` "Delete group and disable schedule"
                        preview `responseBodyShouldContain` "Prepared manual emails keep their original recipients"
                        denied <- callActionWithParams (DeleteRecipientGroupAction group.id) [("recipientGroupRevision", "0")]
                        denied `responseBodyShouldContain` "Review the confirmation"
                        unchanged <- fetch settings.id
                        unchanged.enabled `shouldBe` True
                        deleted <- callActionWithParams (DeleteRecipientGroupAction group.id) [("recipientGroupRevision", "0"), ("recipientGroupDisableSchedule", "true")]
                        deleted `responseBodyShouldContain` "Recipient group deleted"
                    archived <- fetch group.id
                    archived.archivedAt `shouldSatisfy` isJust
                    archived.recipients `shouldBe` ["accounts@example.com"]
                    disabled <- fetch settings.id
                    disabled.enabled `shouldBe` False
                    disabled.recipientGroupId `shouldBe` Nothing
                    disabled.deliveryRevision `shouldBe` settings.deliveryRevision

        it "allows venue-scoped platform support without a venue membership" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Groups support"
                founder <- createUserRecordWithPlatformRole "group-founder@example.com" "staff" (Just SuperAdmin) True
                response <- withPasskeyVerifiedUserAndCurrentVenue founder venue.id do
                    callActionWithParams SaveRecipientGroupAction [("recipientGroupName", "Support-created group"), ("recipientGroupAddresses", "accountant@example.com")]
                response `responseStatusShouldBe` status302
                query @RecipientGroup |> fetchCount `shouldReturn` 1
                query @VenueMembership |> fetchCount `shouldReturn` 0
