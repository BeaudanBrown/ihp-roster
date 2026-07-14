{-# LANGUAGE DataKinds        #-}
{-# LANGUAGE TypeApplications #-}

module Test.FrontendSurfaceNamingSpec
    ( tests
    ) where

import Application.Helper.FrontendContract.Naming
import IHP.Prelude
import Test.Hspec

data RosterSurface
data RosterWeekScope
data MoveRosterShiftToSlotIntent
data XeroOAuthSurface

tests :: Spec
tests = describe "FrontendSurface naming policy" do
    it "splits marker type names with acronym runs intact" do
        wordsFromTypeName "URLBuilder" `shouldBe` ["url", "builder"]
        wordsFromTypeName "HTMXAction" `shouldBe` ["htmx", "action"]
        wordsFromTypeName "XeroOAuthCallback" `shouldBe` ["xero", "oauth", "callback"]
        nameToSnake "URLBuilder" `shouldBe` "url_builder"
        nameToKebab "HTMXAction" `shouldBe` "htmx-action"

    it "strips role suffixes by context without stripping feature prefixes" do
        deriveFrontendSurfaceName SurfaceName "RosterSurface" `shouldBe` "roster"
        deriveFrontendSurfaceName ScopeName "RosterWeekScope" `shouldBe` "roster-week"
        deriveFrontendSurfaceName FragmentName "RosterDaySectionFragment" `shouldBe` "roster-day-section"
        deriveFrontendSurfaceName IntentName "MoveRosterShiftToSlotIntent" `shouldBe` "move-roster-shift-to-slot"
        deriveFrontendSurfaceName ActionName "RefreshPanelAction" `shouldBe` "refresh-panel"
        deriveFrontendSurfaceName SessionName "RosterDragSession" `shouldBe` "roster-drag"
        deriveFrontendSurfaceName LayerName "RosterDragPreviewLayer" `shouldBe` "roster-drag-preview"

    it "derives contextual JSON field DOM event and wire tag names" do
        deriveJsonFieldName "StaffFilterIdField" `shouldBe` "staffFilterId"
        deriveDomAttributeName "DropzoneToken" `shouldBe` "data-bepis-dropzone-token"
        deriveEventName "bepis" "LabCommitted" `shouldBe` "bepis:lab-committed"
        deriveWireTagName ScopeName "RosterWeekScope" `shouldBe` "roster_week"
        deriveWireTagName FragmentName "HTMXPanelFragment" `shouldBe` "htmx_panel"
        deriveFrontendSurfaceName AuthorizationPolicyName "CurrentVenueRosterGroupPolicy" `shouldBe` "current-venue-roster-group"
        deriveFrontendSurfaceName DomTokenName "BepisPointerCloneShadowCopy" `shouldBe` "bepis-pointer-clone-shadow-copy"

    it "requires exact names to be allowlisted with a reason" do
        let allowlist =
                [ ExactNameAllowlistEntry
                    { exactNameContext = SurfaceName
                    , exactNameMarker = "XeroOAuthSurface"
                    , exactNameValue = "xero-oauth"
                    , exactNameReason = "Keep existing protocol name during migration"
                    }
                ]
        deriveFrontendSurfaceTypeNameWithExact @XeroOAuthSurface @"xero-oauth" allowlist SurfaceName
            `shouldBe` Right "xero-oauth"
        deriveFrontendSurfaceTypeNameWithExact @XeroOAuthSurface @"xero" allowlist SurfaceName
            `shouldBe` Left UnauthorizedExactName
                { exactNameContext = SurfaceName
                , exactNameMarker = "XeroOAuthSurface"
                , exactNameRequested = "xero"
                }
        deriveFrontendSurfaceTypeName @RosterSurface SurfaceName `shouldBe` "roster"
        deriveFrontendSurfaceTypeName @RosterWeekScope ScopeName `shouldBe` "roster-week"
        deriveFrontendSurfaceTypeName @MoveRosterShiftToSlotIntent IntentName `shouldBe` "move-roster-shift-to-slot"

    it "reports generated-name collisions within a namespace" do
        validateFrontendSurfaceNameCollisions
            [ ("surface", "roster", "RosterSurface")
            , ("surface", "roster", "Roster")
            , ("fragment", "roster", "RosterFragment")
            ]
            `shouldBe` Left (FrontendSurfaceNameCollisions
                [ NameCollision
                    { collisionNamespace = "surface"
                    , collisionName = "roster"
                    , collisionMarkers = ["Roster", "RosterSurface"]
                    }
                ])
        validateFrontendSurfaceNameCollisions
            [ ("surface", "roster", "RosterSurface")
            , ("fragment", "roster", "RosterFragment")
            ]
            `shouldBe` Right ()
