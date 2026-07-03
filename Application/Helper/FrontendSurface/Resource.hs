module Application.Helper.FrontendSurface.Resource
    ( FrontendSurfaceResourceDefinition (..)
    , FrontendSurfaceResourceValue (..)
    , frontendSurfaceResourceDefinitions
    , liveResourceToFrontendSurfaceResourceValues
    , liveResourcesToFrontendSurfaceResourceValues
    ) where

import qualified Application.Helper.FrontendSurface.ContractIR as SurfaceIR
import Application.Helper.FrontendSurface.Reflect (reflectRegisteredFrontendSurfaces)
import Application.Helper.LiveResource (LiveResource (..))
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Types as Aeson.Types
import qualified Data.List as List
import qualified Data.Set as Set
import qualified Data.UUID as UUID
import IHP.Prelude

-- | Generated-surface resource definition discovered from explicit
-- FrontendSurface DependsOn declarations. V1 keeps this generic until the
-- current LiveResource emitters migrate to generated typed helpers.
data FrontendSurfaceResourceDefinition = FrontendSurfaceResourceDefinition
    { resourceName   :: !Text
    , resourceFields :: ![SurfaceIR.FieldIR]
    }
    deriving (Eq, Show)

-- | Runtime generated resource value used by the generated planner. The
-- temporary bridge below maps legacy LiveResource constructors into this shape
-- while mutation code migrates.
data FrontendSurfaceResourceValue = FrontendSurfaceResourceValue
    { resourceValueName   :: !Text
    , resourceValueFields :: !Aeson.Value
    }
    deriving (Eq, Ord, Show)

frontendSurfaceResourceDefinitions :: [FrontendSurfaceResourceDefinition]
frontendSurfaceResourceDefinitions =
    dependencies
        |> map (definitionFromDependency . (.dependencyResource))
        |> List.nub
        |> List.sortOn (.resourceName)
    where
        dependencies =
            reflectRegisteredFrontendSurfaces.contractSurfaces
                >>= (.surfaceFragments)
                >>= (SurfaceIR.optionResourceDependencies . (.fragmentOptions))
        definitionFromDependency resource = FrontendSurfaceResourceDefinition
            { resourceName = resource.resourceName
            , resourceFields = resource.resourceFields
            }

liveResourcesToFrontendSurfaceResourceValues :: Set.Set LiveResource -> Set.Set FrontendSurfaceResourceValue
liveResourcesToFrontendSurfaceResourceValues =
    Set.fromList . concatMap liveResourceToFrontendSurfaceResourceValues . Set.toAscList

-- TEMPORARY bridge: this mirrors the existing LiveResource constructors until
-- current mutation code emits generated FrontendSurface resource values directly.
-- ir-h5nr must remove this bridge before the epic closes.
liveResourceToFrontendSurfaceResourceValues :: LiveResource -> [FrontendSurfaceResourceValue]
liveResourceToFrontendSurfaceResourceValues = \case
    LeaveRequestsResource venueId -> [resource "leave-requests" ["venueId" Aeson..= uuid venueId]]
    StaffLeaveRequestsResource staffId -> [resource "staff-leave-requests" ["staffId" Aeson..= uuid staffId]]
    LeaveCalendarResource venueId weekOffset -> [resource "leave-calendar" ["venueId" Aeson..= uuid venueId, "weekOffset" Aeson..= weekOffset]]
    TimesheetWeekResource venueId weekOffset -> [resource "timesheet-week" ["venueId" Aeson..= uuid venueId, "weekOffset" Aeson..= weekOffset]]
    TimesheetDayResource venueId weekOffset dayOffset -> [resource "timesheet-day" ["venueId" Aeson..= uuid venueId, "weekOffset" Aeson..= weekOffset, "dayOffset" Aeson..= dayOffset]]
    StaffTimesheetResource staffId -> [resource "staff-timesheet" ["staffId" Aeson..= uuid staffId]]
    StaffProfileResource staffId -> [resource "staff-profile" ["staffId" Aeson..= uuid staffId]]
    StaffPreferencesResource staffId -> [resource "staff-preferences" ["staffId" Aeson..= uuid staffId]]
    StaffRosterMembershipResource staffId -> [resource "staff-roster-membership" ["staffId" Aeson..= uuid staffId]]
    StaffPayProfileResource staffId -> [resource "staff-pay-profile" ["staffId" Aeson..= uuid staffId]]
    StaffRsaDocumentsResource staffId -> [resource "staff-rsa-documents" ["staffId" Aeson..= uuid staffId]]
    RosterWeekResource rosterGroupId weekOffset -> [resource "roster-week" ["rosterGroupId" Aeson..= uuid rosterGroupId, "weekOffset" Aeson..= weekOffset]]
    RosterDayResource rosterDayId -> [resource "roster-day" ["rosterDayId" Aeson..= uuid rosterDayId]]
    RosterSlotResource rosterSlotId -> [resource "roster-slot" ["rosterSlotId" Aeson..= uuid rosterSlotId]]
    AdminVenueSettingsResource venueId -> [resource "admin-venue-settings" ["venueId" Aeson..= uuid venueId]]
    RosterEndTimesConfigResource venueId -> [resource "roster-end-times-config" ["venueId" Aeson..= uuid venueId]]
    RosterWeekBoundaryConfigResource venueId -> [resource "roster-week-boundary-config" ["venueId" Aeson..= uuid venueId]]
    TimesheetWeekBoundaryConfigResource venueId -> [resource "timesheet-week-boundary-config" ["venueId" Aeson..= uuid venueId]]
    AdminRosterGroupsResource venueId -> [resource "admin-roster-groups" ["venueId" Aeson..= uuid venueId]]
    AdminShiftTypesResource venueId -> [resource "admin-shift-types" ["venueId" Aeson..= uuid venueId]]
    AdminInvitesResource venueId -> [resource "admin-invites" ["venueId" Aeson..= uuid venueId]]
    AdminExportsResource venueId -> [resource "admin-exports" ["venueId" Aeson..= uuid venueId]]
    BillingResource venueId -> [resource "billing" ["venueId" Aeson..= uuid venueId]]
    SupportAwardRatesResource -> [resource "support-award-rates" []]
    SupportPublicHolidaysResource -> [resource "support-public-holidays" []]
    XeroConnectionResource venueId -> [resource "xero-connection" ["venueId" Aeson..= uuid venueId]]
    XeroMappingsResource venueId -> [resource "xero-mappings" ["venueId" Aeson..= uuid venueId]]
    XeroPayItemsResource venueId -> [resource "xero-pay-items" ["venueId" Aeson..= uuid venueId]]
    XeroTimesheetsResource venueId -> [resource "xero-timesheets" ["venueId" Aeson..= uuid venueId]]

resource :: Text -> [Aeson.Types.Pair] -> FrontendSurfaceResourceValue
resource name fields = FrontendSurfaceResourceValue
    { resourceValueName = name
    , resourceValueFields = Aeson.object fields
    }

uuid :: UUID.UUID -> Text
uuid = UUID.toText
