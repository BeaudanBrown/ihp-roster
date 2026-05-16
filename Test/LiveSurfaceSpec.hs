module Test.LiveSurfaceSpec where

import Application.Helper.LiveSurface
import Application.Support.LiveUpdates
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
        map (.feature) surfaces `shouldBe` ["billing", "timesheets", "admin-invites", "admin-xero"]
        map (.scopeKey) surfaces
            `shouldBe`
                [ "billing:11111111-1111-1111-1111-111111111111"
                , "timesheet_week:11111111-1111-1111-1111-111111111111:1"
                , "admin_invites:11111111-1111-1111-1111-111111111111"
                , "admin_xero:11111111-1111-1111-1111-111111111111"
                ]

expectUuid :: Text -> UUID.UUID
expectUuid value =
    fromMaybe (error ("Invalid UUID fixture: " <> cs value)) (UUID.fromText value)
