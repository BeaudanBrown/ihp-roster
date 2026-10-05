module Test.Controller.DaysheetDesignerSpec where

import qualified Application.Daysheet.Contract as D
import Application.Daysheet.DefinitionCodec (decodeDefinition)
import qualified Application.Daysheet.Storage as Storage
import qualified Data.Text as Text
import qualified Data.UUID as UUID
import Data.Data (toConstr)
import Generated.Types
import IHP.ControllerPrelude
import IHP.Hspec
import qualified IHP.RouterSupport as Router
import IHP.Test.Mocking
import Network.HTTP.Types.Status
import Network.HTTP.Types.URI (parseQuery)
import Network.Wai (responseHeaders, responseStatus)
import qualified Test.Support.Daysheet as Fixture
import Test.Hspec
import Test.Support
import Web.Controller.DaysheetDesigner ()
import Web.FrontController ()
import Web.Types

setup :: (?modelContext :: ModelContext) => IO (Venue, User, VenueMembership)
setup = do
    venue <- createVenueWithConfig "Designer"
    user <- createUserRecord "designer-controller@example.test" "manager" True
    member <- createVenueMembershipRecord venue user VenueOwner
    pure (venue, user, member)

tests :: Spec
tests = aroundAll withDatabaseTestContext do
    describe "DaysheetDesignerController" do
        it "round-trips optional editor identities through the real router" $ withContext do
            let key = Just (tshow (UUID.fromWords 0 0 0 1))
            forM_ [ShowDesignerFieldAction Nothing Nothing, ShowDesignerFieldAction key Nothing, ShowDesignerFieldBodyAction key key, ShowDesignerListAction key] \action -> do
                let query = parseQuery (cs (Text.dropWhile (/= '?') (pathTo action)))
                either (const Nothing) Just (Router.applyAction @DaysheetDesignerController (toConstr action) query) `shouldBe` Just action

        it "reads the designer without creating configuration or draft records" $ withContext do
            withCleanDb do
                (venue, user, _) <- setup
                response <- withPasskeyVerifiedUserAndCurrentVenue user venue.id $ callActionWithQueryParams DaysheetDesignerAction []
                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Daysheet designer"
                response `responseBodyShouldContain` "No unpublished changes"
                query @DaysheetConfiguration |> fetchCount >>= (`shouldBe` 0)
                query @DaysheetDefinitionDraft |> fetchCount >>= (`shouldBe` 0)

        it "creates typed fields with durable invalidation and requires explicit publication" $ withContext do
            withCleanDb do
                (venue, user, member) <- setup
                before <- query @LiveInvalidationEvent |> fetchCount
                saved <- withPasskeyVerifiedUserAndCurrentVenue user venue.id $ withRequestHeaders [("HX-Request", "true")] $
                    callActionWithParams SaveDesignerFieldAction [("expectedBase", "0"), ("label", "Closing notes"), ("valueKind", "text")]
                saved `responseStatusShouldBe` status200
                lookup "X-Bepis-Form-Saved" (responseHeaders saved) `shouldBe` Just "true"
                query @LiveInvalidationEvent |> fetchCount >>= (`shouldBe` before + 1)
                Right state <- Storage.readDesignerState member
                map D.fieldLabel (D.rootFields state.designerDefinition) `shouldBe` ["Closing notes"]
                query @DaysheetDefinitionVersion |> fetchCount >>= (`shouldBe` 0)
                published <- withPasskeyVerifiedUserAndCurrentVenue user venue.id $ withRequestHeaders [("HX-Request", "true")] $
                    callActionWithParams PublishDesignerDraftAction [("expectedBase", "0"), ("expectedDraft", "0")]
                published `responseStatusShouldBe` status200
                query @DaysheetDefinitionVersion |> fetchCount >>= (`shouldBe` 1)
                query @LiveInvalidationEvent |> fetchCount >>= (`shouldBe` before + 2)

        it "retains native submitted labels on revision conflict and creates no invalidation" $ withContext do
            withCleanDb do
                (venue, user, member) <- setup
                Right _ <- Storage.saveDraft member 0 Nothing Fixture.definition Fixture.references
                before <- query @LiveInvalidationEvent |> fetchCount
                response <- withPasskeyVerifiedUserAndCurrentVenue user venue.id $
                    callActionWithParams SaveDesignerFieldAction [("expectedBase", "0"), ("label", "Unsaved local name"), ("valueKind", "text")]
                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Unsaved local name"
                response `responseBodyShouldContain` "aria-invalid=\"true\""
                lookup "X-Bepis-Form-Saved" (responseHeaders response) `shouldBe` Nothing
                query @LiveInvalidationEvent |> fetchCount >>= (`shouldBe` before)
                Right state <- Storage.readDesignerState member
                state.designerDefinition `shouldBe` Fixture.definition

        it "rejects dependency-breaking field changes without modifying publication" $ withContext do
            withCleanDb do
                (venue, user, member) <- setup
                Right _ <- Storage.saveDraft member 0 Nothing Fixture.definition Fixture.references
                Right version <- Storage.publishDraft member 0 0
                let D.FieldId key = Fixture.field 4
                response <- withPasskeyVerifiedUserAndCurrentVenue user venue.id $
                    callActionWithParams SaveDesignerFieldAction [("expectedBase", "1"), ("definitionFieldId", cs (tshow key)), ("label", "Bad numeric band"), ("valueKind", "whole")]
                response `responseBodyShouldContain` "Bad numeric band"
                query @DaysheetDefinitionDraft |> fetchCount >>= (`shouldBe` 0)
                unchanged <- fetch version.id
                decodeDefinition unchanged.definition `shouldBe` Right Fixture.definition

        it "denies managers and workers on pages, fragments and direct mutations" $ withContext do
            withCleanDb do
                (venue, user, member) <- setup
                forM_ [Manager, Worker] \role -> do
                    _ <- member |> set #venueRole role |> updateRecord
                    forM_ [DaysheetDesignerAction, ShowDesignerIndexBodyAction, ShowDesignerFieldBodyAction Nothing Nothing] \action -> do
                        response <- withPasskeyVerifiedUserAndCurrentVenue user venue.id $ callActionWithQueryParams action []
                        responseStatus response `shouldSatisfy` (/= status200)
                    response <- withPasskeyVerifiedUserAndCurrentVenue user venue.id $
                        callActionWithParams SaveDesignerFieldAction [("expectedBase", "0"), ("label", "Forged"), ("valueKind", "text")]
                    responseStatus response `shouldSatisfy` (/= status200)
                query @DaysheetDefinitionDraft |> fetchCount >>= (`shouldBe` 0)

        it "rejects malformed IDs, unknown control kinds and GET mutations" $ withContext do
            withCleanDb do
                (venue, user, _) <- setup
                malformed <- withPasskeyVerifiedUserAndCurrentVenue user venue.id $ callActionWithQueryParams (ShowDesignerFieldAction (Just "bad") Nothing) []
                malformed `responseStatusShouldBe` status400
                forged <- withPasskeyVerifiedUserAndCurrentVenue user venue.id $
                    callActionWithParams SaveDesignerFieldAction [("expectedBase", "0"), ("label", "Script"), ("valueKind", "javascript")]
                forged `responseStatusShouldBe` status400
                getMutation <- withPasskeyVerifiedUserAndCurrentVenue user venue.id $ callActionWithQueryParams PublishDesignerDraftAction []
                getMutation `responseStatusShouldBe` status405
                query @DaysheetDefinitionDraft |> fetchCount >>= (`shouldBe` 0)
