module Test.LiveSurfaceDependencySpec where

import Application.Helper.LiveResource
import Application.Helper.LiveSurface (TypedLiveSurfaceDefinition (..))
import qualified Data.Set as Set
import Data.UUID (fromWords)
import IHP.Prelude
import Test.Hspec
import Web.Timesheets.Projection (TimesheetProjectionFragment (..),
                                  TimesheetProjectionRequest (..),
                                  timesheetLiveSurfaceDefinitionForVenue)
import Web.View.Admin.Invites (AdminInvitesSurfaceKey (..),
                               adminInvitesFragment,
                               adminInvitesLiveSurfaceDefinitionForVenue)
import Web.View.Admin.Xero (adminXeroLiveSurfaceDefinitionForVenue,
                            adminXeroPayItemsFragment,
                            adminXeroShellFragment,
                            adminXeroStaffMappingsFragment,
                            adminXeroTimesheetsFragment)

tests :: Spec
tests = do
    describe "Live surface resource dependencies" do
        it "declares timesheet week and day dependencies" do
            let venueId = fromWords 1 0 0 0
            let definition = timesheetLiveSurfaceDefinitionForVenue venueId
            let request = TimesheetProjectionRequest 2 True True Nothing

            typedSurfaceDependsOn definition request TimesheetProjectionPage
                `shouldBe` [TimesheetWeekResource venueId 2]
            typedSurfaceDependsOn definition request (TimesheetProjectionDaySection 4)
                `shouldBe` [TimesheetDayResource venueId 2 4]

        it "declares admin Xero dependencies by fragment" do
            let venueId = fromWords 2 0 0 0
            let definition = adminXeroLiveSurfaceDefinitionForVenue venueId
            let shellDependencies = Set.fromList (typedSurfaceDependsOn definition () adminXeroShellFragment)

            shellDependencies
                `shouldBe` Set.fromList
                    [ XeroConnectionResource venueId
                    , XeroMappingsResource venueId
                    , XeroPayItemsResource venueId
                    , XeroTimesheetsResource venueId
                    ]
            typedSurfaceDependsOn definition () adminXeroStaffMappingsFragment
                `shouldBe` [XeroMappingsResource venueId]
            typedSurfaceDependsOn definition () adminXeroPayItemsFragment
                `shouldBe` [XeroPayItemsResource venueId]
            typedSurfaceDependsOn definition () adminXeroTimesheetsFragment
                `shouldBe` [XeroTimesheetsResource venueId]

        it "declares admin invitation dependencies for venue-scoped invite surfaces" do
            let venueId = fromWords 3 0 0 0
            let definition = adminInvitesLiveSurfaceDefinitionForVenue venueId
            let key = AdminInvitesSurfaceKey { adminInvitesRosterGroupId = Nothing }

            typedSurfaceDependsOn definition key adminInvitesFragment
                `shouldBe` [AdminInvitesResource venueId]
