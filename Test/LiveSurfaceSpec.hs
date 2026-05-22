module Test.LiveSurfaceSpec where

import Application.Helper.LiveResource (LiveResource (..))
import Application.Helper.LiveSurface
import Application.Helper.LiveUpdate (LiveFragmentKey (..), LiveUpdateWireFragment (..))
import Application.Support.LiveUpdates
import Data.List.NonEmpty (NonEmpty (..))
import qualified Data.UUID as UUID
import Generated.Types
import IHP.Prelude
import Web.Billing.LiveUpdates
import Web.Timesheets.Projection
import Web.View.Admin.Invites
import Web.View.Admin.Xero
import Test.Hspec
import Test.Support.LiveSurfaceContract

tests :: Spec
tests = describe "LiveSurface contract helpers" do
    it "normalizes fragment refs by containment path" do
        let parent = testFragmentRef RosterContentFragment "roster-content" ["roster-content"]
        let child = testFragmentRef RosterStaffPanelFragment "roster-staff-panel-fragment" ["roster-content", "staff-panel"]
        let duplicateChild = testFragmentRef RosterStaffPanelFragment "roster-staff-panel-fragment-duplicate" ["roster-content", "staff-panel"]
        let grandchild = testFragmentRef RosterRowFragment { rosterDayId = expectUuid "22222222-2222-2222-2222-222222222222", rowIndex = 3 } "roster-row-3" ["roster-content", "day", "22222222", "row", "3"]
        let day = testFragmentRef RosterDaySectionFragment { rosterDayId = expectUuid "22222222-2222-2222-2222-222222222222" } "roster-day-22222222" ["roster-content", "day", "22222222"]
        let sibling = testFragmentRef BillingStatusFragment "billing-status-fragment" ["billing-status-fragment"]

        targetIds (normalizeSurfaceFragmentRefs [child, duplicateChild])
            `shouldBe` ["roster-staff-panel-fragment"]
        targetIds (normalizeSurfaceFragmentRefs [child, parent])
            `shouldBe` ["roster-content"]
        targetIds (normalizeSurfaceFragmentRefs [grandchild, day])
            `shouldBe` ["roster-day-22222222"]
        targetIds (normalizeSurfaceFragmentRefs [child, sibling])
            `shouldBe` ["roster-staff-panel-fragment", "billing-status-fragment"]

    it "derives live fragment refs and dependencies from a single fragment contract" do
        let venueId = expectUuid "11111111-1111-1111-1111-111111111111"
        let billingKey = BillingSurfaceKey { billingSurfaceVenueId = venueId }

        map (.targetId) (unSurfaceFragmentRefs (typedLiveSurfaceFragmentRefs billingLiveSurfaceDefinition billingKey [BillingStatusLiveFragment]))
            `shouldBe` ["billing-status-fragment"]
        typedSurfaceDependsOn billingLiveSurfaceDefinition billingKey BillingStatusLiveFragment
            `shouldBe` [BillingResource venueId]

    it "requires fragment contracts to declare resource dependencies or resync-only intent" do
        let ref = testFragmentRef BillingStatusFragment "billing-status-fragment" ["billing-status-fragment"]
        let dependent = mkSurfaceFragmentContract ref (liveFragmentDependsOn (BillingResource (expectUuid "11111111-1111-1111-1111-111111111111")) [])
        let resyncOnly = mkSurfaceFragmentContract ref (liveFragmentResyncOnly "no passive dependency")

        fragmentContractDependencies dependent `shouldBe` DependsOnLiveResources (BillingResource (expectUuid "11111111-1111-1111-1111-111111111111") :| [])
        fragmentContractDependencies resyncOnly `shouldBe` ResyncOnlyFragment "no passive dependency"

    it "verifies the typed support surface config contract" do
        liveSurfaceConfigShouldRoundTrip supportLiveSurface
        liveSurfaceConfigShouldExposeRefs
            supportLiveSurface
            (unSurfaceFragmentRefs (typedLiveSurfaceFragmentRefs supportLiveSurfaceDefinition () supportLiveFragmentRefs))

    it "verifies context-free typed surface contracts used by background updates" do
        let venueId = expectUuid "11111111-1111-1111-1111-111111111111"
        let rosterGroupId = "22222222-2222-2222-2222-222222222222" :: Id RosterGroup
        let billingKey = BillingSurfaceKey { billingSurfaceVenueId = venueId }
        let timesheetKey = TimesheetProjectionRequest 1 True True Nothing
        let invitesKey = AdminInvitesSurfaceKey { adminInvitesRosterGroupId = Just rosterGroupId }
        let surfaces =
                [ mkTypedDefinedLiveSurface billingLiveSurfaceDefinition billingKey
                , mkTypedDefinedLiveSurface (timesheetLiveSurfaceDefinitionForVenue venueId) timesheetKey
                , mkTypedDefinedLiveSurface (adminInvitesLiveSurfaceDefinitionForVenue venueId) invitesKey
                , mkTypedDefinedLiveSurface (adminXeroLiveSurfaceDefinitionForVenue venueId) ()
                ]

        forM_ surfaces liveSurfaceConfigShouldRoundTrip
        typedLiveSurfaceConfigShouldExposeDefaultRefs
            (timesheetLiveSurfaceDefinitionForVenue venueId)
            timesheetKey
            (map TimesheetProjectionDaySection [0 .. 6])
        typedLiveSurfaceFragmentShouldMapTo
            (timesheetLiveSurfaceDefinitionForVenue venueId)
            timesheetKey
            (TimesheetProjectionDaySection 2)
            TimesheetDaySectionFragment { dayOffset = 2 }
            "timesheet-day-section-2"
            "/ShowTimesheetDaySectionFragment?weekOffset=1&dayOffset=2&showApproved=true&showAllStaff=true"
        typedLiveSurfaceFragmentShouldMapTo
            (adminXeroLiveSurfaceDefinitionForVenue venueId)
            ()
            adminXeroPayItemsFragment
            AdminXeroPayItemsFragment
            "xero-pay-items-data"
            "/ShowAdminXeroPayItemsFragment"
        map (.feature) surfaces `shouldBe` ["billing", "timesheets", "admin-invites", "admin-xero"]
        map (.scopeKey) surfaces
            `shouldBe`
                [ "billing:11111111-1111-1111-1111-111111111111"
                , "timesheet_week:11111111-1111-1111-1111-111111111111:1"
                , "admin_invites:11111111-1111-1111-1111-111111111111"
                , "admin_xero:11111111-1111-1111-1111-111111111111"
                ]

testFragmentRef :: LiveFragmentKey -> Text -> [Text] -> SurfaceFragmentRef ()
testFragmentRef fragmentKey target path =
    mkSurfaceFragmentRef fragmentKey target ("/" <> target)
        |> surfaceFragmentRefWithPath path

targetIds :: [SurfaceFragmentRef surface] -> [Text]
targetIds refs =
    map (.targetId) (unSurfaceFragmentRefs refs)

expectUuid :: Text -> UUID.UUID
expectUuid value =
    fromMaybe (error ("Invalid UUID fixture: " <> cs value)) (UUID.fromText value)
