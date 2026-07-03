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
    , adminVenueSettingsAffectedFragments
    , adminInvitesAffectedFragments
    , adminExportsAffectedFragments
    , adminShiftTypesAffectedFragments
    , adminRosterGroupsAffectedFragments
    , adminXeroAffectedFragments
    , adminVenueSettingsFragment
    , adminInvitesFragment
    , adminExportsFragment
    , adminShiftTypesFragment
    , adminRosterGroupsFragment
    , adminSurfaceWireFragments
    , setAdminXeroActorRefresh
    , adminXeroShellFragment
    , adminXeroStaffMappingsFragment
    , adminXeroPayItemsFragment
    , adminXeroTimesheetsFragment
    ) where

import Application.Helper.Frontend.AppConstants (AppEvents (..),
                                                 canonicalAppEvents)
import qualified Application.Helper.FrontendSurface.Admin as Surface
import Application.Helper.FrontendSurface.DSL
import Application.Helper.FrontendSurface.Runtime
import Application.Helper.LiveResource
import Application.Helper.LiveUpdate.Runtime
import Application.Helper.Url (appendQueryParams)
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as AesonKey
import qualified Data.Set as Set
import qualified Data.Text as Text
import qualified Data.UUID as UUID
import Web.Controller.Prelude

data AdminVenueScopeValue = AdminVenueScopeValue
    { adminVenueId       :: !UUID.UUID
    , adminRosterGroupId :: !(Maybe UUID.UUID)
    }
    deriving (Eq, Show)

adminPageSurfaceImpl :: AdminVenueScopeValue -> SurfaceImpl Surface.AdminPageSurface
adminPageSurfaceImpl scope =
    let config = FrontendSurfaceMountConfig
            { mountSurfaceName = "admin-page"
            , mountScopeKey = "admin-page:" <> tshow scope.adminVenueId
            , mountKey = "primary"
        , mountScope = Aeson.Null
        , mountSubscription = Nothing
            , mountState = Aeson.Null
            , mountFragments = [adminPageContentFragment]
            }
        impl = mkSurfaceImpl "admin-page" config (adminPageHandlers scope adminPageContentFragment)
     in impl

adminXeroPageSurfaceImpl :: AdminVenueScopeValue -> SurfaceImpl Surface.AdminXeroPageSurface
adminXeroPageSurfaceImpl scope =
    let config = FrontendSurfaceMountConfig
            { mountSurfaceName = "admin-xero-page"
            , mountScopeKey = "admin-xero-page:" <> tshow scope.adminVenueId
            , mountKey = "primary"
        , mountScope = Aeson.Null
        , mountSubscription = Nothing
            , mountState = Aeson.Null
            , mountFragments = [adminXeroPageContentFragment]
            }
        impl = mkSurfaceImpl "admin-xero-page" config (adminXeroPageHandlers scope adminXeroPageContentFragment)
     in impl

adminVenueSettingsSurfaceImpl :: AdminVenueScopeValue -> SurfaceImpl Surface.AdminVenueSettingsSurface
adminVenueSettingsSurfaceImpl scope =
    let config = mountConfig "admin-venue-config" scope [adminVenueSettingsFragment]
        impl = mkSurfaceImpl "admin-venue-config" config (unitHandlers scope adminVenueSettingsFragment)
     in impl

adminInvitesSurfaceImpl :: AdminVenueScopeValue -> SurfaceImpl Surface.AdminInvitesSurface
adminInvitesSurfaceImpl scope =
    let fragmentValue = adminInvitesFragment scope.adminRosterGroupId
        config = mountConfig "admin-invites" scope [fragmentValue]
        impl = mkSurfaceImpl "admin-invites" config (invitesHandlers scope fragmentValue)
     in impl

adminExportsSurfaceImpl :: AdminVenueScopeValue -> SurfaceImpl Surface.AdminExportsSurface
adminExportsSurfaceImpl scope =
    let config = mountConfig "admin-exports" scope [adminExportsFragment]
        impl = mkSurfaceImpl "admin-exports" config (unitHandlers scope adminExportsFragment)
     in impl

adminShiftTypesSurfaceImpl :: AdminVenueScopeValue -> SurfaceImpl Surface.AdminShiftTypesSurface
adminShiftTypesSurfaceImpl scope =
    let config = mountConfig "admin-shift-types" scope [adminShiftTypesFragment]
        impl = mkSurfaceImpl "admin-shift-types" config (unitHandlers scope adminShiftTypesFragment)
     in impl

adminRosterGroupsSurfaceImpl :: AdminVenueScopeValue -> SurfaceImpl Surface.AdminRosterGroupsSurface
adminRosterGroupsSurfaceImpl scope =
    let config = mountConfig "admin-roster-groups" scope [adminRosterGroupsFragment]
        impl = mkSurfaceImpl "admin-roster-groups" config (unitHandlers scope adminRosterGroupsFragment)
     in impl

adminXeroSurfaceImpl :: AdminVenueScopeValue -> SurfaceImpl Surface.AdminXeroSurface
adminXeroSurfaceImpl scope =
    let fragments = [adminXeroShellFragment, adminXeroStaffMappingsFragment, adminXeroPayItemsFragment, adminXeroTimesheetsFragment]
        config = mountConfig "admin-xero" scope fragments
        impl = mkSurfaceImpl "admin-xero" config (xeroHandlers scope)
     in impl

mountConfig :: Text -> AdminVenueScopeValue -> [FrontendSurfaceMountedFragment] -> FrontendSurfaceMountConfig
mountConfig name scope fragments =
    FrontendSurfaceMountConfig
        { mountSurfaceName = name
        , mountScopeKey = adminScopeKey name scope
        , mountKey = "primary"
        , mountScope = Aeson.Null
        , mountSubscription = Nothing
        , mountState = Aeson.Null
        , mountFragments = fragments
        }

adminScopeKey :: Text -> AdminVenueScopeValue -> Text
adminScopeKey name scope =
    name <> ":" <> tshow scope.adminVenueId <> maybe "" ((":" <>) . tshow) scope.adminRosterGroupId

adminPageHandlers :: AdminVenueScopeValue -> FrontendSurfaceMountedFragment -> SurfaceImplHandlers Surface.AdminPageSurface
adminPageHandlers scope fragment =
    SurfaceImplHandlers
        { surfaceScopeHandlers = scopeHandler scope `HandlerCons` HandlerNil
        , surfaceMountStateHandlers = HandlerNil
        , surfaceFragmentHandlers = FrontendSurfaceFragmentHandler
            { fragmentHandlerDefaultParams = frontendSurfaceFieldValues Aeson.Null
            , fragmentHandlerMountedFragment = const fragment
            , fragmentHandlerRender = const mempty
            } `HandlerCons` HandlerNil
        , surfaceActionHandlers = HandlerNil
        , surfaceIntentHandlers = HandlerNil
        }

adminXeroPageHandlers :: AdminVenueScopeValue -> FrontendSurfaceMountedFragment -> SurfaceImplHandlers Surface.AdminXeroPageSurface
adminXeroPageHandlers scope fragment =
    SurfaceImplHandlers
        { surfaceScopeHandlers = scopeHandler scope `HandlerCons` HandlerNil
        , surfaceMountStateHandlers = HandlerNil
        , surfaceFragmentHandlers = FrontendSurfaceFragmentHandler
            { fragmentHandlerDefaultParams = frontendSurfaceFieldValues Aeson.Null
            , fragmentHandlerMountedFragment = const fragment
            , fragmentHandlerRender = const mempty
            } `HandlerCons` HandlerNil
        , surfaceActionHandlers = HandlerNil
        , surfaceIntentHandlers = HandlerNil
        }

unitHandlers :: AdminVenueScopeValue -> FrontendSurfaceMountedFragment -> SurfaceImplHandlers ('Surface marker '[ 'Scope scopeMarker '[ 'Field Surface.VenueId 'WireUUID ] auth, 'Fragment fragment '[] policies])
unitHandlers scope fragment =
    SurfaceImplHandlers
        { surfaceScopeHandlers = scopeHandler scope `HandlerCons` HandlerNil
        , surfaceMountStateHandlers = HandlerNil
        , surfaceFragmentHandlers = FrontendSurfaceFragmentHandler
            { fragmentHandlerDefaultParams = frontendSurfaceFieldValues Aeson.Null
            , fragmentHandlerMountedFragment = const fragment
            , fragmentHandlerRender = const mempty
            } `HandlerCons` HandlerNil
        , surfaceActionHandlers = HandlerNil
        , surfaceIntentHandlers = HandlerNil
        }

invitesHandlers :: AdminVenueScopeValue -> FrontendSurfaceMountedFragment -> SurfaceImplHandlers Surface.AdminInvitesSurface
invitesHandlers scope fragment =
    SurfaceImplHandlers
        { surfaceScopeHandlers = invitesScopeHandler scope `HandlerCons` HandlerNil
        , surfaceMountStateHandlers = HandlerNil
        , surfaceFragmentHandlers = FrontendSurfaceFragmentHandler
            { fragmentHandlerDefaultParams = frontendSurfaceFieldValues Aeson.Null
            , fragmentHandlerMountedFragment = const fragment
            , fragmentHandlerRender = const mempty
            } `HandlerCons` HandlerNil
        , surfaceActionHandlers = HandlerNil
        , surfaceIntentHandlers = HandlerNil
        }

xeroHandlers :: AdminVenueScopeValue -> SurfaceImplHandlers Surface.AdminXeroSurface
xeroHandlers scope =
    SurfaceImplHandlers
        { surfaceScopeHandlers = scopeHandler scope `HandlerCons` HandlerNil
        , surfaceMountStateHandlers = HandlerNil
        , surfaceFragmentHandlers =
            fh adminXeroShellFragment `HandlerCons`
            fh adminXeroStaffMappingsFragment `HandlerCons`
            fh adminXeroPayItemsFragment `HandlerCons`
            fh adminXeroTimesheetsFragment `HandlerCons`
            HandlerNil
        , surfaceActionHandlers = HandlerNil
        , surfaceIntentHandlers = HandlerNil
        }

fh :: FrontendSurfaceMountedFragment -> FrontendSurfaceFragmentHandler ('Fragment marker '[] policies)
fh fragment = FrontendSurfaceFragmentHandler
    { fragmentHandlerDefaultParams = frontendSurfaceFieldValues Aeson.Null
    , fragmentHandlerMountedFragment = const fragment
    , fragmentHandlerRender = const mempty
    }

scopeHandler :: AdminVenueScopeValue -> FrontendSurfaceScopeHandler ('Scope scopeMarker '[ 'Field Surface.VenueId 'WireUUID] auth)
scopeHandler scope = FrontendSurfaceScopeHandler
    { scopeHandlerDefaultValue = frontendSurfaceFieldValues (Aeson.object ["venueId" Aeson..= tshow scope.adminVenueId])
    , scopeHandlerKey = \fields -> fromMaybe (tshow scope.adminVenueId) (getSurfaceField @Surface.VenueId fields)
    }

invitesScopeHandler :: AdminVenueScopeValue -> FrontendSurfaceScopeHandler ('Scope Surface.AdminInvitesScope '[ 'Field Surface.VenueId 'WireUUID, 'Field Surface.RosterGroupId 'WireUUID] auth)
invitesScopeHandler scope = FrontendSurfaceScopeHandler
    { scopeHandlerDefaultValue = frontendSurfaceFieldValues (Aeson.object ["venueId" Aeson..= tshow scope.adminVenueId, "rosterGroupId" Aeson..= maybe "" tshow scope.adminRosterGroupId])
    , scopeHandlerKey = \fields ->
        let venueId = fromMaybe (tshow scope.adminVenueId) (getSurfaceField @Surface.VenueId fields)
            rosterGroupId = fromMaybe (maybe "" tshow scope.adminRosterGroupId) (getSurfaceField @Surface.RosterGroupId fields)
         in venueId <> ":" <> rosterGroupId
    }

adminVenueSettingsAffectedFragments, adminInvitesAffectedFragments, adminExportsAffectedFragments, adminShiftTypesAffectedFragments, adminRosterGroupsAffectedFragments, adminXeroAffectedFragments :: AdminVenueScopeValue -> Set.Set LiveResource -> [FrontendSurfaceMountedFragment]
adminVenueSettingsAffectedFragments scope resources = if Set.member (adminVenueSettingsResource scope.adminVenueId) resources then [adminVenueSettingsFragment] else []
adminInvitesAffectedFragments scope resources = if Set.member (adminInvitesResource scope.adminVenueId) resources then [adminInvitesFragment scope.adminRosterGroupId] else []
adminExportsAffectedFragments scope resources = if Set.member (adminExportsResource scope.adminVenueId) resources then [adminExportsFragment] else []
adminShiftTypesAffectedFragments scope resources = if Set.member (adminShiftTypesResource scope.adminVenueId) resources then [adminShiftTypesFragment] else []
adminRosterGroupsAffectedFragments scope resources = if Set.member (adminRosterGroupsResource scope.adminVenueId) resources then [adminRosterGroupsFragment] else []
adminXeroAffectedFragments scope resources =
    concat
        [ [adminXeroShellFragment | any (`Set.member` resources) [xeroConnectionResource scope.adminVenueId]]
        , [adminXeroStaffMappingsFragment | Set.member (xeroMappingsResource scope.adminVenueId) resources]
        , [adminXeroPayItemsFragment | Set.member (xeroPayItemsResource scope.adminVenueId) resources]
        , [adminXeroTimesheetsFragment | Set.member (xeroTimesheetsResource scope.adminVenueId) resources]
        ]

setAdminXeroActorRefresh :: (?context :: ControllerContext, ?request :: Request) => [FrontendSurfaceMountedFragment] -> IO ()
setAdminXeroActorRefresh fragments =
    setHeader
        ( "HX-Trigger"
        , cs (Aeson.encode (adminRefreshTriggerPayload (adminSurfaceWireFragments fragments)))
        )

adminRefreshTriggerPayload :: [LiveUpdateWireFragment] -> Aeson.Value
adminRefreshTriggerPayload fragments =
    Aeson.object
        [ AesonKey.fromText canonicalAppEvents.appLiveFragmentsRefreshEventName Aeson..= Aeson.object
            [ "fragments" Aeson..= coalesceLiveUpdateWireFragments fragments
            ]
        ]

adminSurfaceWireFragments :: [FrontendSurfaceMountedFragment] -> [LiveUpdateWireFragment]
adminSurfaceWireFragments fragments =
    concatMap fragmentsForSurface groupedFragments
    where
        groupedFragments =
            [ ("admin-venue-config", [fragment | fragment <- fragments, fragment.mountedFragmentKey.fragmentKind == "admin-venue-config"])
            , ("admin-invites", [fragment | fragment <- fragments, fragment.mountedFragmentKey.fragmentKind == "admin-invites"])
            , ("admin-exports", [fragment | fragment <- fragments, fragment.mountedFragmentKey.fragmentKind == "admin-exports"])
            , ("admin-shift-types", [fragment | fragment <- fragments, fragment.mountedFragmentKey.fragmentKind == "admin-shift-types"])
            , ("admin-roster-groups", [fragment | fragment <- fragments, fragment.mountedFragmentKey.fragmentKind == "admin-roster-groups"])
            , ("admin-xero", [fragment | fragment <- fragments, Text.isPrefixOf "admin-xero" fragment.mountedFragmentKey.fragmentKind])
            ]
        fragmentsForSurface (surfaceName, surfaceFragments) = frontendSurfaceMountedFragmentsToWire surfaceName surfaceFragments

adminPageContentFragment, adminXeroPageContentFragment, adminVenueSettingsFragment, adminExportsFragment, adminShiftTypesFragment, adminRosterGroupsFragment, adminXeroShellFragment, adminXeroStaffMappingsFragment, adminXeroPayItemsFragment, adminXeroTimesheetsFragment :: FrontendSurfaceMountedFragment
adminPageContentFragment = fragment "admin-page-content" "admin-page-content-fragment" (pathTo AdminAction) FrontendSurfaceReplace
adminXeroPageContentFragment = fragment "admin-xero-page-content" "admin-xero-page-content-fragment" (pathTo XeroAction) FrontendSurfaceReplace
adminVenueSettingsFragment = fragment "admin-venue-config" "admin-venue-settings-fragment" (pathTo ShowAdminVenueSettingsFragmentAction) FrontendSurfaceReplace
adminExportsFragment = fragment "admin-exports" "admin-exports-fragment" (pathTo ShowadminExportsLiveFragmentAction) FrontendSurfaceReplace
adminShiftTypesFragment = fragment "admin-shift-types" "admin-shift-types-fragment" (pathTo ShowadminShiftTypesLiveFragmentAction) (FrontendSurfaceFocusedFieldConfig FrontendSurfaceFocusedFieldProtectionConfig { focusedProtectionActiveSelector = "input[data-admin-shift-type-field-key]:focus", focusedProtectionFieldKeyAttr = "data-admin-shift-type-field-key", focusedProtectionFieldNameFallback = True, focusedProtectionContainerSelector = Just "form[data-admin-shift-type-row]" })
adminRosterGroupsFragment = fragment "admin-roster-groups" "admin-roster-groups-fragment" (pathTo ShowadminRosterGroupsLiveFragmentAction) FrontendSurfaceReplace
adminXeroShellFragment = fragment "admin-xero-shell" "admin-xero-fragment" (pathTo ShowadminXeroShellLiveFragmentAction) FrontendSurfaceReplace
adminXeroStaffMappingsFragment = fragment "admin-xero-staff-mappings" "xero-staff-mappings-data" (pathTo ShowadminXeroStaffMappingsLiveFragmentAction) FrontendSurfaceReplace
adminXeroPayItemsFragment = fragment "admin-xero-pay-items" "xero-pay-items-data" (pathTo ShowadminXeroPayItemsLiveFragmentAction) FrontendSurfaceReplace
adminXeroTimesheetsFragment = fragment "admin-xero-timesheets" "xero-timesheets-data" (pathTo ShowadminXeroTimesheetsLiveFragmentAction) FrontendSurfaceReplace

adminInvitesFragment :: Maybe UUID.UUID -> FrontendSurfaceMountedFragment
adminInvitesFragment maybeRosterGroupId =
    fragment "admin-invites" "admin-invites-fragment" (appendQueryParams (pathTo ShowadminInvitesLiveFragmentAction) (maybe [] (\rg -> [("rosterGroupId", tshow rg)]) maybeRosterGroupId)) FrontendSurfaceReplace

fragment :: Text -> Text -> Text -> FrontendSurfaceProtection -> FrontendSurfaceMountedFragment
fragment kind targetId url prot = FrontendSurfaceMountedFragment
    { mountedFragmentKey = FrontendSurfaceFragmentKey kind Aeson.Null
    , mountedFragmentTargetId = targetId
    , mountedFragmentUrl = url
    , mountedFragmentProtection = prot
    , mountedFragmentLoadPolicy = "eager"
    }
