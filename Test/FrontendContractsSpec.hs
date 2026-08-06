{-# LANGUAGE LambdaCase          #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE TypeApplications    #-}

module Test.FrontendContractsSpec
    ( tests
    ) where

import qualified Application.Helper.FrontendContract.App as App
import qualified Application.Helper.FrontendContract.AppShell as AppShell
import Application.Helper.FrontendContract.AppShell.Request (appShellActionFields,
                                                             appShellActionFor,
                                                             parseAppShellActionParamPairs)
import Application.Helper.FrontendContract.AppShell.Runtime (AppShellActionRoute (..),
                                                             appShellActionByMarker,
                                                             appShellActionHtmxAttrPairs)
import Application.Helper.FrontendContract.AppValues (AppEvents (..),
                                                      canonicalAppEvents,
                                                      interactionIntentSubmitHtmxTrigger)
import Application.Helper.FrontendContract.ClosedScalar (closedScalarLiterals)
import Application.Helper.FrontendContract.Contracts (TypeScriptDeclaration (..),
                                                      TypeScriptDeclarationOrigin (..),
                                                      frontendContractDeclarations,
                                                      frontendContractsTypeScript)
import qualified Application.Helper.FrontendContract.HorizontalScroll as HorizontalScroll
import Application.Helper.FrontendContract.HorizontalScroll.Runtime (HorizontalScrollDom (..),
                                                                     canonicalHorizontalScrollDom)
import qualified Application.Helper.FrontendContract.Htmx as Htmx
import qualified Application.Helper.FrontendContract.IR as Contract
import qualified Application.Helper.FrontendContract.LiveUpdate as LiveContract
import Application.Helper.FrontendContract.LiveUpdateValues (liveUpdateClientIdHeaderName,
                                                             liveUpdateSocketPathSegment,
                                                             surfaceActionDomAttribute,
                                                             surfaceConfigDomAttribute,
                                                             surfaceDomAttribute)
import qualified Application.Helper.FrontendContract.Naming as Naming
import qualified Application.Helper.FrontendContract.OrderedRange as OrderedRange
import Application.Helper.FrontendContract.OrderedRange.Runtime (OrderedRangeDom (..),
                                                                 canonicalOrderedRangeDom)
import qualified Application.Helper.FrontendContract.Overlay as Overlay
import Application.Helper.FrontendContract.Overlay.Runtime (OverlayDom (..),
                                                            canonicalOverlayDom)
import qualified Application.Helper.FrontendContract.Passkey as Passkey
import Application.Helper.FrontendContract.Passkey.Runtime (PasskeyDom (..),
                                                            canonicalPasskeyDom)
import qualified Application.Helper.FrontendContract.PwaInstall as PwaInstall
import Application.Helper.FrontendContract.PwaInstall.Runtime (PwaInstallDom (..),
                                                               canonicalPwaInstallDom)
import Application.Helper.FrontendContract.Registry (registeredFrontendContractIR)
import qualified Application.Helper.FrontendContract.Surface.ContractIR as SurfaceIR
import Application.Helper.FrontendContract.Surface.Contracts (registeredFrontendSurfaceContractIR)
import Application.Helper.FrontendContract.Surface.LeaveRequests (LeaveSectionValue (..))
import Application.Helper.FrontendContract.Surface.Profile (StaffProfileSectionValue (..))
import Application.Helper.FrontendContract.Surface.Reflect (reflectSurfaceSpec)
import Application.Helper.FrontendContract.Surface.Roster (RosterStaffScopeValue (..))
import Application.Helper.FrontendContract.Surface.Values (noSurfaceFields,
                                                           surfaceField,
                                                           surfaceFieldNameFrom,
                                                           surfaceFieldValue)
import qualified Application.Helper.FrontendContract.TimePicker as TimePicker
import Application.Helper.FrontendContract.TimePicker.Runtime (TimePickerDom (..),
                                                               canonicalTimePickerDom)
import Application.Helper.FrontendContract.Values (constantValue, domAttrValue,
                                                   domIdValue, enumLiteralValue,
                                                   eventNameValue,
                                                   lookupConstantValue,
                                                   lookupDomAttrValue,
                                                   lookupDomIdValue,
                                                   lookupEnumLiteralValue,
                                                   lookupEventNameValue)
import Application.Helper.FrontendContract.Wire.Json (validateContractMarkerValue,
                                                      validateContractMarkerValueWith,
                                                      validateSurfaceFragmentKeyValue,
                                                      validateSurfaceScopeValue,
                                                      validateWireValue)
import qualified Application.Helper.FrontendContract.Wire.LiveUpdate as Live
import qualified Application.Helper.FrontendContract.XeroCandidateFilter as XeroCandidateFilter
import Application.Helper.FrontendContract.XeroCandidateFilter.Runtime (XeroCandidateFilterDom (..),
                                                                        canonicalXeroCandidateFilterDom)
import Application.Helper.ShiftTypeColours (ShiftTypeColourKeyEnum (..))
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as AesonKey
import qualified Data.Aeson.KeyMap as KeyMap
import qualified Data.Aeson.Types as AesonTypes
import qualified Data.ByteString.Lazy as LBS
import Data.Either (isLeft, isRight)
import qualified Data.List as List
import qualified Data.Text as Text
import qualified Data.Text.Encoding as TextEncoding
import qualified Data.Text.IO as Text
import Generated.Types (FeedbackTypeEnum (..))
import IHP.Prelude
import Test.Hspec
import qualified Test.Support.FrontendSurfaceFixture as SurfaceFixture

data SpecNested
data SpecRecord
data SpecUnion

tests :: Spec
tests = describe "Frontend contract generator foundation" do
    it "keeps the public generated file entrypoint FrontendContract-owned" do
        frontendContractsTypeScript `shouldSatisfy` Text.isPrefixOf "// @generated by Application.Helper.FrontendContract.Contracts"
        frontendContractsTypeScript `shouldSatisfy` Text.isInfixOf "export type RosterStaffPanelSortRow"
        frontendContractsTypeScript `shouldSatisfy` Text.isInfixOf "export type SurfaceScope"
        frontendContractsTypeScript `shouldSatisfy` Text.isInfixOf "export type LiveUpdateCommand"
        frontendContractsTypeScript `shouldSatisfy` Text.isInfixOf "export type UiRegionTransitionProfile"
        frontendContractsTypeScript `shouldSatisfy` Text.isInfixOf "export type InteractionSessionEffect"

    it "shares reflected live endpoint, header, and mount DOM constants across Haskell and TypeScript" do
        liveUpdateSocketPathSegment `shouldBe` "live-updates"
        liveUpdateClientIdHeaderName `shouldBe` "X-Live-Update-Client-Id"
        surfaceDomAttribute `shouldBe` "data-bepis-surface"
        surfaceConfigDomAttribute `shouldBe` "data-bepis-surface-config"
        surfaceActionDomAttribute `shouldBe` "data-bepis-surface-action"
        frontendContractsTypeScript `shouldSatisfy` Text.isInfixOf "export const liveUpdateSocketPath = \"live-updates\" as const;"
        frontendContractsTypeScript `shouldSatisfy` Text.isInfixOf "export const liveUpdateClientIdHeader = \"X-Live-Update-Client-Id\" as const;"
        frontendContractsTypeScript `shouldSatisfy` Text.isInfixOf "export const surfaceDomAttr = \"data-bepis-surface\" as const;"
        frontendContractsTypeScript `shouldSatisfy` Text.isInfixOf "export const surfaceConfigDomAttr = \"data-bepis-surface-config\" as const;"
        frontendContractsTypeScript `shouldSatisfy` Text.isInfixOf "export const surfaceActionDomAttr = \"data-bepis-surface-action\" as const;"
        frontendContractsTypeScript `shouldSatisfy` Text.isInfixOf "sourceRef: sourceRefDomAttr"
        frontendContractsTypeScript `shouldNotSatisfy` Text.isInfixOf "export const rosterContentDomToken"
        frontendContractsTypeScript `shouldNotSatisfy` Text.isInfixOf "export const rosterWeekShellDomToken"

    it "generates roster chrome roles and closed state guards" do
        forM_
            [ "export const rosterFullscreenRootDomAttr = \"data-bepis-roster-fullscreen-root\" as const;"
            , "export const rosterFullscreenToggleDomAttr = \"data-bepis-roster-fullscreen-toggle\" as const;"
            , "export const rosterFullscreenLabelDomAttr = \"data-bepis-roster-fullscreen-label\" as const;"
            , "export const rosterColumnEditorDomAttr = \"data-bepis-roster-column-editor\" as const;"
            , "export const rosterColumnEditStartDomAttr = \"data-bepis-roster-column-edit-start\" as const;"
            , "export const rosterColumnEditDoneDomAttr = \"data-bepis-roster-column-edit-done\" as const;"
            , "export const rosterFullscreenDomAttr = \"data-bepis-roster-fullscreen\" as const;"
            , "export const rosterColumnEditingDomAttr = \"data-bepis-roster-column-editing\" as const;"
            , "export type RosterFullscreenState = \"collapsed\" | \"expanded\";"
            , "export function isRosterFullscreenState(value: unknown): value is RosterFullscreenState"
            , "export type RosterColumnEditingState = \"inactive\" | \"active\";"
            , "export function isRosterColumnEditingState(value: unknown): value is RosterColumnEditingState"
            ]
            (\expected -> frontendContractsTypeScript `shouldSatisfy` Text.isInfixOf expected)

    it "generates roster image-export roles, format, and exact payload parsers" do
        forM_
            [ "export const rosterImageExportTriggerDomAttr = \"data-bepis-roster-image-export-trigger\" as const;"
            , "export const rosterImageExportConfigDomAttr = \"data-bepis-roster-image-export-config\" as const;"
            , "export const rosterImageExportProjectionDomAttr = \"data-bepis-roster-image-export-projection\" as const;"
            , "export const rosterImageExportRowDomAttr = \"data-bepis-roster-image-export-row\" as const;"
            , "export const rosterImageExportCellDomAttr = \"data-bepis-roster-image-export-cell\" as const;"
            , "export const rosterImageExportFormatDomAttr = \"data-bepis-roster-image-export-format\" as const;"
            , "export type RosterImageExportFormatState = \"jpg\";"
            , "export function isRosterImageExportFormatState(value: unknown): value is RosterImageExportFormatState"
            , "export type RosterImageExportConfig = { imageExportFilename: string"
            , "export function parseRosterImageExportConfig(value: unknown): RosterImageExportConfig"
            , "export type RosterImageExportCell = { imageExportText: string; imageExportEndEllipsis: boolean };"
            , "export function parseRosterImageExportCell(value: unknown): RosterImageExportCell"
            ]
            (\expected -> frontendContractsTypeScript `shouldSatisfy` Text.isInfixOf expected)

    it "generates roster week-overview roles, states, and exact payload parsers" do
        forM_
            [ "export const rosterWeekOverviewPanelDomAttr = \"data-bepis-roster-week-overview-panel\" as const;"
            , "export const rosterWeekOverviewDayDomAttr = \"data-bepis-roster-week-overview-day\" as const;"
            , "export const rosterWeekOverviewTodayDomAttr = \"data-bepis-roster-week-overview-today\" as const;"
            , "export const rosterWeekOverviewDetailsDomAttr = \"data-bepis-roster-week-overview-details\" as const;"
            , "export const rosterWeekOverviewAvailabilityDomAttr = \"data-bepis-roster-week-overview-availability\" as const;"
            , "export const rosterWeekOverviewClosureDomAttr = \"data-bepis-roster-week-overview-closure\" as const;"
            , "export type RosterWeekOverviewAvailabilityState = \"loaded\" | \"unloaded\";"
            , "export type RosterWeekOverviewClosureState = \"open\" | \"closed\";"
            , "export type RosterWeekOverviewCalendarDayState = \"today\" | \"other-day\";"
            , "export type RosterWeekOverviewPanelConfig = { weekOverviewCurrentDate: FrontendContractDay };"
            , "export function parseRosterWeekOverviewPanelConfig(value: unknown): RosterWeekOverviewPanelConfig"
            , "export type RosterWeekOverviewDayConfig = { weekOverviewDate: FrontendContractDay"
            , "export function parseRosterWeekOverviewDayConfig(value: unknown): RosterWeekOverviewDayConfig"
            ]
            (\expected -> frontendContractsTypeScript `shouldSatisfy` Text.isInfixOf expected)

    it "registers one generated FrontendContract declaration block" do
        [(declaration.name, declaration.origin) | declaration <- frontendContractDeclarations]
            `shouldBe` [("FrontendContractGlobals", HaskellSchemaGenerated)]

    it "keeps checked-in contracts byte-identical to the reflection-backed generator" do
        checkedIn <- Text.readFile "frontend/ts/generated/contracts.ts"
        checkedIn `shouldBe` frontendContractsTypeScript

    it "keeps executable fragment descriptors out of the live wire contract" do
        let generatedTypes = generatedContractTypeNames frontendContractsTypeScript
        forM_ ["SurfaceFragmentKey", "SurfaceSubscription", "LiveFragmentsRefreshEventDetail"] \name ->
            generatedTypes `shouldContain` [name]
        forM_ ["SurfaceWireFragment", "SurfaceFragmentProtection"] \name ->
            generatedTypes `shouldNotContain` [name]
        frontendContractsTypeScript
            `shouldSatisfy` Text.isInfixOf "export type SurfaceSubscription = { scope: SurfaceScope; scopeKey: string; fragments: ReadonlyArray<SurfaceFragmentKey> };"

    it "embeds the checked Surface topology directly in the unified registry" do
        registeredFrontendContractIR.contractSurfaces
            `shouldBe` registeredFrontendSurfaceContractIR.contractSurfaces

    it "uses the canonical field, wire, schema, and HTMX core inside an unregistered Surface fixture" do
        let fixture = reflectSurfaceSpec @SurfaceFixture.FrontendSurfaceFixture
        let scopeFields :: [Contract.FieldIR] = concatMap (.scopeFields) fixture.surfaceScopes
        let dtoSchemas :: [Contract.SchemaIR] = map (.surfaceDtoSchema) fixture.surfaceDtos
        let actionOptions :: [Contract.HtmxActionOptionIR] = concatMap (Contract.optionHtmxActionOptions . (.htmxActionOptions)) fixture.surfaceHtmxActions

        map (\field -> (field.fieldName, field.fieldWire)) scopeFields
            `shouldBe` [("venueId", Contract.WireUuidIR), ("weekOffset", Contract.WireIntIR)]
        map Contract.schemaNameAndMarker dtoSchemas
            `shouldBe` [("FixturePayload", "FixturePayload"), ("FixtureRelatedPayload", "FixtureRelatedPayload")]
        actionOptions `shouldContain` [Contract.HtmxActionMethodIR Contract.HtmxPostIR]

    it "declares exceptional browser projections in closed IR instead of root-name switches" do
        let projections =
                [ projection
                | global <- registeredFrontendContractIR.contractGlobals
                , Contract.GlobalProjectionIR projection <- global.globalPrimitives
                ]
        projections `shouldBe` [Contract.InteractionDomProjectionIR]

    it "uses one shared HTMX metadata model for generated request primitives" do
        let genericOptions =
                [ Contract.HtmxActionMethodIR Contract.HtmxPostIR
                , Contract.HtmxActionTriggerIR (Contract.HtmxTypedSyntaxIR "change" [])
                , Contract.HtmxActionIncludeIR (Contract.HtmxTypedSyntaxIR "#filters" [])
                , Contract.HtmxActionSyncIR (Contract.HtmxTypedSyntaxIR "closest form:queue" [])
                , Contract.HtmxActionIndicatorIR (Contract.HtmxTypedSyntaxIR "#spinner" [])
                , Contract.HtmxActionConfirmIR "Continue?"
                , Contract.HtmxActionSelectIR (Contract.HtmxTypedSyntaxIR "#fragment" [])
                , Contract.HtmxActionTargetIR (Contract.HtmxTypedSyntaxIR "#target" [])
                , Contract.HtmxActionSwapIR (Contract.HtmxTypedSyntaxIR "outerHTML" [])
                , Contract.HtmxActionPushUrlIR Contract.HtmxPushUrlFalseIR
                , Contract.HtmxActionCustomHtmxIR "custom-marker" "fixture escape hatch"
                ]
        let surfaceOptions =
                map SurfaceIR.HtmxOption genericOptions
        Contract.optionHtmxActionOptions surfaceOptions `shouldBe` genericOptions
        let metadata = Htmx.htmxActionMetadataFromOptions genericOptions
        metadata `shouldBe` Htmx.htmxActionMetadataFromSurfaceOptions surfaceOptions
        Htmx.htmxActionOptionAttrPairs metadata
            `shouldBe` [ ("hx-trigger", "change")
                       , ("hx-include", "#filters")
                       , ("hx-sync", "closest form:queue")
                       , ("hx-indicator", "#spinner")
                       , ("hx-confirm", "Continue?")
                       , ("hx-select", "#fragment")
                       , ("hx-target", "#target")
                       , ("hx-swap", "outerHTML")
                       , ("hx-push-url", "false")
                       ]

    it "derives nominal AppShell field bundles, names, metadata, and exact parsing from one declaration" do
        let authored =
                appShellActionFields @AppShell.SelectXeroTimesheetPreparationPeriodOverlay
                    (surfaceField @AppShell.PeriodKeyField "calendar:period")
                    noSurfaceFields
        surfaceFieldNameFrom @AppShell.PeriodKeyField authored `shouldBe` "periodKey"
        surfaceFieldValue @AppShell.PeriodKeyField authored `shouldBe` "calendar:period"
        (appShellActionFor authored).appShellActionName
            `shouldBe` "select-xero-timesheet-preparation-period-overlay"
        let parsed =
                parseAppShellActionParamPairs @AppShell.SelectXeroTimesheetPreparationPeriodOverlay
                    [("periodKey", Just "calendar:period")]
        fmap (surfaceFieldValue @AppShell.PeriodKeyField) parsed
            `shouldBe` Right "calendar:period"
        case parseAppShellActionParamPairs @AppShell.SelectXeroTimesheetPreparationPeriodOverlay [] of
            Left _  -> pure ()
            Right _ -> expectationFailure "missing required periodKey parsed successfully"
        case parseAppShellActionParamPairs @AppShell.SelectXeroTimesheetPreparationPeriodOverlay
            [("periodKey", Just "first"), ("periodKey", Just "second")] of
            Left _  -> pure ()
            Right _ -> expectationFailure "repeated scalar periodKey parsed successfully"
        case parseAppShellActionParamPairs @AppShell.ApproveXeroTimesheetPreparationPayItemsOverlay
            [("accountCode", Just ""), ("accountCode", Just "")] of
            Left _  -> pure ()
            Right _ -> expectationFailure "repeated empty optional accountCode parsed successfully"

    it "keeps migrated app-owned request values nominal and closed" do
        closedScalarLiterals @FeedbackTypeEnum `shouldBe` ["bug", "suggestion", "other"]
        closedScalarLiterals @StaffProfileSectionValue `shouldBe` ["profile", "preferences"]
        closedScalarLiterals @RosterStaffScopeValue `shouldBe` ["group", "all"]
        closedScalarLiterals @LeaveSectionValue `shouldBe` ["pending", "approved", "denied", "archive"]
        closedScalarLiterals @ShiftTypeColourKeyEnum
            `shouldBe` ["no_colour", "palette_1", "palette_2", "palette_3", "palette_4", "palette_5", "palette_6", "palette_7", "palette_8", "palette_9", "palette_10"]

        let parsedFeedback =
                parseAppShellActionParamPairs @AppShell.SubmitFeedback
                    [ ("feedbackType", Just "suggestion")
                    , ("content", Just "Typed feedback")
                    ]
        fmap (surfaceFieldValue @AppShell.FeedbackTypeField) parsedFeedback
            `shouldBe` Right Suggestion
        case parseAppShellActionParamPairs @AppShell.SubmitFeedback
            [ ("feedbackType", Just "billing_secret")
            , ("content", Just "Not a declared type")
            ] of
            Left _  -> pure ()
            Right _ -> expectationFailure "undeclared feedback type parsed successfully"

    it "reflects generated AppShell action manifests and runtime attrs" do
        let appShellActions =
                [ action
                | global <- registeredFrontendContractIR.contractGlobals
                , Contract.GlobalAppShellActionIR action <- global.globalPrimitives
                ]
        let partialNavigateAction = appShellActionByMarker @AppShell.PartialNavigate
        let openFeedbackDialogAction = appShellActionByMarker @AppShell.OpenFeedbackDialog
        fmap (.appShellActionName) (find ((== "partial-navigate") . (.appShellActionName)) appShellActions) `shouldBe` Just "partial-navigate"
        partialNavigateAction.appShellActionOptions
            `shouldBe` [ Contract.HtmxActionMethodIR Contract.HtmxGetIR
                       , Contract.HtmxActionCustomHtmxIR "partial-navigation-htmx-attrs" "partial navigation supplies route-specific target, swap, select, push-url, and sync attrs"
                       ]
        openFeedbackDialogAction.appShellActionOptions
            `shouldBe` [ Contract.HtmxActionMethodIR Contract.HtmxGetIR
                       , Contract.HtmxActionTargetIR (Contract.HtmxTypedSyntaxIR "#dialog-overlay-mount" ["dialog-overlay-mount"])
                       , Contract.HtmxActionSwapIR (Contract.HtmxTypedSyntaxIR "innerHTML" [])
                       , Contract.HtmxActionPushUrlIR Contract.HtmxPushUrlFalseIR
                       ]
        let partialNavigateAttrs = appShellActionHtmxAttrPairs partialNavigateAction AppShellActionRoute
                { appShellActionRouteUrl = "/next"
                , appShellActionRouteFields = []
                , appShellActionRouteCustomHtmx = []
                , appShellActionRouteStandardUrl = Nothing
                , appShellActionRouteExtraAttrs = []
                }
        partialNavigateAttrs `shouldContain` [("hx-get", "/next")]
        partialNavigateAttrs `shouldNotContain` [("data-bepis-app-shell-action", "partial-navigate")]
        frontendContractsTypeScript `shouldNotSatisfy` Text.isInfixOf "AppShellActionManifest"
        frontendContractsTypeScript `shouldNotSatisfy` Text.isInfixOf "partialNavigateAppShellActionManifest"
        frontendContractsTypeScript `shouldNotSatisfy` Text.isInfixOf "openFeedbackDialogAppShellActionManifest"

    it "reflects generated app shell action manifests" do
        let appShellActions =
                [ action
                | global <- registeredFrontendContractIR.contractGlobals
                , Contract.GlobalAppShellActionIR action <- global.globalPrimitives
                ]
        let openFeedbackAction = find ((== "open-feedback-dialog") . (.appShellActionName)) appShellActions
        fmap (.appShellActionFields) openFeedbackAction `shouldBe` Just []
        fmap (.appShellActionOptions) openFeedbackAction
            `shouldBe` Just
                [ Contract.HtmxActionMethodIR Contract.HtmxGetIR
                , Contract.HtmxActionTargetIR (Contract.HtmxTypedSyntaxIR "#dialog-overlay-mount" ["dialog-overlay-mount"])
                , Contract.HtmxActionSwapIR (Contract.HtmxTypedSyntaxIR "innerHTML" [])
                , Contract.HtmxActionPushUrlIR Contract.HtmxPushUrlFalseIR
                ]
        let submitFeedbackAction = find ((== "submit-feedback") . (.appShellActionName)) appShellActions
        fmap (fmap (.fieldName) . (.appShellActionFields)) submitFeedbackAction `shouldBe` Just
            [ "feedbackType"
            , "content"
            , "feedbackViewportWidth"
            , "feedbackViewportHeight"
            , "feedbackDevicePixelRatio"
            , "feedbackDisplayMode"
            ]
        fmap (.appShellActionOptions) submitFeedbackAction
            `shouldBe` Just
                [ Contract.HtmxActionMethodIR Contract.HtmxPostIR
                , Contract.HtmxActionTargetIR (Contract.HtmxTypedSyntaxIR "#dialog-overlay-mount" ["dialog-overlay-mount"])
                , Contract.HtmxActionSwapIR (Contract.HtmxTypedSyntaxIR "innerHTML" [])
                , Contract.HtmxActionPushUrlIR Contract.HtmxPushUrlFalseIR
                ]

    it "exposes consistent Profile and Staff surface profile action field sets" do
        let surfaceActions surfaceName actionName =
                [ action.htmxActionName
                | surface <- registeredFrontendContractIR.contractSurfaces
                , surface.surfaceName == surfaceName
                , action <- surface.surfaceHtmxActions
                , action.htmxActionName == actionName
                ]
        let actionFields surfaceName actionName =
                [ action.htmxActionFields
                | surface <- registeredFrontendContractIR.contractSurfaces
                , surface.surfaceName == surfaceName
                , action <- surface.surfaceHtmxActions
                , action.htmxActionName == actionName
                ]
        surfaceActions "staff" "update-staff-profile" `shouldBe` ["update-staff-profile"]
        actionFields "profile" "update-profile-details" `shouldBe` actionFields "staff" "update-staff-profile"
        actionFields "profile" "update-profile-shift-preferences" `shouldBe` actionFields "staff" "update-staff-shift-preferences"
        frontendContractsTypeScript `shouldNotSatisfy` Text.isInfixOf "staffSurfaceManifest"

    it "resolves canonical Haskell value accessors from registered FrontendContract IR" do
        lookupDomIdValue @Overlay.DialogOverlayMount `shouldBe` Right canonicalOverlayDom.overlayDialogMountId
        lookupDomIdValue @Overlay.ToastOverlayMount `shouldBe` Right canonicalOverlayDom.overlayToastMountId
        lookupEventNameValue @Overlay.DialogDismissed `shouldBe` Right canonicalOverlayDom.overlayDialogDismissedEventName
        lookupDomAttrValue @Overlay.DialogMount `shouldBe` Right canonicalOverlayDom.overlayDialogMountAttribute
        lookupDomIdValue @TimePicker.TimePickerModal `shouldBe` Right canonicalTimePickerDom.timePickerModalId
        lookupDomAttrValue @TimePicker.TimePickerField `shouldBe` Right canonicalTimePickerDom.timePickerFieldAttribute
        lookupDomAttrValue @TimePicker.TimePickerOption `shouldBe` Right canonicalTimePickerDom.timePickerOptionAttribute
        lookupDomAttrValue @OrderedRange.OrderedRangeRoot `shouldBe` Right canonicalOrderedRangeDom.orderedRangeRootAttribute
        lookupDomAttrValue @OrderedRange.OrderedRangeAvailability `shouldBe` Right canonicalOrderedRangeDom.orderedRangeAvailabilityAttribute
        lookupDomAttrValue @HorizontalScroll.HorizontalScrollSnap `shouldBe` Right canonicalHorizontalScrollDom.horizontalScrollSnapAttribute
        lookupDomAttrValue @HorizontalScroll.HorizontalScrollDrag `shouldBe` Right canonicalHorizontalScrollDom.horizontalScrollDragAttribute
        lookupDomAttrValue @Passkey.PasskeyLogin `shouldBe` Right canonicalPasskeyDom.passkeyLoginAttribute
        lookupDomAttrValue @Passkey.PasskeyRegistration `shouldBe` Right canonicalPasskeyDom.passkeyRegistrationAttribute
        lookupDomAttrValue @Passkey.PasskeySetupPrompt `shouldBe` Right canonicalPasskeyDom.passkeySetupPromptAttribute
        lookupDomAttrValue @Passkey.PasskeyFlowConfig `shouldBe` Right canonicalPasskeyDom.passkeyFlowConfigAttribute
        lookupEnumLiteralValue @Passkey.PasskeySetupPromptMode @Passkey.FirstPasskey `shouldBe` Right "first-passkey"
        lookupEnumLiteralValue @Passkey.PasskeySetupPromptMode @Passkey.AdditionalDevice `shouldBe` Right "additional-device"
        lookupConstantValue @Passkey.PasskeyFirstPasskeyMode `shouldBe` Right "first-passkey"
        lookupConstantValue @Passkey.PasskeyAdditionalDeviceMode `shouldBe` Right "additional-device"
        lookupDomAttrValue @PwaInstall.PwaInstallPage `shouldBe` Right canonicalPwaInstallDom.pwaInstallPageAttribute
        lookupDomAttrValue @PwaInstall.PwaInstallResultState `shouldBe` Right canonicalPwaInstallDom.pwaInstallResultStateAttribute
        lookupEnumLiteralValue @PwaInstall.PwaInstallState @PwaInstall.Accepted `shouldBe` Right "accepted"
        lookupDomAttrValue @XeroCandidateFilter.XeroCandidateFilterRoot `shouldBe` Right canonicalXeroCandidateFilterDom.xeroCandidateFilterRootAttribute
        lookupDomAttrValue @XeroCandidateFilter.XeroCandidateFilterConfig `shouldBe` Right canonicalXeroCandidateFilterDom.xeroCandidateFilterConfigAttribute
        lookupConstantValue @OrderedRange.OrderedRangeClampOtherEndpoint `shouldBe` Right "clamp-other-endpoint"
        lookupEventNameValue @App.IntentSubmit `shouldBe` Right interactionIntentSubmitHtmxTrigger
        domIdValue @Overlay.DialogOverlayMount `shouldBe` canonicalOverlayDom.overlayDialogMountId
        domAttrValue @Overlay.ToastMount `shouldBe` canonicalOverlayDom.overlayToastMountAttribute
        domIdValue @TimePicker.TimePickerModal `shouldBe` canonicalTimePickerDom.timePickerModalId
        domAttrValue @TimePicker.TimePickerValue `shouldBe` canonicalTimePickerDom.timePickerValueAttribute
        domAttrValue @OrderedRange.OrderedRangeStart `shouldBe` canonicalOrderedRangeDom.orderedRangeStartAttribute
        constantValue @OrderedRange.OrderedRangeStartPositionProperty `shouldBe` canonicalOrderedRangeDom.orderedRangeStartPositionCssProperty
        eventNameValue @App.IntentSubmit `shouldBe` canonicalAppEvents.appInteractionIntentSubmitEventName

    it "returns deterministic diagnostics for missing Haskell value accessors" do
        lookupDomIdValue @Text `shouldBe` Left "No FrontendContract DomId declaration for marker Text"
        lookupEventNameValue @Text `shouldBe` Left "No FrontendContract Event declaration for marker Text"
        lookupEnumLiteralValue @Text @Text `shouldBe` Left "No FrontendContract enum case Text for enum marker Text"

    it "validates records, refs, arrays, nullable fields, and tagged unions through the IR JSON interpreter" do
        let scope = Live.SurfaceScope "timesheets" (Aeson.object ["venueId" Aeson..= ("11111111-1111-1111-1111-111111111111" :: Text), "weekOffset" Aeson..= (4 :: Int)])
        let fragmentKey = Live.SurfaceFragmentKey "timesheets" "timesheet-day-section" (Aeson.object ["dayOffset" Aeson..= (2 :: Int)])
        let subscription = Live.SurfaceSubscription scope "timesheets:11111111-1111-1111-1111-111111111111:4" [fragmentKey]
        let command = Live.Subscribe subscription "client-1" (Just 9)
        let message = Live.Invalidate scope "timesheets:11111111-1111-1111-1111-111111111111:4" 10 [fragmentKey] (Just "client-2")

        AesonTypes.parseEither (validateContractMarkerValue @LiveContract.SurfaceSubscription) (Aeson.toJSON subscription) `shouldSatisfy` isRight
        AesonTypes.parseEither (validateContractMarkerValue @LiveContract.LiveUpdateCommand) (Aeson.toJSON command) `shouldSatisfy` isRight
        AesonTypes.parseEither (validateContractMarkerValue @LiveContract.LiveUpdateMessage) (Aeson.toJSON message) `shouldSatisfy` isRight
        Aeson.eitherDecode (Aeson.encode command) `shouldBe` Right command
        Aeson.eitherDecode (Aeson.encode message) `shouldBe` Right message

    it "rejects invalid surface scopes, fragments, enum values, and union discriminators through the IR JSON interpreter" do
        let badScope = Aeson.object ["surface" Aeson..= ("missing" :: Text), "scope" Aeson..= Aeson.object []]
        let badFragment = Aeson.object ["surface" Aeson..= ("timesheets" :: Text), "kind" Aeson..= ("missing" :: Text), "params" Aeson..= Aeson.object []]
        let badCommand = Aeson.object ["type" Aeson..= ("missing" :: Text)]

        AesonTypes.parseEither validateSurfaceScopeValue badScope `shouldSatisfy` isLeft
        AesonTypes.parseEither validateSurfaceFragmentKeyValue badFragment `shouldSatisfy` isLeft
        AesonTypes.parseEither (validateContractMarkerValue @LiveContract.LiveUpdateCommand) badCommand `shouldSatisfy` isLeft

    it "covers Wire.Json field presence, nested refs, arrays, enums, and tagged unions" do
        let contract = wireJsonSpecContract
        let goodNested = Aeson.object
                [ "name" Aeson..= ("Ada" :: Text)
                , "count" Aeson..= (3 :: Int)
                , "active" Aeson..= True
                , "uuid" Aeson..= ("not-a-uuid-but-contract-string" :: Text)
                , "day" Aeson..= ("not-a-day-but-contract-string" :: Text)
                , "tags" Aeson..= (["alpha", "beta"] :: [Text])
                , "maybeText" Aeson..= Aeson.Null
                , "nullableText" Aeson..= Aeson.Null
                , "status" Aeson..= ("ready" :: Text)
                , "literal" Aeson..= ("special-case" :: Text)
                ]
        let goodRecord = Aeson.object
                [ "nested" Aeson..= goodNested
                , "items" Aeson..= [goodNested]
                ]
        AesonTypes.parseEither (validateContractMarkerValueWith @SpecRecord contract) goodRecord `shouldSatisfy` isRight
        AesonTypes.parseEither (validateContractMarkerValueWith @SpecUnion contract) (Aeson.object ["kind" Aeson..= ("one" :: Text), "value" Aeson..= goodNested]) `shouldSatisfy` isRight
        AesonTypes.parseEither (validateContractMarkerValueWith @SpecUnion contract) (Aeson.object ["kind" Aeson..= ("two" :: Text), "note" Aeson..= ("ok" :: Text)]) `shouldSatisfy` isRight
        AesonTypes.parseEither (validateWireValue "uuid" Contract.WireUuidIR) (Aeson.String "not-a-uuid-but-contract-string") `shouldSatisfy` isRight
        AesonTypes.parseEither (validateWireValue "day" Contract.WireDayIR) (Aeson.String "not-a-day-but-contract-string") `shouldSatisfy` isRight

        AesonTypes.parseEither (validateContractMarkerValueWith @SpecNested contract) (addJsonField "extra" (Aeson.Bool True) goodNested) `shouldSatisfy` isLeft
        AesonTypes.parseEither (validateContractMarkerValueWith @SpecNested contract) (removeJsonField "name" goodNested) `shouldSatisfy` isLeft
        AesonTypes.parseEither (validateContractMarkerValueWith @SpecNested contract) (removeJsonField "maybeText" goodNested) `shouldSatisfy` isRight
        AesonTypes.parseEither (validateContractMarkerValueWith @SpecNested contract) (removeJsonField "nullableText" goodNested) `shouldSatisfy` isLeft
        AesonTypes.parseEither (validateContractMarkerValueWith @SpecNested contract) (replaceJsonField "name" (Aeson.Number 1) goodNested) `shouldSatisfy` isLeft
        AesonTypes.parseEither (validateContractMarkerValueWith @SpecNested contract) (replaceJsonField "count" (Aeson.Number 1.5) goodNested) `shouldSatisfy` isLeft
        AesonTypes.parseEither (validateContractMarkerValueWith @SpecNested contract) (replaceJsonField "tags" (Aeson.String "alpha") goodNested) `shouldSatisfy` isLeft
        AesonTypes.parseEither (validateContractMarkerValueWith @SpecNested contract) (replaceJsonField "status" (Aeson.String "missing") goodNested) `shouldSatisfy` isLeft
        AesonTypes.parseEither (validateContractMarkerValueWith @SpecNested contract) (replaceJsonField "literal" (Aeson.String "case") goodNested) `shouldSatisfy` isLeft
        AesonTypes.parseEither (validateContractMarkerValueWith @SpecRecord contract) (replaceJsonField "nested" (Aeson.object []) goodRecord) `shouldSatisfy` isLeft
        AesonTypes.parseEither (validateContractMarkerValueWith @SpecUnion contract) (Aeson.object ["kind" Aeson..= ("missing" :: Text)]) `shouldSatisfy` isLeft
        AesonTypes.parseEither (validateContractMarkerValueWith @SpecUnion contract) (Aeson.object ["kind" Aeson..= ("one" :: Text), "value" Aeson..= goodNested, "extra" Aeson..= True]) `shouldSatisfy` isLeft

    it "validates semantic scope and fragment-key wire constructors without executable descriptors" do
        let scope = Aeson.object ["surface" Aeson..= ("timesheets" :: Text), "scope" Aeson..= Aeson.object ["venueId" Aeson..= ("11111111-1111-1111-1111-111111111111" :: Text), "weekOffset" Aeson..= (0 :: Int)]]
        let key = Aeson.object ["surface" Aeson..= ("timesheets" :: Text), "kind" Aeson..= ("timesheet-day-section" :: Text), "params" Aeson..= Aeson.object ["dayOffset" Aeson..= (0 :: Int)]]
        let descriptor = addJsonField "url" (Aeson.String "/fragment") key
        AesonTypes.parseEither (validateWireValue "scope" Contract.WireSurfaceScopeIR) scope `shouldSatisfy` isRight
        AesonTypes.parseEither (validateWireValue "key" Contract.WireSurfaceFragmentKeyIR) key `shouldSatisfy` isRight
        AesonTypes.parseEither (validateWireValue "scope" Contract.WireSurfaceScopeIR) (addJsonField "extra" (Aeson.Bool True) scope) `shouldSatisfy` isLeft
        AesonTypes.parseEither (validateWireValue "key" Contract.WireSurfaceFragmentKeyIR) (replaceJsonField "kind" (Aeson.String "missing") key) `shouldSatisfy` isLeft
        AesonTypes.parseEither (validateWireValue "key" Contract.WireSurfaceFragmentKeyIR) descriptor `shouldSatisfy` isLeft

    it "generates codecs only for their declared browser reachability" do
        frontendContractsTypeScript `shouldSatisfy` Text.isInfixOf "export function parseLiveUpdateMessage"
        frontendContractsTypeScript `shouldNotSatisfy` Text.isInfixOf "export function encodeLiveUpdateMessage"
        frontendContractsTypeScript `shouldSatisfy` Text.isInfixOf "export function encodeLiveUpdateCommand"
        frontendContractsTypeScript `shouldNotSatisfy` Text.isInfixOf "export function parseLiveUpdateCommand"
        frontendContractsTypeScript `shouldSatisfy` Text.isInfixOf "export function isRosterStaffPanelSortRow"
        frontendContractsTypeScript `shouldSatisfy` Text.isInfixOf "export function parseRosterStaffPanelSortRow"
        frontendContractsTypeScript `shouldNotSatisfy` Text.isInfixOf "export function encodeRosterStaffPanelSortRow"
        frontendContractsTypeScript `shouldSatisfy` Text.isInfixOf "export function parseFrontendSurfaceMountConfig"
        frontendContractsTypeScript `shouldNotSatisfy` Text.isInfixOf "export function encodeFrontendSurfaceMountConfig"

    it "renders separate minimal fragment and interaction runtime registries" do
        frontendContractsTypeScript `shouldSatisfy` Text.isInfixOf "export const FrontendSurfaceFragmentRegistry"
        frontendContractsTypeScript `shouldSatisfy` Text.isInfixOf "export const FrontendSurfaceInteractionRegistry"
        frontendContractsTypeScript `shouldNotSatisfy` Text.isInfixOf "export const FrontendSurfaceRegistry"
        frontendContractsTypeScript `shouldNotSatisfy` Text.isInfixOf "InteractionStaticSchemas"
        frontendContractsTypeScript `shouldNotSatisfy` Text.isInfixOf "htmxActions"
        frontendContractsTypeScript `shouldNotSatisfy` Text.isInfixOf "containedSurfaces"
        frontendContractsTypeScript `shouldNotSatisfy` Text.isInfixOf "FrontendSurfaceActionManifest"
        frontendContractsTypeScript `shouldNotSatisfy` Text.isInfixOf "timesheetsSurfaceManifest"

generatedContractTypeNames :: Text -> [Text]
generatedContractTypeNames source =
    [ Text.takeWhile (/= ' ') rest
    | line <- Text.lines source
    , Just rest <- [Text.stripPrefix "export type " line]
    ]

wireJsonSpecContract :: Contract.FrontendContractIR
wireJsonSpecContract =
    Contract.FrontendContractIR
        { contractGlobals =
            [ Contract.GlobalIR
                { globalMarker = "SpecGlobal"
                , globalName = "spec-global"
                , globalPrimitives = fmap (Contract.GlobalSchemaIR Contract.BrowserBidirectionalIR)
                    [ Contract.EnumIR "SpecStatus" "SpecStatus" ["ready", "paused"]
                    , Contract.LiteralEnumIR "SpecLiteral" "SpecLiteral" [("SpecialCase", "special-case")]
                    , Contract.RecordIR "SpecNested" "SpecNested"
                        [ field "Name" "name" Contract.WireTextIR Contract.RequiredField
                        , field "Count" "count" Contract.WireIntIR Contract.RequiredField
                        , field "Active" "active" Contract.WireBoolIR Contract.RequiredField
                        , field "Uuid" "uuid" Contract.WireUuidIR Contract.RequiredField
                        , field "Day" "day" Contract.WireDayIR Contract.RequiredField
                        , field "Tags" "tags" (Contract.WireListIR Contract.WireTextIR) Contract.RequiredField
                        , field "MaybeText" "maybeText" (Contract.WireOptionalIR Contract.WireTextIR) Contract.OptionalFieldPresence
                        , field "NullableText" "nullableText" (Contract.WireNullableIR Contract.WireTextIR) Contract.NullableFieldPresence
                        , field "Status" "status" (Contract.WireRefIR "SpecStatus") Contract.RequiredField
                        , field "Literal" "literal" (Contract.WireRefIR "SpecLiteral") Contract.RequiredField
                        ]
                    , Contract.RecordIR "SpecRecord" "SpecRecord"
                        [ field "Nested" "nested" (Contract.WireRefIR "SpecNested") Contract.RequiredField
                        , field "Items" "items" (Contract.WireListIR (Contract.WireRefIR "SpecNested")) Contract.RequiredField
                        ]
                    , Contract.TaggedUnionIR "SpecUnion" "SpecUnion" "kind"
                        [ Contract.UnionCaseIR "One" "one" [field "Value" "value" (Contract.WireRefIR "SpecNested") Contract.RequiredField]
                        , Contract.UnionCaseIR "Two" "two" [field "Note" "note" Contract.WireTextIR Contract.RequiredField]
                        ]
                    ]
                }
            ]
        , contractSurfaces = []
        }
    where
        field marker name wire presence =
            Contract.FieldIR
                { fieldMarker = marker
                , fieldName = name
                , fieldWire = wire
                , fieldPresence = presence
                }

addJsonField :: Text -> Aeson.Value -> Aeson.Value -> Aeson.Value
addJsonField name value = \case
    Aeson.Object object -> Aeson.Object (KeyMap.insert (AesonKey.fromText name) value object)
    other               -> other

removeJsonField :: Text -> Aeson.Value -> Aeson.Value
removeJsonField name = \case
    Aeson.Object object -> Aeson.Object (KeyMap.delete (AesonKey.fromText name) object)
    other               -> other

replaceJsonField :: Text -> Aeson.Value -> Aeson.Value -> Aeson.Value
replaceJsonField name value = \case
    Aeson.Object object -> Aeson.Object (KeyMap.insert (AesonKey.fromText name) value object)
    other               -> other
