module Application.Helper.FrontendSurface.Resource
    ( FrontendSurfaceResourceDefinition (..)
    , FrontendSurfaceResourceValue (..)
    , adminExportsResource
    , adminInvitesResource
    , adminRosterGroupsResource
    , adminShiftTypesResource
    , adminVenueSettingsResource
    , billingResource
    , frontendSurfaceResourceDefinitions
    , leaveCalendarResource
    , leaveRequestsResource
    , resource
    , resourceFieldInt
    , resourceFieldUuid
    , resourceMatches
    , rosterDayResource
    , rosterEndTimesConfigResource
    , rosterSlotResource
    , rosterWeekBoundaryConfigResource
    , rosterWeekResource
    , staffLeaveRequestsResource
    , staffPayProfileResource
    , staffPreferencesResource
    , staffProfileResource
    , staffRosterMembershipResource
    , staffRsaDocumentsResource
    , staffTimesheetResource
    , supportAwardRatesResource
    , supportPublicHolidaysResource
    , timesheetDayResource
    , timesheetWeekBoundaryConfigResource
    , timesheetWeekResource
    , xeroConnectionResource
    , xeroMappingsResource
    , xeroPayItemsResource
    , xeroTimesheetsResource
    ) where

import qualified Application.Helper.FrontendSurface.ContractIR as SurfaceIR
import Application.Helper.FrontendSurface.Reflect (reflectRegisteredFrontendSurfaces)
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as Aeson.Key
import qualified Data.Aeson.KeyMap as Aeson.KeyMap
import qualified Data.Aeson.Types as Aeson.Types
import qualified Data.List as List
import qualified Data.Scientific as Scientific
import qualified Data.UUID as UUID
import IHP.Prelude

-- | Generated-surface resource definition discovered from explicit
-- FrontendSurface DependsOn declarations.
data FrontendSurfaceResourceDefinition = FrontendSurfaceResourceDefinition
    { resourceName   :: !Text
    , resourceFields :: ![SurfaceIR.FieldIR]
    }
    deriving (Eq, Show)

-- | Concrete runtime resource value consumed by the generated FrontendSurface
-- dependency planner.
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
        definitionFromDependency resourceDefinition = FrontendSurfaceResourceDefinition
            { resourceName = resourceDefinition.resourceName
            , resourceFields = resourceDefinition.resourceFields
            }

leaveRequestsResource, staffLeaveRequestsResource, staffTimesheetResource, staffProfileResource, staffPreferencesResource, staffRosterMembershipResource, staffPayProfileResource, staffRsaDocumentsResource, rosterDayResource, rosterSlotResource, adminVenueSettingsResource, rosterEndTimesConfigResource, rosterWeekBoundaryConfigResource, timesheetWeekBoundaryConfigResource, adminRosterGroupsResource, adminShiftTypesResource, adminInvitesResource, adminExportsResource, billingResource, xeroConnectionResource, xeroMappingsResource, xeroPayItemsResource, xeroTimesheetsResource :: UUID.UUID -> FrontendSurfaceResourceValue
leaveRequestsResource venueId = resource "leave-requests" ["venueId" Aeson..= uuid venueId]
staffLeaveRequestsResource staffId = resource "staff-leave-requests" ["staffId" Aeson..= uuid staffId]
staffTimesheetResource staffId = resource "staff-timesheet" ["staffId" Aeson..= uuid staffId]
staffProfileResource staffId = resource "staff-profile" ["staffId" Aeson..= uuid staffId]
staffPreferencesResource staffId = resource "staff-preferences" ["staffId" Aeson..= uuid staffId]
staffRosterMembershipResource staffId = resource "staff-roster-membership" ["staffId" Aeson..= uuid staffId]
staffPayProfileResource staffId = resource "staff-pay-profile" ["staffId" Aeson..= uuid staffId]
staffRsaDocumentsResource staffId = resource "staff-rsa-documents" ["staffId" Aeson..= uuid staffId]
rosterDayResource rosterDayId = resource "roster-day" ["rosterDayId" Aeson..= uuid rosterDayId]
rosterSlotResource rosterSlotId = resource "roster-slot" ["rosterSlotId" Aeson..= uuid rosterSlotId]
adminVenueSettingsResource venueId = resource "admin-venue-settings" ["venueId" Aeson..= uuid venueId]
rosterEndTimesConfigResource venueId = resource "roster-end-times-config" ["venueId" Aeson..= uuid venueId]
rosterWeekBoundaryConfigResource venueId = resource "roster-week-boundary-config" ["venueId" Aeson..= uuid venueId]
timesheetWeekBoundaryConfigResource venueId = resource "timesheet-week-boundary-config" ["venueId" Aeson..= uuid venueId]
adminRosterGroupsResource venueId = resource "admin-roster-groups" ["venueId" Aeson..= uuid venueId]
adminShiftTypesResource venueId = resource "admin-shift-types" ["venueId" Aeson..= uuid venueId]
adminInvitesResource venueId = resource "admin-invites" ["venueId" Aeson..= uuid venueId]
adminExportsResource venueId = resource "admin-exports" ["venueId" Aeson..= uuid venueId]
billingResource venueId = resource "billing" ["venueId" Aeson..= uuid venueId]
xeroConnectionResource venueId = resource "xero-connection" ["venueId" Aeson..= uuid venueId]
xeroMappingsResource venueId = resource "xero-mappings" ["venueId" Aeson..= uuid venueId]
xeroPayItemsResource venueId = resource "xero-pay-items" ["venueId" Aeson..= uuid venueId]
xeroTimesheetsResource venueId = resource "xero-timesheets" ["venueId" Aeson..= uuid venueId]

leaveCalendarResource :: UUID.UUID -> Int -> FrontendSurfaceResourceValue
leaveCalendarResource venueId weekOffset = resource "leave-calendar" ["venueId" Aeson..= uuid venueId, "weekOffset" Aeson..= weekOffset]

timesheetWeekResource :: UUID.UUID -> Int -> FrontendSurfaceResourceValue
timesheetWeekResource venueId weekOffset = resource "timesheet-week" ["venueId" Aeson..= uuid venueId, "weekOffset" Aeson..= weekOffset]

timesheetDayResource :: UUID.UUID -> Int -> Int -> FrontendSurfaceResourceValue
timesheetDayResource venueId weekOffset dayOffset = resource "timesheet-day" ["venueId" Aeson..= uuid venueId, "weekOffset" Aeson..= weekOffset, "dayOffset" Aeson..= dayOffset]

rosterWeekResource :: UUID.UUID -> Int -> FrontendSurfaceResourceValue
rosterWeekResource rosterGroupId weekOffset = resource "roster-week" ["rosterGroupId" Aeson..= uuid rosterGroupId, "weekOffset" Aeson..= weekOffset]

supportAwardRatesResource, supportPublicHolidaysResource :: FrontendSurfaceResourceValue
supportAwardRatesResource = resource "support-award-rates" []
supportPublicHolidaysResource = resource "support-public-holidays" []

resourceMatches :: Text -> FrontendSurfaceResourceValue -> Bool
resourceMatches name value = value.resourceValueName == name

resourceFieldUuid :: Text -> FrontendSurfaceResourceValue -> Maybe UUID.UUID
resourceFieldUuid fieldName value = do
    text <- resourceFieldText fieldName value
    UUID.fromText text

resourceFieldInt :: Text -> FrontendSurfaceResourceValue -> Maybe Int
resourceFieldInt fieldName value = do
    raw <- resourceField fieldName value
    case raw of
        Aeson.Number number -> Scientific.toBoundedInteger number
        _                   -> Nothing

resourceFieldText :: Text -> FrontendSurfaceResourceValue -> Maybe Text
resourceFieldText fieldName value = do
    raw <- resourceField fieldName value
    case raw of
        Aeson.String text -> Just text
        _                 -> Nothing

resourceField :: Text -> FrontendSurfaceResourceValue -> Maybe Aeson.Value
resourceField fieldName value = case value.resourceValueFields of
    Aeson.Object object -> Aeson.KeyMap.lookup (Aeson.Key.fromText fieldName) object
    _ -> Nothing

resource :: Text -> [Aeson.Types.Pair] -> FrontendSurfaceResourceValue
resource name fields = FrontendSurfaceResourceValue
    { resourceValueName = name
    , resourceValueFields = Aeson.object fields
    }

uuid :: UUID.UUID -> Text
uuid = UUID.toText
