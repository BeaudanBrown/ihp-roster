{-# LANGUAGE DataKinds        #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators    #-}

module Test.FrontendSurfaceDslSpec
    ( tests
    ) where

import Application.Helper.FrontendContract.Core (schemaNameAndMarker)
import Application.Helper.FrontendContract.IR (FrontendContractIR (..))
import Application.Helper.FrontendContract.Registry (registeredFrontendContractIR)
import Application.Helper.FrontendContract.Surface.CompleteSetSort (surfaceCompleteSetSortControlAttrs,
                                                                    surfaceCompleteSetSortRootAttrs,
                                                                    surfaceCompleteSetSortRowAttrs)
import Application.Helper.FrontendContract.Surface.ContractIR
import Application.Helper.FrontendContract.Surface.Contracts (registeredFrontendSurfaceContractIR)
import Application.Helper.FrontendContract.Surface.DSL
import Application.Helper.FrontendContract.Surface.Dto (surfaceBrowserDtoRoleAttrs)
import qualified Application.Helper.FrontendContract.Surface.Interaction as SurfaceInteraction
import qualified Application.Helper.FrontendContract.Surface.LinkedHighlight as SurfaceLinkedHighlight
import Application.Helper.FrontendContract.Surface.Live (frontendSurfaceFragmentKey)
import Application.Helper.FrontendContract.Surface.Reflect
import Application.Helper.FrontendContract.Surface.Registry (RegisteredFrontendSurfaces)
import Application.Helper.FrontendContract.Surface.Request
import Application.Helper.FrontendContract.Surface.Request.Runtime
import Application.Helper.FrontendContract.Surface.Resource
import qualified Application.Helper.FrontendContract.Surface.Roster as RosterSurface
import Application.Helper.FrontendContract.Surface.Roster.Chrome
import Application.Helper.FrontendContract.Surface.Roster.ImageExport
import Application.Helper.FrontendContract.Surface.Roster.WeekOverview
import Application.Helper.FrontendContract.Surface.Runtime
import Application.Helper.FrontendContract.Surface.TabSet (surfaceTabSetAttrs)
import qualified Application.Helper.FrontendContract.Surface.Timesheets as TimesheetsSurface
import qualified Application.Helper.FrontendContract.Surface.Timesheets.Resource as TimesheetsResource
import Application.Helper.FrontendContract.Surface.Values
import Application.Helper.FrontendContract.TypeScript (renderFrontendContractTypeScript)
import qualified Data.Aeson as Aeson
import Data.Proxy (Proxy (..))
import qualified Data.Text as Text
import qualified Data.Text.Encoding as TextEncoding
import qualified Data.Time.Calendar as Calendar
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
data NestedOptionalTestField
data RequestContract
data RequestContractScope
data RequestAction
data RequestIntent
data RequestCount
data RequestFilterId
data RequestTags
data RequestNote
data BrowserFixture
data BrowserFixtureScope
data BrowserFixturePayload
data BrowserFixturePayloadLabel
data BrowserFixtureTypeOnlyPayload
data BrowserFixtureGuardPayload
data BrowserFixtureOutboundPayload
data BrowserFixtureBidirectionalPayload
data BrowserFixtureSortRow
data BrowserFixtureSortLabel
data BrowserFixtureSortCount
data BrowserFixtureSortRowKey
data BrowserFixtureSort
data BrowserFixtureSortRootRole
data BrowserFixtureSortRowRole
data BrowserFixtureSortControlRole
data LabelSortKey
data CountSortKey
data BrowserFixtureTabs
data BrowserFixtureTabRole
data StaffTabKey
data SettingsTabKey
data StaffShiftsHighlight
data StaffHighlightSourceRole
data StaffHighlightMemberRole
data StaffHighlightPinRole
data StaffHighlightOrderState
data BrowserFixtureModeState
data Calm
data Busy
data BrowserAttributeCollision
data BrowserAttributeCollisionScope
data SharedHighlightAttributeRole
data SharedHighlightAttributeState
data EmptyBrowserClosedState
data EmptyBrowserClosedStateScope
data EmptyModeState
data DuplicateBrowserClosedState
data DuplicateBrowserClosedStateScope
data DuplicateModeState
data DuplicateModeValue

type BrowserFixtureSurface =
    Surface BrowserFixture
        '[ Scope BrowserFixtureScope '[] '[ 'NoAuth ]
         , BrowserInboundDto BrowserFixturePayload
            '[ Field BrowserFixturePayloadLabel 'WireText ]
         , BrowserTypeDto BrowserFixtureTypeOnlyPayload
            '[ Field BrowserFixturePayloadLabel 'WireText ]
         , BrowserGuardDto BrowserFixtureGuardPayload
            '[ Field BrowserFixturePayloadLabel 'WireText ]
         , BrowserOutboundDto BrowserFixtureOutboundPayload
            '[ Field BrowserFixturePayloadLabel 'WireText ]
         , BrowserBidirectionalDto BrowserFixtureBidirectionalPayload
            '[ Field BrowserFixturePayloadLabel 'WireText ]
         , BrowserInboundDto BrowserFixtureSortRow
            '[ Field BrowserFixtureSortLabel 'WireText
             , Field BrowserFixtureSortCount 'WireInt
             , Field BrowserFixtureSortRowKey 'WireText
             ]
         , BrowserRole BrowserFixtureSortRootRole
         , BrowserRole BrowserFixtureSortRowRole
         , BrowserRole BrowserFixtureSortControlRole
         , CompleteSetSort BrowserFixtureSort BrowserFixtureSortRootRole BrowserFixtureSortRowRole BrowserFixtureSortControlRole BrowserFixtureSortRow
            '[ SortKey LabelSortKey
                '[ SortComparator BrowserFixtureSortLabel 'SortText 'FollowSortDirection
                 , SortComparator BrowserFixtureSortRowKey 'SortOpaque 'AlwaysAscending
                 ]
             , SortKey CountSortKey
                '[ SortComparator BrowserFixtureSortCount 'SortInteger 'FollowSortDirection
                 , SortComparator BrowserFixtureSortLabel 'SortText 'AlwaysAscending
                 , SortComparator BrowserFixtureSortRowKey 'SortOpaque 'AlwaysAscending
                 ]
             ]
            LabelSortKey
            'SortAscending
         , BrowserRole BrowserFixtureTabRole
         , TabSet BrowserFixtureTabs BrowserFixtureTabRole '[ StaffTabKey, SettingsTabKey ] StaffTabKey
         , BrowserRole StaffHighlightSourceRole
         , BrowserRole StaffHighlightMemberRole
         , BrowserRole StaffHighlightPinRole
         , BrowserState StaffHighlightOrderState
         , BrowserClosedState BrowserFixtureModeState '[ Calm, Busy ]
         , LinkedHighlight StaffShiftsHighlight StaffHighlightSourceRole StaffHighlightMemberRole
            '[ 'ActivateOnHover
             , 'ActivateOnFocus
             , 'ActivateOnKeyboard
             , 'ActivateWithPin StaffHighlightPinRole
             ]
            '[ 'HighlightMatchingSource
             , 'HighlightMatchingMember
             , 'HighlightOrderedMemberBounds StaffHighlightOrderState
             ]
         ]

type BrowserAttributeCollisionSurface =
    Surface BrowserAttributeCollision
        '[ Scope BrowserAttributeCollisionScope '[] '[ 'NoAuth ]
         , BrowserRole SharedHighlightAttributeRole
         , BrowserState SharedHighlightAttributeState
         ]

type EmptyBrowserClosedStateSurface =
    Surface EmptyBrowserClosedState
        '[ Scope EmptyBrowserClosedStateScope '[] '[ 'NoAuth ]
         , BrowserClosedState EmptyModeState '[]
         ]

type DuplicateBrowserClosedStateSurface =
    Surface DuplicateBrowserClosedState
        '[ Scope DuplicateBrowserClosedStateScope '[] '[ 'NoAuth ]
         , BrowserClosedState DuplicateModeState '[ DuplicateModeValue, DuplicateModeValue ]
         ]

type RequestContractSurface =
    Surface RequestContract
        '[ Scope RequestContractScope '[] '[ 'NoAuth ]
         , Action RequestAction
            '[ Field RequestCount 'WireInt
             , OptionalField RequestFilterId 'WireUUID
             , OptionalField RequestTags ('WireList 'WireText)
             , NullableField RequestNote 'WireText
             ]
            '[]
         , Intent RequestIntent
            '[ Field RequestCount 'WireInt
             , OptionalField RequestFilterId 'WireUUID
             , OptionalField RequestTags ('WireList 'WireText)
             , NullableField RequestNote 'WireText
             ]
            '[]
         ]

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

browserFixtureTypeScript :: Text
browserFixtureTypeScript =
    either error id (renderFrontendContractTypeScript fixtureContract)
  where
    fixtureContract = FrontendContractIR
        { contractGlobals = registeredFrontendContractIR.contractGlobals
        , contractSurfaces = [reflectSurfaceSpec @BrowserFixtureSurface]
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
        surfaceActionNameValue @TimesheetsSurface.TimesheetsSurface @TimesheetsSurface.NavigateTimesheetWeek `shouldBe` "navigate-timesheet-week"
        (surfaceResourceValue @TimesheetsSurface.TimesheetsSurface @TimesheetsSurface.TimesheetDay).resourceName `shouldBe` "timesheet-day"
        (surfaceResourceValue @RosterSurface.RosterSurface @RosterSurface.RosterTemplateLibrary).resourceName `shouldBe` "roster-template-library"
        (surfaceResourceValue @RosterSurface.RosterSurface @RosterSurface.RosterTemplate).resourceName `shouldBe` "roster-template"
        (surfaceResourceValue @RosterSurface.RosterSurface @RosterSurface.RosterTemplateDraft).resourceName `shouldBe` "roster-template-draft"
        (surfaceDomTokenValue @TimesheetsSurface.TimesheetsSurface @TimesheetsSurface.TimesheetWeekShell) `shouldBe` "timesheet-week-shell"
        (surfaceSourceRefValue @RosterSurface.RosterDayTimelineSurface @SurfaceInteraction.DragSourceRef).sourceRefName `shouldBe` "drag-source"
        (surfaceDropzoneRefValue @RosterSurface.RosterDayTimelineSurface @SurfaceInteraction.DragDropzoneRef).dropzoneRefName `shouldBe` "drag-dropzone"
        let intentFields =
                surfaceField @SurfaceFixture.SourceItemKey "source"
                    &: surfaceField @SurfaceFixture.TargetDropzoneKey "target"
                    &: noSurfaceFields
                :: SurfaceFields (SurfaceIntentFieldSpecs SurfaceFixture.FrontendSurfaceFixture SurfaceFixture.MoveCard)
        surfaceFieldNameFrom @SurfaceFixture.SourceItemKey intentFields `shouldBe` "sourceItemKey"

    it "reflects Surface-owned browser roles, state, and closed linked-highlight semantics" do
        let surface = reflectSurfaceSpec @BrowserFixtureSurface
        map (\role -> (role.browserAttributeName, role.browserAttributeDomAttribute)) surface.surfaceBrowserRoles
            `shouldBe` [ ("browser-fixture-sort-root", "data-bepis-browser-fixture-browser-fixture-sort-root")
                       , ("browser-fixture-sort-row", "data-bepis-browser-fixture-browser-fixture-sort-row")
                       , ("browser-fixture-sort-control", "data-bepis-browser-fixture-browser-fixture-sort-control")
                       , ("browser-fixture-tab", "data-bepis-browser-fixture-browser-fixture-tab")
                       , ("staff-highlight-source", "data-bepis-browser-fixture-staff-highlight-source")
                       , ("staff-highlight-member", "data-bepis-browser-fixture-staff-highlight-member")
                       , ("staff-highlight-pin", "data-bepis-browser-fixture-staff-highlight-pin")
                       ]
        map (\state -> (state.browserAttributeName, state.browserAttributeDomAttribute)) surface.surfaceBrowserStates
            `shouldBe`
                [ ("staff-highlight-order", "data-bepis-browser-fixture-staff-highlight-order")
                , ("browser-fixture-mode", "data-bepis-browser-fixture-browser-fixture-mode")
                ]
        map (\state -> (state.browserClosedStateAttribute.browserAttributeName, state.browserClosedStateValues)) surface.surfaceBrowserClosedStates
            `shouldBe` [("browser-fixture-mode", ["calm", "busy"])]
        let highlight = surfaceLinkedHighlightValue @BrowserFixtureSurface @StaffShiftsHighlight
        highlight.linkedHighlightName `shouldBe` "staff-shifts-highlight"
        highlight.linkedHighlightSourceRole.browserAttributeDomAttribute
            `shouldBe` "data-bepis-browser-fixture-staff-highlight-source"
        highlight.linkedHighlightMemberRole.browserAttributeDomAttribute
            `shouldBe` "data-bepis-browser-fixture-staff-highlight-member"
        map linkedHighlightActivationName highlight.linkedHighlightActivations
            `shouldBe` ["hover", "focus", "keyboard", "pin"]
        map linkedHighlightEffectName highlight.linkedHighlightEffects
            `shouldBe` ["matching-source", "matching-member", "ordered-member-bounds"]
        surfaceBrowserRoleValue @BrowserFixtureSurface @StaffHighlightPinRole
            `shouldBe` BrowserAttributeIR
                { browserAttributeMarker = "StaffHighlightPinRole"
                , browserAttributeName = "staff-highlight-pin"
                , browserAttributeDomAttribute = "data-bepis-browser-fixture-staff-highlight-pin"
                }
        surfaceBrowserStateValue @BrowserFixtureSurface @StaffHighlightOrderState
            `shouldBe` BrowserAttributeIR
                { browserAttributeMarker = "StaffHighlightOrderState"
                , browserAttributeName = "staff-highlight-order"
                , browserAttributeDomAttribute = "data-bepis-browser-fixture-staff-highlight-order"
                }

    it "rejects collisions between Surface-owned browser role and state attributes" do
        let result = checkedSurfaceContractIR (SurfaceContractIR (reflectSurfaceRegistry @'[BrowserAttributeCollisionSurface]))
        diagnosticMessages result
            `shouldContain` ["surface browser-attribute-collision has duplicate browser attribute data-bepis-browser-attribute-collision-shared-highlight-attribute"]

    it "rejects empty and duplicate closed browser state values" do
        let emptyResult = checkedSurfaceContractIR (SurfaceContractIR (reflectSurfaceRegistry @'[EmptyBrowserClosedStateSurface]))
        diagnosticMessages emptyResult
            `shouldContain` ["surface empty-browser-closed-state browser state empty-mode must declare at least one value"]
        let duplicateResult = checkedSurfaceContractIR (SurfaceContractIR (reflectSurfaceRegistry @'[DuplicateBrowserClosedStateSurface]))
        diagnosticMessages duplicateResult
            `shouldContain` ["surface duplicate-browser-closed-state has duplicate browser state duplicate-mode value duplicate-mode-value"]

    it "renders Surface-owned browser attributes and linked-highlight registry data" do
        browserFixtureTypeScript `shouldContainText` "export const browserFixtureStaffHighlightSourceDomAttr = \"data-bepis-browser-fixture-staff-highlight-source\" as const;"
        browserFixtureTypeScript `shouldContainText` "export const browserFixtureStaffHighlightOrderDomAttr = \"data-bepis-browser-fixture-staff-highlight-order\" as const;"
        browserFixtureTypeScript `shouldContainText` "export const browserFixtureBrowserFixtureModeStates = {\"calm\":\"calm\",\"busy\":\"busy\"} as const;"
        browserFixtureTypeScript `shouldContainText` "export type BrowserFixtureBrowserFixtureModeState = \"calm\" | \"busy\";"
        browserFixtureTypeScript `shouldContainText` "export function isBrowserFixtureBrowserFixtureModeState(value: unknown): value is BrowserFixtureBrowserFixtureModeState"
        browserFixtureTypeScript `shouldContainText` "export type FrontendSurfaceLinkedHighlightActivation = \"hover\" | \"focus\" | \"keyboard\" | \"pin\";"
        browserFixtureTypeScript `shouldContainText` "export type FrontendSurfaceLinkedHighlightEffect = \"matching-source\" | \"matching-member\" | \"ordered-member-bounds\";"
        browserFixtureTypeScript `shouldContainText` "export const FrontendSurfaceLinkedHighlightRegistry: Record<FrontendSurfaceName, ReadonlyArray<FrontendSurfaceLinkedHighlightDefinition>> = {\"browser-fixture\":[{\"name\":\"staff-shifts-highlight\",\"sourceRoleAttribute\":browserFixtureStaffHighlightSourceDomAttr,\"memberRoleAttribute\":browserFixtureStaffHighlightMemberDomAttr,\"pinRoleAttribute\":browserFixtureStaffHighlightPinDomAttr,\"orderStateAttribute\":browserFixtureStaffHighlightOrderDomAttr,\"activations\":[\"hover\",\"focus\",\"keyboard\",\"pin\"],\"effects\":[\"matching-source\",\"matching-member\",\"ordered-member-bounds\"]}]};"

    it "renders exact codecs only for browser-reachable Surface DTOs" do
        browserFixtureTypeScript `shouldContainText` "export type BrowserFixturePayload = { browserFixturePayloadLabel: string };"
        browserFixtureTypeScript `shouldContainText` "export function isBrowserFixturePayload(value: unknown): value is BrowserFixturePayload"
        browserFixtureTypeScript `shouldContainText` "export function parseBrowserFixturePayload(value: unknown): BrowserFixturePayload"
        browserFixtureTypeScript `shouldNotContainText` "export function encodeBrowserFixturePayload"
        browserFixtureTypeScript `shouldContainText` "export type BrowserFixtureTypeOnlyPayload"
        browserFixtureTypeScript `shouldNotContainText` "export function isBrowserFixtureTypeOnlyPayload"
        browserFixtureTypeScript `shouldContainText` "export function isBrowserFixtureGuardPayload"
        browserFixtureTypeScript `shouldNotContainText` "export function parseBrowserFixtureGuardPayload"
        browserFixtureTypeScript `shouldContainText` "export function encodeBrowserFixtureOutboundPayload"
        browserFixtureTypeScript `shouldNotContainText` "export function isBrowserFixtureOutboundPayload"
        browserFixtureTypeScript `shouldContainText` "export function isBrowserFixtureBidirectionalPayload"
        browserFixtureTypeScript `shouldContainText` "export function parseBrowserFixtureBidirectionalPayload"
        browserFixtureTypeScript `shouldContainText` "export function encodeBrowserFixtureBidirectionalPayload"
        frontendSurfaceFixtureTypeScript `shouldNotContainText` "export type FixturePayload"
        frontendSurfaceFixtureTypeScript `shouldNotContainText` "export type FixtureRelatedPayload"

    it "rejects browser DTO codecs that reference a DTO without the required browser reachability" do
        let surface = reflectSurfaceSpec @BrowserFixtureSurface
        let malformed = surface
                { surfaceDtos = surface.surfaceDtos
                    <> [ SurfaceDtoIR BrowserUnreachableIR (RecordIR "ServerOnlyPayload" "ServerOnlyPayload" [])
                       , SurfaceDtoIR BrowserInboundIR
                            (RecordIR "NestedBrowserPayload" "NestedBrowserPayload"
                                [FieldIR "NestedServerValue" "nestedServerValue" (WireRefIR "ServerOnlyPayload") RequiredField]
                            )
                       ]
                }
        diagnosticMessages (checkedSurfaceContractIR (SurfaceContractIR [malformed]))
            `shouldContain`
                [ "surface browser-fixture browser dto NestedBrowserPayload references dto ServerOnlyPayload without the browser reachability required by its generated codec"
                ]

    it "renders browser Surface DTO payloads from exact marker-indexed fields" do
        let attrs =
                surfaceBrowserDtoRoleAttrs
                    @BrowserFixtureSurface
                    @StaffHighlightSourceRole
                    @BrowserFixturePayload
                    (surfaceField @BrowserFixturePayloadLabel "typed payload" &: noSurfaceFields)
        attrs
            `shouldBe` [("data-bepis-browser-fixture-staff-highlight-source", "{\"browserFixturePayloadLabel\":\"typed payload\"}")]

    it "reflects and renders complete-set sorting semantics without TypeScript redispatch" do
        let surface = reflectSurfaceSpec @BrowserFixtureSurface
        let sortDefinition = fromMaybe (error "missing fixture sort") (listToMaybe surface.surfaceCompleteSetSorts)
        sortDefinition.completeSetSortName `shouldBe` "browser-fixture-sort"
        sortDefinition.completeSetSortDefaultKey `shouldBe` "label"
        sortDefinition.completeSetSortDefaultDirection `shouldBe` CompleteSetSortAscendingIR
        map (.completeSetSortKeyName) sortDefinition.completeSetSortKeys `shouldBe` ["label", "count"]
        map (map (.completeSetSortComparatorField) . (.completeSetSortKeyComparators)) sortDefinition.completeSetSortKeys
            `shouldBe` [["browserFixtureSortLabel", "browserFixtureSortRowKey"], ["browserFixtureSortCount", "browserFixtureSortLabel", "browserFixtureSortRowKey"]]
        browserFixtureTypeScript `shouldContainText` "export type BrowserFixtureSortRow = { browserFixtureSortLabel: string; browserFixtureSortCount: number; browserFixtureSortRowKey: string };"
        browserFixtureTypeScript `shouldContainText` "export type BrowserFixtureSortKey = \"label\" | \"count\";"
        browserFixtureTypeScript `shouldContainText` "export const FrontendSurfaceCompleteSetSortRegistry"
        browserFixtureTypeScript `shouldContainText` "\"rowRoleAttribute\":browserFixtureBrowserFixtureSortRowDomAttr"
        browserFixtureTypeScript `shouldContainText` "\"parseRow\":parseBrowserFixtureSortRow"
        browserFixtureTypeScript `shouldContainText` "\"defaultKey\":\"label\",\"defaultDirection\":\"ascending\""
        browserFixtureTypeScript `shouldContainText` "\"field\":\"browserFixtureSortCount\",\"valueType\":\"integer\",\"direction\":\"selected\""
        browserFixtureTypeScript `shouldContainText` "\"field\":\"browserFixtureSortRowKey\",\"valueType\":\"opaque\",\"direction\":\"ascending\""

    it "reflects and renders mount-local tab keys and defaults" do
        let surface = reflectSurfaceSpec @BrowserFixtureSurface
        let tabSet = fromMaybe (error "missing fixture tabs") (listToMaybe surface.surfaceTabSets)
        tabSet.tabSetName `shouldBe` "browser-fixture-tabs"
        tabSet.tabSetKeys `shouldBe` ["staff", "settings"]
        tabSet.tabSetDefaultKey `shouldBe` "staff"
        browserFixtureTypeScript `shouldContainText` "export type BrowserFixtureTabsKey = \"staff\" | \"settings\";"
        browserFixtureTypeScript `shouldContainText` "export const FrontendSurfaceTabSetRegistry"
        browserFixtureTypeScript `shouldContainText` "\"tabRoleAttribute\":browserFixtureBrowserFixtureTabDomAttr"
        browserFixtureTypeScript `shouldContainText` "\"keys\":[\"staff\",\"settings\"],\"defaultKey\":\"staff\""

    it "rejects malformed complete-set sort and tab semantics before TypeScript rendering" do
        let surface = reflectSurfaceSpec @BrowserFixtureSurface
        let sortDefinition = fromMaybe (error "missing fixture sort") (listToMaybe surface.surfaceCompleteSetSorts)
        let firstKey = fromMaybe (error "missing fixture sort key") (listToMaybe sortDefinition.completeSetSortKeys)
        let firstComparator = fromMaybe (error "missing fixture comparator") (listToMaybe firstKey.completeSetSortKeyComparators)
        let malformedSort = sortDefinition
                { completeSetSortRootRole = sortDefinition.completeSetSortRootRole
                    { browserAttributeDomAttribute = "data-bepis-wrong-root" }
                , completeSetSortDefaultKey = "missing"
                , completeSetSortKeys = firstKey
                    { completeSetSortKeyComparators = firstComparator
                        { completeSetSortComparatorValueType = CompleteSetSortIntegerIR }
                        : drop 1 firstKey.completeSetSortKeyComparators
                    }
                    : drop 1 sortDefinition.completeSetSortKeys
                }
        let tabSet = fromMaybe (error "missing fixture tab set") (listToMaybe surface.surfaceTabSets)
        let malformed = surface
                { surfaceCompleteSetSorts = [malformedSort]
                , surfaceTabSets = [tabSet { tabSetDefaultKey = "missing" }]
                }
        let messages = diagnosticMessages (checkedSurfaceContractIR (SurfaceContractIR [malformed]))
        messages `shouldContain`
            [ "surface browser-fixture complete-set sort references missing root role browser-fixture-sort-root"
            , "surface browser-fixture complete-set sort browser-fixture-sort references missing default key missing"
            , "surface browser-fixture complete-set sort browser-fixture-sort key label comparator browserFixtureSortLabel has a wire type that disagrees with its declared sort value type"
            , "surface browser-fixture tab set browser-fixture-tabs references missing default key missing"
            ]

    it "renders complete-set sort and tab roles through marker-indexed Haskell helpers" do
        surfaceCompleteSetSortRootAttrs @BrowserFixtureSurface @BrowserFixtureSort
            `shouldBe` [("data-bepis-browser-fixture-browser-fixture-sort-root", "true")]
        surfaceCompleteSetSortControlAttrs @BrowserFixtureSurface @BrowserFixtureSort @CountSortKey
            `shouldBe` [("data-bepis-browser-fixture-browser-fixture-sort-control", "count")]
        surfaceCompleteSetSortRowAttrs
            @BrowserFixtureSurface
            @BrowserFixtureSort
            ( surfaceField @BrowserFixtureSortLabel "Alpha"
                &: surfaceField @BrowserFixtureSortCount (3 :: Int)
                &: surfaceField @BrowserFixtureSortRowKey "opaque:row"
                &: noSurfaceFields
            )
            `shouldBe`
                [ ( "data-bepis-browser-fixture-browser-fixture-sort-row"
                  , "{\"browserFixtureSortCount\":3,\"browserFixtureSortLabel\":\"Alpha\",\"browserFixtureSortRowKey\":\"opaque:row\"}"
                  )
                ]
        surfaceTabSetAttrs @BrowserFixtureSurface @BrowserFixtureTabs @SettingsTabKey
            `shouldBe` [("data-bepis-browser-fixture-browser-fixture-tab", "settings")]

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
                    &: surfaceField @TimesheetsSurface.WeekOffset (2 :: Int)
                    &: noSurfaceFields
        let scopeFields = fields :: SurfaceFields (SurfaceScopeFieldSpecs TimesheetsSurface.TimesheetsSurface TimesheetsSurface.TimesheetWeek)

        surfaceFieldsJson scopeFields
            `shouldBe` Aeson.object
                [ "venueId" Aeson..= ("11111111-1111-1111-1111-111111111111" :: Text)
                , "weekOffset" Aeson..= (2 :: Int)
                ]
        surfaceFieldsText scopeFields
            `shouldBe` [("venueId", "11111111-1111-1111-1111-111111111111"), ("weekOffset", "2")]
        let absentOptionalFields :: SurfaceFields '[ 'OptionalField TimesheetsSurface.StaffFilterId 'WireUUID]
            absentOptionalFields = surfaceOptionalField @TimesheetsSurface.StaffFilterId Nothing &: noSurfaceFields
        surfaceFieldsJson absentOptionalFields `shouldBe` Aeson.object []
        surfaceFieldsText absentOptionalFields `shouldBe` []
        let nullFields :: SurfaceFields '[ 'NullableField NullableTestField 'WireText]
            nullFields = surfaceNullableField @NullableTestField Nothing &: noSurfaceFields
        surfaceFieldsJson nullFields `shouldBe` Aeson.object ["nullableTest" Aeson..= Aeson.Null]
        let nestedOptionalFields :: SurfaceFields '[ 'OptionalField NestedOptionalTestField ('WireOptional 'WireInt)]
            nestedOptionalFields = surfaceOptionalField @NestedOptionalTestField (Just Nothing) &: noSurfaceFields
        surfaceFieldValue @NestedOptionalTestField nestedOptionalFields `shouldBe` Just Nothing
        let actionFields =
                surfaceField @TimesheetsSurface.WeekOffset 0
                    &: surfaceField @TimesheetsSurface.ShowApproved False
                    &: surfaceField @TimesheetsSurface.ShowAllStaff True
                    &: surfaceField @TimesheetsSurface.ShowSuggestions True
                    &: surfaceOptionalField @TimesheetsSurface.StaffFilterId Nothing
                    &: noSurfaceFields
                :: SurfaceFields (SurfaceActionFieldSpecs TimesheetsSurface.TimesheetsSurface TimesheetsSurface.NavigateTimesheetWeek)
        surfaceFieldNameFrom @TimesheetsSurface.WeekOffset actionFields `shouldBe` "weekOffset"

    it "parses complete typed action fields and exposes only marker-indexed values" do
        let filterId = fromMaybe (error "invalid fixture filter UUID") (UUID.fromString "33333333-3333-3333-3333-333333333333")
        let parsed = parseSurfaceActionParamPairs @RequestContractSurface @RequestAction
                [ ("requestCount", Just "7")
                , ("requestFilterId", Just (cs (UUID.toText filterId)))
                , ("requestNote", Just "")
                , ("routeContext", Just "outside-the-contract")
                ]

        case parsed of
            Left errors -> expectationFailure (cs ("expected valid request fields, got " <> show errors))
            Right fields -> do
                surfaceFieldValue @RequestCount fields `shouldBe` 7
                surfaceFieldValue @RequestFilterId fields `shouldBe` Just filterId
                surfaceFieldValue @RequestTags fields `shouldBe` Nothing
                surfaceFieldValue @RequestNote fields `shouldBe` Nothing

    it "parses repeated form values through declared list wires" do
        let parsed = parseSurfaceActionParamPairs @RequestContractSurface @RequestAction
                [ ("requestCount", Just "2")
                , ("requestTags", Just "first")
                , ("requestTags", Just "second")
                , ("requestNote", Just "ready")
                ]

        case parsed of
            Left errors -> expectationFailure (cs ("expected repeated list fields, got " <> show errors))
            Right fields -> surfaceFieldValue @RequestTags fields `shouldBe` Just ["first", "second"]

    it "treats a valueless declared parameter as present and blank" do
        let parsed = parseSurfaceActionParamPairs @RequestContractSurface @RequestAction
                [ ("requestCount", Just "2")
                , ("requestNote", Nothing)
                ]

        case parsed of
            Left errors -> expectationFailure (cs ("expected valueless nullable field, got " <> show errors))
            Right fields -> surfaceFieldValue @RequestNote fields `shouldBe` Nothing

    it "accumulates structured missing and malformed action field validation" do
        let parsed = parseSurfaceActionParamPairs @RequestContractSurface @RequestAction
                [ ("requestCount", Just "not-an-int")
                ]

        case parsed of
            Right _ -> expectationFailure "expected request field validation errors"
            Left errors ->
                map (\fieldError -> (fieldError.surfaceRequestFieldErrorName, fieldError.surfaceRequestFieldErrorKind)) errors
                    `shouldBe` [ ("requestCount", MalformedSurfaceRequestField)
                               , ("requestNote", MissingSurfaceRequestField)
                               ]

    it "parses intent fields through the same complete presence and wire contract" do
        let parsed = parseSurfaceIntentParamPairs @RequestContractSurface @RequestIntent
                [ ("requestCount", Just "4")
                , ("requestNote", Just "ready")
                ]

        case parsed of
            Left errors -> expectationFailure (cs ("expected valid intent fields, got " <> show errors))
            Right fields -> do
                surfaceFieldValue @RequestCount fields `shouldBe` 4
                surfaceFieldValue @RequestFilterId fields `shouldBe` Nothing
                surfaceFieldValue @RequestTags fields `shouldBe` Nothing
                surfaceFieldValue @RequestNote fields `shouldBe` Just "ready"

    it "renders minimal mount-local runtime metadata from production Surface values" do
        let venueId = fromMaybe (error "invalid fixture venue UUID") (UUID.fromString "22222222-2222-2222-2222-222222222222")
        let fragment =
                frontendSurfaceMountedFragmentFor @TimesheetsSurface.TimesheetsSurface @TimesheetsSurface.TimesheetToolbar
                    noSurfaceFields
                    noSurfaceFields
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
                        &: surfaceField @TimesheetsSurface.WeekOffset (0 :: Int)
                        &: noSurfaceFields
                    )
                    ( surfaceField @TimesheetsSurface.ShowApproved False
                        &: surfaceField @TimesheetsSurface.ShowAllStaff False
                        &: surfaceField @TimesheetsSurface.ShowSuggestions True
                        &: surfaceField @TimesheetsSurface.StaffFilterId Nothing
                        &: noSurfaceFields
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
                    (surfaceField @SurfaceFixture.PanelId panelId &: noSurfaceFields)
                    noSurfaceFields
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
        let fields = surfaceField @SurfaceFixture.PanelId panelId &: noSurfaceFields
        let key = frontendSurfaceFragmentKey @SurfaceFixture.FrontendSurfaceFixture @SurfaceFixture.FixturePanel fields
        let fragment =
                frontendSurfaceMountedFragmentFor @SurfaceFixture.FrontendSurfaceFixture @SurfaceFixture.FixturePanel
                    fields
                    noSurfaceFields
                    "/fixture/panel?panelId=11111111-1111-1111-1111-111111111111"
                    FrontendSurfaceReplace

        surfaceFieldsText fields `shouldBe` [("panelId", "11111111-1111-1111-1111-111111111111")]
        Aeson.toJSON key `shouldBe` Aeson.object
            [ "surface" Aeson..= ("contract-fixture" :: Text)
            , "kind" Aeson..= ("fixture-panel" :: Text)
            , "params" Aeson..= Aeson.object ["panelId" Aeson..= ("11111111-1111-1111-1111-111111111111" :: Text)]
            ]
        fragment.mountedFragmentKey `shouldBe` key
        fragment.mountedFragmentTargetId `shouldBe` surfaceFragmentTargetId @SurfaceFixture.FrontendSurfaceFixture @SurfaceFixture.FixturePanel noSurfaceFields
        fragment.mountedFragmentUrl `shouldBe` "/fixture/panel?panelId=11111111-1111-1111-1111-111111111111"

    it "reflects the complete production Surface registry in declared order" do
        map (.surfaceName) registeredFrontendSurfaceContractIR.contractSurfaces
            `shouldBe` [ "timesheets"
                       , "roster"
                       , "roster-day-timeline"
                       , "roster-template-designer"
                       , "leave-requests"
                       , "self-service-leave"
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
        map (fst . schemaNameAndMarker . (.surfaceDtoSchema)) surface.surfaceDtos `shouldBe` ["FixturePayload", "FixtureRelatedPayload"]
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
        let navigateAction = fromMaybe (error "missing navigate action") (find ((== "navigate-timesheet-week") . (.htmxActionName)) surface.surfaceHtmxActions)
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

    it "renders marker-indexed roster chrome roles and closed states" do
        rosterFullscreenRootAttrs RosterFullscreenCollapsed
            `shouldBe`
                [ ("data-bepis-roster-fullscreen-root", "true")
                , ("data-bepis-roster-fullscreen", "collapsed")
                ]
        rosterFullscreenRootAttrs RosterFullscreenExpanded
            `shouldBe`
                [ ("data-bepis-roster-fullscreen-root", "true")
                , ("data-bepis-roster-fullscreen", "expanded")
                ]
        rosterFullscreenToggleAttrs `shouldBe` [("data-bepis-roster-fullscreen-toggle", "true")]
        rosterFullscreenLabelAttrs `shouldBe` [("data-bepis-roster-fullscreen-label", "true")]
        rosterColumnEditorAttrs RosterColumnEditingInactive
            `shouldBe`
                [ ("data-bepis-roster-column-editor", "true")
                , ("data-bepis-roster-column-editing", "inactive")
                ]
        rosterColumnEditorAttrs RosterColumnEditingActive
            `shouldBe`
                [ ("data-bepis-roster-column-editor", "true")
                , ("data-bepis-roster-column-editing", "active")
                ]
        rosterColumnEditStartAttrs `shouldBe` [("data-bepis-roster-column-edit-start", "true")]
        rosterColumnEditDoneAttrs `shouldBe` [("data-bepis-roster-column-edit-done", "true")]

    it "renders the exact roster JPG export boundary from Haskell" do
        let filename = rosterImageExportFilename "Front Bar" (Calendar.fromGregorian 2025 1 6)
        filename `shouldBe` "roster-front-bar-week-of-6-jan.jpg"
        rosterImageExportProjectionAttrs `shouldBe` [("data-bepis-roster-image-export-projection", "true")]
        rosterImageExportRowAttrs `shouldBe` [("data-bepis-roster-image-export-row", "true")]
        rosterImageExportCellAttrs "09:00"
            `shouldBe`
                [ ("data-bepis-roster-image-export-cell", "{\"imageExportEndEllipsis\":false,\"imageExportText\":\"09:00\"}")
                ]
        rosterImageExportEllipsizedCellAttrs "Front of House Supervisor"
            `shouldBe`
                [ ("data-bepis-roster-image-export-cell", "{\"imageExportEndEllipsis\":true,\"imageExportText\":\"Front of House Supervisor\"}")
                ]
        let triggerAttrs = rosterJpgImageExportTriggerAttrs filename
        triggerAttrs `shouldContain` [("data-bepis-roster-image-export-trigger", "true")]
        triggerAttrs `shouldContain` [("data-bepis-roster-image-export-format", "jpg")]
        let rawConfig = fromMaybe (error "missing roster image export config") (lookup "data-bepis-roster-image-export-config" triggerAttrs)
        Aeson.decodeStrict (TextEncoding.encodeUtf8 rawConfig)
            `shouldBe` Just
                ( Aeson.object
                    [ "imageExportFilename" Aeson..= filename
                    , "imageExportMimeType" Aeson..= ("image/jpeg" :: Text)
                    , "imageExportQualityPercent" Aeson..= (92 :: Int)
                    , "imageExportPixelRatio" Aeson..= (2 :: Int)
                    , "imageExportMinimumWidth" Aeson..= (920 :: Int)
                    , "imageExportMaximumWidth" Aeson..= (1240 :: Int)
                    , "imageExportIdleLabel" Aeson..= ("Export JPG" :: Text)
                    , "imageExportPreparingLabel" Aeson..= ("Preparing..." :: Text)
                    , "imageExportDownloadedLabel" Aeson..= ("Downloaded" :: Text)
                    , "imageExportFailedLabel" Aeson..= ("Export failed" :: Text)
                    , "imageExportFailureMessage" Aeson..= ("Roster export failed. Please try again." :: Text)
                    , "imageExportMissingProjectionMessage" Aeson..= ("Could not find the current roster grid." :: Text)
                    , "imageExportCloneFailureMessage" Aeson..= ("Could not clone the current roster grid." :: Text)
                    , "imageExportRenderFailureMessage" Aeson..= ("Failed to render roster export image." :: Text)
                    , "imageExportCanvasFailureMessage" Aeson..= ("Failed to initialize roster export canvas." :: Text)
                    , "imageExportEncodingFailureMessage" Aeson..= ("Failed to encode roster export image." :: Text)
                    ]
                )

    it "renders exact roster week-overview panel, day, slot, and state boundaries" do
        let currentDate = Calendar.fromGregorian 2025 1 6
        rosterWeekOverviewPanelAttrs currentDate
            `shouldBe`
                [ ("data-bepis-roster-week-overview-panel", "{\"weekOverviewCurrentDate\":\"2025-01-06\"}")
                ]
        let payload = RosterWeekOverviewDayPayload
                { weekOverviewDate = currentDate
                , weekOverviewSelectedLabel = "Mon 6 Jan"
                , weekOverviewLeaveDisplay = "2"
                , weekOverviewAssignedDisplay = "5"
                , weekOverviewHoursDisplay = "30h"
                , weekOverviewSummaryText = "2 unavailable periods, 5 shifts assigned, 30h rostered."
                , weekOverviewWeekLabel = "In Week of 6 Jan"
                , weekOverviewNavigationUrl = "/ShowRosterWeek?weekOffset=0&weekDate=2025-01-06"
                , weekOverviewAvailability = RosterWeekOverviewLoaded
                , weekOverviewClosure = RosterWeekOverviewClosed
                }
        let dayAttrs = rosterWeekOverviewDayAttrs RosterWeekOverviewToday payload
        dayAttrs `shouldContain` [("data-bepis-roster-week-overview-availability", "loaded")]
        dayAttrs `shouldContain` [("data-bepis-roster-week-overview-closure", "closed")]
        dayAttrs `shouldContain` [("data-bepis-roster-week-overview-calendar-day", "today")]
        let rawDay = fromMaybe (error "missing roster week-overview day payload") (lookup "data-bepis-roster-week-overview-day" dayAttrs)
        Aeson.decodeStrict (TextEncoding.encodeUtf8 rawDay)
            `shouldBe` Just
                ( Aeson.object
                    [ "weekOverviewDate" Aeson..= currentDate
                    , "weekOverviewSelectedLabel" Aeson..= ("Mon 6 Jan" :: Text)
                    , "weekOverviewLeaveDisplay" Aeson..= ("2" :: Text)
                    , "weekOverviewAssignedDisplay" Aeson..= ("5" :: Text)
                    , "weekOverviewHoursDisplay" Aeson..= ("30h" :: Text)
                    , "weekOverviewSummaryText" Aeson..= ("2 unavailable periods, 5 shifts assigned, 30h rostered." :: Text)
                    , "weekOverviewWeekLabel" Aeson..= ("In Week of 6 Jan" :: Text)
                    , "weekOverviewNavigationUrl" Aeson..= ("/ShowRosterWeek?weekOffset=0&weekDate=2025-01-06" :: Text)
                    , "weekOverviewAvailability" Aeson..= ("loaded" :: Text)
                    , "weekOverviewClosure" Aeson..= ("closed" :: Text)
                    ]
                )
        rosterWeekOverviewTodayAttrs `shouldBe` [("data-bepis-roster-week-overview-today", "true")]
        rosterWeekOverviewDetailsAttrs RosterWeekOverviewLoaded RosterWeekOverviewClosed
            `shouldBe`
                [ ("data-bepis-roster-week-overview-details", "true")
                , ("data-bepis-roster-week-overview-availability", "loaded")
                , ("data-bepis-roster-week-overview-closure", "closed")
                ]
        rosterWeekOverviewSelectedLabelAttrs `shouldBe` [("data-bepis-roster-week-overview-selected-label", "true")]
        rosterWeekOverviewLeaveValueAttrs `shouldBe` [("data-bepis-roster-week-overview-leave-value", "true")]
        rosterWeekOverviewAssignedValueAttrs `shouldBe` [("data-bepis-roster-week-overview-assigned-value", "true")]
        rosterWeekOverviewHoursValueAttrs `shouldBe` [("data-bepis-roster-week-overview-hours-value", "true")]
        rosterWeekOverviewSummaryAttrs `shouldBe` [("data-bepis-roster-week-overview-summary", "true")]
        rosterWeekOverviewWeekLabelAttrs `shouldBe` [("data-bepis-roster-week-overview-week-label", "true")]
        rosterWeekOverviewGoLinkAttrs `shouldBe` [("data-bepis-roster-week-overview-go-link", "true")]

    it "reflects the registered roster surface into checked contract IR" do
        let surface = expectSurface "roster" registeredFrontendSurfaceContractIR

        map (.scopeName) surface.surfaceScopes `shouldBe` ["roster-week"]
        surface.surfaceBrowserDomTokens `shouldBe` []
        map (.fragmentName) surface.surfaceFragments
            `shouldBe` [ "roster-layout"
                       , "roster-content"
                       , "roster-grid-toolbar"
                       , "roster-grid-frame"
                       , "roster-day-columns"
                       , "roster-day-rail"
                       , "roster-wage-rail"
                       , "roster-slots-grid"
                       , "roster-staff-panel"
                       , "roster-week-overview"
                       , "roster-template-library"
                       , "roster-template-record"
                       , "roster-template-draft"
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
                       , "create-roster-week-slot-definition"
                       , "delete-roster-week-slot-definition"
                       , "toggle-roster-day-closed"
                       , "add-roster-row"
                       , "remove-roster-row"
                       , "apply-roster-template-application"
                       , "toggle-roster-staff-scope"
                       , "set-roster-layout-mode"
                       , "move-roster-shift-to-slot"
                       , "duplicate-roster-shift-to-day"
                       , "drop-roster-staff"
                       , "preview-roster-template-application"
                       ]
        ( surface.surfaceHtmxActions
            |> find (\action -> action.htmxActionName == "navigate-roster-week")
            |> maybe [] (.htmxActionOptions)
            )
            `shouldContain` [HtmxOption (HtmxActionSwapIR (HtmxTypedSyntaxIR "outerHTML" []))]
        map (.intentName) surface.surfaceIntents `shouldBe` ["set-roster-layout-mode", "move-roster-shift-to-slot", "duplicate-roster-shift-to-day", "drop-roster-staff", "preview-roster-template-application"]
        map (.sessionName) surface.surfaceSessions `shouldBe` ["drag"]
        map (.sessionLayers) surface.surfaceSessions `shouldBe` [["drag-preview"]]
        map (.sourceRefName) surface.surfaceSourceRefs `shouldBe` ["shift-drag-source", "staff-drag-source", "day-template-drag-source", "week-template-drag-source"]
        map (.sourceRefCompatibleDropzones) surface.surfaceSourceRefs
            `shouldBe` [ ["shift-slot-dropzone", "day-column-dropzone", "delete-shift-dropzone"]
                       , ["existing-shift-dropzone", "shift-slot-dropzone", "staff-create-dropzone"]
                       , ["day-template-dropzone"]
                       , ["week-template-dropzone"]
                       ]
        map (.dropzoneRefName) surface.surfaceDropzoneRefs `shouldBe` ["shift-slot-dropzone", "staff-create-dropzone", "day-column-dropzone", "existing-shift-dropzone", "delete-shift-dropzone", "day-template-dropzone", "week-template-dropzone"]
        map (.activationRefName) surface.surfaceActivationRefs `shouldBe` ["roster-layout-mode-activation"]
        map (.browserAttributeDomAttribute) surface.surfaceBrowserRoles
            `shouldBe` [ "data-bepis-roster-template-card"
                       , "data-bepis-roster-template-card-config"
                       , "data-bepis-roster-template-application-form"
                       , "data-bepis-roster-template-target-input"
                       , "data-bepis-roster-template-cancel"
                       , "data-bepis-roster-template-day-target"
                       , "data-bepis-roster-template-week-target"
                       , "data-bepis-roster-staff-panel-sort-root"
                       , "data-bepis-roster-staff-panel-sort-row"
                       , "data-bepis-roster-staff-panel-sort-control"
                       , "data-bepis-roster-staff-panel-tab"
                       , "data-bepis-roster-fullscreen-root"
                       , "data-bepis-roster-fullscreen-toggle"
                       , "data-bepis-roster-fullscreen-label"
                       , "data-bepis-roster-column-editor"
                       , "data-bepis-roster-column-edit-start"
                       , "data-bepis-roster-column-edit-done"
                       , "data-bepis-roster-image-export-trigger"
                       , "data-bepis-roster-image-export-config"
                       , "data-bepis-roster-image-export-projection"
                       , "data-bepis-roster-image-export-row"
                       , "data-bepis-roster-image-export-cell"
                       , "data-bepis-roster-wage-filter-config"
                       , "data-bepis-roster-week-overview-panel"
                       , "data-bepis-roster-week-overview-day"
                       , "data-bepis-roster-week-overview-today"
                       , "data-bepis-roster-week-overview-details"
                       , "data-bepis-roster-week-overview-selected-label"
                       , "data-bepis-roster-week-overview-leave-value"
                       , "data-bepis-roster-week-overview-assigned-value"
                       , "data-bepis-roster-week-overview-hours-value"
                       , "data-bepis-roster-week-overview-summary"
                       , "data-bepis-roster-week-overview-week-label"
                       , "data-bepis-roster-week-overview-go-link"
                       , "data-bepis-roster-staff-highlight-source"
                       , "data-bepis-roster-staff-highlight-member"
                       , "data-bepis-roster-staff-highlight-pin"
                       , "data-bepis-roster-shift-group-highlight-source"
                       , "data-bepis-roster-shift-group-highlight-member"
                       ]
        map (.browserAttributeDomAttribute) surface.surfaceBrowserStates
            `shouldBe`
                [ "data-bepis-roster-fullscreen"
                , "data-bepis-roster-column-editing"
                , "data-bepis-roster-image-export-format"
                , "data-bepis-roster-week-overview-availability"
                , "data-bepis-roster-week-overview-closure"
                , "data-bepis-roster-week-overview-calendar-day"
                , "data-bepis-roster-staff-highlight-order"
                ]
        map (\state -> (state.browserClosedStateAttribute.browserAttributeName, state.browserClosedStateValues)) surface.surfaceBrowserClosedStates
            `shouldBe`
                [ ("fullscreen", ["collapsed", "expanded"])
                , ("column-editing", ["inactive", "active"])
                , ("image-export-format", ["jpg"])
                , ("week-overview-availability", ["loaded", "unloaded"])
                , ("week-overview-closure", ["open", "closed"])
                , ("week-overview-calendar-day", ["today", "other-day"])
                ]
        map (.linkedHighlightName) surface.surfaceLinkedHighlights
            `shouldBe` ["staff-shifts-highlight", "shift-group-highlight"]
        let staffSort = fromMaybe (error "missing roster staff sort") (listToMaybe surface.surfaceCompleteSetSorts)
        staffSort.completeSetSortName `shouldBe` "roster-staff-panel-sort"
        staffSort.completeSetSortDefaultKey `shouldBe` "name"
        staffSort.completeSetSortDefaultDirection `shouldBe` CompleteSetSortAscendingIR
        map (.completeSetSortKeyName) staffSort.completeSetSortKeys `shouldBe` ["name", "role", "shifts"]
        map (map (.completeSetSortComparatorField) . (.completeSetSortKeyComparators)) staffSort.completeSetSortKeys
            `shouldBe`
                [ ["staffName", "staffRowKey"]
                , ["staffRole", "staffName", "staffRowKey"]
                , ["assignedShifts", "idealShifts", "staffName", "staffRowKey"]
                ]
        map (.tabSetName) surface.surfaceTabSets `shouldBe` ["roster-staff-panel-tabs"]
        map (.tabSetKeys) surface.surfaceTabSets `shouldBe` [["staff", "templates", "settings"]]
        map (.tabSetDefaultKey) surface.surfaceTabSets `shouldBe` ["staff"]
        map (map linkedHighlightActivationName . (.linkedHighlightActivations)) surface.surfaceLinkedHighlights
            `shouldBe` [ ["hover", "focus", "keyboard", "pin"]
                       , ["hover", "focus", "keyboard"]
                       ]
        map (map linkedHighlightEffectName . (.linkedHighlightEffects)) surface.surfaceLinkedHighlights
            `shouldBe` [ ["matching-source", "matching-member", "ordered-member-bounds"]
                       , ["matching-member"]
                       ]
        surface.surfaceLayers `shouldBe` ["drag-preview"]
        map (map interactionEffectSemanticName . (.sessionEffects)) surface.surfaceSessions
            `shouldBe` [["clone-shadow", "dropzone-highlight"]]
        map (map interactionEffectBrowserKind . (.sessionEffects)) surface.surfaceSessions
            `shouldBe` [["clone-shadow", "dropzone-highlight"]]
        map (map interactionEffectClassNames . (.sessionEffects)) surface.surfaceSessions
            `shouldBe` [[["bepis-pointer-clone-shadow"], ["bepis-dropzone-highlight"]]]
        map (map (.modifierVariantSemantic) . (.sourceRefVariants)) surface.surfaceSourceRefs `shouldBe` [["copy"], [], [], []]
        map (concatMap (map interactionEffectSemanticName . (.modifierVariantEffects)) . (.sourceRefVariants)) surface.surfaceSourceRefs `shouldBe` [["clone-shadow-copy", "dropzone-highlight"], [], [], []]
        surface.surfacePolicies `shouldBe` []

    it "renders minimal live, interaction, and DOM-token contracts for the roster surface" do
        frontendSurfaceContractsTypeScript `shouldContainText` "export type RosterSurfaceFragmentKey ="
        frontendSurfaceContractsTypeScript `shouldContainText` "export type RosterRosterWeekScope = { venueId: FrontendContractUuid; rosterGroupId: FrontendContractUuid; weekOffset: number };"
        frontendSurfaceContractsTypeScript `shouldContainText` "{ kind: \"roster-row\"; params: RosterRosterRowFragmentParams }"
        frontendSurfaceContractsTypeScript `shouldNotContainText` "export const rosterContentDomToken"
        frontendSurfaceContractsTypeScript `shouldNotContainText` "export const rosterWeekShellDomToken"
        frontendSurfaceContractsTypeScript `shouldContainText` "export const rosterStaffHighlightSourceDomAttr = \"data-bepis-roster-staff-highlight-source\" as const;"
        frontendSurfaceContractsTypeScript `shouldContainText` "export const rosterDayTimelineShiftGroupHighlightMemberDomAttr = \"data-bepis-roster-day-timeline-shift-group-highlight-member\" as const;"
        frontendSurfaceContractsTypeScript `shouldContainText` "export type RosterStaffPanelSortRow = { staffRowKey: string; staffName: string; staffRole: string; assignedShifts: number; idealShifts: number };"
        frontendSurfaceContractsTypeScript `shouldContainText` "export type RosterImageExportConfig = { imageExportFilename: string; imageExportMimeType: string; imageExportQualityPercent: number; imageExportPixelRatio: number; imageExportMinimumWidth: number; imageExportMaximumWidth: number; imageExportIdleLabel: string; imageExportPreparingLabel: string;"
        frontendSurfaceContractsTypeScript `shouldContainText` "export function parseRosterImageExportConfig(value: unknown): RosterImageExportConfig"
        frontendSurfaceContractsTypeScript `shouldContainText` "export type RosterImageExportCell = { imageExportText: string; imageExportEndEllipsis: boolean };"
        frontendSurfaceContractsTypeScript `shouldContainText` "export type RosterWageFilterConfig = { wageFilterEnabled: boolean; wageFilterRefreshTargetIds: ReadonlyArray<string>; wageFilterRequestTargetIds: ReadonlyArray<string> };"
        frontendSurfaceContractsTypeScript `shouldContainText` "export type RosterWageFilterRequest = { pinnedStaffKey?: string };"
        frontendSurfaceContractsTypeScript `shouldContainText` "export function encodeRosterWageFilterRequest"
        frontendSurfaceContractsTypeScript `shouldContainText` "export type RosterWeekOverviewPanelConfig = { weekOverviewCurrentDate: FrontendContractDay };"
        frontendSurfaceContractsTypeScript `shouldContainText` "export type RosterWeekOverviewDayConfig = { weekOverviewDate: FrontendContractDay; weekOverviewSelectedLabel: string; weekOverviewLeaveDisplay: string; weekOverviewAssignedDisplay: string; weekOverviewHoursDisplay: string; weekOverviewSummaryText: string; weekOverviewWeekLabel: string; weekOverviewNavigationUrl: string; weekOverviewAvailability: string; weekOverviewClosure: string };"
        frontendSurfaceContractsTypeScript `shouldContainText` "export function parseRosterWeekOverviewDayConfig(value: unknown): RosterWeekOverviewDayConfig"
        frontendSurfaceContractsTypeScript `shouldContainText` "export function parseRosterStaffPanelSortRow(value: unknown): RosterStaffPanelSortRow"
        frontendSurfaceContractsTypeScript `shouldContainText` "export type RosterStaffPanelSortKey = \"name\" | \"role\" | \"shifts\";"
        frontendSurfaceContractsTypeScript `shouldContainText` "export type RosterStaffPanelTabsKey = \"staff\" | \"templates\" | \"settings\";"
        frontendSurfaceContractsTypeScript `shouldContainText` "\"roster\":[{\"name\":\"roster-staff-panel-sort\",\"rootRoleAttribute\":rosterStaffPanelSortRootDomAttr"
        frontendSurfaceContractsTypeScript `shouldContainText` "\"roster\":[{\"name\":\"roster-staff-panel-tabs\",\"tabRoleAttribute\":rosterStaffPanelTabDomAttr,\"keys\":[\"staff\",\"templates\",\"settings\"],\"defaultKey\":\"staff\""
        frontendSurfaceContractsTypeScript `shouldContainText` "\"roster\":[{\"name\":\"staff-shifts-highlight\",\"sourceRoleAttribute\":rosterStaffHighlightSourceDomAttr,\"memberRoleAttribute\":rosterStaffHighlightMemberDomAttr,\"pinRoleAttribute\":rosterStaffHighlightPinDomAttr,\"orderStateAttribute\":rosterStaffHighlightOrderDomAttr,\"activations\":[\"hover\",\"focus\",\"keyboard\",\"pin\"],\"effects\":[\"matching-source\",\"matching-member\",\"ordered-member-bounds\"]},{\"name\":\"shift-group-highlight\""
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
        let resourceValue = TimesheetsResource.timesheetDayResource venueId 0 2

        matchFrontendSurfaceResource @TimesheetsSurface.TimesheetsSurface @TimesheetsSurface.TimesheetDay resourceValue
            `shouldBe` Just (venueId, (0, (2, ())))

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

    it "renders linked-highlight roles with opaque membership and order keys" do
        let highlight = surfaceLinkedHighlightValue @BrowserFixtureSurface @StaffShiftsHighlight
        let sourceHtml = cs (HtmlRenderer.renderHtml (SurfaceLinkedHighlight.withFrontendSurfaceLinkedHighlightSource highlight "opaque:staff" (Html5.div "source")))
        let memberHtml = cs (HtmlRenderer.renderHtml (SurfaceLinkedHighlight.withFrontendSurfaceLinkedHighlightMember highlight "opaque:staff" (Just "opaque:shift") (Html5.div "member")))
        let pinHtml = cs (HtmlRenderer.renderHtml (SurfaceLinkedHighlight.withFrontendSurfaceLinkedHighlightPin highlight "opaque:staff" (Html5.button "pin")))

        sourceHtml `shouldContainText` "data-bepis-browser-fixture-staff-highlight-source=\"opaque:staff\""
        memberHtml `shouldContainText` "data-bepis-browser-fixture-staff-highlight-member=\"opaque:staff\""
        memberHtml `shouldContainText` "data-bepis-browser-fixture-staff-highlight-order=\"opaque:shift\""
        pinHtml `shouldContainText` "data-bepis-browser-fixture-staff-highlight-pin=\"opaque:staff\""

    it "renders generated HTMX action attrs from complete typed fixture fields" do
        let panelId = fromMaybe (error "invalid fixture panel UUID") (UUID.fromString "11111111-1111-1111-1111-111111111111")
        let fields =
                surfaceActionFields
                    @SurfaceFixture.FrontendSurfaceFixture
                    @SurfaceFixture.RefreshPanel
                    (surfaceField @SurfaceFixture.PanelId panelId)
                    noSurfaceFields
        let action = frontendSurfaceAction @SurfaceFixture.FrontendSurfaceFixture @SurfaceFixture.RefreshPanel fields
        let route = FrontendSurfaceActionRoute
                { actionRouteUrl = "/fixture/refresh-panel?panelId=wrong&routeContext=keep"
                , actionRouteCustomHtmx = [FrontendSurfaceCustomHtmxAttrs "fixture-panel-custom-htmx" [("hx-vals", "{}")]]
                , actionRouteStandardUrl = Nothing
                , actionRouteExtraAttrs = [("class", "surface-action-test")]
                }
        let formHtml = cs (HtmlRenderer.renderHtml (renderFrontendSurfaceActionFormWithHiddenFields action route (Html5.toHtml ("refresh" :: Text))))
        let linkHtml = cs (HtmlRenderer.renderHtml (renderFrontendSurfaceActionLink action route (Html5.toHtml ("refresh" :: Text))))
        let buttonHtml = cs (HtmlRenderer.renderHtml (renderFrontendSurfaceActionSubmitButton action route (Html5.toHtml ("refresh" :: Text))))

        formHtml `shouldContainText` "method=\"post\""
        formHtml `shouldContainText` "action=\"/fixture/refresh-panel?routeContext=keep\""
        formHtml `shouldContainText` "hx-post=\"/fixture/refresh-panel?routeContext=keep\""
        formHtml `shouldContainText` "hx-target=\"#contract-fixture-panel\""
        formHtml `shouldContainText` "hx-swap=\"outerHTML\""
        formHtml `shouldContainText` "hx-include=\"#fixture-panel-include\""
        formHtml `shouldContainText` "hx-push-url=\"false\""
        formHtml `shouldContainText` "hx-vals=\"{}\""
        formHtml `shouldContainText` "data-bepis-surface-action=\"refresh-panel\""
        formHtml `shouldContainText` "name=\"panelId\" value=\"11111111-1111-1111-1111-111111111111\""
        formHtml `shouldNotContainText` "data-bepis-surface-action-config="
        linkHtml `shouldContainText` "href=\"/fixture/refresh-panel?routeContext=keep&amp;panelId=11111111-1111-1111-1111-111111111111\""
        linkHtml `shouldContainText` "hx-post=\"/fixture/refresh-panel?routeContext=keep&amp;panelId=11111111-1111-1111-1111-111111111111\""
        buttonHtml `shouldContainText` "formaction=\"/fixture/refresh-panel?routeContext=keep\""
        buttonHtml `shouldContainText` "hx-post=\"/fixture/refresh-panel?routeContext=keep\""

    it "renders intent forms only from complete typed intent fields" do
        let fields =
                surfaceIntentFields
                    @SurfaceFixture.FrontendSurfaceFixture
                    @SurfaceFixture.MoveCard
                    (surfaceField @SurfaceFixture.SourceItemKey "card-1")
                    ( surfaceField @SurfaceFixture.TargetDropzoneKey "panel-1"
                        &: noSurfaceFields
                    )
        let request = FrontendSurfaceHtmxRequest
                { htmxRequestMethod = FrontendSurfacePost
                , htmxRequestUrl = "/fixture/refresh-panel"
                , htmxRequestTarget = "#contract-fixture-panel"
                , htmxRequestSwap = "outerHTML"
                }
        let intent = frontendSurfaceIntentForm @SurfaceFixture.FrontendSurfaceFixture @SurfaceFixture.MoveCard fields request
        let intentHtml = cs (HtmlRenderer.renderHtml (renderFrontendSurfaceIntentForm intent (Html5.toHtml ("move" :: Text))))

        intentHtml `shouldContainText` "data-bepis-intent-form=\"move-card\""
        intentHtml `shouldContainText` "hx-target=\"#contract-fixture-panel\""
        intentHtml `shouldContainText` "name=\"sourceItemKey\" value=\"card-1\""
        intentHtml `shouldContainText` "name=\"targetDropzoneKey\" value=\"panel-1\""

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
