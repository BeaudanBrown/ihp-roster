module Test.Controller.DaysheetsSpec where

import qualified Application.Daysheet.Contract as D
import qualified Application.Daysheet.Daily as Daily
import qualified Application.Daysheet.DailyStorage as Storage
import Application.Daysheet.Entry (deletionToken)
import qualified Application.Daysheet.Evaluation as E
import Application.Daysheet.References
import Application.Daysheet.Storage (saveDraft, publishDraft)
import Application.Helper.NominalText (renderNominalText)
import qualified Data.UUID as UUID
import qualified Data.Text as Text
import Data.Data (toConstr)
import qualified IHP.RouterSupport as Router
import Network.HTTP.Types.URI (parseQuery)
import Generated.Types
import IHP.ControllerPrelude
import IHP.Hspec
import IHP.Test.Mocking
import Network.HTTP.Types.Status
import Network.Wai (responseHeaders)
import qualified Test.Support.Daysheet as Fixture
import Test.Hspec
import Test.Support
import Web.Controller.Daysheets ()
import Web.FrontController ()
import Web.Types

setup :: (?modelContext :: ModelContext) => IO (Venue, User, VenueMembership)
setup = do
    venue <- createVenueWithConfig "Single-page Daysheets"
    user <- createUserRecord "daysheet-controller@example.test" "manager" True
    member <- createVenueMembershipRecord venue user VenueOwner
    Right _ <- saveDraft member 0 Nothing Fixture.entryDefinition Fixture.entryReferences
    Right _ <- publishDraft member 0 0
    pure (venue, user, member)

day :: Day
day = fromGregorian 2026 10 1

tests :: Spec
tests = aroundAll withDatabaseTestContext do
    describe "DaysheetsController" do
        it "round-trips root and row URLs through the real IHP AutoRoute parser" $ withContext do
            let key = Id (UUID.fromWords 0 0 0 500)
            forM_ [Nothing, Just (tshow (UUID.fromWords 0 0 0 1))] \row ->
                forM_ [ShowDaysheetCellAction key 3 row, SaveDaysheetNumberAction key 3 row, KeepSavedDaysheetCellAction key 3 row] \action -> do
                    let query = parseQuery (cs (Text.dropWhile (/= '?') (pathTo action)))
                    either (const Nothing) Just (Router.applyAction @DaysheetsController (toConstr action) query) `shouldBe` Just action

        it "reads an absent date without creation and creates only on explicit POST" $ withContext do
            withCleanDb do
                (venue, user, _) <- setup
                response <- withPasskeyVerifiedUserAndCurrentVenue user venue.id $
                    callActionWithQueryParams DaysheetsAction [("operationalDate", "2026-10-01")]
                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "No Daysheet exists"
                query @Daysheet |> fetchCount >>= (`shouldBe` 0)
                query @DaysheetDefinitionCapture |> fetchCount >>= (`shouldBe` 0)
                denied <- withPasskeyVerifiedUserAndCurrentVenue user venue.id $
                    callActionWithQueryParams CreateDaysheetAction [("operationalDate", "2026-10-01")]
                denied `responseStatusShouldBe` status405
                created <- withPasskeyVerifiedUserAndCurrentVenue user venue.id $
                    withRequestHeaders [("HX-Request", "true")] $
                        callActionWithParams CreateDaysheetAction [("operationalDate", "2026-10-01")]
                created `responseStatusShouldBe` status200
                lookup "HX-Redirect" (responseHeaders created) `shouldBe` Just "/Daysheets?operationalDate=2026-10-01"
                query @Daysheet |> fetchCount >>= (`shouldBe` 1)
                query @DaysheetDefinitionCapture |> fetchCount >>= (`shouldBe` 1)

        it "renders all eight preserved terminal rows on one page with typed autosave and submission gate" $ withContext do
            withCleanDb do
                (venue, user, member) <- setup
                Right state <- Storage.createDailySheet member day
                response <- withPasskeyVerifiedUserAndCurrentVenue user venue.id $
                    callActionWithQueryParams (ShowDaysheetBodyAction state.daysheet.id) []
                response `responseStatusShouldBe` status200
                forM_ [1 .. 8 :: Int] \n -> response `responseBodyShouldContain` (cs ("Terminal " <> tshow n))
                response `responseBodyShouldContain` "hx-trigger=\"change, submit\""
                response `responseBodyShouldNotContain` "Replace saved value"
                response `responseBodyShouldContain` "Submit saved Daysheet"
                response `responseBodyShouldNotContain` "entryPage"

        it "acknowledges committed autosaves and preserves a stale submitted value for explicit resolution" $ withContext do
            withCleanDb do
                (venue, user, member) <- setup
                Right state <- Storage.createDailySheet member day
                let action = SaveDaysheetTextAction state.daysheet.id 0 Nothing
                before <- query @LiveInvalidationEvent |> fetchCount
                first <- withPasskeyVerifiedUserAndCurrentVenue user venue.id $
                    withRequestHeaders [("HX-Request", "true")] $
                        callActionWithParams action [("expectedRevision", "0"), ("enteredText", "Saved elsewhere")]
                first `responseStatusShouldBe` status200
                lookup "X-Bepis-Form-Saved" (responseHeaders first) `shouldBe` Just "true"
                query @LiveInvalidationEvent |> fetchCount >>= (`shouldBe` (before + 1))
                conflict <- withPasskeyVerifiedUserAndCurrentVenue user venue.id $
                    withRequestHeaders [("HX-Request", "true")] $
                        callActionWithParams action [("expectedRevision", "0"), ("enteredText", "My unsaved input")]
                conflict `responseStatusShouldBe` status200
                conflict `responseBodyShouldContain` "My unsaved input"
                conflict `responseBodyShouldContain` "Saved elsewhere"
                conflict `responseBodyShouldContain` "Replace saved value"
                conflict `responseBodyShouldContain` "aria-invalid=\"true\""
                lookup "X-Bepis-Form-Saved" (responseHeaders conflict) `shouldBe` Nothing
                query @LiveInvalidationEvent |> fetchCount >>= (`shouldBe` (before + 1))
                Right retained <- Storage.readDailySheet member state.daysheet.id
                Daily.readCell retained.content (Daily.RootCell (Fixture.field 1)) `shouldBe` Right (Daily.Cell 1 (Fixture.text "Saved elsewhere"))

        it "rejects missing revisions, fractional whole numbers, calculated overrides and foreign venue ids" $ withContext do
            withCleanDb do
                (venue, user, member) <- setup
                Right state <- Storage.createDailySheet member day
                malformed <- withPasskeyVerifiedUserAndCurrentVenue user venue.id $
                    withRequestHeaders [("HX-Request", "true")] $
                        callActionWithParams (SaveDaysheetNumberAction state.daysheet.id 1 Nothing) [("enteredNumber", "1.5")]
                malformed `responseStatusShouldBe` status200
                lookup "X-Bepis-Form-Saved" (responseHeaders malformed) `shouldBe` Nothing
                invalidRow <- withPasskeyVerifiedUserAndCurrentVenue user venue.id $
                    callActionWithParams (SaveDaysheetNumberAction state.daysheet.id 3 (Just "not-a-row-id")) [("expectedRevision", "0"), ("enteredNumber", "10.00")]
                invalidRow `responseStatusShouldBe` status400
                invalidRow `responseBodyShouldContain` "Invalid Daysheet row identity."
                invalid <- withPasskeyVerifiedUserAndCurrentVenue user venue.id $
                    withRequestHeaders [("HX-Request", "true")] $
                        callActionWithParams (SaveDaysheetNumberAction state.daysheet.id 1 Nothing) [("expectedRevision", "0"), ("enteredNumber", "1.5")]
                invalid `responseBodyShouldContain` "Enter a whole number"
                invalid `responseBodyShouldContain` "value=\"1.5\""
                readonly <- withPasskeyVerifiedUserAndCurrentVenue user venue.id $
                    callActionWithParams (SaveDaysheetSelectionAction state.daysheet.id 2 (Just (tshow (UUID.fromWords 0 0 0 1)))) [("expectedRevision", "0")]
                readonly `responseStatusShouldBe` status400
                other <- createVenueWithConfig "Different venue"
                _ <- createVenueMembershipRecord other user VenueOwner
                foreignResponse <- withPasskeyVerifiedUserAndCurrentVenue user other.id $
                    callActionWithQueryParams (ShowDaysheetBodyAction state.daysheet.id) []
                foreignResponse `responseStatusShouldBe` status404
                Right retained <- Storage.readDailySheet member state.daysheet.id
                retained.daysheet.revision `shouldBe` 0

        it "submits blank saved content without creating delivery jobs and permits later edits" $ withContext do
            withCleanDb do
                (venue, user, member) <- setup
                Right state <- Storage.createDailySheet member day
                jobs <- query @AppJob |> fetchCount
                response <- withPasskeyVerifiedUserAndCurrentVenue user venue.id $
                    withRequestHeaders [("HX-Request", "true")] $
                        callActionWithParams (SubmitDaysheetAction state.daysheet.id) []
                response `responseStatusShouldBe` status200
                query @AppJob |> fetchCount >>= (`shouldBe` jobs)
                Right submitted <- Storage.readDailySheet member state.daysheet.id
                submitted.daysheet.submittedAt `shouldSatisfy` isJust
                after <- withPasskeyVerifiedUserAndCurrentVenue user venue.id $
                    withRequestHeaders [("HX-Request", "true")] $
                        callActionWithParams (SaveDaysheetTextAction state.daysheet.id 0 Nothing) [("expectedRevision", "0"), ("enteredText", "After submission")]
                after `responseStatusShouldBe` status200
                Right latest <- Storage.readDailySheet member state.daysheet.id
                latest.daysheet.submittedAt `shouldBe` submitted.daysheet.submittedAt

        it "retains a deleted row's unsaved value for explicit discard without resurrection" $ withContext do
            withCleanDb do
                (venue, user, member) <- setup
                Right state <- Storage.createDailySheet member day
                Right _ <- Storage.addDailyRow member state.daysheet.id Fixture.band
                Right plan <- Storage.prepareDailyDeletion member state.daysheet.id Fixture.band
                Right _ <- Storage.deleteDailyRow member state.daysheet.id plan
                let ReferenceKey _ (E.RowId row) = Fixture.band
                    action = SaveDaysheetTextAction state.daysheet.id 4 (Just (tshow row))
                forM_ [[], [("HX-Request", "true")]] \headers -> do
                    response <- withPasskeyVerifiedUserAndCurrentVenue user venue.id $
                        withRequestHeaders headers $
                            callActionWithParams action [("expectedRevision", "0"), ("enteredText", "Keep this unsaved note")]
                    response `responseStatusShouldBe` status200
                    response `responseBodyShouldContain` "Keep this unsaved note"
                    response `responseBodyShouldContain` "Discard this unsaved value"
                    response `responseBodyShouldContain` "aria-invalid=\"true\""
                    lookup "X-Bepis-Form-Saved" (responseHeaders response) `shouldBe` Nothing
                discarded <- withPasskeyVerifiedUserAndCurrentVenue user venue.id $
                    withRequestHeaders [("HX-Request", "true")] $
                        callActionWithQueryParams (KeepSavedDaysheetCellAction state.daysheet.id 4 (Just (tshow row))) []
                discarded `responseStatusShouldBe` status200
                discarded `responseBodyShouldNotContain` "aria-invalid"
                Right retained <- Storage.readDailySheet member state.daysheet.id
                Daily.rowKeys retained.content `shouldSatisfy` notElem Fixture.band

        it "requires a refreshed deletion confirmation after target edits" $ withContext do
            withCleanDb do
                (venue, user, member) <- setup
                Right state <- Storage.createDailySheet member day
                Right added <- Storage.addDailyRow member state.daysheet.id Fixture.band
                Right plan <- Storage.prepareDailyDeletion member state.daysheet.id Fixture.band
                let owner = E.SnapshotKey member.venueId (unpackId state.daysheet.id)
                    token = renderNominalText (deletionToken owner plan)
                    ReferenceKey (D.ListId source) (E.RowId row) = Fixture.band
                Right _ <- Storage.editDailyCell member state.daysheet.id (Daily.RowCell Fixture.band (Fixture.field 4)) 0 (Fixture.text "Changed band")
                response <- withPasskeyVerifiedUserAndCurrentVenue user venue.id $
                    withRequestHeaders [("HX-Request", "true")] $
                        callActionWithParams (DeleteDaysheetRowAction added.daysheet.id source row) [("confirmation", cs token)]
                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Review a fresh deletion confirmation"
                response `responseBodyShouldContain` "Changed band"
                Right retained <- Storage.readDailySheet member state.daysheet.id
                Daily.rowKeys retained.content `shouldSatisfy` elem Fixture.band
