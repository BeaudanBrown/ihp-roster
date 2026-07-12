{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications    #-}

module Application.Helper.FrontendContract.Surface.Resource
    ( FrontendSurfaceResourceDefinition (..)
    , SurfaceResourceValue (..)
    , adminExportsResource
    , adminInvitesResource
    , adminRosterGroupsResource
    , adminShiftTypesResource
    , adminVenueSettingsResource
    , billingResource
    , frontendSurfaceResourceDefinitions
    , archivedLeaveRequestsResource
    , approvedLeaveRequestsResource
    , deniedLeaveRequestsResource
    , leaveRequestsSectionResource
    , pendingLeaveRequestsResource
    , resource
    , resourceFieldInt
    , resourceFieldIntFor
    , resourceFieldUuidFor
    , resourceForSurface
    , resourceMatchesFor
    , resourceFieldText
    , resourceFieldUuid
    , resourceMatches
    , rosterDayResource
    , rosterEndTimesConfigResource
    , rosterWeekBoundaryConfigResource
    , rosterWeekResource
    , staffLeaveRequestsResource
    , staffPreferencesResource
    , staffProfileResource
    , staffRsaDocumentsResource
    , supportAwardRatesResource
    , supportPublicHolidaysResource
    , timesheetDayResource
    , timesheetWeekBoundaryConfigResource
    , timesheetWeekResource
    , timePickerConfigResource
    , xeroConnectionResource
    , xeroMappingsResource
    , xeroPayItemsResource
    , xeroTimesheetsResource
    ) where

import qualified Application.Helper.FrontendContract.Surface.ContractIR as SurfaceIR
import qualified Application.Helper.FrontendContract.Surface.LeaveRequests as LeaveRequestsSurface
import qualified Application.Helper.FrontendContract.Surface.Profile as ProfileSurface
import Application.Helper.FrontendContract.Surface.Reflect (ReflectResource,
                                                            reflectRegisteredFrontendSurfaces)
import qualified Application.Helper.FrontendContract.Surface.Roster as RosterSurface
import qualified Application.Helper.FrontendContract.Surface.Support as SupportSurface
import qualified Application.Helper.FrontendContract.Surface.Timesheets as TimesheetsSurface
import Application.Helper.FrontendContract.Surface.Values
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as Aeson.Key
import qualified Data.Aeson.KeyMap as Aeson.KeyMap
import qualified Data.Aeson.Types as Aeson.Types
import qualified Data.List as List
import qualified Data.Scientific as Scientific
import Data.Typeable (Typeable)
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
data SurfaceResourceValue = SurfaceResourceValue
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

pendingLeaveRequestsResource, approvedLeaveRequestsResource, deniedLeaveRequestsResource, archivedLeaveRequestsResource, staffLeaveRequestsResource, staffProfileResource, staffPreferencesResource, staffRsaDocumentsResource, rosterDayResource, adminVenueSettingsResource, rosterEndTimesConfigResource, rosterWeekBoundaryConfigResource, timesheetWeekBoundaryConfigResource, timePickerConfigResource, adminRosterGroupsResource, adminShiftTypesResource, adminInvitesResource, adminExportsResource, billingResource, xeroConnectionResource, xeroMappingsResource, xeroPayItemsResource, xeroTimesheetsResource :: UUID.UUID -> SurfaceResourceValue
pendingLeaveRequestsResource venueId = leaveRequestsSectionResource venueId "pending"
approvedLeaveRequestsResource venueId = leaveRequestsSectionResource venueId "approved"
deniedLeaveRequestsResource venueId = leaveRequestsSectionResource venueId "denied"
archivedLeaveRequestsResource venueId = leaveRequestsSectionResource venueId "archive"
staffLeaveRequestsResource staffId =
    resourceForSurface @ProfileSurface.ProfileSurface @ProfileSurface.StaffLeaveRequests
        (surfaceField @ProfileSurface.StaffId staffId :& NoSurfaceFields)
staffProfileResource staffId =
    resourceForSurface @ProfileSurface.ProfileSurface @ProfileSurface.StaffProfile
        (surfaceField @ProfileSurface.StaffId staffId :& NoSurfaceFields)
staffPreferencesResource staffId =
    resourceForSurface @ProfileSurface.ProfileSurface @ProfileSurface.StaffPreferences
        (surfaceField @ProfileSurface.StaffId staffId :& NoSurfaceFields)
staffRsaDocumentsResource staffId =
    resourceForSurface @ProfileSurface.ProfileSurface @ProfileSurface.StaffRsaDocuments
        (surfaceField @ProfileSurface.StaffId staffId :& NoSurfaceFields)
rosterDayResource rosterDayId =
    resourceForSurface @RosterSurface.RosterSurface @RosterSurface.RosterDay
        (surfaceField @RosterSurface.RosterDayId rosterDayId :& NoSurfaceFields)
adminVenueSettingsResource venueId = resource "admin-venue-settings" ["venueId" Aeson..= uuid venueId]
rosterEndTimesConfigResource venueId =
    resourceForSurface @RosterSurface.RosterSurface @RosterSurface.RosterEndTimesConfig
        (surfaceField @RosterSurface.VenueId venueId :& NoSurfaceFields)
rosterWeekBoundaryConfigResource venueId =
    resourceForSurface @RosterSurface.RosterSurface @RosterSurface.RosterWeekBoundaryConfig
        (surfaceField @RosterSurface.VenueId venueId :& NoSurfaceFields)
timesheetWeekBoundaryConfigResource venueId = resource "timesheet-week-boundary-config" ["venueId" Aeson..= uuid venueId]
timePickerConfigResource venueId = resource "time-picker-config" ["venueId" Aeson..= uuid venueId]
adminRosterGroupsResource venueId = resource "admin-roster-groups" ["venueId" Aeson..= uuid venueId]
adminShiftTypesResource venueId = resource "admin-shift-types" ["venueId" Aeson..= uuid venueId]
adminInvitesResource venueId = resource "admin-invites" ["venueId" Aeson..= uuid venueId]
adminExportsResource venueId = resource "admin-exports" ["venueId" Aeson..= uuid venueId]
billingResource venueId = resource "billing" ["venueId" Aeson..= uuid venueId]
xeroConnectionResource venueId = resource "xero-connection" ["venueId" Aeson..= uuid venueId]
xeroMappingsResource venueId = resource "xero-mappings" ["venueId" Aeson..= uuid venueId]
xeroPayItemsResource venueId = resource "xero-pay-items" ["venueId" Aeson..= uuid venueId]
xeroTimesheetsResource venueId = resource "xero-timesheets" ["venueId" Aeson..= uuid venueId]

timesheetWeekResource :: UUID.UUID -> Int -> SurfaceResourceValue
timesheetWeekResource venueId weekOffset =
    resourceForSurface @TimesheetsSurface.TimesheetsSurface @TimesheetsSurface.TimesheetWeek
        ( surfaceField @TimesheetsSurface.VenueId venueId
            :& surfaceField @TimesheetsSurface.WeekOffset weekOffset
            :& NoSurfaceFields
        )

timesheetDayResource :: UUID.UUID -> Int -> Int -> SurfaceResourceValue
timesheetDayResource venueId weekOffset dayOffset =
    resourceForSurface @TimesheetsSurface.TimesheetsSurface @TimesheetsSurface.TimesheetDay
        ( surfaceField @TimesheetsSurface.VenueId venueId
            :& surfaceField @TimesheetsSurface.WeekOffset weekOffset
            :& surfaceField @TimesheetsSurface.DayOffset dayOffset
            :& NoSurfaceFields
        )

leaveRequestsSectionResource :: UUID.UUID -> Text -> SurfaceResourceValue
leaveRequestsSectionResource venueId section =
    resourceForSurface @LeaveRequestsSurface.LeaveRequestsSurface @LeaveRequestsSurface.LeaveRequestsSection
        ( surfaceField @LeaveRequestsSurface.VenueId venueId
            :& surfaceField @LeaveRequestsSurface.LeaveSection section
            :& NoSurfaceFields
        )

rosterWeekResource :: UUID.UUID -> Int -> SurfaceResourceValue
rosterWeekResource rosterGroupId weekOffset =
    resourceForSurface @RosterSurface.RosterSurface @RosterSurface.RosterWeek
        ( surfaceField @RosterSurface.RosterGroupId rosterGroupId
            :& surfaceField @RosterSurface.WeekOffset weekOffset
            :& NoSurfaceFields
        )

supportAwardRatesResource, supportPublicHolidaysResource :: SurfaceResourceValue
supportAwardRatesResource =
    resourceForSurface @SupportSurface.SupportSurface @SupportSurface.SupportAwardRates NoSurfaceFields
supportPublicHolidaysResource =
    resourceForSurface @SupportSurface.SupportSurface @SupportSurface.SupportPublicHolidays NoSurfaceFields

resourceForSurface ::
    forall spec marker.
    ReflectResource (SurfaceResourceSpec spec marker) =>
    SurfaceFields (SurfaceResourceFieldSpecs spec marker) ->
    SurfaceResourceValue
resourceForSurface fields =
    SurfaceResourceValue
        { resourceValueName = (surfaceResourceValue @spec @marker).resourceName
        , resourceValueFields = surfaceFieldsJson fields
        }

resourceMatchesFor ::
    forall spec marker.
    ReflectResource (SurfaceResourceSpec spec marker) =>
    SurfaceResourceValue ->
    Bool
resourceMatchesFor value =
    value.resourceValueName == (surfaceResourceValue @spec @marker).resourceName

resourceFieldUuidFor ::
    forall spec resourceMarker fieldMarker.
    ( Typeable fieldMarker
    , RequireSurfaceField resourceMarker fieldMarker (SurfaceResourceFieldSpecs spec resourceMarker)
    ) =>
    SurfaceResourceValue ->
    Maybe UUID.UUID
resourceFieldUuidFor =
    resourceFieldUuid (surfaceResourceFieldName @spec @resourceMarker @fieldMarker)

resourceFieldIntFor ::
    forall spec resourceMarker fieldMarker.
    ( Typeable fieldMarker
    , RequireSurfaceField resourceMarker fieldMarker (SurfaceResourceFieldSpecs spec resourceMarker)
    ) =>
    SurfaceResourceValue ->
    Maybe Int
resourceFieldIntFor =
    resourceFieldInt (surfaceResourceFieldName @spec @resourceMarker @fieldMarker)

resourceMatches :: Text -> SurfaceResourceValue -> Bool
resourceMatches name value = value.resourceValueName == name

resourceFieldUuid :: Text -> SurfaceResourceValue -> Maybe UUID.UUID
resourceFieldUuid fieldName value = do
    text <- resourceFieldText fieldName value
    UUID.fromText text

resourceFieldInt :: Text -> SurfaceResourceValue -> Maybe Int
resourceFieldInt fieldName value = do
    raw <- resourceField fieldName value
    case raw of
        Aeson.Number number -> Scientific.toBoundedInteger number
        _                   -> Nothing

resourceFieldText :: Text -> SurfaceResourceValue -> Maybe Text
resourceFieldText fieldName value = do
    raw <- resourceField fieldName value
    case raw of
        Aeson.String text -> Just text
        _                 -> Nothing

resourceField :: Text -> SurfaceResourceValue -> Maybe Aeson.Value
resourceField fieldName value = case value.resourceValueFields of
    Aeson.Object object -> Aeson.KeyMap.lookup (Aeson.Key.fromText fieldName) object
    _ -> Nothing

resource :: Text -> [Aeson.Types.Pair] -> SurfaceResourceValue
resource name fields = SurfaceResourceValue
    { resourceValueName = name
    , resourceValueFields = Aeson.object fields
    }

uuid :: UUID.UUID -> Text
uuid = UUID.toText
