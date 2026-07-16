{-# LANGUAGE DataKinds        #-}
{-# LANGUAGE TypeApplications #-}

module Test.FrontendSurfaceAdapterGeneratorSpec
    ( tests
    ) where

import Application.Helper.FrontendContract.Surface.ContractIR
import Application.Helper.FrontendContract.Surface.Contracts (registeredFrontendSurfaceContractIR)
import Application.Helper.FrontendContract.Surface.HaskellAdapter.Core
import Application.Helper.FrontendContract.Surface.HaskellAdapter.Family
import Application.Helper.FrontendContract.Surface.HaskellAdapter.Generator
import Application.Helper.FrontendContract.Surface.HaskellAdapter.Live
import Application.Helper.FrontendContract.Surface.HaskellAdapter.Registry (registeredSurfaceAdapterRegistry)
import Application.Helper.FrontendContract.Surface.Reflect (reflectSurfaceRegistry)
import Data.Either (isRight)
import qualified Data.List as List
import qualified Data.Text as Text
import qualified Data.Text.IO as Text
import Data.Time (fromGregorian)
import qualified Data.UUID as UUID
import IHP.Prelude
import Test.Hspec
import qualified Test.Support.FrontendSurfaceAdapterFixture as Fixture
import qualified Test.Support.FrontendSurfaceAdapterFixture.Generated.Live as GeneratedLive
import qualified Test.Support.FrontendSurfaceAdapterFixture.Generated.Resource as Generated

tests :: Spec
tests = describe "FrontendSurface Haskell adapter generator" do
    it "renders the typed fixture registry as one deterministic formatted golden module" do
        expected <- Text.readFile "Test/Support/FrontendSurfaceAdapterFixture/Generated/Resource.hs"
        case generateFixture fixtureRegistry of
            Left diagnostics -> expectationFailure (cs (show diagnostics))
            Right [generated] -> do
                generated.generatedModuleName
                    `shouldBe` "Test.Support.FrontendSurfaceAdapterFixture.Generated.Resource"
                generated.generatedModulePath
                    `shouldBe` "Test/Support/FrontendSurfaceAdapterFixture/Generated/Resource.hs"
                generated.generatedModuleSource `shouldBe` expected
                generated.generatedModuleSource `shouldSatisfy` Text.isInfixOf "frontendSurfaceResource"
                generated.generatedModuleSource `shouldSatisfy` Text.isInfixOf "matchFrontendSurfaceResource"
                generated.generatedModuleSource `shouldNotSatisfy` Text.isInfixOf ".Internal"
                generated.generatedModuleSource `shouldNotSatisfy` Text.isInfixOf "GHC."
            Right generated -> expectationFailure (cs ("expected one generated module, got " <> tshow (length generated)))

    it "renders scope and fragment fixture adapters into one shared Live golden module" do
        expected <- Text.readFile "Test/Support/FrontendSurfaceAdapterFixture/Generated/Live.hs"
        case generateSurfaceLiveAdapterModules fixtureContract fixtureRegistry of
            Left diagnostics -> expectationFailure (cs (show diagnostics))
            Right [generated] -> do
                generated.generatedModuleName
                    `shouldBe` "Test.Support.FrontendSurfaceAdapterFixture.Generated.Live"
                generated.generatedModulePath
                    `shouldBe` "Test/Support/FrontendSurfaceAdapterFixture/Generated/Live.hs"
                generated.generatedModuleSource `shouldSatisfy` Text.isInfixOf "frontendSurfaceScope"
                generated.generatedModuleSource `shouldSatisfy` Text.isInfixOf "matchFrontendSurfaceScope"
                generated.generatedModuleSource `shouldSatisfy` Text.isInfixOf "frontendSurfaceFragmentKey"
                generated.generatedModuleSource `shouldBe` expected
                generated.generatedModuleSource `shouldSatisfy` Text.isInfixOf "crossKindDeclarationLiveScope :: SurfaceScope"
                generated.generatedModuleSource `shouldSatisfy` Text.isInfixOf "fixtureActorOnlyPanelLiveFragment :: SurfaceFragmentKey"
                generated.generatedModuleSource `shouldSatisfy` Text.isInfixOf "matchFrontendSurfaceFragmentKey"
                generated.generatedModuleSource `shouldNotSatisfy` Text.isInfixOf ".Internal"
                generated.generatedModuleSource `shouldNotSatisfy` Text.isInfixOf "HaskellAdapter.Registry"
                generated.generatedModuleSource `shouldNotSatisfy` Text.isInfixOf "Aeson"
            Right generated -> expectationFailure (cs ("expected one generated Live module, got " <> tshow (length generated)))

    it "composes every enabled output lane before exposing the managed module set" do
        case generateSurfaceAdapterModules fixtureContract fixtureRegistry of
            Left diagnostics -> expectationFailure (cs (show diagnostics))
            Right generatedModules ->
                map (.generatedModuleName) generatedModules
                    `shouldBe`
                        [ "Test.Support.FrontendSurfaceAdapterFixture.Generated.Live"
                        , "Test.Support.FrontendSurfaceAdapterFixture.Generated.Resource"
                        ]

    it "returns complete diagnostics from every focused output lane" do
        let resourceDiagnostic =
                ContractDiagnostic
                    { diagnosticCode = "resource-lane-fixture"
                    , diagnosticMessage = "resource lane failed"
                    }
        let liveDiagnostic =
                ContractDiagnostic
                    { diagnosticCode = "live-lane-fixture"
                    , diagnosticMessage = "Live lane failed"
                    }
        diagnosticCodes
            ( composeGeneratedSurfaceAdapterModules
                [Left [resourceDiagnostic], Left [liveDiagnostic]]
            )
            `shouldBe` ["live-lane-fixture", "resource-lane-fixture"]

    it "rejects duplicate physical module paths across output lanes" do
        let duplicate =
                GeneratedHaskellModule
                    { generatedModuleName = "Fixture.Generated.Shared"
                    , generatedModulePath = "Fixture/Generated/Shared.hs"
                    , generatedModuleSource = "module Fixture.Generated.Shared where\n"
                    }
        diagnosticCodes
            ( composeGeneratedSurfaceAdapterModules
                [ Right (GeneratedResourceAdapterLane [duplicate])
                , Right (GeneratedLiveAdapterLane [duplicate])
                ]
            )
            `shouldContain` ["generated-adapter-path-collision"]

    it "typechecks and executes the generated fixture through public generic builders" do
        let memberId =
                fromMaybe
                    (error "invalid generated adapter UUID fixture")
                    (UUID.fromText "11111111-1111-1111-1111-111111111111")
        let archivedAt = fromGregorian 2026 7 15
        let account =
                Generated.fixtureAccountResource
                    "fixture"
                    (Just 2)
                    (Just archivedAt)
                    [memberId]
                    (Just Nothing)
                    (Just [memberId])
                    True
        Generated.matchFixtureAccountResource account
            `shouldBe` Just
                ( "fixture"
                , ( Just 2
                  , ( Just archivedAt
                    , ( [memberId]
                      , (Just Nothing, (Just [memberId], (True, ())))
                      )
                    )
                  )
                )
        Generated.matchFixtureHeartbeatResource Generated.fixtureHeartbeatResource
            `shouldBe` Just ()
        Generated.matchFixtureHeartbeatResource account
            `shouldBe` Nothing

        let liveScope = GeneratedLive.crossKindDeclarationLiveScope
        let liveFragment =
                GeneratedLive.crossKindDeclarationLiveFragment
                    "fixture"
                    (Just 2)
                    (Just archivedAt)
                    [memberId]
                    (Just Nothing)
                    (Just [memberId])
                    True
        let expectedFields =
                ( "fixture"
                , ( Just 2
                  , ( Just archivedAt
                    , ( [memberId]
                      , (Just Nothing, (Just [memberId], (True, ())))
                      )
                    )
                  )
                )
        GeneratedLive.matchCrossKindDeclarationLiveScope liveScope
            `shouldBe` Just ()
        GeneratedLive.matchCrossKindDeclarationLiveFragment liveFragment
            `shouldBe` Just expectedFields
        GeneratedLive.matchCrossKindDeclarationLiveFragment GeneratedLive.fixtureActorOnlyPanelLiveFragment
            `shouldBe` Nothing
        GeneratedLive.matchFixtureActorOnlyPanelLiveFragment GeneratedLive.fixtureActorOnlyPanelLiveFragment
            `shouldBe` Just ()

    it "associates one nominal production family with every registered Surface" do
        map (.haskellTypeName) (map (.adapterFamilySurfaceMarker) registeredSurfaceAdapterRegistry.surfaceAdapterFamilies)
            `shouldBe` map (.surfaceMarker) registeredFrontendSurfaceContractIR.contractSurfaces

    it "defines kind-indexed generated namespaces and matching curated facade boundaries" do
        let surfaceMetadata =
                maybe
                    (error "expected one fixture action home")
                    (.adapterHomeSurface)
                    (listToMaybe fixtureActionHomes)
        adapterGeneratedModuleName resourceAdapterLayout surfaceMetadata
            `shouldBe` "Test.Support.FrontendSurfaceAdapterFixture.Generated.Resource"
        adapterFacadeModuleName resourceAdapterLayout surfaceMetadata
            `shouldBe` "Test.Support.FrontendSurfaceAdapterFixture.Resource"
        adapterGeneratedModuleName scopeAdapterLayout surfaceMetadata
            `shouldBe` "Test.Support.FrontendSurfaceAdapterFixture.Generated.Live"
        adapterFacadeModuleName scopeAdapterLayout surfaceMetadata
            `shouldBe` "Test.Support.FrontendSurfaceAdapterFixture.Live"
        adapterGeneratedModuleName fragmentAdapterLayout surfaceMetadata
            `shouldBe` "Test.Support.FrontendSurfaceAdapterFixture.Generated.Live"
        adapterFacadeModuleName fragmentAdapterLayout surfaceMetadata
            `shouldBe` "Test.Support.FrontendSurfaceAdapterFixture.Live"
        adapterGeneratedModuleName actionAdapterLayout surfaceMetadata
            `shouldBe` "Test.Support.FrontendSurfaceAdapterFixture.Generated.Action"
        adapterFacadeModuleName actionAdapterLayout surfaceMetadata
            `shouldBe` "Test.Support.FrontendSurfaceAdapterFixture.Action"
        adapterGeneratedModuleName intentAdapterLayout surfaceMetadata
            `shouldBe` "Test.Support.FrontendSurfaceAdapterFixture.Generated.Intent"
        adapterFacadeModuleName intentAdapterLayout surfaceMetadata
            `shouldBe` "Test.Support.FrontendSurfaceAdapterFixture.Intent"

    it "selects checked scope and Live fragment declarations from Surface IR" do
        case checkedSurfaceLiveAdapterDeclarations fixtureContract fixtureRegistry of
            Left diagnostics -> expectationFailure (cs (show diagnostics))
            Right declarations -> do
                map (.checkedAdapterDeclarationMarker) declarations.checkedLiveScopeDeclarations
                    `shouldBe` ["CrossKindDeclaration"]
                map (.checkedAdapterDeclarationMarker) declarations.checkedLiveFragmentDeclarations
                    `shouldBe` ["CrossKindDeclaration", "FixtureActorOnlyPanel"]
                map (.actorOnlyFragmentReason) fixtureRegistry.surfaceActorOnlyFragmentAdapters
                    `shouldBe` ["Actor-local fixture refreshes still construct this semantic key"]

    it "requires actor-only eligibility exceptions to be unique, non-Live, and reason-bearing" do
        let actorOnly = fixtureRegistry.surfaceActorOnlyFragmentAdapters
        let blankReasons =
                fixtureRegistry
                    { surfaceActorOnlyFragmentAdapters =
                        map (\exception -> exception { actorOnlyFragmentReason = "" }) actorOnly
                    }
        diagnosticCodes (checkedSurfaceLiveAdapterDeclarations fixtureContract blankReasons)
            `shouldContain` ["actor-only-fragment-adapter-reason"]

        let redundant =
                case (actorOnly, fixtureFragmentHomes) of
                    (exception : _, liveHome : _) ->
                        fixtureRegistry
                            { surfaceActorOnlyFragmentAdapters =
                                [exception { actorOnlyFragmentHome = liveHome }]
                            }
                    _ -> fixtureRegistry
        diagnosticCodes (checkedSurfaceLiveAdapterDeclarations fixtureContract redundant)
            `shouldContain` ["redundant-actor-only-fragment-adapter"]

        let duplicated =
                fixtureRegistry
                    { surfaceActorOnlyFragmentAdapters = actorOnly <> actorOnly
                    }
        diagnosticCodes (checkedSurfaceLiveAdapterDeclarations fixtureContract duplicated)
            `shouldContain` ["duplicate-actor-only-fragment-adapter"]

    it "rejects ambiguous scope identity before Live home resolution" do
        let ambiguous =
                fixtureContract
                    { contractSurfaces =
                        map
                            (\surface -> surface { surfaceScopes = surface.surfaceScopes <> surface.surfaceScopes })
                            fixtureContract.contractSurfaces
                    }
        diagnosticCodes (checkedSurfaceLiveAdapterDeclarations ambiguous fixtureRegistry)
            `shouldContain` ["multiple-scopes"]

    it "covers every production scope and every passive or actor-only semantic fragment" do
        case checkedSurfaceLiveAdapterDeclarations registeredFrontendSurfaceContractIR registeredSurfaceAdapterRegistry of
            Left diagnostics -> expectationFailure (cs (show diagnostics))
            Right declarations -> do
                map (.checkedAdapterSurfaceName) declarations.checkedLiveScopeDeclarations
                    `shouldBe`
                        [ "timesheets"
                        , "roster"
                        , "roster-day-timeline"
                        , "leave-requests"
                        , "billing"
                        , "support"
                        , "profile"
                        , "staff"
                        , "admin-page"
                        , "admin-xero-page"
                        , "admin-venue-config"
                        , "admin-invites"
                        , "admin-exports"
                        , "admin-shift-types"
                        , "admin-roster-groups"
                        , "admin-xero"
                        ]
                map (\declaration -> (declaration.checkedAdapterSurfaceName, declaration.checkedAdapterDeclarationName)) declarations.checkedLiveFragmentDeclarations
                    `shouldBe`
                        [ ("timesheets", "timesheet-toolbar")
                        , ("timesheets", "timesheet-day-columns")
                        , ("timesheets", "timesheet-day-section")
                        , ("roster", "roster-content")
                        , ("roster", "roster-grid-toolbar")
                        , ("roster", "roster-grid-frame")
                        , ("roster", "roster-day-columns")
                        , ("roster", "roster-day-rail")
                        , ("roster", "roster-wage-rail")
                        , ("roster", "roster-slots-grid")
                        , ("roster", "roster-staff-panel")
                        , ("roster", "roster-staff-self-service-leave-form")
                        , ("roster", "roster-day-section")
                        , ("roster", "roster-row")
                        , ("roster-day-timeline", "roster-day-timeline-content")
                        , ("leave-requests", "leave-section-count")
                        , ("leave-requests", "leave-section-list")
                        , ("billing", "billing-status")
                        , ("support", "support-award-rates")
                        , ("support", "support-public-holidays")
                        , ("profile", "profile-details-section")
                        , ("profile", "profile-preferences-section")
                        , ("profile", "profile-security-section")
                        , ("profile", "profile-leave-section")
                        , ("profile", "profile-rsa-section")
                        , ("staff", "staff-details-section")
                        , ("staff", "staff-preferences-section")
                        , ("staff", "staff-leave-section")
                        , ("admin-page", "admin-page-content")
                        , ("admin-xero-page", "admin-xero-page-content")
                        , ("admin-venue-config", "admin-venue-settings")
                        , ("admin-invites", "admin-invites")
                        , ("admin-exports", "admin-exports")
                        , ("admin-shift-types", "admin-shift-types")
                        , ("admin-roster-groups", "admin-roster-groups")
                        , ("admin-xero", "admin-xero-shell")
                        ]

    it "derives checked scope and fragment declarations only from their owning Surface IR" do
        fixtureScopeDeclaration.checkedAdapterSurfaceName
            `shouldBe` fixtureSurface.surfaceName
        fixtureScopeDeclaration.checkedAdapterDeclarationName
            `shouldBe` (theFixtureScope fixtureSurface).scopeName
        fixtureScopeDeclaration.checkedAdapterFields
            `shouldBe` (theFixtureScope fixtureSurface).scopeFields
        fixtureFragmentDeclaration.checkedAdapterSurfaceName
            `shouldBe` fixtureSurface.surfaceName
        fixtureFragmentDeclaration.checkedAdapterDeclarationName
            `shouldBe` (theFixtureFragment fixtureSurface).fragmentName
        fixtureFragmentDeclaration.checkedAdapterFields
            `shouldBe` (theFixtureFragment fixtureSurface).fragmentParams
        adapterIdentityCollisionKey scopeAdapterLayout fixtureScopeDeclaration.checkedAdapterIdentity
            `shouldBe` "scope:adapter-fixture"
        adapterIdentityCollisionKey fragmentAdapterLayout fixtureFragmentDeclaration.checkedAdapterIdentity
            `shouldBe` "fragment:adapter-fixture/cross-kind-declaration"

    it "indexes checked identities by declaration kind and permits action/intent marker reuse" do
        fixtureActionDeclaration.checkedAdapterDeclarationMarker
            `shouldBe` fixtureIntentDeclaration.checkedAdapterDeclarationMarker
        fixtureActionDeclaration.checkedAdapterDeclarationName
            `shouldBe` fixtureIntentDeclaration.checkedAdapterDeclarationName
        map (.adapterHomeDeclaration) fixtureActionHomes
            `shouldBe` map (.adapterHomeDeclaration) fixtureIntentHomes
        adapterIdentityCollisionKey actionAdapterLayout fixtureActionDeclaration.checkedAdapterIdentity
            `shouldNotBe` adapterIdentityCollisionKey intentAdapterLayout fixtureIntentDeclaration.checkedAdapterIdentity
        diagnosticCodes resolveFixtureActions `shouldBe` []
        diagnosticCodes resolveFixtureIntents `shouldBe` []
        case renderFixtureActionIntentModules of
            Left diagnostics -> expectationFailure (cs (show diagnostics))
            Right generatedModules ->
                map (.generatedModuleName) generatedModules
                    `shouldBe`
                        [ "Test.Support.FrontendSurfaceAdapterFixture.Generated.Action"
                        , "Test.Support.FrontendSurfaceAdapterFixture.Generated.Intent"
                        ]

    it "allows shared scope/fragment markers but rejects real Live symbol collisions deterministically" do
        generateSurfaceLiveAdapterModules fixtureContract fixtureRegistry
            `shouldSatisfy` isRight
        diagnosticCodes (generateSurfaceLiveAdapterModules liveCollisionContract liveCollisionRegistry)
            `shouldContain` ["generated-adapter-name-collision"]

    it "checks generated-name collisions across kinds that share one output namespace" do
        diagnosticCodes renderFixtureLiveCollision
            `shouldContain` ["generated-adapter-name-collision"]

    it "renders Live source deterministically regardless of typed home order" do
        let reversedRegistry =
                fixtureRegistry
                    { surfaceScopeAdapterHomes = reverse fixtureRegistry.surfaceScopeAdapterHomes
                    , surfaceFragmentAdapterHomes = reverse fixtureRegistry.surfaceFragmentAdapterHomes
                    }
        generateSurfaceLiveAdapterModules fixtureContract reversedRegistry
            `shouldBe` generateSurfaceLiveAdapterModules fixtureContract fixtureRegistry

    it "applies shared locality validation to Live adapter homes" do
        let unrelatedFamily =
                HaskellTypeMetadata
                    { haskellTypeModule = "Application.Helper.FrontendContract.Surface.HaskellAdapter.Registry"
                    , haskellTypeName = "AdapterFixtureFamily"
                    }
        let nonLocalRegistry =
                fixtureRegistry
                    { surfaceAdapterFamilies =
                        map (\family -> family { adapterFamilyType = unrelatedFamily }) fixtureRegistry.surfaceAdapterFamilies
                    , surfaceScopeAdapterHomes =
                        map (\home -> home { adapterHomeFamily = unrelatedFamily }) fixtureRegistry.surfaceScopeAdapterHomes
                    , surfaceFragmentAdapterHomes =
                        map (\home -> home { adapterHomeFamily = unrelatedFamily }) fixtureRegistry.surfaceFragmentAdapterHomes
                    , surfaceActorOnlyFragmentAdapters =
                        map
                            (\exception ->
                                exception
                                    { actorOnlyFragmentHome =
                                        exception.actorOnlyFragmentHome { adapterHomeFamily = unrelatedFamily }
                                    }
                            )
                            fixtureRegistry.surfaceActorOnlyFragmentAdapters
                    }
        diagnosticCodes (generateSurfaceLiveAdapterModules fixtureContract nonLocalRegistry)
            `shouldContain` ["adapter-import-locality"]

    it "applies shared locality validation to non-resource adapter kinds" do
        let unrelatedFamily =
                HaskellTypeMetadata
                    { haskellTypeModule = "Application.Helper.FrontendContract.Surface.HaskellAdapter.Registry"
                    , haskellTypeName = "AdapterFixtureFamily"
                    }
        let nonLocalFamilies =
                map (\family -> family { adapterFamilyType = unrelatedFamily }) fixtureRegistry.surfaceAdapterFamilies
        let nonLocalHomes =
                map (\home -> home { adapterHomeFamily = unrelatedFamily }) fixtureActionHomes
        diagnosticCodes
            ( resolveAdapterGeneration
                actionAdapterLayout
                fixtureContract
                nonLocalFamilies
                nonLocalHomes
                [fixtureActionDeclaration]
                (const ["crossKindDeclarationFields"])
            )
            `shouldContain` ["adapter-import-locality"]

    it "reports unsupported Live source types with Surface, declaration, and field" do
        let unsupportedFragmentIR =
                fixtureFragmentDeclaration.checkedAdapterPayload
                    { fragmentParams = map replaceLabelWire fixtureFragmentDeclaration.checkedAdapterFields
                    }
        let unsupportedFragment =
                checkedFragmentAdapterDeclaration fixtureSurface unsupportedFragmentIR
        case resolveAdapterGeneration
            fragmentAdapterLayout
            fixtureContract
            fixtureRegistry.surfaceAdapterFamilies
            (take 1 fixtureFragmentHomes)
            [unsupportedFragment]
            (const ["crossKindDeclarationLiveFragment", "matchCrossKindDeclarationLiveFragment"]) of
            Right _ -> expectationFailure "expected unsupported fragment source generation to fail"
            Left diagnostics -> do
                map (.diagnosticCode) diagnostics
                    `shouldContain` ["unsupported-generated-source-type"]
                map (.diagnosticMessage) diagnostics
                    `shouldContain`
                        ["Fragment adapter-fixture/cross-kind-declaration field label has unsupported generated Haskell source type Map Text Text"]

    it "reports unsupported source types with adapter kind, owning declaration, and field" do
        let unsupportedActionIR =
                fixtureActionDeclaration.checkedAdapterPayload
                    { htmxActionFields = map replaceLabelWire fixtureActionDeclaration.checkedAdapterFields
                    }
        let unsupportedAction =
                checkedActionAdapterDeclaration fixtureSurface unsupportedActionIR
        case resolveAdapterGeneration
            actionAdapterLayout
            fixtureContract
            fixtureRegistry.surfaceAdapterFamilies
            fixtureActionHomes
            [unsupportedAction]
            (const ["crossKindDeclarationFields"]) of
            Right _ -> expectationFailure "expected unsupported action source generation to fail"
            Left diagnostics -> do
                map (.diagnosticCode) diagnostics
                    `shouldContain` ["unsupported-generated-source-type"]
                map (.diagnosticMessage) diagnostics
                    `shouldSatisfy` any (\message ->
                        "Action adapter-fixture/cross-kind-declaration field label " `Text.isInfixOf` message
                            && "Map Text Text" `Text.isInfixOf` message
                    )

    it "renders the Timesheets pilot through a feature-local generated module" do
        case generateSurfaceResourceAdapterModules registeredFrontendSurfaceContractIR registeredSurfaceAdapterRegistry of
            Left diagnostics -> expectationFailure (cs (show diagnostics))
            Right generatedModules ->
                case find ((== "Application.Helper.FrontendContract.Surface.Timesheets.Generated.Resource") . (.generatedModuleName)) generatedModules of
                    Nothing -> expectationFailure "expected the Timesheets generated resource module"
                    Just generated -> do
                        generated.generatedModuleSource `shouldSatisfy` Text.isInfixOf "timesheetDayResource"
                        generated.generatedModuleSource `shouldSatisfy` Text.isInfixOf "timesheetWeekBoundaryConfigResource"
                        generated.generatedModuleSource `shouldSatisfy` Text.isInfixOf "timesheetWeekResource"
                        generated.generatedModuleSource `shouldNotSatisfy` Text.isInfixOf "HaskellAdapter.Registry"

    it "registers exactly one home for every unique checked production resource" do
        let incompleteRegistry =
                registeredSurfaceAdapterRegistry
                    { surfaceResourceAdapterHomes = drop 1 registeredSurfaceAdapterRegistry.surfaceResourceAdapterHomes
                    }
        diagnosticCodes (generateSurfaceResourceAdapterModules registeredFrontendSurfaceContractIR incompleteRegistry)
            `shouldContain` ["missing-adapter-resource-home"]
        length registeredSurfaceAdapterRegistry.surfaceResourceAdapterHomes
            `shouldBe` length productionResourceNames
        case generateSurfaceResourceAdapterModules registeredFrontendSurfaceContractIR registeredSurfaceAdapterRegistry of
            Left diagnostics       -> expectationFailure (cs (show diagnostics))
            Right generatedModules -> length generatedModules `shouldBe` 7

    it "renders zero-field constants without unused field-builder imports" do
        let heartbeatOnly =
                fixtureRegistry
                    { surfaceResourceAdapterHomes = drop 1 fixtureRegistry.surfaceResourceAdapterHomes
                    }
        case generateSurfaceResourceAdapterModules heartbeatOnlyContract heartbeatOnly of
            Right [generated] -> do
                generated.generatedModuleSource
                    `shouldSatisfy` Text.isInfixOf "SurfaceFields (NoSurfaceFields)"
                generated.generatedModuleSource
                    `shouldNotSatisfy` Text.isInfixOf "surfaceField"
            Right _ -> expectationFailure "expected one zero-field generated module"
            Left diagnostics -> expectationFailure (cs (show diagnostics))

    it "canonicalizes typed home order before rendering" do
        let reversedRegistry =
                fixtureRegistry
                    { surfaceResourceAdapterHomes = reverse fixtureRegistry.surfaceResourceAdapterHomes
                    }
        generateFixture reversedRegistry `shouldBe` generateFixture fixtureRegistry

    it "rejects duplicate homes and resources not owned by the associated Surface" do
        let homes = fixtureRegistry.surfaceResourceAdapterHomes
        let duplicateRegistry = fixtureRegistry { surfaceResourceAdapterHomes = homes <> take 1 homes }
        diagnosticCodes (generateFixture duplicateRegistry)
            `shouldContain` ["duplicate-adapter-resource-home"]

        let missingResource =
                case homes of
                    home : rest ->
                        home
                            { adapterHomeDeclaration =
                                home.adapterHomeDeclaration { haskellTypeName = "MissingResource" }
                            }
                            : rest
                    [] -> []
        let missingRegistry = fixtureRegistry { surfaceResourceAdapterHomes = missingResource }
        diagnosticCodes (generateFixture missingRegistry)
            `shouldContain` ["adapter-resource-home-ownership"]

    it "rejects generated imports outside the owning feature module tree" do
        let unrelatedFamily =
                HaskellTypeMetadata
                    { haskellTypeModule = "Application.Helper.FrontendContract.Surface.HaskellAdapter.Registry"
                    , haskellTypeName = "AdapterFixtureFamily"
                    }
        let nonLocalRegistry =
                fixtureRegistry
                    { surfaceAdapterFamilies =
                        map (\family -> family { adapterFamilyType = unrelatedFamily }) fixtureRegistry.surfaceAdapterFamilies
                    , surfaceResourceAdapterHomes =
                        map (\home -> home { adapterHomeFamily = unrelatedFamily }) fixtureRegistry.surfaceResourceAdapterHomes
                    }
        diagnosticCodes (generateFixture nonLocalRegistry)
            `shouldContain` ["adapter-import-locality"]

    it "rejects generated declaration collisions in one feature home" do
        let collisionRegistry = fixtureRegistry { surfaceResourceAdapterHomes = collisionHomes }
        diagnosticCodes (generateSurfaceResourceAdapterModules collisionContract collisionRegistry)
            `shouldContain` ["generated-adapter-name-collision"]

    it "reports unsupported source types with the resource and field" do
        case generateSurfaceResourceAdapterModules unsupportedSourceContract fixtureRegistry of
            Right _ -> expectationFailure "expected unsupported source generation to fail"
            Left diagnostics -> do
                map (.diagnosticCode) diagnostics
                    `shouldContain` ["unsupported-generated-source-type"]
                map (.diagnosticMessage) diagnostics
                    `shouldContain` ["Resource adapter-fixture/fixture-account field label has unsupported generated Haskell source type Map Text Text"]

fixtureRegistry :: SurfaceAdapterRegistry
fixtureRegistry =
    reflectSurfaceAdapterRegistry
        @Fixture.FixtureAdapterFamilies
        @Fixture.FixtureResourceHomes
        @Fixture.FixtureScopeHomes
        @Fixture.FixtureFragmentHomes
        Fixture.fixtureActorOnlyFragments

fixtureContract :: SurfaceContractIR
fixtureContract =
    SurfaceContractIR
        { contractSurfaces = reflectSurfaceRegistry @'[Fixture.AdapterFixtureSurface]
        }
        |> either (error . cs . show) id . checkedSurfaceContractIR

liveCollisionContract :: SurfaceContractIR
liveCollisionContract =
    SurfaceContractIR
        { contractSurfaces = reflectSurfaceRegistry @Fixture.LiveCollisionSurfaces
        }
        |> either (error . cs . show) id . checkedSurfaceContractIR

liveCollisionRegistry :: SurfaceAdapterRegistry
liveCollisionRegistry =
    reflectSurfaceAdapterRegistry
        @Fixture.CollisionAdapterFamilies
        @'[]
        @Fixture.CollisionScopeHomes
        @'[]
        []

generateFixture :: SurfaceAdapterRegistry -> Either [ContractDiagnostic] [GeneratedHaskellModule]
generateFixture = generateSurfaceResourceAdapterModules fixtureContract

diagnosticCodes :: Either [ContractDiagnostic] value -> [Text]
diagnosticCodes = \case
    Right _ -> []
    Left diagnostics -> map (.diagnosticCode) diagnostics

fixtureScopeHomes :: [SurfaceAdapterHomeMetadata 'ScopeAdapterKind]
fixtureScopeHomes =
    reflectSurfaceAdapterHomes
        @'ScopeAdapterKind
        @Fixture.FixtureScopeHomes

fixtureFragmentHomes :: [SurfaceAdapterHomeMetadata 'FragmentAdapterKind]
fixtureFragmentHomes =
    reflectSurfaceAdapterHomes
        @'FragmentAdapterKind
        @Fixture.FixtureFragmentHomes

fixtureActionHomes :: [SurfaceAdapterHomeMetadata 'ActionAdapterKind]
fixtureActionHomes =
    reflectSurfaceAdapterHomes
        @'ActionAdapterKind
        @Fixture.FixtureActionHomes

fixtureIntentHomes :: [SurfaceAdapterHomeMetadata 'IntentAdapterKind]
fixtureIntentHomes =
    reflectSurfaceAdapterHomes
        @'IntentAdapterKind
        @Fixture.FixtureIntentHomes

fixtureScopeDeclaration :: CheckedAdapterDeclaration 'ScopeAdapterKind ScopeIR
fixtureScopeDeclaration =
    checkedScopeAdapterDeclaration fixtureSurface (theFixtureScope fixtureSurface)

fixtureFragmentDeclaration :: CheckedAdapterDeclaration 'FragmentAdapterKind FragmentIR
fixtureFragmentDeclaration =
    checkedFragmentAdapterDeclaration fixtureSurface (theFixtureFragment fixtureSurface)

theFixtureScope :: SurfaceIR -> ScopeIR
theFixtureScope surface =
    case surface.surfaceScopes of
        [value] -> value
        values  -> error ("expected one fixture scope, got " <> show (length values))

theFixtureFragment :: SurfaceIR -> FragmentIR
theFixtureFragment surface =
    fromMaybe
        (error "expected the CrossKindDeclaration fixture fragment")
        (find ((== "CrossKindDeclaration") . (.fragmentMarker)) surface.surfaceFragments)

fixtureActionDeclaration :: CheckedAdapterDeclaration 'ActionAdapterKind HtmxActionIR
fixtureActionDeclaration =
    checkedActionAdapterDeclaration fixtureSurface action
  where
    action = case fixtureSurface.surfaceHtmxActions of
        [value] -> value
        values  -> error ("expected one fixture action, got " <> show (length values))

fixtureIntentDeclaration :: CheckedAdapterDeclaration 'IntentAdapterKind IntentIR
fixtureIntentDeclaration =
    checkedIntentAdapterDeclaration fixtureSurface intent
  where
    intent = case fixtureSurface.surfaceIntents of
        [value] -> value
        values  -> error ("expected one fixture intent, got " <> show (length values))

fixtureSurface :: SurfaceIR
fixtureSurface =
    case fixtureContract.contractSurfaces of
        [surface] -> surface
        surfaces  -> error ("expected one fixture Surface, got " <> show (length surfaces))

resolveFixtureScopes :: Either [ContractDiagnostic] [ResolvedAdapter 'ScopeAdapterKind ScopeIR]
resolveFixtureScopes =
    resolveAdapterGeneration
        scopeAdapterLayout
        fixtureContract
        fixtureRegistry.surfaceAdapterFamilies
        fixtureScopeHomes
        fixtureLiveDeclarations.checkedLiveScopeDeclarations
        (const ["crossKindDeclaration"])

resolveFixtureFragments :: Either [ContractDiagnostic] [ResolvedAdapter 'FragmentAdapterKind FragmentIR]
resolveFixtureFragments =
    resolveAdapterGeneration
        fragmentAdapterLayout
        fixtureContract
        fixtureRegistry.surfaceAdapterFamilies
        fixtureFragmentHomes
        fixtureLiveDeclarations.checkedLiveFragmentDeclarations
        (const ["crossKindDeclaration"])

fixtureLiveDeclarations :: CheckedSurfaceLiveAdapterDeclarations
fixtureLiveDeclarations =
    either
        (error . cs . show)
        id
        (checkedSurfaceLiveAdapterDeclarations fixtureContract fixtureRegistry)

resolveFixtureActions :: Either [ContractDiagnostic] [ResolvedAdapter 'ActionAdapterKind HtmxActionIR]
resolveFixtureActions =
    resolveAdapterGeneration
        actionAdapterLayout
        fixtureContract
        fixtureRegistry.surfaceAdapterFamilies
        fixtureActionHomes
        [fixtureActionDeclaration]
        (const ["crossKindDeclarationFields"])

resolveFixtureIntents :: Either [ContractDiagnostic] [ResolvedAdapter 'IntentAdapterKind IntentIR]
resolveFixtureIntents =
    resolveAdapterGeneration
        intentAdapterLayout
        fixtureContract
        fixtureRegistry.surfaceAdapterFamilies
        fixtureIntentHomes
        [fixtureIntentDeclaration]
        (const ["crossKindDeclarationFields"])

fixtureKindRenderer :: AdapterModuleRenderer ()
fixtureKindRenderer =
    AdapterModuleRenderer
        { adapterRendererLanguagePragmas = ["{-# LANGUAGE TypeApplications #-}"]
        , adapterRendererHeaderLines = ["-- generated fixture"]
        , adapterRendererImports = \_ _ -> ["import IHP.Prelude"]
        , adapterRendererDeclaration = \_ adapter ->
            case adapter.renderableAdapterGeneratedNames of
                generatedName : _ -> [generatedName <> " = ()"]
                []                -> []
        }

renderFixtureActionIntentModules :: Either [ContractDiagnostic] [GeneratedHaskellModule]
renderFixtureActionIntentModules = do
    actions <- resolveFixtureActions
    intents <- resolveFixtureIntents
    renderGeneratedAdapterModules
        fixtureKindRenderer
        ( map (toRenderableAdapter (const ())) actions
            <> map (toRenderableAdapter (const ())) intents
        )

renderFixtureLiveCollision :: Either [ContractDiagnostic] [GeneratedHaskellModule]
renderFixtureLiveCollision = do
    scopes <- resolveFixtureScopes
    fragments <- resolveFixtureFragments
    renderGeneratedAdapterModules
        fixtureKindRenderer
        ( map (toRenderableAdapter (const ())) scopes
            <> map (toRenderableAdapter (const ())) fragments
        )

replaceLabelWire :: FieldIR -> FieldIR
replaceLabelWire field
    | field.fieldName == "label" = field { fieldWire = WireMapIR WireTextIR WireTextIR }
    | otherwise = field

productionResourceNames :: [Text]
productionResourceNames =
    [ dependency.dependencyResource.resourceName
    | surface <- registeredFrontendSurfaceContractIR.contractSurfaces
    , fragment <- surface.surfaceFragments
    , dependency <- optionResourceDependencies fragment.fragmentOptions
    ]
        |> List.nub

collisionHomes :: [SurfaceResourceAdapterHomeMetadata]
collisionHomes =
    case fixtureRegistry.surfaceResourceAdapterHomes of
        [accountHome, heartbeatHome] ->
            [ accountHome
            , heartbeatHome
                { adapterHomeDeclaration =
                    heartbeatHome.adapterHomeDeclaration
                        { haskellTypeName = "FixtureAccountResource"
                        }
                }
            ]
        homes -> homes

collisionContract :: SurfaceContractIR
collisionContract =
    mapResources renameHeartbeat fixtureContract
  where
    renameHeartbeat resource
        | resource.resourceMarker == "FixtureHeartbeatResource" =
            resource { resourceMarker = "FixtureAccountResource" }
        | otherwise = resource

heartbeatOnlyContract :: SurfaceContractIR
heartbeatOnlyContract =
    fixtureContract
        { contractSurfaces = map keepHeartbeatDependencies fixtureContract.contractSurfaces
        }
  where
    keepHeartbeatDependencies surface =
        surface
            { surfaceFragments = map keepFragmentDependencies surface.surfaceFragments
            }
    keepFragmentDependencies fragment =
        fragment
            { fragmentOptions = mapMaybe keepOption fragment.fragmentOptions
            }
    keepOption = \case
        DependsOnOption dependency
            | dependency.dependencyResource.resourceName == "fixture-heartbeat-resource" -> Just (DependsOnOption dependency)
            | otherwise -> Nothing
        LazyOption options -> Just (LazyOption (mapMaybe keepOption options))
        option -> Just option

unsupportedSourceContract :: SurfaceContractIR
unsupportedSourceContract =
    mapResources replaceLabelWire fixtureContract
  where
    replaceLabelWire resource
        | resource.resourceMarker == "FixtureAccount" =
            resource
                { resourceFields =
                    map
                        (\field ->
                            if field.fieldName == "label"
                                then field { fieldWire = WireMapIR WireTextIR WireTextIR }
                                else field
                        )
                        resource.resourceFields
                }
        | otherwise = resource

mapResources :: (ResourceIR -> ResourceIR) -> SurfaceContractIR -> SurfaceContractIR
mapResources transform contract =
    contract
        { contractSurfaces = map mapSurface contract.contractSurfaces
        }
  where
    mapSurface surface =
        surface
            { surfaceFragments = map mapFragment surface.surfaceFragments
            }
    mapFragment fragment =
        fragment
            { fragmentOptions = map mapOption fragment.fragmentOptions
            }
    mapOption = \case
        DependsOnOption dependency ->
            DependsOnOption dependency
                { dependencyResource = transform dependency.dependencyResource
                }
        LazyOption options -> LazyOption (map mapOption options)
        option -> option
