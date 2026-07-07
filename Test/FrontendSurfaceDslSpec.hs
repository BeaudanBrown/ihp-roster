{-# LANGUAGE DataKinds        #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators    #-}

module Test.FrontendSurfaceDslSpec
    ( tests
    ) where

import Application.Helper.FrontendContract.Registry (registeredFrontendContractIRForSurfaceContract)
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

frontendSurfaceContractsTypeScript :: Text
frontendSurfaceContractsTypeScript =
    either error id (renderFrontendContractTypeScript (registeredFrontendContractIRForSurfaceContract registeredFrontendSurfaceContractIR))

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
                , mountedFragmentLoadPolicy = "lazy"
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

        impl.surfaceImplActions |> map (.htmxRequestName) `shouldBe` ["refresh-panel"]
        impl.surfaceImplIntents |> map (.intentFormName) `shouldBe` ["move-lab-card"]
        html `shouldContainText` "data-bepis-surface=\"surface-lab\""
        html `shouldContainText` "data-bepis-surface-config="
        html `shouldNotContainText` "data-live-update-surface"
        frontendSurfaceMountConfigJson config `shouldContainText` "\"mountKey\":\"primary\""
        frontendSurfaceMountConfigJson config `shouldContainText` "\"targetId\":\"surface-lab-panel\""
        frontendSurfaceMountConfigJson config `shouldContainText` "\"kind\":\"focused-field\""
        frontendSurfaceMountConfigJson config `shouldContainText` "\"activeSelector\":\"input[data-lab-field]:focus\""

    it "renders lazy fragments with canonical UI-region attrs and feature slot classes" do
        let fragment = FrontendSurfaceMountedFragment
                { mountedFragmentKey = FrontendSurfaceFragmentKey "lab-panel" Aeson.Null
                , mountedFragmentTargetId = "surface-lab-panel"
                , mountedFragmentUrl = "/ShowFrontendSurfaceLabPanelFragment"
                , mountedFragmentProtection = FrontendSurfaceReplace
                , mountedFragmentLoadPolicy = "lazy"
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

    it "derives lazy render defaults from existing primitive options" do
        let defaults = knownFragmentOptions @'[ 'Lazy '[ 'Trigger TestLoad, 'Placeholder TestPanel ]]
        defaults.lazyFragmentDefaultLoadPolicy `shouldBe` "lazy"
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

    it "extracts the registered lab surface into checked contract IR" do
        let surface = expectSurface "surface-lab" registeredFrontendSurfaceContractIR

        surface.surfaceName `shouldBe` "surface-lab"
        map (.scopeName) surface.surfaceScopes `shouldBe` ["lab"]
        map (.fragmentName) surface.surfaceFragments `shouldBe` ["lab-shell", "lab-panel"]
        map (.htmxActionName) surface.surfaceHtmxActions `shouldBe` ["refresh-panel"]
        map (.intentName) surface.surfaceIntents `shouldBe` ["move-lab-card"]
        surface.surfaceSessions `shouldBe` ["drag"]
        surface.surfaceLayers `shouldBe` ["drag-preview"]
        surface.surfaceDomTokens `shouldBe` ["lab-root", "lab-dropzone", "lab-panel-target", "lab-panel-include"]
        map fst surface.surfaceDtos `shouldBe` ["lab-payload", "lab-related-payload"]
        surface.surfaceFragments
            |> find (\fragment -> fragment.fragmentName == "lab-panel")
            |> fmap (.fragmentOptions)
            `shouldBe` Just [LazyOption [TriggerOption "load", PlaceholderOption "panel"]]
        surface.surfaceHtmxActions
            |> find (\action -> action.htmxActionName == "refresh-panel")
            |> fmap (.htmxActionOptions)
            `shouldBe` Just
                [ TargetOption "lab-panel"
                , HtmxMethodOption HtmxPostIR
                , HtmxTargetOption "lab-panel-target"
                , HtmxSwapOption "outer-html"
                , HtmxIncludeOption "lab-panel-include"
                , HtmxPushUrlOption HtmxPushUrlFalseIR
                , CustomHtmxOption "lab-panel-custom-htmx" "lab fixture covers auditable custom HTMX metadata"
                ]

    it "extracts the registered timesheets surface into checked contract IR" do
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
        frontendSurfaceContractsTypeScript `shouldContainText` "{ kind: \"lab-panel\"; params: SurfaceLabLabPanelFragmentParams }"
        frontendSurfaceContractsTypeScript `shouldContainText` "export type RefreshPanelActionFields = SurfaceLabRefreshPanelActionFields;"
        frontendSurfaceContractsTypeScript `shouldContainText` "export type MoveLabCardIntentFields = SurfaceLabMoveLabCardIntentFields;"
        frontendSurfaceContractsTypeScript `shouldContainText` "export type LabPayload = { label: string; count?: number; note: string | null; tags: ReadonlyArray<string>; dueDay: FrontendContractDay; maybeRank: number | undefined; maybeMemo: string | null; relatedPayload: LabRelatedPayload };"
        frontendSurfaceContractsTypeScript `shouldContainText` "export type LabRelatedPayload = { label: string };"
        frontendSurfaceContractsTypeScript `shouldContainText` "export const surfaceLabSurfaceManifest"
        frontendSurfaceContractsTypeScript `shouldContainText` "export function parseFrontendSurfaceName"

    it "renders generated TypeScript contracts for the timesheets surface" do
        frontendSurfaceContractsTypeScript `shouldContainText` "export type TimesheetsFragmentKey ="
        frontendSurfaceContractsTypeScript `shouldContainText` "{ kind: \"timesheet-day-section\"; params: TimesheetsTimesheetDaySectionFragmentParams }"
        frontendSurfaceContractsTypeScript `shouldContainText` "export type TimesheetsMountState = TimesheetsTimesheetsMountStateMountState;"
        frontendSurfaceContractsTypeScript `shouldContainText` "export const timesheetsSurfaceManifest"

    it "extracts the registered roster surface into checked contract IR" do
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
                       , "roster-day-section"
                       , "roster-row"
                       ]
        surface.surfaceFragments
            |> find (\fragment -> fragment.fragmentName == "roster-row")
            |> fmap (.fragmentParams)
            |> fmap (map (.fieldName))
            `shouldBe` Just ["rosterDayId", "rowIndex"]
        map (.htmxActionName) surface.surfaceHtmxActions `shouldBe` ["set-roster-layout-mode", "move-roster-shift-to-slot"]
        map (.intentName) surface.surfaceIntents `shouldBe` ["set-roster-layout-mode", "move-roster-shift-to-slot"]
        surface.surfaceSessions `shouldBe` ["drag"]
        map (.sourceRefName) surface.surfaceSourceRefs `shouldBe` ["drag-source"]
        map (.dropzoneRefName) surface.surfaceDropzoneRefs `shouldBe` ["drag-dropzone"]
        map (.activationRefName) surface.surfaceActivationRefs `shouldBe` ["roster-layout-mode-activation"]
        surface.surfaceLayers `shouldBe` ["drag-preview"]
        map fst surface.surfaceEffects `shouldBe` ["clone-shadow", "dropzone-highlight"]
        map (.conflictPolicyResolution) surface.surfacePolicies `shouldBe` [DeferIR]

    it "renders generated TypeScript contracts for the roster surface" do
        frontendSurfaceContractsTypeScript `shouldContainText` "export type RosterFragmentKey ="
        frontendSurfaceContractsTypeScript `shouldContainText` "export type RosterRosterWeekScope = { venueId: FrontendContractUuid; rosterGroupId: FrontendContractUuid; weekOffset: number };"
        frontendSurfaceContractsTypeScript `shouldContainText` "{ kind: \"roster-row\"; params: RosterRosterRowFragmentParams }"
        frontendSurfaceContractsTypeScript `shouldContainText` "\"intents\":[{\"name\":\"set-roster-layout-mode\""
        frontendSurfaceContractsTypeScript `shouldContainText` "export type MoveRosterShiftToSlotIntentFields = RosterMoveRosterShiftToSlotIntentFields;"
        frontendSurfaceContractsTypeScript `shouldContainText` "export type RosterSessionName = \"drag\";"
        frontendSurfaceContractsTypeScript `shouldContainText` "export type RosterSourceRef = \"drag-source\";"
        frontendSurfaceContractsTypeScript `shouldContainText` "export type RosterDropzoneRef = \"drag-dropzone\";"
        frontendSurfaceContractsTypeScript `shouldContainText` "export type RosterActivationRef = \"roster-layout-mode-activation\";"
        frontendSurfaceContractsTypeScript `shouldContainText` "\"interaction\":{\"sourceRefs\":[{\"ref\":\"drag-source\",\"session\":\"drag\",\"intent\":\"move-roster-shift-to-slot\",\"sourceField\":\"sourceItemKey\"}]"
        frontendSurfaceContractsTypeScript `shouldContainText` "\"dropzoneRefs\":[{\"ref\":\"drag-dropzone\",\"session\":\"drag\",\"targetField\":\"targetDropzoneKey\"}]"
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
        diagnosticMessages missingDtoRef `shouldContain` ["field missingPayload references missing dto missing-payload on surface missing-dto-ref"]
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

        sourceHtml `shouldContainText` "data-bepis-source-ref=\"drag-source\""
        sourceHtml `shouldContainText` "data-bepis-source-key=\"shift:1\""
        sourceHtml `shouldNotContainText` "data-bepis-session-kind"
        dropzoneHtml `shouldContainText` "data-bepis-dropzone-ref=\"drag-dropzone\""
        dropzoneHtml `shouldContainText` "data-bepis-dropzone-key=\"slot:2\""
        activationHtml `shouldContainText` "data-bepis-activation-ref=\"roster-layout-mode-activation\""
        activationHtml `shouldNotContainText` "data-bepis-activation-intent"

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
