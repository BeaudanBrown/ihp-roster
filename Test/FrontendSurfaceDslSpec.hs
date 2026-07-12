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
import Application.Helper.FrontendContract.Surface.Lab (SurfaceLabSurface)
import Application.Helper.FrontendContract.Surface.Reflect
import Application.Helper.FrontendContract.Surface.Registry (RegisteredFrontendSurfaces)
import Application.Helper.FrontendContract.Surface.Resource
import qualified Application.Helper.FrontendContract.Surface.Roster as RosterSurface
import Application.Helper.FrontendContract.Surface.Runtime
import qualified Application.Helper.FrontendContract.Surface.Timesheets as TimesheetsSurface
import Application.Helper.FrontendContract.TypeScript (renderFrontendContractTypeScript)
import Application.Helper.SurfaceResource
import qualified Data.Aeson as Aeson
import Data.Proxy (Proxy (..))
import qualified Data.Text as Text
import qualified Data.UUID as UUID
import IHP.Prelude
import Test.Hspec
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

type ParentSurface =
    Surface Parent
        '[ Scope ParentScope '[] '[ 'NoAuth ]
         , Fragment ParentContent '[] '[ 'ContainsSurface Child ]
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

tests :: Spec
tests = describe "FrontendSurface DSL foundation" do
    it "kind-checks the support lab surface and root registry" do
        let _lab = Proxy @SurfaceLabSurface
        let _timesheets = Proxy @TimesheetsSurface.TimesheetsSurface
        let _roster = Proxy @RosterSurface.RosterSurface
        let _registry = Proxy @RegisteredFrontendSurfaces
        True `shouldBe` True

    it "renders minimal mount-local runtime metadata without legacy live-surface config" do
        let fragment = FrontendSurfaceMountedFragment
                { mountedFragmentKey = FrontendSurfaceFragmentKey "lab-panel" (Aeson.object ["panelId" Aeson..= ("panel-1" :: Text)])
                , mountedFragmentTargetId = "surface-lab-panel"
                , mountedFragmentUrl = "/ShowFrontendSurfaceLabPanelFragment?panelId=panel-1"
                , mountedFragmentProtection = FrontendSurfaceFocusedFieldConfig FrontendSurfaceFocusedFieldProtectionConfig
                    { focusedProtectionActiveSelector = "input[data-lab-field]:focus"
                    , focusedProtectionFieldKeyAttr = "data-lab-field"
                    , focusedProtectionFieldNameFallback = True
                    , focusedProtectionContainerSelector = Just "form[data-lab-row]"
                    }
                , mountedFragmentLazyTrigger = Nothing
                , mountedFragmentPlaceholderKind = Nothing
                }
        let config = FrontendSurfaceMountConfig
                { mountSurfaceName = "surface-lab"
                , mountScopeKey = "surface-lab:scope"
                , mountKey = "primary"
                , mountScope = Aeson.Null
                , mountSubscription = Nothing
                , mountState = Aeson.object ["showArchived" Aeson..= False]
                , mountFragments = [fragment]
                }
        let minimalRequest = FrontendSurfaceHtmxRequest
                { htmxRequestName = "refresh-panel"
                , htmxRequestMethod = FrontendSurfacePost
                , htmxRequestUrl = "/RefreshFrontendSurfaceLabPanel"
                , htmxRequestTarget = "#surface-lab-panel"
                , htmxRequestSwap = "outerHTML"
                , htmxRequestFields = []
                }
        let handlers = SurfaceImplHandlers
                { surfaceScopeHandlers = FrontendSurfaceScopeHandler
                    { scopeHandlerDefaultValue = frontendSurfaceFieldValues (Aeson.object ["venueId" Aeson..= ("venue-1" :: Text), "weekOffset" Aeson..= (0 :: Int)])
                    , scopeHandlerKey = const "surface-lab:scope"
                    } `HandlerCons` HandlerNil
                , surfaceMountStateHandlers = FrontendSurfaceMountStateHandler
                    { mountStateHandlerDefaultValue = frontendSurfaceFieldValues (Aeson.object ["showArchived" Aeson..= False])
                    } `HandlerCons` HandlerNil
                , surfaceFragmentHandlers =
                    FrontendSurfaceFragmentHandler
                        { fragmentHandlerDefaultParams = frontendSurfaceFieldValues Aeson.Null
                        , fragmentHandlerMountedFragment = const fragment
                        , fragmentHandlerRender = const mempty
                        }
                        `HandlerCons` FrontendSurfaceFragmentHandler
                            { fragmentHandlerDefaultParams = frontendSurfaceFieldValues (Aeson.object ["panelId" Aeson..= ("panel-1" :: Text)])
                            , fragmentHandlerMountedFragment = const fragment
                            , fragmentHandlerRender = const mempty
                            }
                        `HandlerCons` HandlerNil
                , surfaceActionHandlers = FrontendSurfaceActionHandler
                    { actionHandlerDefaultFields = frontendSurfaceFieldValues (Aeson.object ["panelId" Aeson..= ("panel-1" :: Text)])
                    , actionHandlerRequest = const minimalRequest
                    } `HandlerCons` HandlerNil
                , surfaceIntentHandlers = FrontendSurfaceIntentHandler
                    { intentHandlerDefaultFields = frontendSurfaceFieldValues (Aeson.object ["sourceItemKey" Aeson..= ("card-a" :: Text), "targetDropzoneKey" Aeson..= ("dropzone-b" :: Text)])
                    , intentHandlerForm = const (FrontendSurfaceIntentForm "move-lab-card" minimalRequest)
                    } `HandlerCons` HandlerNil
                }
        let impl = (mkSurfaceImpl "surface-lab" config handlers :: SurfaceImpl SurfaceLabSurface)
        let html = cs (HtmlRenderer.renderHtml (renderFrontendSurfaceMount impl (Html5.toHtml ("body" :: Text))))
        let parameterlessConfig = config
                { mountFragments =
                    [ fragment
                        { mountedFragmentKey = FrontendSurfaceFragmentKey "lab-shell" Aeson.Null
                        }
                    ]
                }

        impl.surfaceImplActions |> map (.htmxRequestName) `shouldBe` ["refresh-panel"]
        impl.surfaceImplIntents |> map (.intentFormName) `shouldBe` ["move-lab-card"]
        html `shouldContainText` "data-bepis-surface=\"surface-lab\""
        html `shouldContainText` "data-bepis-surface-config="
        html `shouldNotContainText` "data-live-update-surface"
        frontendSurfaceMountConfigJson config `shouldContainText` "\"mountKey\":\"primary\""
        frontendSurfaceMountConfigJson config `shouldContainText` "\"targetId\":\"surface-lab-panel\""
        frontendSurfaceMountConfigJson config `shouldContainText` "\"kind\":\"focused-field\""
        frontendSurfaceMountConfigJson config `shouldContainText` "\"activeSelector\":\"input[data-lab-field]:focus\""
        frontendSurfaceMountConfigJson parameterlessConfig `shouldContainText` "\"fragmentKey\":{\"kind\":\"lab-shell\",\"params\":{},\"surface\":\"surface-lab\"}"
        let mountConfigJson = frontendSurfaceMountConfigJson impl.surfaceImplMountConfig
        mountConfigJson `shouldContainText` "\"fragmentKey\""
        mountConfigJson `shouldNotContainText` "\"mountState\""
        mountConfigJson `shouldNotContainText` "\"loadPolicy\""
        mountConfigJson `shouldNotContainText` "\"resyncFragments\""
        mountConfigJson `shouldNotContainText` "\"deferUntilBlur\""
        mountConfigJson `shouldNotContainText` "\"protectionPolicy\""
        Text.count "\"url\":" mountConfigJson `shouldBe` length impl.surfaceImplMountConfig.mountFragments

    it "renders lazy fragments with canonical UI-region attrs and feature slot classes" do
        let fragment = FrontendSurfaceMountedFragment
                { mountedFragmentKey = FrontendSurfaceFragmentKey "lab-panel" Aeson.Null
                , mountedFragmentTargetId = "surface-lab-panel"
                , mountedFragmentUrl = "/ShowFrontendSurfaceLabPanelFragment"
                , mountedFragmentProtection = FrontendSurfaceReplace
                , mountedFragmentLazyTrigger = Just "load"
                , mountedFragmentPlaceholderKind = Just "panel"
                }
        let html = cs (HtmlRenderer.renderHtml (renderFrontendSurfaceLazyFragmentWithConfig defaultFrontendSurfaceLazyFragmentConfig { lazyFragmentRootClasses = ["col-12", "col-xl-4", "surface-lab-side"] } fragment (Html5.toHtml ("Loading" :: Text))))
        html `shouldContainText` "id=\"surface-lab-panel\""
        html `shouldContainText` "class=\"col-12 col-xl-4 surface-lab-side app-lazy-surface app-lazy-surface-compact app-lazy-surface-panel\""
        html `shouldContainText` "data-bepis-fragment=\"true\""
        html `shouldContainText` "data-bepis-lazy-surface=\"true\""
        html `shouldContainText` "data-bepis-lazy-fragment=\"lab-panel\""
        html `shouldContainText` "data-bepis-lazy-retry=\"true\""
        html `shouldContainText` "hx-get=\"/ShowFrontendSurfaceLabPanelFragment\""
        html `shouldContainText` "hx-trigger=\"load\""
        html `shouldNotContainText` "data-bepis-surface-lazy"

        let customPlaceholderHtml = cs (HtmlRenderer.renderHtml (renderFrontendSurfaceLazyFragmentWithConfig customPlaceholderFrontendSurfaceLazyFragmentConfig { lazyFragmentRootClasses = ["col-12", "col-xl-4", "surface-lab-side"] } fragment (Html5.toHtml ("Loading" :: Text))))
        customPlaceholderHtml `shouldContainText` "class=\"col-12 col-xl-4 surface-lab-side app-lazy-surface app-lazy-surface-custom app-lazy-surface-panel\""

    it "derives lazy trigger and placeholder defaults from existing primitive options" do
        let defaults = knownFragmentOptions @'[ 'Lazy '[ 'Trigger TestLoad, 'Placeholder TestPanel ]]
        defaults.lazyFragmentDefaultTrigger `shouldBe` Just "test-load"
        defaults.lazyFragmentDefaultPlaceholderKind `shouldBe` Just "test-panel"

    it "parses typed handler field values from declared field lists" do
        let panelParams = frontendSurfaceFieldValues (Aeson.object ["panelId" Aeson..= ("panel-1" :: Text)]) :: FrontendSurfaceFieldValues '[Field PanelId 'WireUUID]
        let optionalParams = frontendSurfaceFieldValues (Aeson.object []) :: FrontendSurfaceFieldValues '[OptionalField StaffFilterId 'WireUUID]
        let badParams = frontendSurfaceFieldValues (Aeson.object ["panelId" Aeson..= (123 :: Int)]) :: FrontendSurfaceFieldValues '[Field PanelId 'WireUUID]

        getSurfaceField @PanelId panelParams `shouldBe` Just ("panel-1" :: Text)
        requireSurfaceField @StaffFilterId optionalParams `shouldBe` Right (Nothing :: Maybe Text)
        requireSurfaceField @PanelId badParams `shouldSatisfy` \case
            Left (FrontendSurfaceFieldParseFailed "panelId" _) -> True
            _ -> False

    it "builds mounted parameterized fragment keys from canonical params" do
        let fields = frontendSurfaceFieldValuesFromPairs ["panelId" Aeson..= ("panel-1" :: Text)] :: FrontendSurfaceFieldValues '[Field PanelId 'WireUUID]
        let key = frontendSurfaceFragmentKeyFromPairs "lab-panel" ["panelId" Aeson..= ("panel-1" :: Text)]
        let fragment = frontendSurfaceMountedFragment "lab-panel" key.fragmentParams "surface-lab-panel-panel-1" "/lab/panel?panelId=panel-1" FrontendSurfaceReplace

        getSurfaceField @PanelId fields `shouldBe` Just ("panel-1" :: Text)
        key `shouldBe` FrontendSurfaceFragmentKey "lab-panel" (Aeson.object ["panelId" Aeson..= ("panel-1" :: Text)])
        fragment.mountedFragmentKey `shouldBe` key
        fragment.mountedFragmentTargetId `shouldBe` "surface-lab-panel-panel-1"
        fragment.mountedFragmentUrl `shouldBe` "/lab/panel?panelId=panel-1"

    it "reflects the complete production Surface registry in declared order" do
        map (.surfaceName) registeredFrontendSurfaceContractIR.contractSurfaces
            `shouldBe` [ "surface-lab"
                       , "timesheets"
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
            `shouldBe` Just [ContainsSurfaceOption "child"]
        let fixtureContract = FrontendContractIR
                { contractGlobals = registeredFrontendContractIR.contractGlobals
                , contractSurfaces = reflected.contractSurfaces
                }
        let rendered = either error id (renderFrontendContractTypeScript fixtureContract)
        rendered `shouldContainText` "{ parentSurface: \"parent\", parentFragment: \"parent-content\", childSurface: \"child\" }"

    it "validates missing and cyclic contained Surface references after reflection" do
        let missingChild = checkedSurfaceContractIR (SurfaceContractIR (reflectSurfaceRegistry @'[MissingContainedSurface]))
        let cycle = checkedSurfaceContractIR (SurfaceContractIR (reflectSurfaceRegistry @'[CycleASurface, CycleBSurface]))
        diagnosticMessages missingChild `shouldContain` ["surface missing-contained fragment missing-contained-content contains missing surface child"]
        diagnosticMessages cycle `shouldContain` ["surface containment cycle includes cycle-a"]

    it "reflects the registered lab surface into checked contract IR" do
        let surface = expectSurface "surface-lab" registeredFrontendSurfaceContractIR

        surface.surfaceName `shouldBe` "surface-lab"
        map (.scopeName) surface.surfaceScopes `shouldBe` ["lab"]
        map (.fragmentName) surface.surfaceFragments `shouldBe` ["lab-shell", "lab-panel"]
        map (.htmxActionName) surface.surfaceHtmxActions `shouldBe` ["refresh-panel"]
        map (.intentName) surface.surfaceIntents `shouldBe` ["move-lab-card"]
        surface.surfaceSessions `shouldBe` ["drag"]
        surface.surfaceLayers `shouldBe` ["drag-preview"]
        surface.surfaceDomTokens `shouldBe` ["lab-root", "lab-dropzone", "lab-panel-target", "lab-panel-include"]
        map (fst . schemaNameAndMarker) surface.surfaceDtos `shouldBe` ["LabPayload", "LabRelatedPayload"]
        surface.surfaceFragments
            |> find (\fragment -> fragment.fragmentName == "lab-panel")
            |> fmap (.fragmentOptions)
            `shouldBe` Just [LazyOption [TriggerOption "load", PlaceholderOption "panel"]]
        surface.surfaceHtmxActions
            |> find (\action -> action.htmxActionName == "refresh-panel")
            |> fmap (.htmxActionOptions)
            `shouldBe` Just
                [ TargetOption "lab-panel"
                , HtmxOption (HtmxActionMethodIR HtmxPostIR)
                , HtmxOption (HtmxActionTargetIR "lab-panel-target")
                , HtmxOption (HtmxActionSwapIR "outerHTML")
                , HtmxOption (HtmxActionIncludeIR "lab-panel-include")
                , HtmxOption (HtmxActionPushUrlIR HtmxPushUrlFalseIR)
                , HtmxOption (HtmxActionCustomHtmxIR "lab-panel-custom-htmx" "lab fixture covers auditable custom HTMX metadata")
                ]

    it "reflects the registered timesheets surface into checked contract IR" do
        let surface = expectSurface "timesheets" registeredFrontendSurfaceContractIR

        map (.scopeName) surface.surfaceScopes `shouldBe` ["timesheet-week"]
        map (.mountStateName) surface.surfaceMountStates `shouldBe` ["timesheets-mount-state"]
        map (.fragmentName) surface.surfaceFragments `shouldBe` ["timesheet-toolbar", "timesheet-day-columns", "timesheet-day-section"]
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
                , ("staffFilterId", WireOptionalIR WireUuidIR)
                ]

    it "renders generated TypeScript contracts for every lab primitive family" do
        frontendSurfaceContractsTypeScript `shouldContainText` "export type SurfaceLabFragmentKey ="
        frontendSurfaceContractsTypeScript `shouldContainText` "export type SurfaceLabMountConfig = { surface: \"surface-lab\"; scopeKey: string; mountKey: string; fragments: ReadonlyArray<SurfaceLabMountedFragmentConfig>; subscription: null };"
        frontendSurfaceContractsTypeScript `shouldContainText` "{ kind: \"lab-panel\"; params: SurfaceLabLabPanelFragmentParams }"
        frontendSurfaceContractsTypeScript `shouldContainText` "export type RefreshPanelActionFields = SurfaceLabRefreshPanelActionFields;"
        frontendSurfaceContractsTypeScript `shouldContainText` "export type FrontendSurfaceActionManifest ="
        frontendSurfaceContractsTypeScript `shouldContainText` "\"htmxActions\":[{\"name\":\"refresh-panel\",\"fields\":[\"panelId\"],\"htmx\":{\"method\":\"post\""
        frontendSurfaceContractsTypeScript `shouldContainText` "\"custom\":[{\"name\":\"lab-panel-custom-htmx\",\"reason\":\"lab fixture covers auditable custom HTMX metadata\"}]"
        frontendSurfaceContractsTypeScript `shouldContainText` "export type MoveLabCardIntentFields = SurfaceLabMoveLabCardIntentFields;"
        frontendSurfaceContractsTypeScript `shouldContainText` "export type LabPayload = { label: string; count?: number; note: string | null; tags: ReadonlyArray<string>; dueDay: FrontendContractDay; maybeRank: number | undefined; maybeMemo: string | null; relatedPayload: LabRelatedPayload };"
        frontendSurfaceContractsTypeScript `shouldContainText` "export type LabRelatedPayload = { label: string };"
        frontendSurfaceContractsTypeScript `shouldContainText` "export const surfaceLabSurfaceManifest"
        frontendSurfaceContractsTypeScript `shouldContainText` "export function parseFrontendSurfaceName"

    it "renders generated TypeScript contracts for the timesheets surface" do
        frontendSurfaceContractsTypeScript `shouldContainText` "export type TimesheetsFragmentKey ="
        frontendSurfaceContractsTypeScript `shouldContainText` "{ kind: \"timesheet-day-section\"; params: TimesheetsTimesheetDaySectionFragmentParams }"
        frontendSurfaceContractsTypeScript `shouldContainText` "export type TimesheetsMountConfig ="
        frontendSurfaceContractsTypeScript `shouldNotContainText` "TimesheetsTimesheetsMountStateMountState"
        frontendSurfaceContractsTypeScript `shouldNotContainText` "export type TimesheetsMountState ="
        frontendSurfaceContractsTypeScript `shouldContainText` "export const timesheetsSurfaceManifest"

    it "reflects the registered roster surface into checked contract IR" do
        let surface = expectSurface "roster" registeredFrontendSurfaceContractIR

        map (.scopeName) surface.surfaceScopes `shouldBe` ["roster-week"]
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
        map (.intentName) surface.surfaceIntents `shouldBe` ["set-roster-layout-mode", "move-roster-shift-to-slot", "duplicate-roster-shift-to-day", "drop-roster-staff"]
        surface.surfaceSessions `shouldBe` ["drag"]
        map (.sourceRefName) surface.surfaceSourceRefs `shouldBe` ["shift-drag-source", "staff-drag-source"]
        map (.dropzoneRefName) surface.surfaceDropzoneRefs `shouldBe` ["shift-slot-dropzone", "staff-create-dropzone", "day-column-dropzone", "existing-shift-dropzone", "delete-shift-dropzone"]
        map (.activationRefName) surface.surfaceActivationRefs `shouldBe` ["roster-layout-mode-activation"]
        surface.surfaceLayers `shouldBe` ["drag-preview"]
        map fst surface.surfaceEffects `shouldBe` ["clone-shadow", "dropzone-highlight"]
        map (map (.modifierVariantSemantic) . (.sourceRefVariants)) surface.surfaceSourceRefs `shouldBe` [["copy"], []]
        map (concatMap (map fst . (.modifierVariantEffects)) . (.sourceRefVariants)) surface.surfaceSourceRefs `shouldBe` [["clone-shadow-copy", "dropzone-highlight"], []]
        surface.surfacePolicies `shouldBe` []

    it "renders generated TypeScript contracts for the roster surface" do
        frontendSurfaceContractsTypeScript `shouldContainText` "export type RosterFragmentKey ="
        frontendSurfaceContractsTypeScript `shouldContainText` "export type RosterRosterWeekScope = { venueId: FrontendContractUuid; rosterGroupId: FrontendContractUuid; weekOffset: number };"
        frontendSurfaceContractsTypeScript `shouldContainText` "{ kind: \"roster-row\"; params: RosterRosterRowFragmentParams }"
        frontendSurfaceContractsTypeScript `shouldContainText` "\"htmxActions\":[{\"name\":\"navigate-roster-week\""
        frontendSurfaceContractsTypeScript `shouldContainText` "{\"name\":\"set-roster-layout-mode\",\"fields\":[\"rosterLayoutMode\"]"
        frontendSurfaceContractsTypeScript `shouldContainText` "\"intents\":[\"set-roster-layout-mode\",\"move-roster-shift-to-slot\",\"duplicate-roster-shift-to-day\",\"drop-roster-staff\"]"
        frontendSurfaceContractsTypeScript `shouldContainText` "export type MoveRosterShiftToSlotIntentFields = RosterMoveRosterShiftToSlotIntentFields;"
        frontendSurfaceContractsTypeScript `shouldContainText` "export type DuplicateRosterShiftToDayIntentFields = RosterDuplicateRosterShiftToDayIntentFields;"
        frontendSurfaceContractsTypeScript `shouldContainText` "export type RosterSessionName = \"drag\";"
        frontendSurfaceContractsTypeScript `shouldContainText` "export type RosterSourceRef = \"shift-drag-source\" | \"staff-drag-source\";"
        frontendSurfaceContractsTypeScript `shouldContainText` "export type RosterDropzoneRef = \"shift-slot-dropzone\" | \"staff-create-dropzone\" | \"day-column-dropzone\" | \"existing-shift-dropzone\" | \"delete-shift-dropzone\";"
        frontendSurfaceContractsTypeScript `shouldContainText` "export type RosterActivationRef = \"roster-layout-mode-activation\";"
        frontendSurfaceContractsTypeScript `shouldContainText` "\"interaction\":{\"sourceRefs\":[{\"ref\":\"shift-drag-source\",\"session\":\"drag\",\"intent\":\"move-roster-shift-to-slot\",\"sourceField\":\"sourceItemKey\",\"compatibleDropzones\":[\"shift-slot-dropzone\",\"day-column-dropzone\",\"delete-shift-dropzone\"],\"modifierVariants\":[{\"semantic\":\"copy\",\"intent\":\"duplicate-roster-shift-to-day\""
        frontendSurfaceContractsTypeScript `shouldContainText` "\"dropzoneRefs\":[{\"ref\":\"shift-slot-dropzone\",\"session\":\"drag\",\"targetField\":\"targetDropzoneKey\"},{\"ref\":\"staff-create-dropzone\",\"session\":\"drag\",\"targetField\":\"targetDropzoneKey\"}"
        frontendSurfaceContractsTypeScript `shouldContainText` "\"activationRefs\":[{\"ref\":\"roster-layout-mode-activation\",\"intent\":\"set-roster-layout-mode\",\"valueField\":\"rosterLayoutMode\",\"trigger\":\"click\"}]"
        frontendSurfaceContractsTypeScript `shouldContainText` "export const rosterSurfaceManifest"

    it "reports stable diagnostics for malformed reflected specs" do
        let duplicateFields = checkedSurfaceContractIR (SurfaceContractIR (reflectSurfaceRegistry @'[DuplicateFieldSurface]))
        let missingReference = checkedSurfaceContractIR (SurfaceContractIR (reflectSurfaceRegistry @'[MissingReferenceSurface]))
        let conflictingShared = checkedSurfaceContractIR (SurfaceContractIR (reflectSurfaceRegistry @'[SharedScopeA, SharedScopeB]))
        let missingDtoRef = checkedSurfaceContractIR (SurfaceContractIR (reflectSurfaceRegistry @'[MissingDtoRefSurface]))
        let missingAuth = checkedSurfaceContractIR (SurfaceContractIR (reflectSurfaceRegistry @'[MissingAuthSurface]))
        let missingLiveInvalidation = checkedSurfaceContractIR (SurfaceContractIR (reflectSurfaceRegistry @'[MissingLiveInvalidationSurface]))
        let missingResourceSource = checkedSurfaceContractIR (SurfaceContractIR (reflectSurfaceRegistry @'[MissingResourceSourceSurface]))
        let invalidScopeSource = checkedSurfaceContractIR (SurfaceContractIR (reflectSurfaceRegistry @'[InvalidScopeSourceSurface]))
        let invalidFragmentSource = checkedSurfaceContractIR (SurfaceContractIR (reflectSurfaceRegistry @'[InvalidFragmentSourceSurface]))
        let sourceTypeMismatch = checkedSurfaceContractIR (SurfaceContractIR (reflectSurfaceRegistry @'[ResourceSourceTypeMismatchSurface]))
        let duplicateResourceSource = checkedSurfaceContractIR (SurfaceContractIR (reflectSurfaceRegistry @'[DuplicateResourceSourceSurface]))
        let conflictingResources = checkedSurfaceContractIR (SurfaceContractIR (reflectSurfaceRegistry @'[DuplicateResourceSurfaceA, DuplicateResourceSurfaceB]))
        let invalidInteractionRef = checkedSurfaceContractIR (SurfaceContractIR (reflectSurfaceRegistry @'[InvalidInteractionRefSurface]))
        let invalidHtmxTargetRef = checkedSurfaceContractIR (SurfaceContractIR (reflectSurfaceRegistry @'[InvalidHtmxTargetRefSurface]))
        let duplicateHtmxMethod = checkedSurfaceContractIR (SurfaceContractIR (reflectSurfaceRegistry @'[DuplicateHtmxMethodSurface]))
        let emptyCustomHtmxReason = checkedSurfaceContractIR (SurfaceContractIR (reflectSurfaceRegistry @'[EmptyCustomHtmxReasonSurface]))

        diagnosticMessages duplicateFields `shouldContain` ["surface duplicate has duplicate scope field panelId"]
        diagnosticMessages missingReference `shouldContain` ["htmx action bad references missing fragment missing on surface missing-reference"]
        diagnosticMessages conflictingShared `shouldContain` ["conflicting shared declaration: scope shared"]
        diagnosticMessages missingDtoRef `shouldContain` ["field missingPayload references missing dto MissingPayload on surface missing-dto-ref"]
        diagnosticMessages missingAuth `shouldContain` ["surface missing-auth scope lab must declare exactly one authorization policy"]
        diagnosticMessages missingLiveInvalidation `shouldContain` ["surface missing-live-invalidation live fragment bad must declare DependsOn or ResyncOnly"]
        diagnosticMessages missingResourceSource `shouldContain` ["surface missing-resource-source fragment bad dependency test-resource missing source for resource field weekOffset"]
        diagnosticMessages invalidScopeSource `shouldContain` ["surface invalid-scope-source fragment bad dependency test-resource references missing scope field weekOffset"]
        diagnosticMessages invalidFragmentSource `shouldContain` ["surface invalid-fragment-source fragment bad dependency test-resource references missing fragment field panelId"]
        diagnosticMessages sourceTypeMismatch `shouldContain` ["surface resource-source-type-mismatch fragment bad dependency mismatched-resource maps scope field venueId with incompatible wire type or presence"]
        diagnosticMessages duplicateResourceSource `shouldContain` ["surface duplicate-resource-source fragment bad dependency test-resource supplies resource field venueId more than once"]
        diagnosticMessages conflictingResources `shouldContain` ["conflicting shared declaration: resource test-resource"]
        diagnosticMessages invalidInteractionRef `shouldContain` ["source ref bad references missing session missing-fragment on surface invalid-interaction-ref"]
        diagnosticMessages invalidInteractionRef `shouldContain` ["source ref bad references missing intent field missingPayload for intent bad on surface invalid-interaction-ref"]
        diagnosticMessages invalidHtmxTargetRef `shouldContain` ["htmx action bad references missing dom token missing-fragment on surface invalid-htmx-target-ref"]
        diagnosticMessages duplicateHtmxMethod `shouldContain` ["surface duplicate-htmx-method htmx action bad declares method more than once"]
        diagnosticMessages emptyCustomHtmxReason `shouldContain` ["surface empty-custom-htmx-reason custom HTMX missing-fragment must include a non-empty reason"]

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

    it "renders generated HTMX action attrs from surface action metadata" do
        let surface = expectSurface "surface-lab" registeredFrontendSurfaceContractIR
        let action = fromMaybe (error "missing lab action") (listToMaybe surface.surfaceHtmxActions)
        let route = FrontendSurfaceActionRoute
                { actionRouteUrl = "/RefreshFrontendSurfaceLabPanel"
                , actionRouteFields = [FrontendSurfaceFieldValue "panelId" "panel-1"]
                , actionRouteCustomHtmx = [FrontendSurfaceCustomHtmxAttrs "lab-panel-custom-htmx" [("hx-vals", "{}")]]
                , actionRouteStandardUrl = Nothing
                , actionRouteExtraAttrs = [("class", "surface-action-test")]
                }
        let formHtml = cs (HtmlRenderer.renderHtml (renderFrontendSurfaceActionForm action route (Html5.toHtml ("refresh" :: Text))))
        let linkHtml = cs (HtmlRenderer.renderHtml (renderFrontendSurfaceActionLink action route (Html5.toHtml ("refresh" :: Text))))
        let buttonHtml = cs (HtmlRenderer.renderHtml (renderFrontendSurfaceActionSubmitButton action route (Html5.toHtml ("refresh" :: Text))))

        formHtml `shouldContainText` "method=\"post\""
        formHtml `shouldContainText` "action=\"/RefreshFrontendSurfaceLabPanel\""
        formHtml `shouldContainText` "hx-post=\"/RefreshFrontendSurfaceLabPanel\""
        formHtml `shouldContainText` "hx-target=\"#lab-panel-target\""
        formHtml `shouldContainText` "hx-swap=\"outerHTML\""
        formHtml `shouldContainText` "hx-include=\"lab-panel-include\""
        formHtml `shouldContainText` "hx-push-url=\"false\""
        formHtml `shouldContainText` "hx-vals=\"{}\""
        formHtml `shouldContainText` "data-bepis-surface-action=\"refresh-panel\""
        formHtml `shouldContainText` "data-bepis-surface-action-config="
        linkHtml `shouldContainText` "href=\"/RefreshFrontendSurfaceLabPanel\""
        linkHtml `shouldContainText` "hx-post=\"/RefreshFrontendSurfaceLabPanel\""
        buttonHtml `shouldContainText` "formaction=\"/RefreshFrontendSurfaceLabPanel\""
        buttonHtml `shouldContainText` "hx-post=\"/RefreshFrontendSurfaceLabPanel\""

    it "renders minimal HTMX action and intent forms from SurfaceImpl metadata" do
        let request = FrontendSurfaceHtmxRequest
                { htmxRequestName = "refresh-panel"
                , htmxRequestMethod = FrontendSurfacePost
                , htmxRequestUrl = "/RefreshFrontendSurfaceLabPanel"
                , htmxRequestTarget = "#surface-lab-panel"
                , htmxRequestSwap = "outerHTML"
                , htmxRequestFields = [FrontendSurfaceFieldValue "panelId" "panel-1"]
                }
        let intent = FrontendSurfaceIntentForm "move-lab-card" request
        let actionHtml = cs (HtmlRenderer.renderHtml (renderFrontendSurfaceHtmxForm request (Html5.toHtml ("refresh" :: Text))))
        let intentHtml = cs (HtmlRenderer.renderHtml (renderFrontendSurfaceIntentForm intent (Html5.toHtml ("move" :: Text))))

        actionHtml `shouldContainText` "hx-post=\"/RefreshFrontendSurfaceLabPanel\""
        actionHtml `shouldContainText` "data-bepis-surface-action=\"refresh-panel\""
        actionHtml `shouldContainText` "name=\"panelId\""
        intentHtml `shouldContainText` "data-bepis-intent-form=\"move-lab-card\""
        intentHtml `shouldContainText` "hx-target=\"#surface-lab-panel\""

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
data MissingLiveInvalidation
data MissingResourceSource
data InvalidScopeSource
data InvalidFragmentSource
data ResourceSourceTypeMismatch
data DuplicateResourceSource
data DuplicateResourceA
data DuplicateResourceB
data InvalidInteractionRef
data InvalidHtmxTargetRef
data DuplicateHtmxMethod
data EmptyCustomHtmxReason
data MissingPayload
data PanelId
data StaffFilterId
data VenueId
data WeekOffset
data LabScope

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
        '[ Scope LabScope '[ Field VenueId 'WireUUID ] '[ 'NoAuth ]
         , Action Bad '[] '[ 'Target MissingFragment ]
         ]

type MissingDtoRefSurface =
    Surface MissingDtoRef
        '[ Scope LabScope '[ Field VenueId 'WireUUID ] '[ 'NoAuth ]
         , Dto Bad '[ Field MissingPayload ('WireRef MissingPayload) ]
         ]

type MissingAuthSurface =
    Surface MissingAuth
        '[ Scope LabScope '[ Field VenueId 'WireUUID ] '[]
         ]

type MissingLiveInvalidationSurface =
    Surface MissingLiveInvalidation
        '[ Scope LabScope '[ Field VenueId 'WireUUID ] '[ 'NoAuth ]
         , Fragment Bad '[] '[ 'Live ]
         ]

type MissingResourceSourceSurface =
    Surface MissingResourceSource
        '[ Scope LabScope '[ Field VenueId 'WireUUID ] '[ 'NoAuth ]
         , Fragment Bad '[]
            '[ 'Live
             , 'DependsOn ('Resource TestResource '[ Field VenueId 'WireUUID, Field WeekOffset 'WireInt ])
                '[ 'FromScope VenueId ]
             ]
         ]

type InvalidScopeSourceSurface =
    Surface InvalidScopeSource
        '[ Scope LabScope '[ Field VenueId 'WireUUID ] '[ 'NoAuth ]
         , Fragment Bad '[]
            '[ 'Live
             , 'DependsOn ('Resource TestResource '[ Field WeekOffset 'WireInt ])
                '[ 'FromScope WeekOffset ]
             ]
         ]

type InvalidFragmentSourceSurface =
    Surface InvalidFragmentSource
        '[ Scope LabScope '[ Field VenueId 'WireUUID ] '[ 'NoAuth ]
         , Fragment Bad '[]
            '[ 'Live
             , 'DependsOn ('Resource TestResource '[ Field PanelId 'WireUUID ])
                '[ 'FromFragment PanelId ]
             ]
         ]

type ResourceSourceTypeMismatchSurface =
    Surface ResourceSourceTypeMismatch
        '[ Scope LabScope '[ Field VenueId 'WireUUID ] '[ 'NoAuth ]
         , Fragment Bad '[]
            '[ 'Live
             , 'DependsOn ('Resource MismatchedResource '[ Field VenueId 'WireText ])
                '[ 'FromScope VenueId ]
             ]
         ]

type DuplicateResourceSourceSurface =
    Surface DuplicateResourceSource
        '[ Scope LabScope '[ Field VenueId 'WireUUID ] '[ 'NoAuth ]
         , Fragment Bad '[ Field VenueId 'WireUUID ]
            '[ 'Live
             , 'DependsOn ('Resource TestResource '[ Field VenueId 'WireUUID ])
                '[ 'FromScope VenueId, 'FromFragment VenueId ]
             ]
         ]

type DuplicateResourceSurfaceA =
    Surface DuplicateResourceA
        '[ Scope LabScope '[ Field VenueId 'WireUUID ] '[ 'NoAuth ]
         , Fragment Bad '[]
            '[ 'Live
             , 'DependsOn ('Resource TestResource '[ Field VenueId 'WireUUID ])
                '[ 'FromScope VenueId ]
             ]
         ]

type DuplicateResourceSurfaceB =
    Surface DuplicateResourceB
        '[ Scope LabScope '[ Field VenueId 'WireUUID ] '[ 'NoAuth ]
         , Fragment Bad '[]
            '[ 'Live
             , 'DependsOn ('Resource TestResource '[ Field VenueId 'WireText ])
                '[ 'FromScope VenueId ]
             ]
         ]

type InvalidInteractionRefSurface =
    Surface InvalidInteractionRef
        '[ Scope LabScope '[ Field VenueId 'WireUUID ] '[ 'NoAuth ]
         , Intent Bad '[ Field PanelId 'WireUUID ] '[]
         , SourceRef Bad '[ 'SessionOption MissingFragment, 'Submits Bad, 'SourceField MissingPayload ]
         ]

type InvalidHtmxTargetRefSurface =
    Surface InvalidHtmxTargetRef
        '[ Scope LabScope '[ Field VenueId 'WireUUID ] '[ 'NoAuth ]
         , Action Bad '[] '[ 'HtmxTarget MissingFragment ]
         ]

type DuplicateHtmxMethodSurface =
    Surface DuplicateHtmxMethod
        '[ Scope LabScope '[ Field VenueId 'WireUUID ] '[ 'NoAuth ]
         , Action Bad '[] '[ 'HtmxMethod 'HtmxPost, 'HtmxMethod 'HtmxDelete ]
         ]

type EmptyCustomHtmxReasonSurface =
    Surface EmptyCustomHtmxReason
        '[ Scope LabScope '[ Field VenueId 'WireUUID ] '[ 'NoAuth ]
         , Action Bad '[] '[ 'CustomHtmx MissingFragment "" ]
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
