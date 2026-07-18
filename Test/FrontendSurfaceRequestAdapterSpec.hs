{-# LANGUAGE DataKinds        #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE ImplicitParams   #-}
{-# LANGUAGE TypeApplications #-}

module Test.FrontendSurfaceRequestAdapterSpec
    ( tests
    ) where

import Application.Helper.FrontendContract.Surface.ContractIR
import Application.Helper.FrontendContract.Surface.Contracts (registeredFrontendSurfaceContractIR)
import Application.Helper.FrontendContract.Surface.HaskellAdapter.Action
import Application.Helper.FrontendContract.Surface.HaskellAdapter.Core
import Application.Helper.FrontendContract.Surface.HaskellAdapter.Family
import Application.Helper.FrontendContract.Surface.HaskellAdapter.Intent
import Application.Helper.FrontendContract.Surface.HaskellAdapter.Registry (registeredSurfaceAdapterRegistry)
import qualified Application.Helper.FrontendContract.Surface.Interaction as SurfaceInteraction
import qualified Application.Helper.FrontendContract.Surface.Profile as Profile
import qualified Application.Helper.FrontendContract.Surface.Profile.Action as ProfileAction
import Application.Helper.FrontendContract.Surface.Reflect (reflectSurfaceRegistry)
import Application.Helper.FrontendContract.Surface.Request (SurfaceRequestFieldError (..),
                                                            SurfaceRequestFieldErrorKind (..),
                                                            parseSurfaceActionParamPairs)
import Application.Helper.FrontendContract.Surface.Request.Runtime (FrontendSurfaceHtmxMethod (..),
                                                                    FrontendSurfaceHtmxRequest (..),
                                                                    FrontendSurfaceIntentForm,
                                                                    intentFormName)
import qualified Application.Helper.FrontendContract.Surface.Roster as Roster
import qualified Application.Helper.FrontendContract.Surface.Roster.Intent as RosterIntent
import Application.Helper.FrontendContract.Surface.Runtime (FrontendSurfaceActionRoute (..),
                                                            FrontendSurfaceCustomHtmxAttrs (..),
                                                            frontendSurfaceActionHtmxAttrPairs,
                                                            renderFrontendSurfaceIntentForm)
import Application.Helper.FrontendContract.Surface.Values (SurfaceActionFields,
                                                           SurfaceFieldBundleOf,
                                                           surfaceFieldValue)
import qualified Data.ByteString as ByteString
import qualified Data.ByteString.Lazy as LBS
import qualified Data.List as List
import qualified Data.Text as Text
import qualified Data.Text.IO as Text
import Data.Time (fromGregorian)
import qualified Data.UUID as UUID
import qualified Data.Vault.Lazy as Vault
import Generated.Types (RosterDay, RosterGroup)
import IHP.ModelSupport.Types (Id' (Id))
import IHP.Prelude
import qualified Network.Wai as Wai
import Test.Hspec
import qualified Test.Support.FrontendSurfaceAdapterFixture as Fixture
import qualified Test.Support.FrontendSurfaceAdapterFixture.Action as FixtureAction
import qualified Test.Support.FrontendSurfaceAdapterFixture.Intent as FixtureIntent
import qualified Text.Blaze.Html.Renderer.Text as HtmlRenderer
import Wai.Request.Params.Middleware (RequestBody (FormBody),
                                      requestBodyVaultKey)
import Web.RosterWeeks.FrontendSurface (RosterDayTimelineScopeValue (..),
                                        RosterWeekScopeValue (..),
                                        rosterDayTimelineIntentForms,
                                        rosterIntentForms)
import Web.Staff.ProfileSurfaceRequest (StaffProfileDetailsSubmission (..),
                                        StaffProfileSurfaceSubmission (..),
                                        StaffShiftPreferencesSubmission (..),
                                        parseProfileSurfaceSubmission,
                                        parseStaffSurfaceSubmission)

tests :: Spec
tests = describe "FrontendSurfaceRequestAdapter" do
    it "renders the action fixture through the checked Action lane" do
        expected <- Text.readFile "Test/Support/FrontendSurfaceAdapterFixture/Generated/Action.hs"
        case generateSurfaceActionAdapterModules fixtureContract fixtureRegistry of
            Left diagnostics -> expectationFailure (cs (show diagnostics))
            Right [generated] -> do
                generated.generatedModuleName
                    `shouldBe` "Test.Support.FrontendSurfaceAdapterFixture.Generated.Action"
                generated.generatedModulePath
                    `shouldBe` "Test/Support/FrontendSurfaceAdapterFixture/Generated/Action.hs"
                generated.generatedModuleSource `shouldBe` expected
                generated.generatedModuleSource `shouldSatisfy` Text.isInfixOf "crossKindDeclarationActionFields"
                generated.generatedModuleSource `shouldSatisfy` Text.isInfixOf "crossKindDeclarationAction"
                generated.generatedModuleSource `shouldSatisfy` Text.isInfixOf "parseCrossKindDeclarationActionParams"
                generated.generatedModuleSource `shouldSatisfy` Text.isInfixOf "frontendSurfaceAction"
                generated.generatedModuleSource `shouldSatisfy` Text.isInfixOf "parseSurfaceActionParams"
                generated.generatedModuleSource
                    `shouldSatisfy` Text.isInfixOf "Application.Helper.FrontendContract.Surface.Request.Runtime"
                generated.generatedModuleSource
                    `shouldNotSatisfy` Text.isInfixOf "Application.Helper.FrontendContract.Surface.Runtime"
                generated.generatedModuleSource `shouldNotSatisfy` Text.isInfixOf ".Internal"
                generated.generatedModuleSource `shouldNotSatisfy` Text.isInfixOf "Aeson"
            Right generated -> expectationFailure (cs ("expected one generated Action module, got " <> tshow (length generated)))

    it "renders the intent fixture through the checked Intent lane" do
        expected <- Text.readFile "Test/Support/FrontendSurfaceAdapterFixture/Generated/Intent.hs"
        case generateSurfaceIntentAdapterModules fixtureContract fixtureRegistry of
            Left diagnostics -> expectationFailure (cs (show diagnostics))
            Right [generated] -> do
                generated.generatedModuleName
                    `shouldBe` "Test.Support.FrontendSurfaceAdapterFixture.Generated.Intent"
                generated.generatedModulePath
                    `shouldBe` "Test/Support/FrontendSurfaceAdapterFixture/Generated/Intent.hs"
                generated.generatedModuleSource `shouldBe` expected
                generated.generatedModuleSource `shouldSatisfy` Text.isInfixOf "crossKindDeclarationIntentFields"
                generated.generatedModuleSource `shouldSatisfy` Text.isInfixOf "crossKindDeclarationIntentForm"
                generated.generatedModuleSource `shouldSatisfy` Text.isInfixOf "parseCrossKindDeclarationIntentParams"
                generated.generatedModuleSource `shouldSatisfy` Text.isInfixOf "frontendSurfaceIntentForm"
                generated.generatedModuleSource `shouldSatisfy` Text.isInfixOf "parseSurfaceIntentParams"
                generated.generatedModuleSource
                    `shouldSatisfy` Text.isInfixOf "Application.Helper.FrontendContract.Surface.Request.Runtime"
                generated.generatedModuleSource
                    `shouldNotSatisfy` Text.isInfixOf "Application.Helper.FrontendContract.Surface.Runtime"
                generated.generatedModuleSource `shouldNotSatisfy` Text.isInfixOf ".Internal"
                generated.generatedModuleSource `shouldNotSatisfy` Text.isInfixOf "Aeson"
            Right generated -> expectationFailure (cs ("expected one generated Intent module, got " <> tshow (length generated)))

    it "executes the generated Intent facade builder, form metadata, and exact parser" do
        let memberId = fixtureMemberId "11111111-1111-1111-1111-111111111111"
        let archivedAt = fromGregorian 2026 7 15
        let fields =
                FixtureIntent.crossKindDeclarationIntentFields
                    "intent-fixture"
                    Nothing
                    (Just archivedAt)
                    [memberId]
                    (Just (Just "note"))
                    (Just [memberId])
                    False
                    [[memberId]]
        surfaceFieldValue @Fixture.Label fields `shouldBe` "intent-fixture"
        surfaceFieldValue @Fixture.MaybeNote fields `shouldBe` Just (Just "note")
        surfaceFieldValue @Fixture.NestedMemberIds fields `shouldBe` [[memberId]]
        let htmxRequest =
                FrontendSurfaceHtmxRequest
                    { htmxRequestMethod = FrontendSurfacePost
                    , htmxRequestUrl = "/fixture-intent"
                    , htmxRequestTarget = "#fixture"
                    , htmxRequestSwap = "none"
                    }
        intentFormName (FixtureIntent.crossKindDeclarationIntentForm fields htmxRequest)
            `shouldBe` "cross-kind-declaration"

        let ?request = requestWithParams
                [ ("label", Just "parsed-intent")
                , ("retryCount", Just "7")
                , ("archivedAt", Just "2026-07-15")
                , ("memberIds", Just "11111111-1111-1111-1111-111111111111")
                , ("maybeIds", Just "")
                , ("enabled", Just "false")
                , ("nestedMemberIds", Just "[[\"11111111-1111-1111-1111-111111111111\"]]")
                ]
        case FixtureIntent.parseCrossKindDeclarationIntentParams of
            Left errors -> expectationFailure (cs (show errors))
            Right parsed -> do
                surfaceFieldValue @Fixture.Label parsed `shouldBe` "parsed-intent"
                surfaceFieldValue @Fixture.RetryCount parsed `shouldBe` Just 7
                surfaceFieldValue @Fixture.ArchivedAt parsed `shouldBe` Just archivedAt
                surfaceFieldValue @Fixture.MemberIds parsed `shouldBe` [memberId]
                surfaceFieldValue @Fixture.MaybeNote parsed `shouldBe` Nothing
                surfaceFieldValue @Fixture.MaybeIds parsed `shouldBe` Nothing
                surfaceFieldValue @Fixture.Enabled parsed `shouldBe` False
                surfaceFieldValue @Fixture.NestedMemberIds parsed `shouldBe` [[memberId]]

    it "preserves structured missing and malformed errors through both generated parser adapters" do
        let ?request = requestWithParams []
        let expectedMissingNames = ["label", "archivedAt", "memberIds", "maybeIds", "enabled", "nestedMemberIds"]
        case FixtureAction.parseCrossKindDeclarationActionParams of
            Right _ -> expectationFailure "expected missing Action request fields"
            Left errors -> do
                map (.surfaceRequestFieldErrorName) errors `shouldBe` expectedMissingNames
                map (.surfaceRequestFieldErrorKind) errors
                    `shouldBe` replicate (length expectedMissingNames) MissingSurfaceRequestField
        case FixtureIntent.parseCrossKindDeclarationIntentParams of
            Right _ -> expectationFailure "expected missing Intent request fields"
            Left errors -> map (.surfaceRequestFieldErrorName) errors `shouldBe` expectedMissingNames

        let ?request = requestWithParams
                [ ("label", Just "valid")
                , ("retryCount", Just "not-an-int")
                , ("archivedAt", Just "not-a-day")
                , ("memberIds", Just "not-a-uuid")
                , ("maybeNote", Just "valid")
                , ("maybeIds", Just "not-a-uuid")
                , ("enabled", Just "perhaps")
                , ("nestedMemberIds", Just "[[\"not-a-uuid\"]]")
                ]
        let expectedMalformedNames = ["retryCount", "archivedAt", "memberIds", "maybeIds", "enabled", "nestedMemberIds"]
        case FixtureAction.parseCrossKindDeclarationActionParams of
            Right _ -> expectationFailure "expected malformed Action request fields"
            Left errors -> do
                map (.surfaceRequestFieldErrorName) errors `shouldBe` expectedMalformedNames
                map (.surfaceRequestFieldErrorKind) errors
                    `shouldBe` replicate (length expectedMalformedNames) MalformedSurfaceRequestField
        case FixtureIntent.parseCrossKindDeclarationIntentParams of
            Right _ -> expectationFailure "expected malformed Intent request fields"
            Left errors -> do
                map (.surfaceRequestFieldErrorName) errors `shouldBe` expectedMalformedNames
                map (.surfaceRequestFieldErrorKind) errors
                    `shouldBe` replicate (length expectedMalformedNames) MalformedSurfaceRequestField

    it "executes the generated Action facade builder, metadata, and exact parser" do
        let memberId = fixtureMemberId "11111111-1111-1111-1111-111111111111"
        let otherMemberId = fixtureMemberId "22222222-2222-2222-2222-222222222222"
        let archivedAt = fromGregorian 2026 7 15
        let fields =
                FixtureAction.crossKindDeclarationActionFields
                    "fixture"
                    (Just 2)
                    (Just archivedAt)
                    [memberId]
                    (Just Nothing)
                    (Just [otherMemberId])
                    True
                    [[memberId], [otherMemberId, memberId]]
        surfaceFieldValue @Fixture.Label fields `shouldBe` "fixture"
        surfaceFieldValue @Fixture.RetryCount fields `shouldBe` Just 2
        surfaceFieldValue @Fixture.ArchivedAt fields `shouldBe` Just archivedAt
        surfaceFieldValue @Fixture.MemberIds fields `shouldBe` [memberId]
        surfaceFieldValue @Fixture.MaybeNote fields `shouldBe` Just Nothing
        surfaceFieldValue @Fixture.MaybeIds fields `shouldBe` Just [otherMemberId]
        surfaceFieldValue @Fixture.Enabled fields `shouldBe` True
        surfaceFieldValue @Fixture.NestedMemberIds fields
            `shouldBe` [[memberId], [otherMemberId, memberId]]

        let route = emptyActionRoute "/fixture"
        lookup "data-bepis-surface-action"
            (frontendSurfaceActionHtmxAttrPairs (FixtureAction.crossKindDeclarationAction fields) route)
            `shouldBe` Just "cross-kind-declaration"

        let ?request = requestWithParams
                [ ("label", Just "parsed")
                , ("archivedAt", Just "")
                , ("memberIds", Just "11111111-1111-1111-1111-111111111111")
                , ("memberIds", Just "22222222-2222-2222-2222-222222222222")
                , ("maybeNote", Just "note")
                , ("maybeIds", Just "11111111-1111-1111-1111-111111111111")
                , ("enabled", Just "on")
                , ("nestedMemberIds", Just "[[\"11111111-1111-1111-1111-111111111111\"],[\"22222222-2222-2222-2222-222222222222\",\"11111111-1111-1111-1111-111111111111\"]]")
                , ("unrelated-route-context", Just "preserved")
                ]
        case FixtureAction.parseCrossKindDeclarationActionParams of
            Left errors -> expectationFailure (cs (show errors))
            Right parsed -> do
                surfaceFieldValue @Fixture.Label parsed `shouldBe` "parsed"
                surfaceFieldValue @Fixture.RetryCount parsed `shouldBe` Nothing
                surfaceFieldValue @Fixture.ArchivedAt parsed `shouldBe` Nothing
                surfaceFieldValue @Fixture.MemberIds parsed `shouldBe` [memberId, otherMemberId]
                surfaceFieldValue @Fixture.MaybeNote parsed `shouldBe` Just (Just "note")
                surfaceFieldValue @Fixture.MaybeIds parsed `shouldBe` Just [memberId]
                surfaceFieldValue @Fixture.Enabled parsed `shouldBe` True
                surfaceFieldValue @Fixture.NestedMemberIds parsed
                    `shouldBe` [[memberId], [otherMemberId, memberId]]

    it "emits only inventoried Action and Intent operations and requires exclusion reasons" do
        let builderOnlyOperations =
                SurfaceRequestAdapterOperations
                    { surfaceAdapterFieldsBuilderOperation = GenerateSurfaceAdapterOperation
                    , surfaceAdapterRenderMetadataOperation = ExcludeSurfaceAdapterOperation "No metadata consumer in this fixture variant"
                    , surfaceAdapterRequestParserOperation = ExcludeSurfaceAdapterOperation "No parser consumer in this fixture variant"
                    }
        let builderOnlyActionRegistry =
                fixtureRegistry
                    { surfaceActionAdapterRegistrations =
                        [ surfaceActionAdapter
                            @Fixture.AdapterFixtureFamily
                            @Fixture.CrossKindDeclaration
                            builderOnlyOperations
                        ]
                    }
        case generateSurfaceActionAdapterModules fixtureContract builderOnlyActionRegistry of
            Left diagnostics -> expectationFailure (cs (show diagnostics))
            Right [generated] -> do
                generated.generatedModuleSource `shouldSatisfy` Text.isInfixOf "crossKindDeclarationActionFields"
                generated.generatedModuleSource `shouldNotSatisfy` Text.isInfixOf "crossKindDeclarationAction ::"
                generated.generatedModuleSource `shouldNotSatisfy` Text.isInfixOf "parseCrossKindDeclarationActionParams"
                generated.generatedModuleSource `shouldNotSatisfy` Text.isInfixOf "frontendSurfaceAction"
                generated.generatedModuleSource `shouldNotSatisfy` Text.isInfixOf "parseSurfaceActionParams"
            Right generated -> expectationFailure (cs ("expected one builder-only Action module, got " <> tshow (length generated)))

        let metadataOnlyOperations =
                SurfaceRequestAdapterOperations
                    { surfaceAdapterFieldsBuilderOperation = ExcludeSurfaceAdapterOperation "No builder consumer in this fixture variant"
                    , surfaceAdapterRenderMetadataOperation = GenerateSurfaceAdapterOperation
                    , surfaceAdapterRequestParserOperation = ExcludeSurfaceAdapterOperation "No parser consumer in this fixture variant"
                    }
        let metadataOnlyIntentRegistry =
                fixtureRegistry
                    { surfaceIntentAdapterRegistrations =
                        [ surfaceIntentAdapter
                            @Fixture.AdapterFixtureFamily
                            @Fixture.CrossKindDeclaration
                            metadataOnlyOperations
                        ]
                    }
        case generateSurfaceIntentAdapterModules fixtureContract metadataOnlyIntentRegistry of
            Left diagnostics -> expectationFailure (cs (show diagnostics))
            Right [generated] -> do
                generated.generatedModuleSource `shouldSatisfy` Text.isInfixOf "crossKindDeclarationIntentForm"
                generated.generatedModuleSource `shouldNotSatisfy` Text.isInfixOf "crossKindDeclarationIntentFields"
                generated.generatedModuleSource `shouldNotSatisfy` Text.isInfixOf "parseCrossKindDeclarationIntentParams"
                generated.generatedModuleSource `shouldNotSatisfy` Text.isInfixOf "surfaceField"
                generated.generatedModuleSource `shouldNotSatisfy` Text.isInfixOf "parseSurfaceIntentParams"
            Right generated -> expectationFailure (cs ("expected one metadata-only Intent module, got " <> tshow (length generated)))

        let blankOperationReason =
                builderOnlyOperations
                    { surfaceAdapterRenderMetadataOperation = ExcludeSurfaceAdapterOperation ""
                    }
        let blankOperationRegistry =
                fixtureRegistry
                    { surfaceActionAdapterRegistrations =
                        [ surfaceActionAdapter
                            @Fixture.AdapterFixtureFamily
                            @Fixture.CrossKindDeclaration
                            blankOperationReason
                        ]
                    }
        diagnosticCodes (generateSurfaceActionAdapterModules fixtureContract blankOperationRegistry)
            `shouldContain` ["adapter-action-operation-exclusion-reason"]

        let blankDeclarationRegistry =
                fixtureRegistry
                    { surfaceActionAdapterRegistrations =
                        [ surfaceActionAdapterExcluded
                            @Fixture.AdapterFixtureFamily
                            @Fixture.CrossKindDeclaration
                            ""
                        ]
                    }
        diagnosticCodes (generateSurfaceActionAdapterModules fixtureContract blankDeclarationRegistry)
            `shouldContain` ["adapter-action-declaration-exclusion-reason"]

    it "records complete typed production Action and Intent operation inventories" do
        actionDeclarations <-
            case checkedSurfaceActionAdapterDeclarations registeredFrontendSurfaceContractIR of
                Left diagnostics -> expectationFailure (cs (show diagnostics)) >> pure []
                Right declarations -> pure declarations
        actionInventory <-
            case resolveSurfaceRequestAdapterRegistrations
                actionAdapterLayout
                registeredFrontendSurfaceContractIR
                registeredSurfaceAdapterRegistry.surfaceAdapterFamilies
                actionDeclarations
                registeredSurfaceAdapterRegistry.surfaceActionAdapterRegistrations of
                Left diagnostics -> expectationFailure (cs (show diagnostics)) >> pure []
                Right inventory -> pure inventory
        length actionDeclarations `shouldBe` 53
        length actionInventory `shouldBe` length actionDeclarations
        let generatedActionOperations = mapMaybe (.checkedSurfaceRequestAdapterOperations) actionInventory
        length generatedActionOperations `shouldBe` 48
        length (filter (surfaceAdapterOperationIsGenerated . (.surfaceAdapterFieldsBuilderOperation)) generatedActionOperations)
            `shouldBe` 48
        length (filter (surfaceAdapterOperationIsGenerated . (.surfaceAdapterRenderMetadataOperation)) generatedActionOperations)
            `shouldBe` 48
        length (filter (surfaceAdapterOperationIsGenerated . (.surfaceAdapterRequestParserOperation)) generatedActionOperations)
            `shouldBe` 33
        let actionIdentity registration =
                let declaration = registration.checkedSurfaceRequestAdapterDeclaration
                 in (declaration.checkedAdapterSurfaceName, declaration.checkedAdapterDeclarationName)
        List.sort
            [ actionIdentity registration
            | registration <- actionInventory
            , isNothing registration.checkedSurfaceRequestAdapterOperations
            ]
            `shouldBe` List.sort
                [ ("roster", "set-roster-layout-mode")
                , ("roster", "move-roster-shift-to-slot")
                , ("roster", "duplicate-roster-shift-to-day")
                , ("roster", "drop-roster-staff")
                , ("roster-day-timeline", "move-roster-timeline-shift")
                ]
        List.sort
            [ actionIdentity registration
            | registration <- actionInventory
            , Just operations <- [registration.checkedSurfaceRequestAdapterOperations]
            , not (surfaceAdapterOperationIsGenerated operations.surfaceAdapterRequestParserOperation)
            ]
            `shouldBe` List.sort
                [ ("roster", "sort-roster-week")
                , ("roster", "copy-roster-week")
                , ("roster", "create-roster-week-slot-definition")
                , ("roster", "delete-roster-week-slot-definition")
                , ("roster", "toggle-roster-day-closed")
                , ("roster", "add-roster-row")
                , ("roster", "remove-roster-row")
                , ("leave-requests", "approve-leave-request")
                , ("leave-requests", "deny-leave-request")
                , ("support", "create-public-holiday-refresh-job")
                , ("support", "create-fwc-mapd-refresh-job")
                , ("admin-invites", "revoke-venue-invitation")
                , ("admin-shift-types", "autosave-shift-type-name")
                , ("admin-shift-types", "autosave-shift-type-selection")
                , ("admin-xero", "sync-xero-payroll-reference-data")
                ]

        intentDeclarations <-
            case checkedSurfaceIntentAdapterDeclarations registeredFrontendSurfaceContractIR of
                Left diagnostics -> expectationFailure (cs (show diagnostics)) >> pure []
                Right declarations -> pure declarations
        intentInventory <-
            case resolveSurfaceRequestAdapterRegistrations
                intentAdapterLayout
                registeredFrontendSurfaceContractIR
                registeredSurfaceAdapterRegistry.surfaceAdapterFamilies
                intentDeclarations
                registeredSurfaceAdapterRegistry.surfaceIntentAdapterRegistrations of
                Left diagnostics -> expectationFailure (cs (show diagnostics)) >> pure []
                Right inventory -> pure inventory
        length intentDeclarations `shouldBe` 5
        length intentInventory `shouldBe` length intentDeclarations
        let generatedIntentOperations = mapMaybe (.checkedSurfaceRequestAdapterOperations) intentInventory
        length generatedIntentOperations `shouldBe` 5
        generatedIntentOperations
            `shouldSatisfy` all
                (\operations ->
                    all
                        surfaceAdapterOperationIsGenerated
                        [ operations.surfaceAdapterFieldsBuilderOperation
                        , operations.surfaceAdapterRenderMetadataOperation
                        , operations.surfaceAdapterRequestParserOperation
                        ]
                )

        case generateSurfaceActionAdapterModules registeredFrontendSurfaceContractIR registeredSurfaceAdapterRegistry of
            Left diagnostics -> expectationFailure (cs (show diagnostics))
            Right generatedModules ->
                map (.generatedModuleName) generatedModules
                    `shouldBe`
                        [ "Application.Helper.FrontendContract.Surface.Admin.Generated.Action"
                        , "Application.Helper.FrontendContract.Surface.LeaveRequests.Generated.Action"
                        , "Application.Helper.FrontendContract.Surface.Profile.Generated.Action"
                        , "Application.Helper.FrontendContract.Surface.Roster.Generated.Action"
                        , "Application.Helper.FrontendContract.Surface.Support.Generated.Action"
                        , "Application.Helper.FrontendContract.Surface.Timesheets.Generated.Action"
                        ]
        length registeredSurfaceAdapterRegistry.surfaceIntentAdapterHomes `shouldBe` 5
        case generateSurfaceIntentAdapterModules registeredFrontendSurfaceContractIR registeredSurfaceAdapterRegistry of
            Left diagnostics -> expectationFailure (cs (show diagnostics))
            Right generatedModules ->
                map (.generatedModuleName) generatedModules
                    `shouldBe` ["Application.Helper.FrontendContract.Surface.Roster.Generated.Intent"]

    it "pins complete Roster Intent bundles and DOM-owned form metadata from independent literals" do
        let venueId = fixtureMemberId "00000000-0000-0000-0000-000000000111"
        let rosterGroupId = Id (fixtureMemberId "00000000-0000-0000-0000-000000000222") :: Id RosterGroup
        let rosterDayId = Id (fixtureMemberId "00000000-0000-0000-0000-000000000333") :: Id RosterDay
        let rosterScope =
                RosterWeekScopeValue
                    { rosterWeekVenueId = venueId
                    , rosterWeekGroupId = rosterGroupId
                    , rosterWeekWeekOffset = 3
                    , rosterWeekTimelineDayOffset = Nothing
                    }
        let timelineScope =
                RosterDayTimelineScopeValue
                    { rosterDayTimelineVenueId = venueId
                    , rosterDayTimelineGroupId = rosterGroupId
                    , rosterDayTimelineWeekOffset = 3
                    , rosterDayTimelineDayOffset = 2
                    , rosterDayTimelineDayId = rosterDayId
                    }
        let rosterForms = rosterIntentForms rosterScope
        let timelineForms = rosterDayTimelineIntentForms timelineScope
        map intentFormName rosterForms
            `shouldBe`
                [ "set-roster-layout-mode"
                , "move-roster-shift-to-slot"
                , "duplicate-roster-shift-to-day"
                , "drop-roster-staff"
                ]
        map intentFormName timelineForms `shouldBe` ["move-roster-timeline-shift"]

        let renderedForms = map renderIntentFormText (rosterForms <> timelineForms)
        let expectedFormMetadata =
                [ ("set-roster-layout-mode", "/UpdateRosterLayoutPreference?weekOffset=3&amp;rosterGroupId=00000000-0000-0000-0000-000000000222", 1)
                , ("move-roster-shift-to-slot", "/MoveRosterShiftToSlot?weekOffset=3&amp;rosterGroupId=00000000-0000-0000-0000-000000000222", 11)
                , ("duplicate-roster-shift-to-day", "/DuplicateRosterShiftToDay?weekOffset=3&amp;rosterGroupId=00000000-0000-0000-0000-000000000222", 11)
                , ("drop-roster-staff", "/DropRosterStaff?weekOffset=3&amp;rosterGroupId=00000000-0000-0000-0000-000000000222", 11)
                , ("move-roster-timeline-shift", "/MoveRosterTimelineShift?weekOffset=3&amp;rosterGroupId=00000000-0000-0000-0000-000000000222&amp;rosterView=timeline&amp;dayOffset=2", 11)
                ]
        forM_ (zip expectedFormMetadata renderedForms) \(metadata, html) ->
            assertRosterIntentFormMetadata metadata html

        let layoutHtml = fromMaybe (error "missing rendered Roster layout Intent form") (listToMaybe renderedForms)
        layoutHtml
            `shouldSatisfy` Text.isInfixOf "name=\"rosterLayoutMode\" value=\"day_rows\" data-bepis-intent-field=\"rosterLayoutMode\" data-bepis-field-presence=\"required\""
        forM_ (drop 1 renderedForms) \dragHtml -> do
            forM_ ["sourceItemKey", "targetDropzoneKey"] \fieldName ->
                dragHtml `shouldSatisfy` Text.isInfixOf (renderedIntentField fieldName "required")
            forM_ rosterOptionalDragFieldNames \fieldName ->
                dragHtml `shouldSatisfy` Text.isInfixOf (renderedIntentField fieldName "optional")

    it "parses every production Roster Intent shape through the canonical facade" do
        let parsedLayout =
                let ?request = requestWithParams
                        [("rosterLayoutMode", Just "day_columns"), ("unrelated-route-context", Just "ignored")]
                 in RosterIntent.parseSetRosterLayoutModeIntentParams
        case parsedLayout of
            Left errors -> expectationFailure (cs (show errors))
            Right fields ->
                surfaceFieldValue @Roster.RosterLayoutMode fields `shouldBe` "day_columns"

        let ?request = requestWithParams validRosterDragIntentParams
        assertRosterDragIntentFields RosterIntent.parseMoveRosterShiftToSlotIntentParams
        assertRosterDragIntentFields RosterIntent.parseDuplicateRosterShiftToDayIntentParams
        assertRosterDragIntentFields RosterIntent.parseDropRosterStaffIntentParams
        assertRosterDragIntentFields RosterIntent.parseMoveRosterTimelineShiftIntentParams

    it "preserves canonical Roster Intent facade missing and malformed diagnostics" do
        let missingLayout =
                let ?request = requestWithParams []
                 in RosterIntent.parseSetRosterLayoutModeIntentParams
        assertRequestErrors ["rosterLayoutMode"] MissingSurfaceRequestField missingLayout

        let malformedLayout =
                let ?request = requestWithParams [("rosterLayoutMode", Just invalidUtf8)]
                 in RosterIntent.parseSetRosterLayoutModeIntentParams
        assertRequestErrors ["rosterLayoutMode"] MalformedSurfaceRequestField malformedLayout

        let missingDragIntentChecks =
                let ?request = requestWithParams []
                 in do
                    assertRequestErrors ["sourceItemKey", "targetDropzoneKey"] MissingSurfaceRequestField RosterIntent.parseMoveRosterShiftToSlotIntentParams
                    assertRequestErrors ["sourceItemKey", "targetDropzoneKey"] MissingSurfaceRequestField RosterIntent.parseDuplicateRosterShiftToDayIntentParams
                    assertRequestErrors ["sourceItemKey", "targetDropzoneKey"] MissingSurfaceRequestField RosterIntent.parseDropRosterStaffIntentParams
                    assertRequestErrors ["sourceItemKey", "targetDropzoneKey"] MissingSurfaceRequestField RosterIntent.parseMoveRosterTimelineShiftIntentParams
        missingDragIntentChecks

        let malformedDragIntentChecks =
                let ?request = requestWithParams invalidRosterDragIntentParams
                 in do
                    assertRequestErrors ["sourceItemKey", "targetDropzoneKey"] MalformedSurfaceRequestField RosterIntent.parseMoveRosterShiftToSlotIntentParams
                    assertRequestErrors ["sourceItemKey", "targetDropzoneKey"] MalformedSurfaceRequestField RosterIntent.parseDuplicateRosterShiftToDayIntentParams
                    assertRequestErrors ["sourceItemKey", "targetDropzoneKey"] MalformedSurfaceRequestField RosterIntent.parseDropRosterStaffIntentParams
                    assertRequestErrors ["sourceItemKey", "targetDropzoneKey"] MalformedSurfaceRequestField RosterIntent.parseMoveRosterTimelineShiftIntentParams
        malformedDragIntentChecks

    it "pins all Profile and Staff Action metadata from independent literals" do
        frontendSurfaceActionHtmxAttrPairs
            (ProfileAction.updateProfileDetailsAction profileDetailsFields)
            (sectionActionRoute "/profile/details" "#profile-details")
            `shouldBe`
                [ ("hx-post", "/profile/details")
                , ("data-bepis-surface-action", "update-profile-details")
                , ("hx-push-url", "false")
                , ("hx-target", "#profile-details")
                , ("hx-swap", "outerHTML show:none")
                ]
        frontendSurfaceActionHtmxAttrPairs
            (ProfileAction.updateProfileShiftPreferencesAction preferenceFields)
            (sectionActionRoute "/profile/preferences" "#profile-preferences")
            `shouldBe`
                [ ("hx-post", "/profile/preferences")
                , ("data-bepis-surface-action", "update-profile-shift-preferences")
                , ("hx-push-url", "false")
                , ("hx-target", "#profile-preferences")
                , ("hx-swap", "outerHTML show:none")
                ]
        frontendSurfaceActionHtmxAttrPairs
            (ProfileAction.updateStaffProfileAction staffProfileDetailsFields)
            (sectionActionRoute "/staff/details" "#staff-profile-details")
            `shouldBe`
                [ ("hx-post", "/staff/details")
                , ("data-bepis-surface-action", "update-staff-profile")
                , ("hx-push-url", "false")
                , ("hx-target", "#staff-profile-details")
                , ("hx-swap", "outerHTML show:none")
                ]
        frontendSurfaceActionHtmxAttrPairs
            (ProfileAction.updateStaffShiftPreferencesAction staffPreferenceFields)
            (sectionActionRoute "/staff/preferences" "#staff-profile-preferences")
            `shouldBe`
                [ ("hx-post", "/staff/preferences")
                , ("data-bepis-surface-action", "update-staff-shift-preferences")
                , ("hx-push-url", "false")
                , ("hx-target", "#staff-profile-preferences")
                , ("hx-swap", "outerHTML show:none")
                ]
        frontendSurfaceActionHtmxAttrPairs
            (ProfileAction.createProfileLeaveRequestAction profileLeaveRequestFields)
            (emptyActionRoute "/profile/leave")
            `shouldBe`
                [ ("hx-post", "/profile/leave")
                , ("data-bepis-surface-action", "create-profile-leave-request")
                , ("hx-target", "#profile-leave-request-form-fragment")
                , ("hx-swap", "outerHTML")
                , ("hx-push-url", "false")
                ]
        frontendSurfaceActionHtmxAttrPairs
            (ProfileAction.createStaffLeaveRequestAction staffLeaveRequestFields)
            (emptyActionRoute "/staff/leave")
            `shouldBe`
                [ ("hx-post", "/staff/leave")
                , ("data-bepis-surface-action", "create-staff-leave-request")
                , ("hx-target", "#staff-leave-request-form-fragment")
                , ("hx-swap", "outerHTML")
                , ("hx-push-url", "false")
                ]

    it "parses complete Profile and Staff detail submissions with every production presence shape" do
        let ?request = requestWithParams validDetailsParams
        assertDetailsSubmission "Profile" parseProfileSurfaceSubmission
        assertDetailsSubmission "Staff" parseStaffSurfaceSubmission

    it "selects Profile and Staff preference submissions semantically and parses optional text lists" do
        let ?request = requestWithParams
                [ ("section", Just "preferences")
                , ("shiftPreferenceKeys", Just "monday:9:17")
                , ("shiftPreferenceKeys", Just "friday:10:18")
                , ("unrelated-route-context", Just "ignored")
                ]
        assertPreferencesSubmission "Profile" parseProfileSurfaceSubmission
        assertPreferencesSubmission "Staff" parseStaffSurfaceSubmission

    it "preserves complete missing and malformed Profile and Staff diagnostics" do
        let ?request = requestWithParams [("section", Just "profile")]
        forM_ [parseProfileSurfaceSubmission, parseStaffSurfaceSubmission] $
            assertRequestErrors
                [ "firstName"
                , "lastName"
                , "preferredName"
                , "phone"
                , "idealShiftsPerWeek"
                , "emergencyContactName"
                , "emergencyContactPhone"
                ]
                MissingSurfaceRequestField

        let ?request = requestWithParams malformedDetailsParams
        forM_ [parseProfileSurfaceSubmission, parseStaffSurfaceSubmission] $
            assertRequestErrors
                ["idealShiftsPerWeek", "isActive", "rosterGroupIds"]
                MalformedSurfaceRequestField

    it "parses Profile and Staff leave bundles and accumulates Day diagnostics" do
        let expectedStart = fromGregorian 2026 7 20
        let expectedEnd = fromGregorian 2026 7 22
        case parseSurfaceActionParamPairs @Profile.ProfileSurface @Profile.CreateProfileLeaveRequest validLeaveParams of
            Left errors -> expectationFailure (cs (show errors))
            Right fields -> do
                surfaceFieldValue @Profile.StartDate fields `shouldBe` expectedStart
                surfaceFieldValue @Profile.EndDate fields `shouldBe` expectedEnd
                surfaceFieldValue @Profile.Notes fields `shouldBe` "Family event"
        case parseSurfaceActionParamPairs @Profile.StaffSurface @Profile.CreateStaffLeaveRequest validLeaveParams of
            Left errors -> expectationFailure (cs (show errors))
            Right fields -> do
                surfaceFieldValue @Profile.StartDate fields `shouldBe` expectedStart
                surfaceFieldValue @Profile.EndDate fields `shouldBe` expectedEnd
                surfaceFieldValue @Profile.Notes fields `shouldBe` "Family event"

        assertRequestErrors
            ["startDate", "endDate", "notes"]
            MissingSurfaceRequestField
            (parseSurfaceActionParamPairs @Profile.ProfileSurface @Profile.CreateProfileLeaveRequest [])
        assertRequestErrors
            ["startDate", "endDate", "notes"]
            MissingSurfaceRequestField
            (parseSurfaceActionParamPairs @Profile.StaffSurface @Profile.CreateStaffLeaveRequest [])
        let malformedLeaveParams =
                [ ("startDate", Just "20/07/2026")
                , ("endDate", Just "tomorrow")
                , ("notes", Just "still valid text")
                ]
        assertRequestErrors
            ["startDate", "endDate"]
            MalformedSurfaceRequestField
            (parseSurfaceActionParamPairs @Profile.ProfileSurface @Profile.CreateProfileLeaveRequest malformedLeaveParams)
        assertRequestErrors
            ["startDate", "endDate"]
            MalformedSurfaceRequestField
            (parseSurfaceActionParamPairs @Profile.StaffSurface @Profile.CreateStaffLeaveRequest malformedLeaveParams)

renderIntentFormText :: FrontendSurfaceIntentForm -> Text
renderIntentFormText intentForm =
    cs (HtmlRenderer.renderHtml (renderFrontendSurfaceIntentForm intentForm mempty))

assertRosterIntentFormMetadata :: (Text, Text, Int) -> Text -> Expectation
assertRosterIntentFormMetadata (intentName, actionUrl, expectedFieldCount) html = do
    html `shouldSatisfy` Text.isInfixOf ("hx-post=\"" <> actionUrl <> "\"")
    html `shouldSatisfy` Text.isInfixOf "hx-target=\"#roster-content\""
    html `shouldSatisfy` Text.isInfixOf "hx-swap=\"none\""
    html `shouldSatisfy` Text.isInfixOf ("data-bepis-intent-form=\"" <> intentName <> "\"")
    Text.count "data-bepis-intent-field=" html `shouldBe` expectedFieldCount

renderedIntentField :: Text -> Text -> Text
renderedIntentField fieldName presence =
    "name=\"" <> fieldName <> "\" value=\"\" data-bepis-intent-field=\"" <> fieldName
        <> "\" data-bepis-field-presence=\"" <> presence <> "\""

rosterOptionalDragFieldNames :: [Text]
rosterOptionalDragFieldNames =
    [ "sessionKind"
    , "pointerId"
    , "pointerType"
    , "startClientX"
    , "startClientY"
    , "currentClientX"
    , "currentClientY"
    , "deltaX"
    , "deltaY"
    ]

validRosterDragIntentParams :: [(ByteString.ByteString, Maybe ByteString.ByteString)]
validRosterDragIntentParams =
    [ ("sourceItemKey", Just "existing:source")
    , ("targetDropzoneKey", Just "new:target")
    , ("sessionKind", Just "drag")
    , ("pointerId", Just "7")
    , ("pointerType", Just "mouse")
    , ("startClientX", Just "100")
    , ("startClientY", Just "200")
    , ("currentClientX", Just "140")
    , ("currentClientY", Just "250")
    , ("deltaX", Just "40")
    , ("deltaY", Just "50")
    , ("unrelated-route-context", Just "ignored")
    ]

invalidUtf8 :: ByteString.ByteString
invalidUtf8 = ByteString.pack [0xff]

invalidRosterDragIntentParams :: [(ByteString.ByteString, Maybe ByteString.ByteString)]
invalidRosterDragIntentParams =
    [ ("sourceItemKey", Just invalidUtf8)
    , ("targetDropzoneKey", Just invalidUtf8)
    ]

assertRosterDragIntentFields ::
    SurfaceFieldBundleOf SurfaceInteraction.DragDropFields fields =>
    Either [SurfaceRequestFieldError] fields ->
    Expectation
assertRosterDragIntentFields = \case
    Left errors -> expectationFailure (cs (show errors))
    Right fields -> do
        surfaceFieldValue @SurfaceInteraction.SourceItemKey fields `shouldBe` "existing:source"
        surfaceFieldValue @SurfaceInteraction.TargetDropzoneKey fields `shouldBe` "new:target"
        surfaceFieldValue @SurfaceInteraction.SessionKind fields `shouldBe` Just "drag"
        surfaceFieldValue @SurfaceInteraction.PointerId fields `shouldBe` Just "7"
        surfaceFieldValue @SurfaceInteraction.PointerType fields `shouldBe` Just "mouse"
        surfaceFieldValue @SurfaceInteraction.StartClientX fields `shouldBe` Just "100"
        surfaceFieldValue @SurfaceInteraction.StartClientY fields `shouldBe` Just "200"
        surfaceFieldValue @SurfaceInteraction.CurrentClientX fields `shouldBe` Just "140"
        surfaceFieldValue @SurfaceInteraction.CurrentClientY fields `shouldBe` Just "250"
        surfaceFieldValue @SurfaceInteraction.DeltaX fields `shouldBe` Just "40"
        surfaceFieldValue @SurfaceInteraction.DeltaY fields `shouldBe` Just "50"

fixtureRegistry :: SurfaceAdapterRegistry
fixtureRegistry =
    reflectSurfaceAdapterRegistry
        @Fixture.FixtureAdapterFamilies
        @Fixture.FixtureResourceHomes
        @Fixture.FixtureScopeHomes
        @Fixture.FixtureFragmentHomes
        @Fixture.FixtureActionHomes
        @Fixture.FixtureIntentHomes
        Fixture.fixtureActorOnlyFragments
        [ surfaceActionAdapter
            @Fixture.AdapterFixtureFamily
            @Fixture.CrossKindDeclaration
            allFixtureRequestAdapterOperations
        ]
        [ surfaceIntentAdapter
            @Fixture.AdapterFixtureFamily
            @Fixture.CrossKindDeclaration
            allFixtureRequestAdapterOperations
        ]

allFixtureRequestAdapterOperations :: SurfaceRequestAdapterOperations
allFixtureRequestAdapterOperations =
    SurfaceRequestAdapterOperations
        { surfaceAdapterFieldsBuilderOperation = GenerateSurfaceAdapterOperation
        , surfaceAdapterRenderMetadataOperation = GenerateSurfaceAdapterOperation
        , surfaceAdapterRequestParserOperation = GenerateSurfaceAdapterOperation
        }

fixtureContract :: SurfaceContractIR
fixtureContract =
    SurfaceContractIR
        { contractSurfaces = reflectSurfaceRegistry @'[Fixture.AdapterFixtureSurface]
        }
        |> either (error . cs . show) id . checkedSurfaceContractIR

fixtureMemberId :: Text -> UUID.UUID
fixtureMemberId value =
    fromMaybe (error ("invalid generated adapter UUID fixture " <> cs value)) (UUID.fromText value)

diagnosticCodes :: Either [ContractDiagnostic] value -> [Text]
diagnosticCodes = \case
    Right _ -> []
    Left diagnostics -> map (.diagnosticCode) diagnostics

requestWithParams :: [(ByteString.ByteString, Maybe ByteString.ByteString)] -> Wai.Request
requestWithParams params =
    let request = Wai.defaultRequest
        parsedBody = FormBody [] [] LBS.empty
     in request
            { Wai.vault = Vault.insert requestBodyVaultKey parsedBody (Wai.vault request)
            , Wai.queryString = params
            }

emptyActionRoute :: Text -> FrontendSurfaceActionRoute
emptyActionRoute url =
    FrontendSurfaceActionRoute
        { actionRouteUrl = url
        , actionRouteCustomHtmx = []
        , actionRouteStandardUrl = Nothing
        , actionRouteExtraAttrs = []
        }

sectionActionRoute :: Text -> Text -> FrontendSurfaceActionRoute
sectionActionRoute url target =
    (emptyActionRoute url)
        { actionRouteCustomHtmx =
            [ FrontendSurfaceCustomHtmxAttrs
                { customHtmxAttrMarker = "staff-profile-section-htmx-attrs"
                , customHtmxAttrValues =
                    [ ("hx-target", target)
                    , ("hx-swap", "outerHTML show:none")
                    ]
                }
            ]
        }

profileDetailsFields :: SurfaceActionFields Profile.ProfileSurface Profile.UpdateProfileDetails
profileDetailsFields =
    ProfileAction.updateProfileDetailsActionFields
        "Ada"
        "Lovelace"
        ""
        "0400000000"
        4
        "Charles"
        "0411111111"
        "profile"
        (Just "manager")
        Nothing
        (Just "award:level-1")
        (Just True)
        (Just [firstRosterGroupId, secondRosterGroupId])

staffProfileDetailsFields :: SurfaceActionFields Profile.StaffSurface Profile.UpdateStaffProfile
staffProfileDetailsFields =
    ProfileAction.updateStaffProfileActionFields
        "Ada"
        "Lovelace"
        ""
        "0400000000"
        4
        "Charles"
        "0411111111"
        "profile"
        (Just "manager")
        Nothing
        (Just "award:level-1")
        (Just True)
        (Just [firstRosterGroupId, secondRosterGroupId])

preferenceFields :: SurfaceActionFields Profile.ProfileSurface Profile.UpdateProfileShiftPreferences
preferenceFields =
    ProfileAction.updateProfileShiftPreferencesActionFields
        "preferences"
        (Just ["monday:9:17", "friday:10:18"])

staffPreferenceFields :: SurfaceActionFields Profile.StaffSurface Profile.UpdateStaffShiftPreferences
staffPreferenceFields =
    ProfileAction.updateStaffShiftPreferencesActionFields
        "preferences"
        (Just ["monday:9:17", "friday:10:18"])

profileLeaveRequestFields :: SurfaceActionFields Profile.ProfileSurface Profile.CreateProfileLeaveRequest
profileLeaveRequestFields =
    ProfileAction.createProfileLeaveRequestActionFields
        (fromGregorian 2026 7 20)
        (fromGregorian 2026 7 22)
        "Family event"

staffLeaveRequestFields :: SurfaceActionFields Profile.StaffSurface Profile.CreateStaffLeaveRequest
staffLeaveRequestFields =
    ProfileAction.createStaffLeaveRequestActionFields
        (fromGregorian 2026 7 20)
        (fromGregorian 2026 7 22)
        "Family event"

validDetailsParams :: [(ByteString.ByteString, Maybe ByteString.ByteString)]
validDetailsParams =
    [ ("firstName", Just "Ada")
    , ("lastName", Just "Lovelace")
    , ("preferredName", Just "")
    , ("phone", Just "0400000000")
    , ("idealShiftsPerWeek", Just "4")
    , ("emergencyContactName", Just "Charles")
    , ("emergencyContactPhone", Just "0411111111")
    , ("section", Just "profile")
    , ("venueRole", Just "manager")
    , ("employmentBasis", Just "")
    , ("payRateSelection", Just "award:level-1")
    , ("isActive", Just "on")
    , ("rosterGroupIds", Just "11111111-1111-1111-1111-111111111111")
    , ("rosterGroupIds", Just "22222222-2222-2222-2222-222222222222")
    , ("unrelated-route-context", Just "ignored")
    ]

malformedDetailsParams :: [(ByteString.ByteString, Maybe ByteString.ByteString)]
malformedDetailsParams =
    [ ("firstName", Just "Ada")
    , ("lastName", Just "Lovelace")
    , ("preferredName", Just "")
    , ("phone", Just "0400000000")
    , ("idealShiftsPerWeek", Just "many")
    , ("emergencyContactName", Just "Charles")
    , ("emergencyContactPhone", Just "0411111111")
    , ("section", Just "profile")
    , ("isActive", Just "perhaps")
    , ("rosterGroupIds", Just "not-a-uuid")
    ]

validLeaveParams :: [(ByteString.ByteString, Maybe ByteString.ByteString)]
validLeaveParams =
    [ ("startDate", Just "2026-07-20")
    , ("endDate", Just "2026-07-22")
    , ("notes", Just "Family event")
    ]

firstRosterGroupId :: UUID.UUID
firstRosterGroupId = fixtureMemberId "11111111-1111-1111-1111-111111111111"

secondRosterGroupId :: UUID.UUID
secondRosterGroupId = fixtureMemberId "22222222-2222-2222-2222-222222222222"

assertDetailsSubmission :: Text -> Either [SurfaceRequestFieldError] StaffProfileSurfaceSubmission -> Expectation
assertDetailsSubmission family = \case
    Left errors -> expectationFailure (cs (family <> " details parse failed: " <> tshow errors))
    Right (SubmittedStaffShiftPreferences _) ->
        expectationFailure (cs (family <> " details request selected preferences"))
    Right (SubmittedStaffProfileDetails submission) -> do
        submission.submittedFirstName `shouldBe` "Ada"
        submission.submittedLastName `shouldBe` "Lovelace"
        submission.submittedPreferredName `shouldBe` ""
        submission.submittedPhone `shouldBe` "0400000000"
        submission.submittedIdealShiftsPerWeek `shouldBe` 4
        submission.submittedEmergencyContactName `shouldBe` "Charles"
        submission.submittedEmergencyContactPhone `shouldBe` "0411111111"
        submission.submittedProfileSection `shouldBe` "profile"
        submission.submittedVenueRole `shouldBe` Just "manager"
        submission.submittedEmploymentBasis `shouldBe` Nothing
        submission.submittedPayRateSelection `shouldBe` Just "award:level-1"
        submission.submittedIsActive `shouldBe` Just True
        submission.submittedRosterGroupIds `shouldBe` Just [firstRosterGroupId, secondRosterGroupId]

assertPreferencesSubmission :: Text -> Either [SurfaceRequestFieldError] StaffProfileSurfaceSubmission -> Expectation
assertPreferencesSubmission family = \case
    Left errors -> expectationFailure (cs (family <> " preferences parse failed: " <> tshow errors))
    Right (SubmittedStaffProfileDetails _) ->
        expectationFailure (cs (family <> " preferences request selected details"))
    Right (SubmittedStaffShiftPreferences submission) -> do
        submission.submittedPreferencesSection `shouldBe` "preferences"
        submission.submittedShiftPreferenceKeys `shouldBe` ["monday:9:17", "friday:10:18"]

assertRequestErrors :: [Text] -> SurfaceRequestFieldErrorKind -> Either [SurfaceRequestFieldError] value -> Expectation
assertRequestErrors expectedNames expectedKind = \case
    Right _ -> expectationFailure "expected Surface request field errors"
    Left errors -> do
        map (.surfaceRequestFieldErrorName) errors `shouldBe` expectedNames
        map (.surfaceRequestFieldErrorKind) errors
            `shouldBe` replicate (length expectedNames) expectedKind
