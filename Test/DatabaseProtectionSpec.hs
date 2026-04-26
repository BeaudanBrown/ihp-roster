module Test.DatabaseProtectionSpec where

import Control.Exception (SomeException, try)
import Data.Either (isLeft)
import qualified Database.PostgreSQL.Simple as PG
import Generated.Types
import IHP.ControllerPrelude
import IHP.ModelSupport (sqlExecDiscardResult, unpackId)
import IHP.Test.Mocking
import Test.Hspec
import Test.Support

tests :: Spec
tests = beforeAll testContext do
    describe "database hard-delete protection" do
        it "blocks direct DELETEs on protected operational records" $ withContext do
            withCleanDb do
                availability <- createProtectedAvailability

                result <-
                    try
                        ( sqlExecDiscardResult
                            "DELETE FROM staff_availability WHERE id = ?"
                            (PG.Only (unpackId availability.id))
                        ) :: IO (Either SomeException ())

                result `shouldSatisfy` isLeft
                retainedAvailability <-
                    query @StaffAvailability
                        |> filterWhere (#id, availability.id)
                        |> fetchOneOrNothing
                retainedAvailability `shouldSatisfy` isJust

        it "allows maintenance hard DELETEs only when the session setting opts in" $ withContext do
            withCleanDb do
                availability <- createProtectedAvailability

                withTransaction do
                    sqlExecDiscardResult
                        "SET LOCAL ihp_roster.allow_hard_delete = 'on'"
                        ()
                    sqlExecDiscardResult
                        "DELETE FROM staff_availability WHERE id = ?"
                        (PG.Only (unpackId availability.id))

                deletedAvailability <-
                    query @StaffAvailability
                        |> filterWhere (#id, availability.id)
                        |> fetchOneOrNothing
                deletedAvailability `shouldBe` Nothing

createProtectedAvailability :: (?modelContext :: ModelContext) => IO StaffAvailability
createProtectedAvailability = do
    venue <- createVenueWithConfig "Delete Guard Venue"
    user <- createUserRecord "delete-guard@example.com" "staff" True
    staff <- createStaffRecord venue (Just user) "Delete" "Guard"
    newRecord @StaffAvailability
        |> set #venueId (unpackId venue.id)
        |> set #staffId (unpackId staff.id)
        |> set #weekdayIndex (Just 1)
        |> set #specificDate Nothing
        |> set #isAvailable False
        |> set #note (Just "Unavailable")
        |> createRecord
