{-# LANGUAGE DataKinds        #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators    #-}

module Test.FrontendSurfaceDslSpec
    ( tests
    ) where

import Application.Helper.FrontendContract.Core (schemaNameAndMarker)
import Application.Helper.FrontendContract.IR (FrontendContractIR (..))
import Application.Helper.FrontendContract.Registry (registeredFrontendContractIR)
import Application.Helper.FrontendContract.Surface.ContractIR
import Application.Helper.FrontendContract.Surface.Contracts (registeredFrontendSurfaceContractIR)
import Application.Helper.FrontendContract.Surface.DSL
import qualified Application.Helper.FrontendContract.Surface.Interaction as SurfaceInteraction
import Application.Helper.FrontendContract.Surface.Live (frontendSurfaceFragmentKey)
import Application.Helper.FrontendContract.Surface.Reflect
import Application.Helper.FrontendContract.Surface.Registry (RegisteredFrontendSurfaces)
import Application.Helper.FrontendContract.Surface.Resource
import qualified Application.Helper.FrontendContract.Surface.Roster as RosterSurface
import Application.Helper.FrontendContract.Surface.Runtime
import qualified Application.Helper.FrontendContract.Surface.Timesheets as TimesheetsSurface
import Application.Helper.FrontendContract.Surface.Values
import Application.Helper.FrontendContract.TypeScript (renderFrontendContractTypeScript)
import Application.Helper.SurfaceResource
import qualified Data.Aeson as Aeson
import Data.Proxy (Proxy (..))
import qualified Data.Text as Text
import qualified Data.UUID as UUID
import IHP.Prelude
import Test.Hspec
import qualified Test.Support.FrontendSurfaceFixture as SurfaceFixture
import qualified Text.Blaze.Html.Renderer.Text as HtmlRenderer
import qualified Text.Blaze.Html5 as Html5

data TestLoad
data TestPanel
data Parent
data ParentScope
data ParentContent
data Child
data ChildScope
data MissingContained
data MissingContainedScope
data MissingContainedContent
data CycleA
data CycleAScope
data CycleAContent
data CycleB
data CycleBScope
data CycleBContent
data TypedHtmx
data TypedHtmxScope
data TypedHtmxAction
data RawHtmxAction
data TypedHtmxShell
data NullableTestField

type TypedHtmxSurface =
    Surface TypedHtmx
        '[ Scope TypedHtmxScope '[] '[ 'NoAuth ]
         , DomToken TypedHtmxShell
         , Action TypedHtmxAction '[]
            '[ 'HtmxMethod 'HtmxGet
             , 'HtmxTrigger 'HtmxClick
             , 'HtmxTarget ('HtmxId TypedHtmxShell)
             , 'HtmxSwap 'HtmxNoSwap
             , 'HtmxSync ('HtmxSyncOn ('HtmxClosest ('HtmxId TypedHtmxShell)) 'HtmxSyncReplace)
             ]
         , Action RawHtmxAction '[]
            '[ 'HtmxTarget ('HtmxRawSelector "[data-fixture]" "fixture proves the reason-bearing raw selector escape")
             ]
         ]

type ParentSurface =
    Surface Parent
        '[ Scope ParentScope '[] '[ 'NoAuth ]
         , Fragment ParentContent '[] '[ 'MountTarget ParentContent '[], 'ContainsSurface Child ]
         ]

type ChildSurface =
    Surface Child
        '[ Scope ChildScope '[] '[ 'NoAuth ]
         ]

type MissingContainedSurface =
    Surface MissingContained
        '[ Scope MissingContainedScope '[] '[ 'NoAuth ]
         , Fragment MissingContainedContent '[] '[ 'ContainsSurface Child ]
         ]

type CycleASurface =
    Surface CycleA
        '[ Scope CycleAScope '[] '[ 'NoAuth ]
         , Fragment CycleAContent '[] '[ 'ContainsSurface CycleB ]
         ]

type CycleBSurface =
    Surface CycleB
        '[ Scope CycleBScope '[] '[ 'NoAuth ]
         , Fragment CycleBContent '[] '[ 'ContainsSurface CycleA ]
         ]

frontendSurfaceContractsTypeScript :: Text
frontendSurfaceContractsTypeScript =
    either error id (renderFrontendContractTypeScript registeredFrontendContractIR)

frontendSurfaceFixtureContractIR :: SurfaceContractIR
frontendSurfaceFixtureContractIR =
    let reflected = SurfaceContractIR (reflectSurfaceRegistry @'[SurfaceFixture.FrontendSurfaceFixture])
     in either (error . cs . tshow) id (checkedSurfaceContractIR reflected)

frontendSurfaceFixtureTypeScript :: Text
frontendSurfaceFixtureTypeScript =
    either error id (renderFrontendContractTypeScript fixtureContract)
  where
    fixtureContract :: FrontendContractIR
    fixtureContract = FrontendContractIR
        { contractGlobals = registeredFrontendContractIR.contractGlobals
        , contractSurfaces = frontendSurfaceFixtureContractIR.contractSurfaces
        }

tests :: Spec
tests = describe "FrontendSurface DSL foundation" do
    it "kind-checks the unregistered contract fixture and production root registry" do
        let _fixture = Proxy @SurfaceFixture.FrontendSurfaceFixture
        let _timesheets = Proxy @TimesheetsSurface.TimesheetsSurface
        let _roster = Proxy @RosterSurface.RosterSurface
        let _registry = Proxy @RegisteredFrontendSurfaces
        True `shouldBe` True

    it "resolves Surface values by owning surface and marker without registry scans" do
        (surfaceNameValue @TimesheetsSurface.TimesheetsSurface) `shouldBe` "timesheets"
        (surfaceScopeValue @TimesheetsSurface.TimesheetsSurface @TimesheetsSurface.TimesheetWeek).scopeName `shouldBe` "timesheet-week"
        (surfaceScopeFieldName @TimesheetsSurface.TimesheetsSurface @TimesheetsSurface.TimesheetWeek @TimesheetsSurface.VenueId) `shouldBe` "venueId"
        (surfaceFragmentValue @TimesheetsSurface.TimesheetsSurface @TimesheetsSurface.TimesheetDaySection).fragmentName `shouldBe` "timesheet-day-section"
        (surfaceFragmentFieldName @TimesheetsSurface.TimesheetsSurface @TimesheetsSurface.TimesheetDaySection @TimesheetsSurface.DayOffset) `shouldBe` "dayOffset"
        (surfaceActionValue @TimesheetsSurface.TimesheetsSurface @TimesheetsSurface.NavigateTimesheetWeek).htmxActionName `shouldBe` "navigate-timesheet-week"
        (surfaceResourceValue @TimesheetsSurface.TimesheetsSurface @TimesheetsSurface.TimesheetDay).resourceName `shouldBe` "timesheet-day"
        (surfaceDomTokenValue @TimesheetsSurface.TimesheetsSurface @TimesheetsSurface.TimesheetWeekShell) `shouldBe` "timesheet-week-shell"
        (surfaceSourceRefValue @RosterSurface.RosterDayTimelineSurface @SurfaceInteraction.DragSourceRef).sourceRefName `shouldBe` "drag-source"
        (surfaceDropzoneRefValue @RosterSurface.RosterDayTimelineSurface @SurfaceInteraction.DragDropzoneRef).dropzoneRefName `shouldBe` "drag-dropzone"
        (surfaceIntentFieldName @SurfaceFixture.FrontendSurfaceFixture @SurfaceFixture.MoveCard @SurfaceFixture.SourceItemKey) `shouldBe` "sourceItemKey"

    it "renders typed HTMX selector, trigger, swap, and sync syntax deterministically" do
        let surface = reflectSurfaceSpec @TypedHtmxSurface
        let typedAction = surface.surfaceHtmxActions |> find ((== "typed-htmx") . (.htmxActionName))
        let rawAction = surface.surfaceHtmxActions |> find ((== "raw-htmx") . (.htmxActionName))

        fmap (.htmxActionOptions) typedAction
            `shouldBe` Just
                [ HtmxOption (HtmxActionMethodIR HtmxGetIR)
                , HtmxOption (HtmxActionTriggerIR (HtmxTypedSyntaxIR "click" []))
                , HtmxOption (HtmxActionTargetIR (HtmxTypedSyntaxIR "#typed-htmx-shell" ["typed-htmx-shell"]))
                , HtmxOption (HtmxActionSwapIR (HtmxTypedSyntaxIR "none" []))
                , HtmxOption (HtmxActionSyncIR (HtmxTypedSyntaxIR "closest #typed-htmx-shell:replace" ["typed-htmx-shell"]))
                ]
        fmap (.htmxActionOptions) rawAction
            `shouldBe` Just
                [ HtmxOption (HtmxActionTargetIR (HtmxRawSyntaxIR "[data-fixture]" "fixture proves the reason-bearing raw selector escape"))
                ]

    it "builds exact typed Surface fields without phantom JSON" do
        let fields =
                surfaceField @TimesheetsSurface.VenueId
                    (fromMaybe (error "invalid fixture UUID") (UUID.fromString "11111111-1111-1111-1111-111111111111"))
                    :& surfaceField @TimesheetsSurface.WeekOffset (2 :: Int)
                    :& NoSurfaceFields
        let scopeFields = fields :: SurfaceFields (SurfaceScopeFieldSpecs TimesheetsSurface.TimesheetsSurface TimesheetsSurface.TimesheetWeek)

        surfaceFieldsJson scopeFields
            `shouldBe` Aeson.object
                [ "venueId" Aeson..= ("11111111-1111-1111-1111-111111111111" :: Text)
                , "weekOffset" Aeson..= (2 :: Int)
                ]
        surfaceFieldsText scopeFields
            `shouldBe` [("venueId", "11111111-1111-1111-1111-111111111111"), ("weekOffset", "2")]
        let absentOptionalFields :: SurfaceFields '[ 'OptionalField TimesheetsSurface.StaffFilterId 'WireUUID]
            absentOptionalFields = surfaceOptionalField @TimesheetsSurface.StaffFilterId Nothing :& NoSurfaceFields
        surfaceFieldsJson absentOptionalFields `shouldBe` Aeson.object []
        surfaceFieldsText absentOptionalFields `shouldBe` []
        let nullFields :: SurfaceFields '[ 'NullableField NullableTestField 'WireText]
            nullFields = surfaceNullableField @NullableTestField Nothing :& NoSurfaceFields
        surfaceFieldsJson nullFields `shouldBe` Aeson.object ["nullableTest" Aeson..= Aeson.Null]
        (surfaceActionFieldName @TimesheetsSurface.TimesheetsSurface @TimesheetsSurface.NavigateTimesheetWeek @TimesheetsSurface.WeekOffset)
            `shouldBe` "weekOffset"

    it "renders minimal mount-local runtime metadata from production Surface values" do
        let venueId = fromMaybe (error "invalid fixture venue UUID") (UUID.fromString "22222222-2222-2222-2222-222222222222")
        let fragment =
                frontendSurfaceMountedFragmentFor @TimesheetsSurface.TimesheetsSurface @TimesheetsSurface.TimesheetToolbar
                    NoSurfaceFields
                    NoSurfaceFields
                    "/fixture/timesheet-toolbar"
                    ( FrontendSurfaceFocusedFieldConfig FrontendSurfaceFocusedFieldProtectionConfig
                        { focusedProtectionActiveSelector = "input[data-fixture-field]:focus"
                        , focusedProtectionFieldKeyAttr = "data-fixture-field"
                        , focusedProtectionFieldNameFallback = True
                        , focusedProtectionContainerSelector = Just "form[data-fixture-row]"
                        }
                    )
        let impl =
                mkSurfaceImplFromValues @TimesheetsSurface.TimesheetsSurface @TimesheetsSurface.TimesheetWeek
                    "primary"
                    ( surfaceField @TimesheetsSurface.VenueId venueId
                        :& surfaceField @TimesheetsSurface.WeekOffset (0 :: Int)
                        :& NoSurfaceFields
                    )
                    ( surfaceField @TimesheetsSurface.ShowApproved False
                        :& surfaceField @TimesheetsSurface.ShowAllStaff False
                        :& surfaceField @TimesheetsSurface.ShowSuggestions True
                        :& surfaceField @TimesheetsSurface.StaffFilterId Nothing
                        :& NoSurfaceFields
                    )
                    [fragment]
        let config = impl.surfaceImplMountConfig
        let html = cs (HtmlRenderer.renderHtml (renderFrontendSurfaceMount impl (Html5.toHtml ("body" :: Text))))
        impl.surfaceImplName `shouldBe` "timesheets"
        surfaceActionNameValue @SurfaceFixture.FrontendSurfaceFixture @SurfaceFixture.RefreshPanel `shouldBe` "refresh-panel"
        surfaceIntentNameValue @SurfaceFixture.FrontendSurfaceFixture @SurfaceFixture.MoveCard `shouldBe` "move-card"
        html `shouldContainText` "data-bepis-surface=\"timesheets\""
        html `shouldContainText` "data-bepis-surface-config="
        html `shouldNotContainText` "data-live-update-surface"
        frontendSurfaceMountConfigJson config `shouldContainText` "\"mountKey\":\"primary\""
        frontendSurfaceMountConfigJson config `shouldContainText` "\"targetId\":\"timesheet-week-toolbar\""
        frontendSurfaceMountConfigJson config `shouldContainText` "\"kind\":\"focused-field\""
        frontendSurfaceMountConfigJson config `shouldContainText` "\"activeSelector\":\"input[data-fixture-field]:focus\""
        frontendSurfaceMountConfigJson config `shouldContainText` "\"fragmentKey\":{\"kind\":\"timesheet-toolbar\",\"params\":{},\"surface\":\"timesheets\"}"
        let mountConfigJson = frontendSurfaceMountConfigJson config
        mountConfigJson `shouldContainText` "\"fragmentKey\""
        mountConfigJson `shouldNotContainText` "\"mountState\""
        mountConfigJson `shouldNotContainText` "\"loadPolicy\""
        mountConfigJson `shouldNotContainText` "\"resyncFragments\""
        mountConfigJson `shouldNotContainText` "\"deferUntilBlur\""
        mountConfigJson `shouldNotContainText` "\"protectionPolicy\""
        Text.count "\"url\":" mountConfigJson `shouldBe` length config.mountFragments

    it "renders lazy fragments with canonical UI-region attrs and feature slot classes" do
        let panelId = fromMaybe (error "invalid fixture panel UUID") (UUID.fromString "11111111-1111-1111-1111-111111111111")
        let fragment =
                frontendSurfaceMountedFragmentFor @SurfaceFixture.FrontendSurfaceFixture @SurfaceFixture.FixturePanel
                    (surfaceField @SurfaceFixture.PanelId panelId :& NoSurfaceFields)
                    NoSurfaceFields
                    "/fixture/panel"
                    FrontendSurfaceReplace
        let html = cs (HtmlRenderer.renderHtml (renderFrontendSurfaceLazyFragmentWithConfig defaultFrontendSurfaceLazyFragmentConfig { lazyFragmentRootClasses = ["col-12", "col-xl-4", "contract-fixture-side"] } fragment (Html5.toHtml ("Loading" :: Text))))
        html `shouldContainText` "id=\"contract-fixture-panel\""
        html `shouldContainText` "class=\"col-12 col-xl-4 contract-fixture-side app-lazy-surface app-lazy-surface-compact app-lazy-surface-panel\""
        html `shouldContainText` "data-bepis-fragment=\"true\""
        html `shouldContainText` "data-bepis-lazy-surface=\"true\""
        html `shouldContainText` "data-bepis-lazy-fragment=\"fixture-panel\""
        html `shouldContainText` "data-bepis-lazy-retry=\"true\""
        html `shouldContainText` "hx-get=\"/fixture/panel\""
        html `shouldContainText` "hx-trigger=\"load\""
        html `shouldNotContainText` "data-bepis-surface-lazy"

        let customPlaceholderHtml = cs (HtmlRenderer.renderHtml (renderFrontendSurfaceLazyFragmentWithConfig customPlaceholderFrontendSurfaceLazyFragmentConfig { lazyFragmentRootClasses = ["col-12", "col-xl-4", "contract-fixture-side"] } fragment (Html5.toHtml ("Loading" :: Text))))
        customPlaceholderHtml `shouldContainText` "class=\"col-12 col-xl-4 contract-fixture-side app-lazy-surface app-lazy-surface-custom app-lazy-surface-panel\""

    it "derives lazy trigger and placeholder defaults from existing primitive options" do
        let defaults = knownFragmentOptions @'[ 'Lazy '[ 'Trigger TestLoad, 'Placeholder TestPanel ]]
        defaults.lazyFragmentDefaultTrigger `shouldBe` Just "test-load"
        defaults.lazyFragmentDefaultPlaceholderKind `shouldBe` Just "test-panel"

    it "builds mounted parameterized fragment keys from exact marker-indexed values" do
        let panelId = fromMaybe (error "invalid fixture panel UUID") (UUID.fromString "11111111-1111-1111-1111-111111111111")
        let fields = surfaceField @SurfaceFixture.PanelId panelId :& NoSurfaceFields
        let key = frontendSurfaceFragmentKey @SurfaceFixture.FrontendSurfaceFixture @SurfaceFixture.FixturePanel fields
        let fragment =
                frontendSurfaceMountedFragmentFor @SurfaceFixture.FrontendSurfaceFixture @SurfaceFixture.FixturePanel
                    fields
                    NoSurfaceFields
                    "/fixture/panel?panelId=11111111-1111-1111-1111-111111111111"
                    FrontendSurfaceReplace

        surfaceFieldsText fields `shouldBe` [("panelId", "11111111-1111-1111-1111-111111111111")]
        Aeson.toJSON key `shouldBe` Aeson.object
            [ "surface" Aeson..= ("contract-fixture" :: Text)
            , "kind" Aeson..= ("fixture-panel" :: Text)
            , "params" Aeson..= Aeson.object ["panelId" Aeson..= ("11111111-1111-1111-1111-111111111111" :: Text)]
            ]
        fragment.mountedFragmentKey `shouldBe` key
        fragment.mountedFragmentTargetId `shouldBe` surfaceFragmentTargetId @SurfaceFixture.FrontendSurfaceFixture @SurfaceFixture.FixturePanel NoSurfaceFields
        fragment.mountedFragmentUrl `shouldBe` "/fixture/panel?panelId=11111111-1111-1111-1111-111111111111"

    it "reflects the complete production Surface registry in declared order" do
        map (.surfaceName) registeredFrontendSurfaceContractIR.contractSurfaces
            `shouldBe` [ "timesheets"
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

    it "reflects and renders contained Surface topology from real DSL specs" do
        let reflected = SurfaceContractIR (reflectSurfaceRegistry @'[ParentSurface, ChildSurface])
        checkedSurfaceContractIR reflected `shouldBe` Right reflected
        let parent = expectSurface "parent" reflected
        parent.surfaceFragments
            |> listToMaybe
            |> fmap (.fragmentOptions)
            `shouldBe` Just [MountTargetOption "parent-content" [], ContainsSurfaceOption "child"]
        let fixtureContract = FrontendContractIR
                { contractGlobals = registeredFrontendContractIR.contractGlobals
                , contractSurfaces = reflected.contractSurfaces
                }
        let rendered = either error id (renderFrontendContractTypeScript fixtureContract)
        rendered `shouldNotContainText` "parentSurface"
        rendered `shouldNotContainText` "containedSurfaces"

    it "validates missing and cyclic contained Surface references after reflection" do
        let missingChild = checkedSurfaceContractIR (SurfaceContractIR (reflectSurfaceRegistry @'[MissingContainedSurface]))
        let cycle = checkedSurfaceContractIR (SurfaceContractIR (reflectSurfaceRegistry @'[CycleASurface, CycleBSurface]))
        diagnosticMessages missingChild `shouldContain` ["surface missing-contained fragment missing-contained-content contains missing surface child"]
        diagnosticMessages cycle `shouldContain` ["surface containment cycle includes cycle-a"]

    it "reflects the unregistered fixture surface into checked contract IR" do
        let surface = expectSurface "contract-fixture" frontendSurfaceFixtureContractIR

        surface.surfaceName `shouldBe` "contract-fixture"
        map (.scopeName) surface.surfaceScopes `shouldBe` ["fixture"]
        map (.fragmentName) surface.surfaceFragments `shouldBe` ["fixture-shell", "fixture-panel"]
        map (.htmxActionName) surface.surfaceHtmxActions `shouldBe` ["refresh-panel"]
        map (.intentName) surface.surfaceIntents `shouldBe` ["move-card"]
        map (.sessionName) surface.surfaceSessions `shouldBe` ["drag"]
        map (.sessionLayers) surface.surfaceSessions `shouldBe` [["drag-preview"]]
        map (map interactionEffectSemanticName . (.sessionEffects)) surface.surfaceSessions
            `shouldBe` [["clone-shadow", "dropzone-highlight"]]
        surface.surfaceLayers `shouldBe` ["drag-preview"]
        surface.surfaceDomTokens `shouldBe` ["fixture-root", "fixture-dropzone", "fixture-panel-include"]
        surface.surfaceBrowserDomTokens `shouldBe` []
        map (fst . schemaNameAndMarker) surface.surfaceDtos `shouldBe` ["FixturePayload", "FixtureRelatedPayload"]
        surface.surfaceFragments
            |> find (\fragment -> fragment.fragmentName == "fixture-panel")
            |> fmap (.fragmentOptions)
            `shouldBe` Just [MountTargetOption "contract-fixture-panel" [], LazyOption [TriggerOption "load", PlaceholderOption "panel"]]
        surface.surfaceHtmxActions
            |> find (\action -> action.htmxActionName == "refresh-panel")
            |> fmap (.htmxActionOptions)
            `shouldBe` Just
                [ TargetOption "fixture-panel"
                , HtmxOption (HtmxActionMethodIR HtmxPostIR)
                , HtmxOption (HtmxActionTargetIR (HtmxTypedSyntaxIR "#contract-fixture-panel" ["contract-fixture-panel"]))
                , HtmxOption (HtmxActionSwapIR (HtmxTypedSyntaxIR "outerHTML" []))
                , HtmxOption (HtmxActionIncludeIR (HtmxTypedSyntaxIR "#fixture-panel-include" ["fixture-panel-include"]))
                , HtmxOption (HtmxActionPushUrlIR HtmxPushUrlFalseIR)
                , HtmxOption (HtmxActionCustomHtmxIR "fixture-panel-custom-htmx" "test fixture covers auditable custom HTMX metadata")
                ]

    it "reflects the registered timesheets surface into checked contract IR" do
        let surface = expectSurface "timesheets" registeredFrontendSurfaceContractIR

        map (.scopeName) surface.surfaceScopes `shouldBe` ["timesheet-week"]
        map (.scopeOptions) surface.surfaceScopes `shouldBe` [[AuthorizeCurrentVenueIR "venueId"]]
        map (.mountStateName) surface.surfaceMountStates `shouldBe` ["timesheets-mount-state"]
        map (.fragmentName) surface.surfaceFragments `shouldBe` ["timesheet-toolbar", "timesheet-day-columns", "timesheet-day-section"]
        surface.surfaceBrowserDomTokens `shouldBe` ["timesheet-week-shell"]
        surface.surfaceFragments
            |> find (\fragment -> fragment.fragmentName == "timesheet-day-section")
            |> fmap (.fragmentParams)
            |> fmap (map (.fieldName))
            `shouldBe` Just ["dayOffset"]
        surface.surfaceMountStates
            |> listToMaybe
            |> fmap (.mountStateFields)
            |> fmap (map (\field -> (field.fieldName, field.fieldWire)))
            `shouldBe` Just
                [ ("showApproved", WireBoolIR)
                , ("showAllStaff", WireBoolIR)
                , ("showSuggestions", WireBoolIR)
                , ("staffFilterId", WireOptionalIR WireUuidIR)
                ]
        let navigateAction = surfaceActionValue @TimesheetsSurface.TimesheetsSurface @TimesheetsSurface.NavigateTimesheetWeek
        navigateAction.htmxActionOptions
            `shouldContain` [HtmxOption (HtmxActionSyncIR (HtmxTypedSyntaxIR "closest #timesheet-week-shell:replace" ["timesheet-week-shell"]))]
        navigateAction.htmxActionOptions
            `shouldSatisfy` all (\case HtmxOption HtmxActionCustomHtmxIR {} -> False; _ -> True)

    it "renders only browser-reachable contracts for the unregistered fixture" do
        frontendSurfaceFixtureTypeScript `shouldContainText` "export type ContractFixtureSurfaceFragmentKey ="
        frontendSurfaceFixtureTypeScript `shouldContainText` "export type ContractFixtureMountConfig = { surface: \"contract-fixture\"; scopeKey: string; mountKey: string; fragments: ReadonlyArray<ContractFixtureMountedFragmentConfig>; subscription: null };"
        frontendSurfaceFixtureTypeScript `shouldContainText` "{ kind: \"fixture-panel\"; params: ContractFixtureFixturePanelFragmentParams }"
        frontendSurfaceFixtureTypeScript `shouldContainText` "\"contract-fixture\":[]"
        frontendSurfaceFixtureTypeScript `shouldContainText` "\"contract-fixture\":{\"sourceRefs\":[]"
        frontendSurfaceFixtureTypeScript `shouldNotContainText` "RefreshPanelActionFields"
        frontendSurfaceFixtureTypeScript `shouldNotContainText` "FrontendSurfaceActionManifest"
        frontendSurfaceFixtureTypeScript `shouldNotContainText` "MoveCardIntentFields"
        frontendSurfaceFixtureTypeScript `shouldNotContainText` "export type FixturePayload"
        frontendSurfaceFixtureTypeScript `shouldNotContainText` "contractFixtureSurfaceManifest"
        frontendSurfaceFixtureTypeScript `shouldNotContainText` "parseFrontendSurfaceName"

    it "renders generated TypeScript contracts for the timesheets surface" do
        frontendSurfaceContractsTypeScript `shouldContainText` "export type TimesheetsSurfaceFragmentKey ="
        frontendSurfaceContractsTypeScript `shouldContainText` "{ kind: \"timesheet-day-section\"; params: TimesheetsTimesheetDaySectionFragmentParams }"
        frontendSurfaceContractsTypeScript `shouldContainText` "export type TimesheetsMountConfig ="
        frontendSurfaceContractsTypeScript `shouldNotContainText` "TimesheetsTimesheetsMountStateMountState"
        frontendSurfaceContractsTypeScript `shouldNotContainText` "export type TimesheetsMountState ="
        frontendSurfaceContractsTypeScript `shouldContainText` "\"timesheets\":[\"timesheet-toolbar\",\"timesheet-day-columns\",\"timesheet-day-section\"]"
        frontendSurfaceContractsTypeScript `shouldNotContainText` "timesheetsSurfaceManifest"

    it "reflects the registered roster surface into checked contract IR" do
        let surface = expectSurface "roster" registeredFrontendSurfaceContractIR

        map (.scopeName) surface.surfaceScopes `shouldBe` ["roster-week"]
        surface.surfaceBrowserDomTokens `shouldBe` ["roster-content", "roster-week-shell"]
        map (.fragmentName) surface.surfaceFragments
            `shouldBe` [ "roster-content"
                       , "roster-grid-toolbar"
                       , "roster-grid-frame"
                       , "roster-day-columns"
                       , "roster-day-rail"
                       , "roster-wage-rail"
                       , "roster-slots-grid"
                       , "roster-staff-panel"
                       , "roster-staff-self-service-leave-form"
                       , "roster-week-overview"
                       , "roster-day-section"
                       , "roster-row"
                       ]
        surface.surfaceFragments
            |> find (\fragment -> fragment.fragmentName == "roster-row")
            |> fmap (.fragmentParams)
            |> fmap (map (.fieldName))
            `shouldBe` Just ["rosterDayId", "rowIndex"]
        map (.htmxActionName) surface.surfaceHtmxActions
            `shouldBe` [ "navigate-roster-week"
                       , "toggle-roster-warnings"
                       , "toggle-roster-wage-estimates"
                       , "sort-roster-week"
                       , "toggle-roster-week-live-status"
                       , "toggle-roster-assignment-filters"
                       , "copy-roster-week"
                       , "create-roster-self-service-leave-request"
                       , "create-roster-week-slot-definition"
                       , "delete-roster-week-slot-definition"
                       , "toggle-roster-day-closed"
                       , "add-roster-row"
                       , "remove-roster-row"
                       , "toggle-roster-staff-scope"
                       , "set-roster-layout-mode"
                       , "move-roster-shift-to-slot"
                       , "duplicate-roster-shift-to-day"
                       , "drop-roster-staff"
                       ]
        ( surface.surfaceHtmxActions
            |> find (\action -> action.htmxActionName == "navigate-roster-week")
            |> maybe [] (.htmxActionOptions)
            )
            `shouldContain` [HtmxOption (HtmxActionSwapIR (HtmxTypedSyntaxIR "outerHTML" []))]
        map (.intentName) surface.surfaceIntents `shouldBe` ["set-roster-layout-mode", "move-roster-shift-to-slot", "duplicate-roster-shift-to-day", "drop-roster-staff"]
        map (.sessionName) surface.surfaceSessions `shouldBe` ["drag"]
        map (.sessionLayers) surface.surfaceSessions `shouldBe` [["drag-preview"]]
        map (.sourceRefName) surface.surfaceSourceRefs `shouldBe` ["shift-drag-source", "staff-drag-source"]
        map (.sourceRefCompatibleDropzones) surface.surfaceSourceRefs
            `shouldBe` [ ["shift-slot-dropzone", "day-column-dropzone", "delete-shift-dropzone"]
                       , ["existing-shift-dropzone", "shift-slot-dropzone", "staff-create-dropzone"]
                       ]
        map (.dropzoneRefName) surface.surfaceDropzoneRefs `shouldBe` ["shift-slot-dropzone", "staff-create-dropzone", "day-column-dropzone", "existing-shift-dropzone", "delete-shift-dropzone"]
        map (.activationRefName) surface.surfaceActivationRefs `shouldBe` ["roster-layout-mode-activation"]
        surface.surfaceLayers `shouldBe` ["drag-preview"]
        map (map interactionEffectSemanticName . (.sessionEffects)) surface.surfaceSessions
            `shouldBe` [["clone-shadow", "dropzone-highlight"]]
        map (map interactionEffectBrowserKind . (.sessionEffects)) surface.surfaceSessions
            `shouldBe` [["clone-shadow", "dropzone-highlight"]]
        map (map interactionEffectClassNames . (.sessionEffects)) surface.surfaceSessions
            `shouldBe` [[["bepis-pointer-clone-shadow"], ["bepis-dropzone-highlight"]]]
        map (map (.modifierVariantSemantic) . (.sourceRefVariants)) surface.surfaceSourceRefs `shouldBe` [["copy"], []]
        map (concatMap (map interactionEffectSemanticName . (.modifierVariantEffects)) . (.sourceRefVariants)) surface.surfaceSourceRefs `shouldBe` [["clone-shadow-copy", "dropzone-highlight"], []]
        surface.surfacePolicies `shouldBe` []

    it "renders minimal live, interaction, and DOM-token contracts for the roster surface" do
        frontendSurfaceContractsTypeScript `shouldContainText` "export type RosterSurfaceFragmentKey ="
        frontendSurfaceContractsTypeScript `shouldContainText` "export type RosterRosterWeekScope = { venueId: FrontendContractUuid; rosterGroupId: FrontendContractUuid; weekOffset: number };"
        frontendSurfaceContractsTypeScript `shouldContainText` "{ kind: \"roster-row\"; params: RosterRosterRowFragmentParams }"
        frontendSurfaceContractsTypeScript `shouldContainText` "export const rosterContentDomToken = \"roster-content\" as const;"
        frontendSurfaceContractsTypeScript `shouldContainText` "export const rosterWeekShellDomToken = \"roster-week-shell\" as const;"
        frontendSurfaceContractsTypeScript `shouldContainText` "\"roster\":{\"sourceRefs\":[{\"ref\":\"shift-drag-source\",\"session\":\"drag\",\"intent\":\"move-roster-shift-to-slot\",\"sourceField\":\"sourceItemKey\",\"compatibleDropzones\":[\"shift-slot-dropzone\",\"day-column-dropzone\",\"delete-shift-dropzone\"],\"modifierVariants\":[{\"semantic\":\"copy\",\"intent\":\"duplicate-roster-shift-to-day\""
        frontendSurfaceContractsTypeScript `shouldContainText` "\"dropzoneRefs\":[{\"ref\":\"shift-slot-dropzone\",\"session\":\"drag\",\"targetField\":\"targetDropzoneKey\"},{\"ref\":\"staff-create-dropzone\",\"session\":\"drag\",\"targetField\":\"targetDropzoneKey\"}"
        frontendSurfaceContractsTypeScript `shouldContainText` "\"activationRefs\":[{\"ref\":\"roster-layout-mode-activation\",\"intent\":\"set-roster-layout-mode\",\"valueField\":\"rosterLayoutMode\",\"trigger\":\"click\"}]"
        frontendSurfaceContractsTypeScript `shouldContainText` "\"sessionKinds\":[{\"kind\":\"drag\",\"effects\":{\"global\":[{\"className\":\"bepis-pointer-clone-shadow\""
        frontendSurfaceContractsTypeScript `shouldNotContainText` "MoveRosterShiftToSlotIntentFields"
        frontendSurfaceContractsTypeScript `shouldNotContainText` "RosterSessionName"
        frontendSurfaceContractsTypeScript `shouldNotContainText` "rosterSurfaceManifest"

    it "reports stable diagnostics for malformed reflected specs" do
        let duplicateFields = checkedSurfaceContractIR (SurfaceContractIR (reflectSurfaceRegistry @'[DuplicateFieldSurface]))
        let missingReference = checkedSurfaceContractIR (SurfaceContractIR (reflectSurfaceRegistry @'[MissingReferenceSurface]))
        let conflictingShared = checkedSurfaceContractIR (SurfaceContractIR (reflectSurfaceRegistry @'[SharedScopeA, SharedScopeB]))
        let missingDtoRef = checkedSurfaceContractIR (SurfaceContractIR (reflectSurfaceRegistry @'[MissingDtoRefSurface]))
        let missingAuth = checkedSurfaceContractIR (SurfaceContractIR (reflectSurfaceRegistry @'[MissingAuthSurface]))
        let invalidAuthFields = checkedSurfaceContractIR (SurfaceContractIR (reflectSurfaceRegistry @'[InvalidAuthFieldsSurface]))
        let duplicateAuthFields = checkedSurfaceContractIR (SurfaceContractIR (reflectSurfaceRegistry @'[DuplicateAuthFieldsSurface]))
        let invalidAuthWire = checkedSurfaceContractIR (SurfaceContractIR (reflectSurfaceRegistry @'[InvalidAuthWireSurface]))
        let missingLiveInvalidation = checkedSurfaceContractIR (SurfaceContractIR (reflectSurfaceRegistry @'[MissingLiveInvalidationSurface]))
        let missingResourceSource = checkedSurfaceContractIR (SurfaceContractIR (reflectSurfaceRegistry @'[MissingResourceSourceSurface]))
        let invalidScopeSource = checkedSurfaceContractIR (SurfaceContractIR (reflectSurfaceRegistry @'[InvalidScopeSourceSurface]))
        let invalidFragmentSource = checkedSurfaceContractIR (SurfaceContractIR (reflectSurfaceRegistry @'[InvalidFragmentSourceSurface]))
        let sourceTypeMismatch = checkedSurfaceContractIR (SurfaceContractIR (reflectSurfaceRegistry @'[ResourceSourceTypeMismatchSurface]))
        let duplicateResourceSource = checkedSurfaceContractIR (SurfaceContractIR (reflectSurfaceRegistry @'[DuplicateResourceSourceSurface]))
        let conflictingResources = checkedSurfaceContractIR (SurfaceContractIR (reflectSurfaceRegistry @'[DuplicateResourceSurfaceA, DuplicateResourceSurfaceB]))
        let invalidInteractionRef = checkedSurfaceContractIR (SurfaceContractIR (reflectSurfaceRegistry @'[InvalidInteractionRefSurface]))
        let missingEffectLayer = checkedSurfaceContractIR (SurfaceContractIR (reflectSurfaceRegistry @'[MissingInteractionEffectLayerSurface]))
        let fixtureWithIncompleteEffect =
                (reflectSurfaceSpec @SurfaceFixture.FrontendSurfaceFixture)
                    { surfaceSessions =
                        [ InteractionSessionIR
                            { sessionMarker = "DragSession"
                            , sessionName = "drag"
                            , sessionLayers = ["drag-preview"]
                            , sessionEffects = [(cloneShadowEffectIR "drag-preview") { interactionEffectClasses = [] }]
                            }
                        ]
                    }
        let incompleteEffect = checkedSurfaceContractIR (SurfaceContractIR [fixtureWithIncompleteEffect])
        let invalidHtmxTargetRef = checkedSurfaceContractIR (SurfaceContractIR (reflectSurfaceRegistry @'[InvalidHtmxTargetRefSurface]))
        let duplicateHtmxMethod = checkedSurfaceContractIR (SurfaceContractIR (reflectSurfaceRegistry @'[DuplicateHtmxMethodSurface]))
        let emptyCustomHtmxReason = checkedSurfaceContractIR (SurfaceContractIR (reflectSurfaceRegistry @'[EmptyCustomHtmxReasonSurface]))
        let emptyRawHtmxReason = checkedSurfaceContractIR (SurfaceContractIR (reflectSurfaceRegistry @'[EmptyRawHtmxReasonSurface]))

        diagnosticMessages duplicateFields `shouldContain` ["surface duplicate has duplicate scope field panelId"]
        diagnosticMessages missingReference `shouldContain` ["htmx action bad references missing fragment missing on surface missing-reference"]
        diagnosticMessages conflictingShared `shouldContain` ["conflicting shared declaration: scope shared"]
        diagnosticMessages missingDtoRef `shouldContain` ["field missingPayload references missing dto MissingPayload on surface missing-dto-ref"]
        diagnosticMessages missingAuth `shouldContain` ["surface missing-auth scope test must declare exactly one authorization policy"]
        diagnosticMessages invalidAuthFields `shouldContain` ["surface invalid-auth-fields scope test authorization current-venue expects 1 fields but declares 2"]
        diagnosticMessages duplicateAuthFields `shouldContain` ["surface duplicate-auth-fields scope test authorization current-venue-user repeats field venueId"]
        diagnosticMessages invalidAuthWire `shouldContain` ["surface invalid-auth-wire scope test authorization current-venue field venueId must be a required UUID"]
        diagnosticMessages missingLiveInvalidation `shouldContain` ["surface missing-live-invalidation live fragment bad must declare DependsOn or ResyncOnly"]
        diagnosticMessages missingResourceSource `shouldContain` ["surface missing-resource-source fragment bad dependency test-resource missing source for resource field weekOffset"]
        diagnosticMessages invalidScopeSource `shouldContain` ["surface invalid-scope-source fragment bad dependency test-resource references missing scope field weekOffset"]
        diagnosticMessages invalidFragmentSource `shouldContain` ["surface invalid-fragment-source fragment bad dependency test-resource references missing fragment field panelId"]
        diagnosticMessages sourceTypeMismatch `shouldContain` ["surface resource-source-type-mismatch fragment bad dependency mismatched-resource maps scope field venueId with incompatible wire type or presence"]
        diagnosticMessages duplicateResourceSource `shouldContain` ["surface duplicate-resource-source fragment bad dependency test-resource supplies resource field venueId more than once"]
        diagnosticMessages conflictingResources `shouldContain` ["conflicting shared declaration: resource test-resource"]
        diagnosticMessages invalidInteractionRef `shouldContain` ["source ref bad references missing session missing-fragment on surface invalid-interaction-ref"]
        diagnosticMessages invalidInteractionRef `shouldContain` ["source ref bad references missing intent field missingPayload for intent bad on surface invalid-interaction-ref"]
        diagnosticMessages missingEffectLayer `shouldContain` ["surface missing-effect-layer session layerless effect clone-shadow references missing layer missing"]
        diagnosticMessages incompleteEffect `shouldContain` ["surface contract-fixture session drag has incomplete or non-canonical clone-shadow effect"]
        diagnosticMessages invalidHtmxTargetRef `shouldContain` ["htmx action bad references missing dom token missing-fragment on surface invalid-htmx-target-ref"]
        diagnosticMessages duplicateHtmxMethod `shouldContain` ["surface duplicate-htmx-method htmx action bad declares method more than once"]
        diagnosticMessages emptyCustomHtmxReason `shouldContain` ["surface empty-custom-htmx-reason custom HTMX missing-fragment must include a non-empty reason"]
        diagnosticMessages emptyRawHtmxReason `shouldContain` ["surface empty-raw-htmx-reason raw HTMX syntax must include a non-empty reason"]

    it "constructs generated FrontendSurface resource values" do
        let venueId = fromMaybe (error "invalid UUID") (UUID.fromString "11111111-1111-1111-1111-111111111111")

        timesheetDayResource venueId 0 2
            `shouldBe` SurfaceResourceValue
                { resourceValueName = "timesheet-day"
                , resourceValueFields = Aeson.object ["venueId" Aeson..= ("11111111-1111-1111-1111-111111111111" :: Text), "weekOffset" Aeson..= (0 :: Int), "dayOffset" Aeson..= (2 :: Int)]
                }

    it "renders generated role-specific interaction refs" do
        let surface = expectSurface "roster" registeredFrontendSurfaceContractIR
        let sourceRef = fromMaybe (error "missing source ref") (listToMaybe surface.surfaceSourceRefs)
        let dropzoneRef = fromMaybe (error "missing dropzone ref") (listToMaybe surface.surfaceDropzoneRefs)
        let activationRef = fromMaybe (error "missing activation ref") (listToMaybe surface.surfaceActivationRefs)
        let sourceHtml = cs (HtmlRenderer.renderHtml (SurfaceInteraction.renderFrontendSurfaceSourceRef sourceRef "shift:1" (Html5.toHtml ("card" :: Text))))
        let dropzoneHtml = cs (HtmlRenderer.renderHtml (SurfaceInteraction.renderFrontendSurfaceDropzoneRef dropzoneRef "slot:2" (Html5.toHtml ("slot" :: Text))))
        let activationHtml = cs (HtmlRenderer.renderHtml (SurfaceInteraction.renderFrontendSurfaceActivationRef activationRef (Html5.toHtml ("mode" :: Text))))

        sourceHtml `shouldContainText` "data-bepis-source-ref=\"shift-drag-source\""
        sourceHtml `shouldContainText` "data-bepis-source-key=\"shift:1\""
        sourceHtml `shouldNotContainText` "data-bepis-session-kind"
        dropzoneHtml `shouldContainText` "data-bepis-dropzone-ref=\"shift-slot-dropzone\""
        dropzoneHtml `shouldContainText` "data-bepis-dropzone-key=\"slot:2\""
        activationHtml `shouldContainText` "data-bepis-activation-ref=\"roster-layout-mode-activation\""
        activationHtml `shouldNotContainText` "data-bepis-activation-intent"

    it "renders generated HTMX action attrs from fixture action metadata" do
        let surface = expectSurface "contract-fixture" frontendSurfaceFixtureContractIR
        let action = fromMaybe (error "missing fixture action") (listToMaybe surface.surfaceHtmxActions)
        let route = FrontendSurfaceActionRoute
                { actionRouteUrl = "/fixture/refresh-panel"
                , actionRouteFields = [FrontendSurfaceFieldValue "panelId" "panel-1"]
                , actionRouteCustomHtmx = [FrontendSurfaceCustomHtmxAttrs "fixture-panel-custom-htmx" [("hx-vals", "{}")]]
                , actionRouteStandardUrl = Nothing
                , actionRouteExtraAttrs = [("class", "surface-action-test")]
                }
        let formHtml = cs (HtmlRenderer.renderHtml (renderFrontendSurfaceActionForm action route (Html5.toHtml ("refresh" :: Text))))
        let linkHtml = cs (HtmlRenderer.renderHtml (renderFrontendSurfaceActionLink action route (Html5.toHtml ("refresh" :: Text))))
        let buttonHtml = cs (HtmlRenderer.renderHtml (renderFrontendSurfaceActionSubmitButton action route (Html5.toHtml ("refresh" :: Text))))

        formHtml `shouldContainText` "method=\"post\""
        formHtml `shouldContainText` "action=\"/fixture/refresh-panel\""
        formHtml `shouldContainText` "hx-post=\"/fixture/refresh-panel\""
        formHtml `shouldContainText` "hx-target=\"#contract-fixture-panel\""
        formHtml `shouldContainText` "hx-swap=\"outerHTML\""
        formHtml `shouldContainText` "hx-include=\"#fixture-panel-include\""
        formHtml `shouldContainText` "hx-push-url=\"false\""
        formHtml `shouldContainText` "hx-vals=\"{}\""
        formHtml `shouldContainText` "data-bepis-surface-action=\"refresh-panel\""
        formHtml `shouldNotContainText` "data-bepis-surface-action-config="
        linkHtml `shouldContainText` "href=\"/fixture/refresh-panel\""
        linkHtml `shouldContainText` "hx-post=\"/fixture/refresh-panel\""
        buttonHtml `shouldContainText` "formaction=\"/fixture/refresh-panel\""
        buttonHtml `shouldContainText` "hx-post=\"/fixture/refresh-panel\""

    it "renders minimal HTMX action and intent forms from SurfaceImpl metadata" do
        let request = FrontendSurfaceHtmxRequest
                { htmxRequestName = "refresh-panel"
                , htmxRequestMethod = FrontendSurfacePost
                , htmxRequestUrl = "/fixture/refresh-panel"
                , htmxRequestTarget = "#contract-fixture-panel"
                , htmxRequestSwap = "outerHTML"
                , htmxRequestFields = [FrontendSurfaceFieldValue "panelId" "panel-1"]
                }
        let intent = FrontendSurfaceIntentForm "move-card" request
        let actionHtml = cs (HtmlRenderer.renderHtml (renderFrontendSurfaceHtmxForm request (Html5.toHtml ("refresh" :: Text))))
        let intentHtml = cs (HtmlRenderer.renderHtml (renderFrontendSurfaceIntentForm intent (Html5.toHtml ("move" :: Text))))

        actionHtml `shouldContainText` "hx-post=\"/fixture/refresh-panel\""
        actionHtml `shouldContainText` "data-bepis-surface-action=\"refresh-panel\""
        actionHtml `shouldContainText` "name=\"panelId\""
        intentHtml `shouldContainText` "data-bepis-intent-form=\"move-card\""
        intentHtml `shouldContainText` "hx-target=\"#contract-fixture-panel\""

diagnosticMessages :: Either [ContractDiagnostic] SurfaceContractIR -> [Text]
diagnosticMessages = \case
    Right _ -> []
    Left diagnostics -> map (.diagnosticMessage) diagnostics

data Duplicate
data DuplicateScope
data MissingReference
data SharedA
data SharedB
data Shared
data Bad
data TestResource
data MismatchedResource
data MissingFragment
data MissingDtoRef
data MissingAuth
data InvalidAuthFields
data DuplicateAuthFields
data InvalidAuthWire
data MissingLiveInvalidation
data MissingResourceSource
data InvalidScopeSource
data InvalidFragmentSource
data ResourceSourceTypeMismatch
data DuplicateResourceSource
data DuplicateResourceA
data DuplicateResourceB
data InvalidInteractionRef
data MissingEffectLayer
data MissingLayer
data LayerlessSession
data InvalidHtmxTargetRef
data DuplicateHtmxMethod
data EmptyCustomHtmxReason
data MissingPayload
data PanelId
data StaffFilterId
data VenueId
data WeekOffset
data TestScope

expectSurface :: Text -> SurfaceContractIR -> SurfaceIR
expectSurface surfaceName SurfaceContractIR { contractSurfaces } =
    case find (\surface -> surface.surfaceName == surfaceName) contractSurfaces of
        Just surface -> surface
        Nothing      -> error ("missing surface in contract IR: " <> cs surfaceName)

type DuplicateFieldSurface =
    Surface Duplicate
        '[ Scope DuplicateScope
            '[ Field PanelId 'WireUUID
             , Field PanelId 'WireText
             ]
            '[ 'NoAuth ]
         ]

type MissingReferenceSurface =
    Surface MissingReference
        '[ Scope TestScope '[ Field VenueId 'WireUUID ] '[ 'NoAuth ]
         , Action Bad '[] '[ 'Target MissingFragment ]
         ]

type MissingDtoRefSurface =
    Surface MissingDtoRef
        '[ Scope TestScope '[ Field VenueId 'WireUUID ] '[ 'NoAuth ]
         , Dto Bad '[ Field MissingPayload ('WireRef MissingPayload) ]
         ]

type MissingAuthSurface =
    Surface MissingAuth
        '[ Scope TestScope '[ Field VenueId 'WireUUID ] '[]
         ]

type InvalidAuthFieldsSurface =
    Surface InvalidAuthFields
        '[ Scope TestScope
            '[ Field VenueId 'WireUUID
             , Field StaffFilterId 'WireUUID
             ]
            '[ 'Authorize 'CurrentVenue '[ VenueId, StaffFilterId ] ]
         ]

type DuplicateAuthFieldsSurface =
    Surface DuplicateAuthFields
        '[ Scope TestScope
            '[ Field VenueId 'WireUUID ]
            '[ 'Authorize 'CurrentVenueUser '[ VenueId, VenueId ] ]
         ]

type InvalidAuthWireSurface =
    Surface InvalidAuthWire
        '[ Scope TestScope '[ Field VenueId 'WireText ] '[ 'Authorize 'CurrentVenue '[ VenueId ] ]
         ]

type MissingLiveInvalidationSurface =
    Surface MissingLiveInvalidation
        '[ Scope TestScope '[ Field VenueId 'WireUUID ] '[ 'NoAuth ]
         , Fragment Bad '[] '[ 'Live ]
         ]

type MissingResourceSourceSurface =
    Surface MissingResourceSource
        '[ Scope TestScope '[ Field VenueId 'WireUUID ] '[ 'NoAuth ]
         , Fragment Bad '[]
            '[ 'Live
             , 'DependsOn ('Resource TestResource '[ Field VenueId 'WireUUID, Field WeekOffset 'WireInt ])
                '[ 'FromScope VenueId ]
             ]
         ]

type InvalidScopeSourceSurface =
    Surface InvalidScopeSource
        '[ Scope TestScope '[ Field VenueId 'WireUUID ] '[ 'NoAuth ]
         , Fragment Bad '[]
            '[ 'Live
             , 'DependsOn ('Resource TestResource '[ Field WeekOffset 'WireInt ])
                '[ 'FromScope WeekOffset ]
             ]
         ]

type InvalidFragmentSourceSurface =
    Surface InvalidFragmentSource
        '[ Scope TestScope '[ Field VenueId 'WireUUID ] '[ 'NoAuth ]
         , Fragment Bad '[]
            '[ 'Live
             , 'DependsOn ('Resource TestResource '[ Field PanelId 'WireUUID ])
                '[ 'FromFragment PanelId ]
             ]
         ]

type ResourceSourceTypeMismatchSurface =
    Surface ResourceSourceTypeMismatch
        '[ Scope TestScope '[ Field VenueId 'WireUUID ] '[ 'NoAuth ]
         , Fragment Bad '[]
            '[ 'Live
             , 'DependsOn ('Resource MismatchedResource '[ Field VenueId 'WireText ])
                '[ 'FromScope VenueId ]
             ]
         ]

type DuplicateResourceSourceSurface =
    Surface DuplicateResourceSource
        '[ Scope TestScope '[ Field VenueId 'WireUUID ] '[ 'NoAuth ]
         , Fragment Bad '[ Field VenueId 'WireUUID ]
            '[ 'Live
             , 'DependsOn ('Resource TestResource '[ Field VenueId 'WireUUID ])
                '[ 'FromScope VenueId, 'FromFragment VenueId ]
             ]
         ]

type DuplicateResourceSurfaceA =
    Surface DuplicateResourceA
        '[ Scope TestScope '[ Field VenueId 'WireUUID ] '[ 'NoAuth ]
         , Fragment Bad '[]
            '[ 'Live
             , 'DependsOn ('Resource TestResource '[ Field VenueId 'WireUUID ])
                '[ 'FromScope VenueId ]
             ]
         ]

type DuplicateResourceSurfaceB =
    Surface DuplicateResourceB
        '[ Scope TestScope '[ Field VenueId 'WireUUID ] '[ 'NoAuth ]
         , Fragment Bad '[]
            '[ 'Live
             , 'DependsOn ('Resource TestResource '[ Field VenueId 'WireText ])
                '[ 'FromScope VenueId ]
             ]
         ]

type InvalidInteractionRefSurface =
    Surface InvalidInteractionRef
        '[ Scope TestScope '[ Field VenueId 'WireUUID ] '[ 'NoAuth ]
         , Intent Bad '[ Field PanelId 'WireUUID ] '[]
         , SourceRef Bad '[ 'SessionOption MissingFragment, 'Submits Bad, 'SourceField MissingPayload ]
         ]

type MissingInteractionEffectLayerSurface =
    Surface MissingEffectLayer
        '[ Scope TestScope '[ Field VenueId 'WireUUID ] '[ 'NoAuth ]
         , Session LayerlessSession '[ 'Effect (SurfaceInteraction.CloneShadow MissingLayer) ]
         ]

type InvalidHtmxTargetRefSurface =
    Surface InvalidHtmxTargetRef
        '[ Scope TestScope '[ Field VenueId 'WireUUID ] '[ 'NoAuth ]
         , Action Bad '[] '[ 'HtmxTarget ('HtmxId MissingFragment) ]
         ]

type DuplicateHtmxMethodSurface =
    Surface DuplicateHtmxMethod
        '[ Scope TestScope '[ Field VenueId 'WireUUID ] '[ 'NoAuth ]
         , Action Bad '[] '[ 'HtmxMethod 'HtmxPost, 'HtmxMethod 'HtmxDelete ]
         ]

type EmptyCustomHtmxReasonSurface =
    Surface EmptyCustomHtmxReason
        '[ Scope TestScope '[ Field VenueId 'WireUUID ] '[ 'NoAuth ]
         , Action Bad '[] '[ 'CustomHtmx MissingFragment "" ]
         ]

data EmptyRawHtmxReason

type EmptyRawHtmxReasonSurface =
    Surface EmptyRawHtmxReason
        '[ Scope TestScope '[ Field VenueId 'WireUUID ] '[ 'NoAuth ]
         , Action Bad '[] '[ 'HtmxTarget ('HtmxRawSelector "[data-fixture]" "") ]
         ]

type SharedScopeA =
    Surface SharedA
        '[ Scope Shared '[ Field VenueId 'WireUUID ] '[ 'NoAuth ]
         ]

type SharedScopeB =
    Surface SharedB
        '[ Scope Shared '[ Field WeekOffset 'WireInt ] '[ 'NoAuth ]
         ]

shouldContainText :: Text -> Text -> Expectation
shouldContainText actual expected =
    actual `shouldSatisfy` Text.isInfixOf expected

shouldNotContainText :: Text -> Text -> Expectation
shouldNotContainText actual expected =
    actual `shouldSatisfy` (not . Text.isInfixOf expected)
