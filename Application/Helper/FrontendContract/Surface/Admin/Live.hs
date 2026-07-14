{-# LANGUAGE TypeApplications #-}

module Application.Helper.FrontendContract.Surface.Admin.Live
    ( adminExportsLiveFragment
    , adminExportsLiveScope
    , adminInvitesLiveFragment
    , adminInvitesLiveScope
    , adminPageContentFragmentKey
    , adminPageLiveScope
    , adminRosterGroupsLiveFragment
    , adminRosterGroupsLiveScope
    , adminShiftTypesLiveFragment
    , adminShiftTypesLiveScope
    , adminVenueConfigLiveFragment
    , adminVenueConfigLiveScope
    , adminXeroLiveScope
    , adminXeroPageContentFragmentKey
    , adminXeroPageLiveScope
    , adminXeroShellLiveFragment
    ) where

import qualified Application.Helper.FrontendContract.Surface.Admin as Surface
import Application.Helper.FrontendContract.Surface.Live
import Application.Helper.FrontendContract.Surface.Values
import qualified Data.UUID as UUID
import IHP.Prelude

adminPageLiveScope, adminXeroPageLiveScope, adminVenueConfigLiveScope, adminInvitesLiveScope, adminExportsLiveScope, adminShiftTypesLiveScope, adminRosterGroupsLiveScope, adminXeroLiveScope :: UUID.UUID -> SurfaceScope
adminPageLiveScope venueId =
    frontendSurfaceScope @Surface.AdminPageSurface @Surface.AdminPageScope (venueFields venueId)
adminXeroPageLiveScope venueId =
    frontendSurfaceScope @Surface.AdminXeroPageSurface @Surface.AdminXeroPageScope (venueFields venueId)
adminVenueConfigLiveScope venueId =
    frontendSurfaceScope @Surface.AdminVenueSettingsSurface @Surface.AdminVenueConfigScope (venueFields venueId)
adminInvitesLiveScope venueId =
    frontendSurfaceScope @Surface.AdminInvitesSurface @Surface.AdminInvitesScope (venueFields venueId)
adminExportsLiveScope venueId =
    frontendSurfaceScope @Surface.AdminExportsSurface @Surface.AdminExportsScope (venueFields venueId)
adminShiftTypesLiveScope venueId =
    frontendSurfaceScope @Surface.AdminShiftTypesSurface @Surface.AdminShiftTypesScope (venueFields venueId)
adminRosterGroupsLiveScope venueId =
    frontendSurfaceScope @Surface.AdminRosterGroupsSurface @Surface.AdminRosterGroupsScope (venueFields venueId)
adminXeroLiveScope venueId =
    frontendSurfaceScope @Surface.AdminXeroSurface @Surface.AdminXeroScope (venueFields venueId)

venueFields :: UUID.UUID -> SurfaceFields (SurfaceScopeFieldSpecs Surface.AdminPageSurface Surface.AdminPageScope)
venueFields venueId = surfaceField @Surface.VenueId venueId :& NoSurfaceFields

adminPageContentFragmentKey, adminXeroPageContentFragmentKey, adminVenueConfigLiveFragment, adminInvitesLiveFragment, adminExportsLiveFragment, adminShiftTypesLiveFragment, adminRosterGroupsLiveFragment, adminXeroShellLiveFragment :: SurfaceFragmentKey
adminPageContentFragmentKey = frontendSurfaceFragmentKey @Surface.AdminPageSurface @Surface.AdminPageContentFragment NoSurfaceFields
adminXeroPageContentFragmentKey = frontendSurfaceFragmentKey @Surface.AdminXeroPageSurface @Surface.AdminXeroPageContentFragment NoSurfaceFields
adminVenueConfigLiveFragment = frontendSurfaceFragmentKey @Surface.AdminVenueSettingsSurface @Surface.AdminVenueSettingsFragment NoSurfaceFields
adminInvitesLiveFragment = frontendSurfaceFragmentKey @Surface.AdminInvitesSurface @Surface.AdminInvitesFragment NoSurfaceFields
adminExportsLiveFragment = frontendSurfaceFragmentKey @Surface.AdminExportsSurface @Surface.AdminExportsFragment NoSurfaceFields
adminShiftTypesLiveFragment = frontendSurfaceFragmentKey @Surface.AdminShiftTypesSurface @Surface.AdminShiftTypesFragment NoSurfaceFields
adminRosterGroupsLiveFragment = frontendSurfaceFragmentKey @Surface.AdminRosterGroupsSurface @Surface.AdminRosterGroupsFragment NoSurfaceFields
adminXeroShellLiveFragment = frontendSurfaceFragmentKey @Surface.AdminXeroSurface @Surface.AdminXeroShellFragment NoSurfaceFields
