{-# LANGUAGE DataKinds        #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators    #-}

module Web.Admin.FrontendSurface
    ( AdminVenueScopeValue (..)
    , adminPageSurfaceImpl
    , adminXeroPageSurfaceImpl
    , adminVenueSettingsSurfaceImpl
    , adminInvitesSurfaceImpl
    , adminExportsSurfaceImpl
    , adminExportsSurfaceImplForWeek
    , adminShiftTypesSurfaceImpl
    , adminRosterGroupsSurfaceImpl
    , adminXeroSurfaceImpl
    , adminVenueSettingsFragment
    , adminInvitesFragment
    , adminShiftTypesFragment
    , adminRosterGroupsFragment
    , adminXeroShellFragment
    , adminRosterGroupsFragmentKeys
    , adminXeroFragmentKeys
    ) where

import qualified Application.Helper.FrontendContract.Surface.Admin as Surface
import Application.Helper.FrontendContract.Surface.DSL (FieldSpec (..),
                                                        WireType (..))
import Application.Helper.FrontendContract.Surface.Live (SurfaceFragmentKey)
import Application.Helper.FrontendContract.Surface.Runtime
import Application.Helper.FrontendContract.Surface.Values
import Application.Helper.Url (appendQueryParams)
import qualified Data.UUID as UUID
import Web.Controller.Prelude

data AdminVenueScopeValue = AdminVenueScopeValue
    { adminVenueId       :: !UUID.UUID
    , adminRosterGroupId :: !(Maybe UUID.UUID)
    }
    deriving (Eq, Show)

adminPageSurfaceImpl :: AdminVenueScopeValue -> SurfaceImpl Surface.AdminPageSurface
adminPageSurfaceImpl scope =
    mkSurfaceImplFromValues @Surface.AdminPageSurface @Surface.AdminPageScope
        "primary"
        (adminVenueScopeFields scope)
        noSurfaceFields
        [adminPageContentFragment]

adminXeroPageSurfaceImpl :: AdminVenueScopeValue -> SurfaceImpl Surface.AdminXeroPageSurface
adminXeroPageSurfaceImpl scope =
    mkSurfaceImplFromValues @Surface.AdminXeroPageSurface @Surface.AdminXeroPageScope
        "primary"
        (adminVenueScopeFields scope)
        noSurfaceFields
        [adminXeroPageContentFragment]

adminVenueSettingsSurfaceImpl :: AdminVenueScopeValue -> SurfaceImpl Surface.AdminVenueSettingsSurface
adminVenueSettingsSurfaceImpl scope =
    mkSurfaceImplFromValues @Surface.AdminVenueSettingsSurface @Surface.AdminVenueConfigScope
        "primary"
        (adminVenueScopeFields scope)
        noSurfaceFields
        [adminVenueSettingsFragment]

adminInvitesSurfaceImpl :: AdminVenueScopeValue -> SurfaceImpl Surface.AdminInvitesSurface
adminInvitesSurfaceImpl scope =
    mkSurfaceImplFromValues @Surface.AdminInvitesSurface @Surface.AdminInvitesScope
        "primary"
        (adminVenueScopeFields scope)
        noSurfaceFields
        [adminInvitesFragment scope.adminRosterGroupId]

adminExportsSurfaceImpl :: AdminVenueScopeValue -> SurfaceImpl Surface.AdminExportsSurface
adminExportsSurfaceImpl scope = adminExportsSurfaceImplForWeek scope 0

adminExportsSurfaceImplForWeek :: AdminVenueScopeValue -> Int -> SurfaceImpl Surface.AdminExportsSurface
adminExportsSurfaceImplForWeek scope weekOffset =
    mkSurfaceImplFromValues @Surface.AdminExportsSurface @Surface.AdminExportsScope
        "primary"
        (adminVenueScopeFields scope)
        noSurfaceFields
        [adminExportsFragmentForWeek weekOffset]

adminShiftTypesSurfaceImpl :: AdminVenueScopeValue -> SurfaceImpl Surface.AdminShiftTypesSurface
adminShiftTypesSurfaceImpl scope =
    mkSurfaceImplFromValues @Surface.AdminShiftTypesSurface @Surface.AdminShiftTypesScope
        "primary"
        (adminVenueScopeFields scope)
        noSurfaceFields
        [adminShiftTypesFragment]

adminRosterGroupsSurfaceImpl :: AdminVenueScopeValue -> SurfaceImpl Surface.AdminRosterGroupsSurface
adminRosterGroupsSurfaceImpl scope =
    mkSurfaceImplFromValues @Surface.AdminRosterGroupsSurface @Surface.AdminRosterGroupsScope
        "primary"
        (adminVenueScopeFields scope)
        noSurfaceFields
        [adminRosterGroupsFragment]

adminXeroSurfaceImpl :: AdminVenueScopeValue -> SurfaceImpl Surface.AdminXeroSurface
adminXeroSurfaceImpl scope =
    mkSurfaceImplFromValues @Surface.AdminXeroSurface @Surface.AdminXeroScope
        "primary"
        (adminVenueScopeFields scope)
        noSurfaceFields
        [adminXeroShellFragment]

adminVenueScopeFields :: AdminVenueScopeValue -> SurfaceFields '[ 'Field Surface.VenueId 'WireUUID]
adminVenueScopeFields scope =
    surfaceField @Surface.VenueId scope.adminVenueId &: noSurfaceFields

adminPageContentFragment :: FrontendSurfaceMountedFragment
adminPageContentFragment =
    frontendSurfaceMountedFragmentFor @Surface.AdminPageSurface @Surface.AdminPageContentFragment
        noSurfaceFields
        noSurfaceFields
        (pathTo AdminAction)
        FrontendSurfaceReplace

adminXeroPageContentFragment :: FrontendSurfaceMountedFragment
adminXeroPageContentFragment =
    frontendSurfaceMountedFragmentFor @Surface.AdminXeroPageSurface @Surface.AdminXeroPageContentFragment
        noSurfaceFields
        noSurfaceFields
        (pathTo XeroAction)
        FrontendSurfaceReplace

adminVenueSettingsFragment :: FrontendSurfaceMountedFragment
adminVenueSettingsFragment =
    frontendSurfaceMountedFragmentFor @Surface.AdminVenueSettingsSurface @Surface.AdminVenueSettingsFragment
        noSurfaceFields
        noSurfaceFields
        (pathTo ShowAdminVenueSettingsFragmentAction)
        FrontendSurfaceReplace

adminInvitesFragment :: Maybe UUID.UUID -> FrontendSurfaceMountedFragment
adminInvitesFragment maybeRosterGroupId =
    frontendSurfaceMountedFragmentFor @Surface.AdminInvitesSurface @Surface.AdminInvitesFragment
        noSurfaceFields
        noSurfaceFields
        (appendQueryParams (pathTo ShowadminInvitesLiveFragmentAction) query)
        FrontendSurfaceReplace
  where
    query = maybe [] (\rosterGroupId -> [("rosterGroupId", tshow rosterGroupId)]) maybeRosterGroupId


adminExportsFragmentForWeek :: Int -> FrontendSurfaceMountedFragment
adminExportsFragmentForWeek weekOffset =
    frontendSurfaceMountedFragmentFor @Surface.AdminExportsSurface @Surface.AdminExportsFragment
        noSurfaceFields
        noSurfaceFields
        (appendQueryParams (pathTo ShowadminExportsLiveFragmentAction) [("weekOffset", tshow weekOffset)])
        FrontendSurfaceReplace

adminShiftTypesFragment :: FrontendSurfaceMountedFragment
adminShiftTypesFragment =
    frontendSurfaceMountedFragmentFor @Surface.AdminShiftTypesSurface @Surface.AdminShiftTypesFragment
        noSurfaceFields
        noSurfaceFields
        (pathTo ShowadminShiftTypesLiveFragmentAction)
        ( FrontendSurfaceFocusedFieldConfig
            FrontendSurfaceFocusedFieldProtectionConfig
                { focusedProtectionActiveSelector = "input[data-admin-shift-type-field-key]:focus"
                , focusedProtectionFieldKeyAttr = "data-admin-shift-type-field-key"
                , focusedProtectionFieldNameFallback = True
                , focusedProtectionContainerSelector = Just "form[data-admin-shift-type-row]"
                }
        )

adminRosterGroupsFragment :: FrontendSurfaceMountedFragment
adminRosterGroupsFragment =
    frontendSurfaceMountedFragmentFor @Surface.AdminRosterGroupsSurface @Surface.AdminRosterGroupsFragment
        noSurfaceFields
        noSurfaceFields
        (pathTo ShowadminRosterGroupsLiveFragmentAction)
        FrontendSurfaceReplace

adminXeroShellFragment :: FrontendSurfaceMountedFragment
adminXeroShellFragment =
    frontendSurfaceMountedFragmentFor @Surface.AdminXeroSurface @Surface.AdminXeroShellFragment
        noSurfaceFields
        noSurfaceFields
        (pathTo ShowadminXeroShellLiveFragmentAction)
        FrontendSurfaceReplace


adminRosterGroupsFragmentKeys :: [FrontendSurfaceMountedFragment] -> [SurfaceFragmentKey]
adminRosterGroupsFragmentKeys = map (.mountedFragmentKey)

adminXeroFragmentKeys :: [FrontendSurfaceMountedFragment] -> [SurfaceFragmentKey]
adminXeroFragmentKeys = map (.mountedFragmentKey)
