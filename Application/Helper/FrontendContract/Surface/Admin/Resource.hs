{-# LANGUAGE TypeApplications #-}

module Application.Helper.FrontendContract.Surface.Admin.Resource
    ( adminExportsResource
    , adminInvitesResource
    , adminRosterGroupsResource
    , adminShiftTypesResource
    , adminVenueSettingsResource
    , xeroConnectionResource
    ) where

import qualified Application.Helper.FrontendContract.Surface.Admin as Surface
import Application.Helper.FrontendContract.Surface.Resource
import Application.Helper.FrontendContract.Surface.Values
import qualified Data.UUID as UUID
import IHP.Prelude

adminVenueSettingsResource, adminInvitesResource, adminExportsResource, adminShiftTypesResource, adminRosterGroupsResource, xeroConnectionResource :: UUID.UUID -> SurfaceResourceValue
adminVenueSettingsResource venueId =
    frontendSurfaceResource @Surface.AdminVenueSettingsSurface @Surface.AdminVenueSettings
        (surfaceField @Surface.VenueId venueId :& NoSurfaceFields)
adminInvitesResource venueId =
    frontendSurfaceResource @Surface.AdminInvitesSurface @Surface.AdminInvites
        (surfaceField @Surface.VenueId venueId :& NoSurfaceFields)
adminExportsResource venueId =
    frontendSurfaceResource @Surface.AdminExportsSurface @Surface.AdminExports
        (surfaceField @Surface.VenueId venueId :& NoSurfaceFields)
adminShiftTypesResource venueId =
    frontendSurfaceResource @Surface.AdminShiftTypesSurface @Surface.AdminShiftTypes
        (surfaceField @Surface.VenueId venueId :& NoSurfaceFields)
adminRosterGroupsResource venueId =
    frontendSurfaceResource @Surface.AdminRosterGroupsSurface @Surface.AdminRosterGroups
        (surfaceField @Surface.VenueId venueId :& NoSurfaceFields)
xeroConnectionResource venueId =
    frontendSurfaceResource @Surface.AdminXeroSurface @Surface.XeroConnection
        (surfaceField @Surface.VenueId venueId :& NoSurfaceFields)
