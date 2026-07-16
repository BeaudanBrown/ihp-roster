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
import Application.Helper.FrontendContract.Surface.HaskellAdapter.Registry (registeredSurfaceAdapterRegistry)
import Application.Helper.FrontendContract.Surface.Reflect (reflectSurfaceRegistry)
import qualified Data.List as List
import qualified Data.Text as Text
import qualified Data.Text.IO as Text
import Data.Time (fromGregorian)
import qualified Data.UUID as UUID
import IHP.Prelude
import Test.Hspec
import qualified Test.Support.FrontendSurfaceAdapterFixture as Fixture
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

    it "checks generated-name collisions across kinds that share one output namespace" do
        diagnosticCodes renderFixtureLiveCollision
            `shouldContain` ["generated-adapter-name-collision"]

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

    it "reports unsupported source types with adapter kind, owning declaration, and field" do
        let unsupportedAction =
                fixtureActionDeclaration
                    { checkedAdapterFields = map replaceLabelWire fixtureActionDeclaration.checkedAdapterFields
                    }
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
                        "Action " `Text.isInfixOf` message
                            && " field label " `Text.isInfixOf` message
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
                    `shouldContain` ["Resource fixture-account field label has unsupported generated Haskell source type Map Text Text"]

fixtureRegistry :: SurfaceAdapterRegistry
fixtureRegistry =
    reflectSurfaceAdapterRegistry
        @Fixture.FixtureAdapterFamilies
        @Fixture.FixtureResourceHomes

fixtureContract :: SurfaceContractIR
fixtureContract =
    SurfaceContractIR
        { contractSurfaces = reflectSurfaceRegistry @'[Fixture.AdapterFixtureSurface]
        }
        |> either (error . cs . show) id . checkedSurfaceContractIR

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
    let surface = fixtureSurface
        scope = case surface.surfaceScopes of
            [value] -> value
            values  -> error ("expected one fixture scope, got " <> show (length values))
     in CheckedAdapterDeclaration
            { checkedAdapterIdentity = scopeAdapterIdentity surface.surfaceName
            , checkedAdapterSurfaceMarker = surface.surfaceMarker
            , checkedAdapterSurfaceName = surface.surfaceName
            , checkedAdapterDeclarationMarker = scope.scopeMarker
            , checkedAdapterDeclarationName = scope.scopeName
            , checkedAdapterFields = scope.scopeFields
            , checkedAdapterPayload = scope
            }

fixtureFragmentDeclaration :: CheckedAdapterDeclaration 'FragmentAdapterKind FragmentIR
fixtureFragmentDeclaration =
    let surface = fixtureSurface
        fragment = case surface.surfaceFragments of
            [value] -> value
            values  -> error ("expected one fixture fragment, got " <> show (length values))
     in CheckedAdapterDeclaration
            { checkedAdapterIdentity = fragmentAdapterIdentity surface.surfaceName fragment.fragmentName
            , checkedAdapterSurfaceMarker = surface.surfaceMarker
            , checkedAdapterSurfaceName = surface.surfaceName
            , checkedAdapterDeclarationMarker = fragment.fragmentMarker
            , checkedAdapterDeclarationName = fragment.fragmentName
            , checkedAdapterFields = fragment.fragmentParams
            , checkedAdapterPayload = fragment
            }

fixtureActionDeclaration :: CheckedAdapterDeclaration 'ActionAdapterKind HtmxActionIR
fixtureActionDeclaration =
    let surface = fixtureSurface
        action = case surface.surfaceHtmxActions of
            [value] -> value
            values  -> error ("expected one fixture action, got " <> show (length values))
     in CheckedAdapterDeclaration
            { checkedAdapterIdentity = actionAdapterIdentity surface.surfaceName action.htmxActionName
            , checkedAdapterSurfaceMarker = surface.surfaceMarker
            , checkedAdapterSurfaceName = surface.surfaceName
            , checkedAdapterDeclarationMarker = action.htmxActionMarker
            , checkedAdapterDeclarationName = action.htmxActionName
            , checkedAdapterFields = action.htmxActionFields
            , checkedAdapterPayload = action
            }

fixtureIntentDeclaration :: CheckedAdapterDeclaration 'IntentAdapterKind IntentIR
fixtureIntentDeclaration =
    let surface = fixtureSurface
        intent = case surface.surfaceIntents of
            [value] -> value
            values  -> error ("expected one fixture intent, got " <> show (length values))
     in CheckedAdapterDeclaration
            { checkedAdapterIdentity = intentAdapterIdentity surface.surfaceName intent.intentName
            , checkedAdapterSurfaceMarker = surface.surfaceMarker
            , checkedAdapterSurfaceName = surface.surfaceName
            , checkedAdapterDeclarationMarker = intent.intentMarker
            , checkedAdapterDeclarationName = intent.intentName
            , checkedAdapterFields = intent.intentFields
            , checkedAdapterPayload = intent
            }

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
        [fixtureScopeDeclaration]
        (const ["crossKindDeclaration"])

resolveFixtureFragments :: Either [ContractDiagnostic] [ResolvedAdapter 'FragmentAdapterKind FragmentIR]
resolveFixtureFragments =
    resolveAdapterGeneration
        fragmentAdapterLayout
        fixtureContract
        fixtureRegistry.surfaceAdapterFamilies
        fixtureFragmentHomes
        [fixtureFragmentDeclaration]
        (const ["crossKindDeclaration"])

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
