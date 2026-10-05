module Test.Controller.DaysheetDesignerSpec where

import qualified Application.Daysheet.Contract as D
import Application.Daysheet.DefinitionCodec (decodeDefinition)
import qualified Application.Daysheet.Storage as Storage
import qualified Application.Daysheet.Evaluation as E
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
            let uuid = UUID.fromWords 0 0 0 1
                key = Just (tshow uuid)
            forM_ [ShowDesignerFieldAction Nothing Nothing, ShowDesignerFieldAction key Nothing, ShowDesignerFieldBodyAction key key, ShowDesignerListAction key, ShowDesignerReportAction key, ShowDesignerSectionAction key key, ShowDesignerBlockAction key uuid (Just "0") "table" key] \action -> do
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
                lookup "HX-Redirect" (responseHeaders published) `shouldBe` Nothing
                lookup "HX-Reswap" (responseHeaders published) `shouldBe` Just "none"
                lookup "HX-Trigger" (responseHeaders published) `shouldSatisfy` isJust
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

        it "stages reference edits and retirement without rewriting an existing capture" $ withContext do
            withCleanDb do
                (venue, user, member) <- setup
                Right _ <- Storage.saveDraft member 0 Nothing Fixture.definition Fixture.references
                Right _ <- Storage.publishDraft member 0 0
                Right captured <- Storage.captureDefinition member (fromGregorian 2026 10 1)
                let D.ListId source = Fixture.list 10
                    D.FieldId field = Fixture.field 9
                    E.RowId row = Fixture.row 1
                    E.RowId retired = Fixture.row 2
                    params key = [("expectedBase", "1"), ("definitionListId", cs (tshow source)), ("referenceRecordId", cs (tshow key)), ("definitionFieldId", cs (tshow field)), ("enteredValue", "Renamed terminal")]
                form <- withPasskeyVerifiedUserAndCurrentVenue user venue.id $ callActionWithQueryParams (ShowDesignerReferenceAction source row field) []
                form `responseStatusShouldBe` status200
                form `responseBodyShouldContain` "Preserved terminal"
                denied <- withPasskeyVerifiedUserAndCurrentVenue user venue.id $ withRequestHeaders [("HX-Request", "true")] $
                    callActionWithParams SaveDesignerReferenceValueAction (params retired)
                lookup "X-Bepis-Form-Saved" (responseHeaders denied) `shouldBe` Nothing
                query @DaysheetDefinitionDraft |> fetchCount >>= (`shouldBe` 0)
                saved <- withPasskeyVerifiedUserAndCurrentVenue user venue.id $ withRequestHeaders [("HX-Request", "true")] $
                    callActionWithParams SaveDesignerReferenceValueAction (params row)
                lookup "X-Bepis-Form-Saved" (responseHeaders saved) `shouldBe` Just "true"
                retirement <- withPasskeyVerifiedUserAndCurrentVenue user venue.id $ withRequestHeaders [("HX-Request", "true")] $
                    callActionWithParams RetireDesignerReferenceAction [("expectedBase", "1"), ("expectedDraft", "0"), ("definitionListId", cs (tshow source)), ("referenceRecordId", cs (tshow row))]
                lookup "X-Bepis-Form-Saved" (responseHeaders retirement) `shouldBe` Just "true"
                Right _ <- Storage.publishDraft member 1 1
                Right fresh <- Storage.captureDefinition member (fromGregorian 2026 10 2)
                fresh.referenceData `shouldNotBe` captured.referenceData
                unchanged <- fetch captured.id
                unchanged.referenceData `shouldBe` captured.referenceData

        it "builds independent report layouts with repeated typed column parameters and rejects invalid sorting" $ withContext do
            withCleanDb do
                (venue, user, member) <- setup
                Right _ <- Storage.saveDraft member 0 Nothing Fixture.entryDefinition Fixture.entryReferences
                let post action params = withPasskeyVerifiedUserAndCurrentVenue user venue.id $ withRequestHeaders [("HX-Request", "true")] $ callActionWithParams action params
                nul <- post SaveDesignerReportAction [("expectedBase", "0"), ("expectedDraft", "0"), ("label", "Bad\NULname"), ("targets", "formatted-and-excel")]
                nul `responseStatusShouldBe` status200
                lookup "X-Bepis-Form-Saved" (responseHeaders nul) `shouldBe` Nothing
                created <- post SaveDesignerReportAction [("expectedBase", "0"), ("expectedDraft", "0"), ("label", "Closing report"), ("targets", "formatted-and-excel")]
                lookup "X-Bepis-Form-Saved" (responseHeaders created) `shouldBe` Just "true"
                Right reportState <- Storage.readDesignerState member
                [D.Report (D.ReportId reportId) _ [] _] <- pure (D.reports reportState.designerDefinition)
                section <- post SaveDesignerSectionAction [("expectedBase", "0"), ("expectedDraft", "1"), ("definitionReportId", cs (tshow reportId)), ("label", "Receipts summary")]
                lookup "X-Bepis-Form-Saved" (responseHeaders section) `shouldBe` Just "true"
                Right sectionState <- Storage.readDesignerState member
                [D.Report _ _ [D.Section (D.SectionId sectionId) _ []] _] <- pure (D.reports sectionState.designerDefinition)
                let D.ListId source = Fixture.list 20
                    D.FieldId terminal = Fixture.field 7
                    D.FieldId amount = Fixture.field 8
                    params = [("expectedBase", "0"), ("expectedDraft", "2"), ("definitionReportId", cs (tshow reportId)), ("definitionSectionId", cs (tshow sectionId)), ("contentKind", "table"), ("definitionListId", cs (tshow source)), ("columnIds", cs (tshow terminal)), ("columnIds", cs (tshow amount)), ("groupingFieldId", cs (tshow terminal)), ("descendingFieldIds", cs (tshow amount))]
                before <- query @LiveInvalidationEvent |> fetchCount
                rejected <- post SaveDesignerBlockAction params
                lookup "X-Bepis-Form-Saved" (responseHeaders rejected) `shouldBe` Nothing
                query @LiveInvalidationEvent |> fetchCount >>= (`shouldBe` before)
                saved <- post SaveDesignerBlockAction (params <> [("sortingFieldIds", cs (tshow amount))])
                lookup "X-Bepis-Form-Saved" (responseHeaders saved) `shouldBe` Just "true"
                Right final <- Storage.readDesignerState member
                D.entryLayout final.designerDefinition `shouldBe` D.entryLayout Fixture.entryDefinition
                D.reports final.designerDefinition `shouldBe`
                    [D.Report (D.ReportId reportId) "Closing report" [D.Section (D.SectionId sectionId) "Receipts summary"
                        [D.TableBlock (Fixture.list 20) [Fixture.field 7, Fixture.field 8] (Just (Fixture.field 7)) [(Fixture.field 8, D.Descending)]]] [D.FormattedReport, D.ExcelDownload]]

        it "denies managers and workers on pages, fragments and direct mutations" $ withContext do
            withCleanDb do
                (venue, user, member) <- setup
                forM_ [Manager, Worker] \role -> do
                    _ <- member |> set #venueRole role |> updateRecord
                    forM_ [DaysheetDesignerAction, ShowDesignerIndexBodyAction, ShowDesignerFieldBodyAction Nothing Nothing, ShowDesignerReportBodyAction Nothing, ShowDesignerSectionBodyAction Nothing Nothing] \action -> do
                        response <- withPasskeyVerifiedUserAndCurrentVenue user venue.id $ callActionWithQueryParams action []
                        responseStatus response `shouldSatisfy` (/= status200)
                    response <- withPasskeyVerifiedUserAndCurrentVenue user venue.id $
                        callActionWithParams SaveDesignerFieldAction [("expectedBase", "0"), ("label", "Forged"), ("valueKind", "text")]
                    responseStatus response `shouldSatisfy` (/= status200)
                    reference <- withPasskeyVerifiedUserAndCurrentVenue user venue.id $
                        callActionWithParams AddDesignerReferenceAction [("expectedBase", "0"), ("definitionListId", cs (tshow UUID.nil))]
                    responseStatus reference `shouldSatisfy` (/= status200)
                    report <- withPasskeyVerifiedUserAndCurrentVenue user venue.id $
                        callActionWithParams SaveDesignerReportAction [("expectedBase", "0"), ("label", "Forged report"), ("targets", "formatted")]
                    responseStatus report `shouldSatisfy` (/= status200)
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
