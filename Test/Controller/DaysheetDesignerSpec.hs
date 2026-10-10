module Test.Controller.DaysheetDesignerSpec where

import Application.Daysheet.Authority (memberAccess)
import qualified Application.Daysheet.Contract as D
import qualified Application.Daysheet.Designer.Calculation as Calculation
import Application.Daysheet.Designer.Controls (CalculationGroup (..))
import Application.Daysheet.DefinitionCodec (decodeDefinition)
import qualified Application.Daysheet.Storage as Storage
import qualified Application.Daysheet.References as References
import Application.Daysheet.Designer.ReferenceRetirement
import Application.Helper.NominalText (renderNominalText)
import qualified Application.Daysheet.Evaluation as E
import qualified Data.Aeson as Aeson
import qualified Data.Text as Text
import qualified Data.UUID as UUID
import Data.Data (toConstr)
import Data.Time.Calendar (fromGregorian)
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
            forM_ [ShowDesignerFieldAction Nothing Nothing, ShowDesignerFieldAction key Nothing, ShowDesignerFieldBodyAction key key, ShowDesignerListAction key, ShowDesignerReportAction key, ShowDesignerSectionAction key key, ShowDesignerBlockAction key uuid (Just "0") "table" key, ShowDesignerChoiceAction uuid key, ShowDesignerChoiceBodyAction uuid Nothing, ShowDesignerCalculationAction uuid Nothing "fields" Nothing, ShowDesignerCalculationBodyAction uuid (Just "right/left") "fields" (Just ("root/" <> tshow uuid)), ShowDesignerConstantAction uuid (Just "right")] \action -> do
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

        forM_ [False, True] \founderMode ->
          it ("stages and publishes the starter with member or founder authority: " <> cs (show founderMode)) $ withContext do
            withCleanDb do
                (venue, venueUser, member) <- setup
                user <- if founderMode then createUserRecordWithPlatformRole "designer-founder@example.test" "staff" (Just SuperAdmin) True else pure venueUser
                let post params = withPasskeyVerifiedUserAndCurrentVenue user venue.id $ withRequestHeaders [("HX-Request", "true")] $ callActionWithParams StageDesignerStarterAction params
                malformed <- post []
                malformed `responseStatusShouldBe` status400
                saved <- post [("expectedBase", "0")]
                saved `responseStatusShouldBe` status200
                lookup "X-Bepis-Form-Saved" (responseHeaders saved) `shouldBe` Just "true"
                Right initial <- Storage.readDesignerState (memberAccess member)
                forM_ ["Terminals", "POS readings", "Cash in / cash out"] \label ->
                    map D.listLabel (D.recordLists initial.designerDefinition) `shouldContain` [label]
                query @DaysheetDefinitionVersion |> fetchCount >>= (`shouldBe` 0)
                before <- query @LiveInvalidationEvent |> fetchCount
                repeated <- post [("expectedBase", "0")]
                lookup "X-Bepis-Form-Saved" (responseHeaders repeated) `shouldBe` Nothing
                query @LiveInvalidationEvent |> fetchCount >>= (`shouldBe` before)
                Right unchanged <- Storage.readDesignerState (memberAccess member)
                unchanged.designerDefinition `shouldBe` initial.designerDefinition
                published <- withPasskeyVerifiedUserAndCurrentVenue user venue.id $ callActionWithParams PublishDesignerDraftAction [("expectedBase", "0"), ("expectedDraft", "0")]
                responseStatus published `shouldSatisfy` (`elem` [status200, status302, status303])
                query @DaysheetDefinitionVersion |> fetchCount >>= (`shouldBe` 1)
                version <- query @DaysheetDefinitionVersion |> fetchOne
                version.publishedBy `shouldBe` unpackId user.id
                when founderMode do
                    query @VenueMembership |> filterWhere (#userId, unpackId user.id) |> fetchCount >>= (`shouldBe` 0)
                    event <- query @AuditEvent |> filterWhere (#eventType, "daysheet_definition_published") |> fetchOne
                    event.actorUserId `shouldBe` unpackId user.id
                    event.payload `shouldBe` Aeson.object ["version" Aeson..= (1 :: Int), "requestContext" Aeson..= Aeson.object ["accessMode" Aeson..= ("support" :: Text)]]
                replacement <- post [("expectedBase", "1")]
                lookup "X-Bepis-Form-Saved" (responseHeaders replacement) `shouldBe` Nothing

        forM_ [False, True] \enhanced ->
          it ("resolves dependent reference retirement atomically with retained failures: " <> if enhanced then "enhanced" else "native") $ withContext do
            withCleanDb do
                (venue, user, member) <- setup
                let D.ListId sourceId = Fixture.list 10
                    E.RowId rowId = Fixture.row 1
                    target = References.ReferenceKey (Fixture.list 10) (Fixture.row 1)
                    replacement = References.ReferenceKey (Fixture.list 10) (Fixture.row 3)
                    dependent = References.ReferenceKey (Fixture.list 50) (Fixture.row 60)
                    definition = Fixture.definition { D.recordLists = D.recordLists Fixture.definition <> [D.RecordList (Fixture.list 50) "Counters" D.VenueReference [D.Field (Fixture.field 51) "Terminal" (D.ReferenceType (Fixture.list 10)) D.Entered]] }
                    references = References.ReferenceData
                        [ References.ReferenceList (Fixture.list 10) [References.ReferenceRecord (Fixture.row n) False [(Fixture.field 9, References.ReferenceScalar (D.TextLiteral ("Terminal " <> tshow n)))] | n <- [1, 3, 4]]
                        , References.ReferenceList (Fixture.list 50) [References.ReferenceRecord (Fixture.row 60) False [(Fixture.field 51, References.ReferenceLink target)]] ]
                    choice = renderNominalText (ResolveReference (References.ReassignReference dependent (Fixture.field 51) replacement))
                    params = [("expectedBase", "0"), ("expectedDraft", "0"), ("definitionListId", cs (tshow sourceId)), ("referenceRecordId", cs (tshow rowId))]
                    post values = withPasskeyVerifiedUserAndCurrentVenue user venue.id $ withRequestHeaders (if enhanced then [("HX-Request", "true")] else []) $ callActionWithParams RetireDesignerReferenceAction values
                Right _ <- Storage.saveDraft (memberAccess member) 0 Nothing definition references
                shown <- withPasskeyVerifiedUserAndCurrentVenue user venue.id $ callActionWithQueryParams (ShowDesignerReferenceRetirementAction sourceId rowId) []
                shown `responseStatusShouldBe` status200
                shown `responseBodyShouldContain` "Retire with these resolutions"
                shown `responseBodyShouldContain` "referenceResolutions"
                before <- query @LiveInvalidationEvent |> fetchCount
                unresolved <- post params
                lookup "X-Bepis-Form-Saved" (responseHeaders unresolved) `shouldBe` Nothing
                Right unchanged <- Storage.readDesignerState (memberAccess member)
                unchanged.designerReferences `shouldBe` references
                query @LiveInvalidationEvent |> fetchCount >>= (`shouldBe` before)
                forged <- post (("referenceResolutions", cs (renderNominalText (ResolveReference (References.RetireReference replacement)))) : params)
                lookup "X-Bepis-Form-Saved" (responseHeaders forged) `shouldBe` Nothing
                conflicting <- post (("referenceResolutions", cs choice) : ("referenceResolutions", cs (renderNominalText (ResolveReference (References.ReassignReference dependent (Fixture.field 51) (References.ReferenceKey (Fixture.list 10) (Fixture.row 4)))))) : params)
                lookup "X-Bepis-Form-Saved" (responseHeaders conflicting) `shouldBe` Nothing
                malformed <- post (("referenceResolutions", "{\"resolution\":[\"unknown\"]}") : params)
                malformed `responseStatusShouldBe` status400
                stale <- post (("referenceResolutions", cs choice) : filter ((/= "expectedDraft") . fst) params)
                lookup "X-Bepis-Form-Saved" (responseHeaders stale) `shouldBe` Nothing
                query @LiveInvalidationEvent |> fetchCount >>= (`shouldBe` before)
                Right afterRejected <- Storage.readDesignerState (memberAccess member)
                afterRejected.designerReferences `shouldBe` references
                saved <- post (("referenceResolutions", cs choice) : params)
                lookup "X-Bepis-Form-Saved" (responseHeaders saved) `shouldBe` Just "true"
                Right changed <- Storage.readDesignerState (memberAccess member)
                Right expected <- pure (References.retireReferences definition Fixture.owner references target [References.ReassignReference dependent (Fixture.field 51) replacement])
                changed.designerReferences `shouldBe` expected
                query @LiveInvalidationEvent |> fetchCount >>= (`shouldBe` before + 1)

        it "creates typed fields with durable invalidation and requires explicit publication" $ withContext do
            withCleanDb do
                (venue, user, member) <- setup
                before <- query @LiveInvalidationEvent |> fetchCount
                saved <- withPasskeyVerifiedUserAndCurrentVenue user venue.id $ withRequestHeaders [("HX-Request", "true")] $
                    callActionWithParams SaveDesignerFieldAction [("expectedBase", "0"), ("label", "Closing notes"), ("valueKind", "text")]
                saved `responseStatusShouldBe` status200
                lookup "X-Bepis-Form-Saved" (responseHeaders saved) `shouldBe` Just "true"
                query @LiveInvalidationEvent |> fetchCount >>= (`shouldBe` before + 1)
                Right state <- Storage.readDesignerState (memberAccess member)
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
                Right _ <- Storage.saveDraft (memberAccess member) 0 Nothing Fixture.definition Fixture.references
                before <- query @LiveInvalidationEvent |> fetchCount
                response <- withPasskeyVerifiedUserAndCurrentVenue user venue.id $
                    callActionWithParams SaveDesignerFieldAction [("expectedBase", "0"), ("label", "Unsaved local name"), ("valueKind", "text")]
                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Unsaved local name"
                response `responseBodyShouldContain` "aria-invalid=\"true\""
                lookup "X-Bepis-Form-Saved" (responseHeaders response) `shouldBe` Nothing
                query @LiveInvalidationEvent |> fetchCount >>= (`shouldBe` before)
                Right state <- Storage.readDesignerState (memberAccess member)
                state.designerDefinition `shouldBe` Fixture.definition

        it "rejects dependency-breaking field changes without modifying publication" $ withContext do
            withCleanDb do
                (venue, user, member) <- setup
                Right _ <- Storage.saveDraft (memberAccess member) 0 Nothing Fixture.definition Fixture.references
                Right version <- Storage.publishDraft (memberAccess member) 0 0
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
                Right _ <- Storage.saveDraft (memberAccess member) 0 Nothing Fixture.definition Fixture.references
                Right _ <- Storage.publishDraft (memberAccess member) 0 0
                Right captured <- Storage.captureDefinition (memberAccess member) (fromGregorian 2026 10 1)
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
                Right _ <- Storage.publishDraft (memberAccess member) 1 1
                Right fresh <- Storage.captureDefinition (memberAccess member) (fromGregorian 2026 10 2)
                fresh.referenceData `shouldNotBe` captured.referenceData
                unchanged <- fetch captured.id
                unchanged.referenceData `shouldBe` captured.referenceData

        it "builds independent report layouts with repeated typed column parameters and rejects invalid sorting" $ withContext do
            withCleanDb do
                (venue, user, member) <- setup
                Right _ <- Storage.saveDraft (memberAccess member) 0 Nothing Fixture.entryDefinition Fixture.entryReferences
                let post action params = withPasskeyVerifiedUserAndCurrentVenue user venue.id $ withRequestHeaders [("HX-Request", "true")] $ callActionWithParams action params
                nul <- post SaveDesignerReportAction [("expectedBase", "0"), ("expectedDraft", "0"), ("label", "Bad\NULname"), ("targets", "formatted-and-excel")]
                nul `responseStatusShouldBe` status200
                lookup "X-Bepis-Form-Saved" (responseHeaders nul) `shouldBe` Nothing
                created <- post SaveDesignerReportAction [("expectedBase", "0"), ("expectedDraft", "0"), ("label", "Closing report"), ("targets", "formatted-and-excel")]
                lookup "X-Bepis-Form-Saved" (responseHeaders created) `shouldBe` Just "true"
                Right reportState <- Storage.readDesignerState (memberAccess member)
                [D.Report (D.ReportId reportId) _ [] _] <- pure (D.reports reportState.designerDefinition)
                section <- post SaveDesignerSectionAction [("expectedBase", "0"), ("expectedDraft", "1"), ("definitionReportId", cs (tshow reportId)), ("label", "Receipts summary")]
                lookup "X-Bepis-Form-Saved" (responseHeaders section) `shouldBe` Just "true"
                Right sectionState <- Storage.readDesignerState (memberAccess member)
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
                Right final <- Storage.readDesignerState (memberAccess member)
                D.entryLayout final.designerDefinition `shouldBe` D.entryLayout Fixture.entryDefinition
                D.reports final.designerDefinition `shouldBe`
                    [D.Report (D.ReportId reportId) "Closing report" [D.Section (D.SectionId sectionId) "Receipts summary"
                        [D.TableBlock (Fixture.list 20) [Fixture.field 7, Fixture.field 8] (Just (Fixture.field 7)) [(Fixture.field 8, D.Descending)]]] [D.FormattedReport, D.ExcelDownload]]

        it "adds, renames and reorders choice options with exact revisions and immutable earlier captures" $ withContext do
            withCleanDb do
                (venue, user, member) <- setup
                Right _ <- Storage.saveDraft (memberAccess member) 0 Nothing Fixture.entryDefinition Fixture.entryReferences
                let post action params = withPasskeyVerifiedUserAndCurrentVenue user venue.id $ withRequestHeaders [("HX-Request", "true")] $ callActionWithParams action params
                added <- post SaveDesignerFieldAction [("expectedBase", "0"), ("expectedDraft", "0"), ("label", "Category"), ("valueKind", "choice"), ("initialChoice", "Sale")]
                lookup "X-Bepis-Form-Saved" (responseHeaders added) `shouldBe` Just "true"
                Right initial <- Storage.readDesignerState (memberAccess member)
                Just field <- pure (find ((== "Category") . D.fieldLabel) (D.rootFields initial.designerDefinition))
                let D.FieldId fieldId = D.fieldId field
                D.ChoiceType [D.Choice (D.ChoiceId first) _] <- pure (D.fieldType field)
                Right original <- Storage.publishDraft (memberAccess member) 0 1
                Right captured <- Storage.captureDefinition (memberAccess member) (fromGregorian 2026 10 1)
                option <- post SaveDesignerChoiceAction [("expectedBase", "1"), ("definitionFieldId", cs (tshow fieldId)), ("label", "Expense")]
                lookup "X-Bepis-Form-Saved" (responseHeaders option) `shouldBe` Just "true"
                Right options <- Storage.readDesignerState (memberAccess member)
                [D.Choice _ _, D.Choice (D.ChoiceId second) _] <- pure [choice | value <- D.rootFields options.designerDefinition, D.fieldId value == D.fieldId field, D.ChoiceType choices <- [D.fieldType value], choice <- choices]
                let base = [("expectedBase", "1"), ("definitionFieldId", cs (tshow fieldId))]
                renamed <- post SaveDesignerChoiceAction (base <> [("expectedDraft", "0"), ("definitionChoiceId", cs (tshow first)), ("label", "Customer payment")])
                lookup "X-Bepis-Form-Saved" (responseHeaders renamed) `shouldBe` Just "true"
                moved <- post MoveDesignerChoiceAction (base <> [("expectedDraft", "1"), ("definitionChoiceId", cs (tshow second)), ("toPosition", "0")])
                lookup "HX-Trigger" (responseHeaders moved) `shouldSatisfy` isJust
                Right final <- Storage.readDesignerState (memberAccess member)
                D.fieldType <$> find ((== D.fieldId field) . D.fieldId) (D.rootFields final.designerDefinition)
                    `shouldBe` Just (D.ChoiceType [D.Choice (D.ChoiceId second) "Expense", D.Choice (D.ChoiceId first) "Customer payment"])
                before <- query @LiveInvalidationEvent |> fetchCount
                stale <- withPasskeyVerifiedUserAndCurrentVenue user venue.id $ callActionWithParams SaveDesignerChoiceAction
                    (base <> [("expectedDraft", "0"), ("definitionChoiceId", cs (tshow first)), ("label", "Unsaved option spelling")])
                stale `responseBodyShouldContain` "Unsaved option spelling"
                lookup "X-Bepis-Form-Saved" (responseHeaders stale) `shouldBe` Nothing
                query @LiveInvalidationEvent |> fetchCount >>= (`shouldBe` before)
                Right published <- Storage.publishDraft (memberAccess member) 1 2
                published.id `shouldNotBe` original.id
                retained <- fetch captured.id
                retained.definitionVersionId `shouldBe` unpackId original.id
                unchanged <- fetch original.id
                unchanged.definition `shouldBe` original.definition

        it "uses canonical menu choices and closed nested locations with revision-safe constants" $ withContext do
            withCleanDb do
                (venue, user, member) <- setup
                Right _ <- Storage.saveDraft (memberAccess member) 0 Nothing Fixture.entryDefinition Fixture.entryReferences
                Right menu <- pure (Calculation.calculationMenu OperationParts (Fixture.field 2) [] Nothing Fixture.entryDefinition)
                Just (index, _) <- pure (find ((== "Add — Whole number / Whole number") . Calculation.calculationOptionLabel . snd) (zip [0 :: Int ..] (Calculation.calculationMenuOptions menu)))
                let post action params = withPasskeyVerifiedUserAndCurrentVenue user venue.id $ withRequestHeaders [("HX-Request", "true")] $ callActionWithParams action params
                    base = [("expectedBase", "0"), ("definitionFieldId", "00000000-0000-0000-0000-000000000002")]
                    operation = [("calculationGroup", "operations"), ("candidateIndex", cs (tshow index))]
                saved <- post UseDesignerCalculationPartAction (base <> [("expectedDraft", "0")] <> operation)
                lookup "HX-Trigger" (responseHeaders saved) `shouldSatisfy` isJust
                constant <- post SaveDesignerConstantAction (base <> [("expectedDraft", "1"), ("expressionSlots", "right"), ("enteredValue", "2")])
                lookup "X-Bepis-Form-Saved" (responseHeaders constant) `shouldBe` Just "true"
                Right state <- Storage.readDesignerState (memberAccess member)
                D.fieldSource <$> find ((== Fixture.field 2) . D.fieldId) (D.rootFields state.designerDefinition)
                    `shouldBe` Just (D.Calculated (D.Binary D.Add (D.Constant (D.WholeLiteral 0)) (D.Constant (D.WholeLiteral 2))))
                before <- query @LiveInvalidationEvent |> fetchCount
                invalid <- post SaveDesignerConstantAction (base <> [("expectedDraft", "2"), ("expressionSlots", "right"), ("enteredValue", "2.5")])
                lookup "X-Bepis-Form-Saved" (responseHeaders invalid) `shouldBe` Nothing
                stale <- post UseDesignerCalculationPartAction (base <> [("expectedDraft", "0")] <> operation)
                lookup "X-Bepis-Form-Saved" (responseHeaders stale) `shouldBe` Nothing
                forged <- post UseDesignerCalculationPartAction (base <> [("expectedDraft", "2"), ("calculationGroup", "fields"), ("candidateIndex", "99999")])
                lookup "X-Bepis-Form-Saved" (responseHeaders forged) `shouldBe` Nothing
                malformed <- post SaveDesignerConstantAction (base <> [("expectedDraft", "2"), ("expressionSlots", "eval"), ("enteredValue", "2")])
                malformed `responseStatusShouldBe` status400
                query @LiveInvalidationEvent |> fetchCount >>= (`shouldBe` before)
                entered <- post MakeDesignerFieldEnteredAction (base <> [("expectedDraft", "2")])
                lookup "X-Bepis-Form-Saved" (responseHeaders entered) `shouldBe` Just "true"
                failed <- withPasskeyVerifiedUserAndCurrentVenue user venue.id $ callActionWithParams SaveDesignerConstantAction
                    (base <> [("expectedDraft", "2"), ("enteredValue", "007")])
                failed `responseBodyShouldContain` ">007</textarea>"
                lookup "X-Bepis-Form-Saved" (responseHeaders failed) `shouldBe` Nothing

        it "denies managers and workers on pages, fragments and direct mutations" $ withContext do
            withCleanDb do
                (venue, user, member) <- setup
                forM_ [Manager, Worker] \role -> do
                    _ <- member |> set #venueRole role |> updateRecord
                    forM_ [DaysheetDesignerAction, ShowDesignerIndexBodyAction, ShowDesignerReferenceRetirementAction UUID.nil UUID.nil, ShowDesignerReferenceRetirementBodyAction UUID.nil UUID.nil, ShowDesignerFieldBodyAction Nothing Nothing, ShowDesignerReportBodyAction Nothing, ShowDesignerSectionBodyAction Nothing Nothing, ShowDesignerChoiceBodyAction (UUID.fromWords 0 0 0 1) Nothing, ShowDesignerCalculationBodyAction (UUID.fromWords 0 0 0 1) Nothing "fields" Nothing, ShowDesignerConstantBodyAction (UUID.fromWords 0 0 0 1) Nothing] \action -> do
                        response <- withPasskeyVerifiedUserAndCurrentVenue user venue.id $ callActionWithQueryParams action []
                        responseStatus response `shouldSatisfy` (`elem` [status302, status303, status403])
                    response <- withPasskeyVerifiedUserAndCurrentVenue user venue.id $
                        callActionWithParams SaveDesignerFieldAction [("expectedBase", "0"), ("label", "Forged"), ("valueKind", "text")]
                    responseStatus response `shouldSatisfy` (`elem` [status302, status303, status403])
                    reference <- withPasskeyVerifiedUserAndCurrentVenue user venue.id $
                        callActionWithParams AddDesignerReferenceAction [("expectedBase", "0"), ("definitionListId", cs (tshow UUID.nil))]
                    responseStatus reference `shouldSatisfy` (`elem` [status302, status303, status403])
                    report <- withPasskeyVerifiedUserAndCurrentVenue user venue.id $
                        callActionWithParams SaveDesignerReportAction [("expectedBase", "0"), ("label", "Forged report"), ("targets", "formatted")]
                    responseStatus report `shouldSatisfy` (`elem` [status302, status303, status403])
                    forM_ [StageDesignerStarterAction, RetireDesignerReferenceAction, SaveDesignerChoiceAction, RemoveDesignerChoiceAction, MoveDesignerChoiceAction, UseDesignerCalculationPartAction, SaveDesignerConstantAction, MakeDesignerFieldEnteredAction] \action -> do
                        choice <- withPasskeyVerifiedUserAndCurrentVenue user venue.id $ callActionWithParams action
                            [("expectedBase", "0"), ("definitionFieldId", "00000000-0000-0000-0000-000000000001"), ("definitionChoiceId", "00000000-0000-0000-0000-000000000002"), ("label", "Forged option"), ("toPosition", "0"), ("calculationGroup", "values"), ("candidateIndex", "0"), ("enteredValue", "2")]
                        responseStatus choice `shouldSatisfy` (`elem` [status302, status303, status403])
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
