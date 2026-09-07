{-# LANGUAGE DataKinds        #-}
{-# LANGUAGE TypeApplications #-}

module Test.FrontendSurfaceNamingSpec
    ( tests
    ) where

import Application.Helper.FrontendContract.Naming
import Application.Helper.FrontendContract.Surface.ContractIR
import Application.Helper.FrontendContract.Surface.DSL
import Application.Helper.FrontendContract.Surface.Reflect (reflectSurfaceRegistry)
import IHP.Prelude
import Test.Hspec

-- Unregistered declarations exercise the same reflection/checking boundary as
-- production, not a parallel naming-policy evaluator.
data XeroOAuthSurface
data XeroOAuth
data OtherSurface
data RosterWeekScope
data HTMXPanelFragment
data SharedOperation
data SharedOperationAction
data StaffFilterIdField
data URLBuilderField
data Version2Field
data SelectedRole
data SelectedState

type NamingDeclarations =
    '[ Scope RosterWeekScope '[] '[ 'NoAuth ]
     , Fragment HTMXPanelFragment '[] '[ 'MountTarget HTMXPanelFragment '[] ]
     , Action SharedOperation
        '[ Field StaffFilterIdField 'WireText
         , Field URLBuilderField 'WireText
         , Field Version2Field 'WireInt
         ] '[]
     , Intent SharedOperation '[] '[]
     , BrowserRole SelectedRole
     ]

type NamingSurface = Surface XeroOAuthSurface NamingDeclarations

tests :: Spec
tests = describe "FrontendSurface naming policy" do
    it "splits marker type names with acronym runs intact" do
        wordsFromTypeName "URLBuilder" `shouldBe` ["url", "builder"]
        wordsFromTypeName "HTMXAction" `shouldBe` ["htmx", "action"]
        wordsFromTypeName "XeroOAuthCallback" `shouldBe` ["xero", "oauth", "callback"]
        nameToKebab "HTMXAction" `shouldBe` "htmx-action"

    it "strips role suffixes by context without stripping feature prefixes" do
        deriveFrontendSurfaceName SurfaceName "RosterSurface" `shouldBe` "roster"
        deriveFrontendSurfaceName ScopeName "RosterWeekScope" `shouldBe` "roster-week"
        deriveFrontendSurfaceName FragmentName "RosterDaySectionFragment" `shouldBe` "roster-day-section"
        deriveFrontendSurfaceName IntentName "MoveRosterShiftToSlotIntent" `shouldBe` "move-roster-shift-to-slot"
        deriveFrontendSurfaceName ActionName "RefreshPanelAction" `shouldBe` "refresh-panel"
        deriveFrontendSurfaceName SessionName "RosterDragSession" `shouldBe` "roster-drag"
        deriveFrontendSurfaceName LayerName "RosterDragPreviewLayer" `shouldBe` "roster-drag-preview"

    it "derives contextual JSON field DOM and event names" do
        deriveJsonFieldName "StaffFilterIdField" `shouldBe` "staffFilterId"
        deriveDomAttributeName "DropzoneToken" `shouldBe` "data-bepis-dropzone-token"
        deriveEventName "bepis" "LabCommitted" `shouldBe` "bepis:lab-committed"
        deriveFrontendSurfaceName AuthorizationPolicyName "CurrentVenueRosterGroupPolicy" `shouldBe` "current-venue-roster-group"
        deriveFrontendSurfaceName DomTokenName "BepisPointerCloneShadowCopy" `shouldBe` "bepis-pointer-clone-shadow-copy"
        deriveFrontendSurfaceTypeName @RosterWeekScope ScopeName `shouldBe` "roster-week"
        deriveFrontendSurfaceTypeName @StaffFilterIdField FieldName `shouldBe` "staffFilterId"

    it "checks reflected names and permits the same marker across Action and Intent kinds" do
        let reflected = SurfaceContractIR (reflectSurfaceRegistry @'[NamingSurface])
        case checkedSurfaceContractIR reflected of
            Left diagnostics -> expectationFailure (cs (show diagnostics))
            Right checked -> do
                map (.surfaceName) checked.contractSurfaces `shouldBe` ["xero-oauth"]
                let scopes = concatMap (.surfaceScopes) checked.contractSurfaces
                map (.scopeName) scopes `shouldBe` ["roster-week"]
                let fragments = concatMap (.surfaceFragments) checked.contractSurfaces
                map (.fragmentName) fragments `shouldBe` ["htmx-panel"]
                let actions = concatMap (.surfaceHtmxActions) checked.contractSurfaces
                map (.htmxActionName) actions `shouldBe` ["shared-operation"]
                map (map (.fieldName) . (.htmxActionFields)) actions
                    `shouldBe` [["staffFilterId", "urlBuilder", "version2"]]
                let intents = concatMap (.surfaceIntents) checked.contractSurfaces
                map (.intentName) intents `shouldBe` ["shared-operation"]
                map (.browserAttributeDomAttribute) (concatMap (.surfaceBrowserRoles) checked.contractSurfaces)
                    `shouldBe` ["data-bepis-xero-oauth-selected"]

    it "allows identical local names on distinct surfaces with namespaced browser attributes" do
        let reflected = SurfaceContractIR (reflectSurfaceRegistry @'[NamingSurface, Surface OtherSurface NamingDeclarations])
        case checkedSurfaceContractIR reflected of
            Left diagnostics -> expectationFailure (cs (show diagnostics))
            Right checked -> do
                map (.surfaceName) checked.contractSurfaces `shouldBe` ["xero-oauth", "other"]
                map (.browserAttributeDomAttribute) (concatMap (.surfaceBrowserRoles) checked.contractSurfaces)
                    `shouldBe` ["data-bepis-xero-oauth-selected", "data-bepis-other-selected"]

    it "rejects different Surface markers deriving the same name" do
        let reflected = SurfaceContractIR (reflectSurfaceRegistry @'[NamingSurface, Surface XeroOAuth NamingDeclarations])
        checkedSurfaceContractIR reflected `shouldBe` Left
            [ContractDiagnostic "duplicate-surface" "duplicate surface name xero-oauth"]

    it "rejects different Action markers deriving the same name within one Surface" do
        let reflected = SurfaceContractIR (reflectSurfaceRegistry
                @'[Surface XeroOAuthSurface (Append NamingDeclarations '[Action SharedOperationAction '[] '[]])])
        checkedSurfaceContractIR reflected `shouldBe` Left
            [ContractDiagnostic "duplicate-htmx-action" "surface xero-oauth has duplicate htmx action shared-operation"]

    it "rejects cross-kind role and state names sharing one browser attribute namespace" do
        let reflected = SurfaceContractIR (reflectSurfaceRegistry
                @'[Surface XeroOAuthSurface (Append NamingDeclarations '[BrowserState SelectedState])])
        checkedSurfaceContractIR reflected `shouldBe` Left
            [ContractDiagnostic "duplicate-browser-attribute" "surface xero-oauth has duplicate browser attribute data-bepis-xero-oauth-selected"]
