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
    , adminShiftTypesSurfaceImpl
    , adminRosterGroupsSurfaceImpl
    , adminXeroSurfaceImpl
    , adminVenueSettingsFragment
    , adminInvitesFragment
    , adminExportsFragment
    , adminShiftTypesFragment
    , adminRosterGroupsFragment
    , adminXeroShellFragment
    , adminShiftTypesFragmentKeys
    , adminRosterGroupsFragmentKeys
    , adminXeroFragmentKeys
    ) where

import qualified Application.Helper.FrontendContract.Surface.Admin as Surface
import Application.Helper.FrontendContract.Surface.DSL (FieldSpec (..),
                                                        WireType (..))
import Application.Helper.FrontendContract.Surface.Runtime
import Application.Helper.FrontendContract.Surface.Values
import Application.Helper.LiveUpdate.Runtime (SurfaceFragmentKey)
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
        NoSurfaceFields
        [adminPageContentFragment]

adminXeroPageSurfaceImpl :: AdminVenueScopeValue -> SurfaceImpl Surface.AdminXeroPageSurface
adminXeroPageSurfaceImpl scope =
    mkSurfaceImplFromValues @Surface.AdminXeroPageSurface @Surface.AdminXeroPageScope
        "primary"
        (adminVenueScopeFields scope)
        NoSurfaceFields
        [adminXeroPageContentFragment]

adminVenueSettingsSurfaceImpl :: AdminVenueScopeValue -> SurfaceImpl Surface.AdminVenueSettingsSurface
adminVenueSettingsSurfaceImpl scope =
    mkSurfaceImplFromValues @Surface.AdminVenueSettingsSurface @Surface.AdminVenueConfigScope
        "primary"
        (adminVenueScopeFields scope)
        NoSurfaceFields
        [adminVenueSettingsFragment]

adminInvitesSurfaceImpl :: AdminVenueScopeValue -> SurfaceImpl Surface.AdminInvitesSurface
adminInvitesSurfaceImpl scope =
    mkSurfaceImplFromValues @Surface.AdminInvitesSurface @Surface.AdminInvitesScope
        "primary"
        (adminVenueScopeFields scope)
        NoSurfaceFields
        [adminInvitesFragment scope.adminRosterGroupId]

adminExportsSurfaceImpl :: AdminVenueScopeValue -> SurfaceImpl Surface.AdminExportsSurface
adminExportsSurfaceImpl scope =
    mkSurfaceImplFromValues @Surface.AdminExportsSurface @Surface.AdminExportsScope
        "primary"
        (adminVenueScopeFields scope)
        NoSurfaceFields
        [adminExportsFragment]

adminShiftTypesSurfaceImpl :: AdminVenueScopeValue -> SurfaceImpl Surface.AdminShiftTypesSurface
adminShiftTypesSurfaceImpl scope =
    mkSurfaceImplFromValues @Surface.AdminShiftTypesSurface @Surface.AdminShiftTypesScope
        "primary"
        (adminVenueScopeFields scope)
        NoSurfaceFields
        [adminShiftTypesFragment]

adminRosterGroupsSurfaceImpl :: AdminVenueScopeValue -> SurfaceImpl Surface.AdminRosterGroupsSurface
adminRosterGroupsSurfaceImpl scope =
    mkSurfaceImplFromValues @Surface.AdminRosterGroupsSurface @Surface.AdminRosterGroupsScope
        "primary"
        (adminVenueScopeFields scope)
        NoSurfaceFields
        [adminRosterGroupsFragment]

adminXeroSurfaceImpl :: AdminVenueScopeValue -> SurfaceImpl Surface.AdminXeroSurface
adminXeroSurfaceImpl scope =
    mkSurfaceImplFromValues @Surface.AdminXeroSurface @Surface.AdminXeroScope
        "primary"
        (adminVenueScopeFields scope)
        NoSurfaceFields
        [adminXeroShellFragment]

adminVenueScopeFields :: AdminVenueScopeValue -> SurfaceFields '[ 'Field Surface.VenueId 'WireUUID]
adminVenueScopeFields scope =
    surfaceField @Surface.VenueId scope.adminVenueId :& NoSurfaceFields

adminPageContentFragment :: FrontendSurfaceMountedFragment
adminPageContentFragment =
    frontendSurfaceMountedFragmentFor @Surface.AdminPageSurface @Surface.AdminPageContentFragment
        NoSurfaceFields
        NoSurfaceFields
        (pathTo AdminAction)
        FrontendSurfaceReplace

adminXeroPageContentFragment :: FrontendSurfaceMountedFragment
adminXeroPageContentFragment =
    frontendSurfaceMountedFragmentFor @Surface.AdminXeroPageSurface @Surface.AdminXeroPageContentFragment
        NoSurfaceFields
        NoSurfaceFields
        (pathTo XeroAction)
        FrontendSurfaceReplace

adminVenueSettingsFragment :: FrontendSurfaceMountedFragment
adminVenueSettingsFragment =
    frontendSurfaceMountedFragmentFor @Surface.AdminVenueSettingsSurface @Surface.AdminVenueSettingsFragment
        NoSurfaceFields
        NoSurfaceFields
        (pathTo ShowAdminVenueSettingsFragmentAction)
        FrontendSurfaceReplace

adminInvitesFragment :: Maybe UUID.UUID -> FrontendSurfaceMountedFragment
adminInvitesFragment maybeRosterGroupId =
    frontendSurfaceMountedFragmentFor @Surface.AdminInvitesSurface @Surface.AdminInvitesFragment
        NoSurfaceFields
        NoSurfaceFields
        (appendQueryParams (pathTo ShowadminInvitesLiveFragmentAction) query)
        FrontendSurfaceReplace
  where
    query = maybe [] (\rosterGroupId -> [("rosterGroupId", tshow rosterGroupId)]) maybeRosterGroupId

adminExportsFragment :: FrontendSurfaceMountedFragment
adminExportsFragment =
    frontendSurfaceMountedFragmentFor @Surface.AdminExportsSurface @Surface.AdminExportsFragment
        NoSurfaceFields
        NoSurfaceFields
        (pathTo ShowadminExportsLiveFragmentAction)
        FrontendSurfaceReplace

adminShiftTypesFragment :: FrontendSurfaceMountedFragment
adminShiftTypesFragment =
    frontendSurfaceMountedFragmentFor @Surface.AdminShiftTypesSurface @Surface.AdminShiftTypesFragment
        NoSurfaceFields
        NoSurfaceFields
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
        NoSurfaceFields
        NoSurfaceFields
        (pathTo ShowadminRosterGroupsLiveFragmentAction)
        FrontendSurfaceReplace

adminXeroShellFragment :: FrontendSurfaceMountedFragment
adminXeroShellFragment =
    frontendSurfaceMountedFragmentFor @Surface.AdminXeroSurface @Surface.AdminXeroShellFragment
        NoSurfaceFields
        NoSurfaceFields
        (pathTo ShowadminXeroShellLiveFragmentAction)
        FrontendSurfaceReplace

adminShiftTypesFragmentKeys :: [FrontendSurfaceMountedFragment] -> [SurfaceFragmentKey]
adminShiftTypesFragmentKeys =
    frontendSurfaceMountedFragmentsToKeysFor @Surface.AdminShiftTypesSurface

adminRosterGroupsFragmentKeys :: [FrontendSurfaceMountedFragment] -> [SurfaceFragmentKey]
adminRosterGroupsFragmentKeys =
    frontendSurfaceMountedFragmentsToKeysFor @Surface.AdminRosterGroupsSurface

adminXeroFragmentKeys :: [FrontendSurfaceMountedFragment] -> [SurfaceFragmentKey]
adminXeroFragmentKeys =
    frontendSurfaceMountedFragmentsToKeysFor @Surface.AdminXeroSurface
