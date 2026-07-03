{-# LANGUAGE DataKinds        #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators    #-}

module Web.Admin.FrontendSurface
    ( AdminVenueScopeValue (..)
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
import Application.Helper.LiveUpdate.Runtime (FocusedFieldProtectionConfig (..),
                                              LiveFragmentKey (..),
                                              LiveFragmentProtection (..),
                                              LiveUpdateWireFragment (..),
                                              coalesceLiveUpdateWireFragments)
import Application.Helper.Url (appendQueryParams)
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as AesonKey
import qualified Data.Set as Set
import qualified Data.UUID as UUID
import Web.Controller.Prelude

data AdminVenueScopeValue = AdminVenueScopeValue
    { adminVenueId       :: !UUID.UUID
    , adminRosterGroupId :: !(Maybe UUID.UUID)
    }
    deriving (Eq, Show)

adminVenueSettingsSurfaceImpl :: AdminVenueScopeValue -> SurfaceImpl Surface.AdminVenueSettingsSurface
adminVenueSettingsSurfaceImpl scope = oneFragmentImpl "admin-venue-config" scope adminVenueSettingsFragment

adminInvitesSurfaceImpl :: AdminVenueScopeValue -> SurfaceImpl Surface.AdminInvitesSurface
adminInvitesSurfaceImpl scope =
    let fragmentValue = adminInvitesFragment scope.adminRosterGroupId
        config = mountConfig "admin-invites" scope [fragmentValue]
        impl = mkSurfaceImpl "admin-invites" config (invitesHandlers scope fragmentValue)
     in impl { surfaceImplMountConfig = config }

adminExportsSurfaceImpl :: AdminVenueScopeValue -> SurfaceImpl Surface.AdminExportsSurface
adminExportsSurfaceImpl scope = oneFragmentImpl "admin-exports" scope adminExportsFragment

adminShiftTypesSurfaceImpl :: AdminVenueScopeValue -> SurfaceImpl Surface.AdminShiftTypesSurface
adminShiftTypesSurfaceImpl scope = oneFragmentImpl "admin-shift-types" scope adminShiftTypesFragment

adminRosterGroupsSurfaceImpl :: AdminVenueScopeValue -> SurfaceImpl Surface.AdminRosterGroupsSurface
adminRosterGroupsSurfaceImpl scope = oneFragmentImpl "admin-roster-groups" scope adminRosterGroupsFragment

adminXeroSurfaceImpl :: AdminVenueScopeValue -> SurfaceImpl Surface.AdminXeroSurface
adminXeroSurfaceImpl scope =
    let fragments = [adminXeroShellFragment, adminXeroStaffMappingsFragment, adminXeroPayItemsFragment, adminXeroTimesheetsFragment]
        config = mountConfig "admin-xero" scope fragments
        impl = mkSurfaceImpl "admin-xero" config (xeroHandlers scope)
     in impl { surfaceImplMountConfig = config }

oneFragmentImpl :: forall spec. Text -> AdminVenueScopeValue -> FrontendSurfaceMountedFragment -> SurfaceImpl spec
oneFragmentImpl name scope fragment =
    let config = mountConfig name scope [fragment]
        impl = mkSurfaceImpl name config (unitHandlers scope fragment)
     in impl { surfaceImplMountConfig = config }

mountConfig :: Text -> AdminVenueScopeValue -> [FrontendSurfaceMountedFragment] -> FrontendSurfaceMountConfig
mountConfig name scope fragments =
    FrontendSurfaceMountConfig
        { mountSurfaceName = name
        , mountScopeKey = adminScopeKey name scope
        , mountKey = "primary"
        , mountState = Aeson.Null
        , mountFragments = fragments
        }

adminScopeKey :: Text -> AdminVenueScopeValue -> Text
adminScopeKey name scope =
    name <> ":" <> tshow scope.adminVenueId <> maybe "" ((":" <>) . tshow) scope.adminRosterGroupId

unitHandlers :: AdminVenueScopeValue -> FrontendSurfaceMountedFragment -> SurfaceImplHandlers ('Surface marker '[ 'Scope scopeMarker '[ 'Field Surface.VenueId 'WireUUID ], 'Fragment fragment '[] '[ 'Eager ]])
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

scopeHandler :: AdminVenueScopeValue -> FrontendSurfaceScopeHandler ('Scope scopeMarker '[ 'Field Surface.VenueId 'WireUUID])
scopeHandler scope = FrontendSurfaceScopeHandler
    { scopeHandlerDefaultValue = frontendSurfaceFieldValues (Aeson.object ["venueId" Aeson..= tshow scope.adminVenueId])
    , scopeHandlerKey = \fields -> fromMaybe (tshow scope.adminVenueId) (getSurfaceField @Surface.VenueId fields)
    }

invitesScopeHandler :: AdminVenueScopeValue -> FrontendSurfaceScopeHandler ('Scope Surface.AdminInvitesScope '[ 'Field Surface.VenueId 'WireUUID, 'Field Surface.RosterGroupId 'WireUUID])
invitesScopeHandler scope = FrontendSurfaceScopeHandler
    { scopeHandlerDefaultValue = frontendSurfaceFieldValues (Aeson.object ["venueId" Aeson..= tshow scope.adminVenueId, "rosterGroupId" Aeson..= maybe "" tshow scope.adminRosterGroupId])
    , scopeHandlerKey = \fields ->
        let venueId = fromMaybe (tshow scope.adminVenueId) (getSurfaceField @Surface.VenueId fields)
            rosterGroupId = fromMaybe (maybe "" tshow scope.adminRosterGroupId) (getSurfaceField @Surface.RosterGroupId fields)
         in venueId <> ":" <> rosterGroupId
    }

adminVenueSettingsAffectedFragments, adminInvitesAffectedFragments, adminExportsAffectedFragments, adminShiftTypesAffectedFragments, adminRosterGroupsAffectedFragments, adminXeroAffectedFragments :: AdminVenueScopeValue -> Set.Set LiveResource -> [FrontendSurfaceMountedFragment]
adminVenueSettingsAffectedFragments scope resources = if Set.member (AdminVenueSettingsResource scope.adminVenueId) resources then [adminVenueSettingsFragment] else []
adminInvitesAffectedFragments scope resources = if Set.member (AdminInvitesResource scope.adminVenueId) resources then [adminInvitesFragment scope.adminRosterGroupId] else []
adminExportsAffectedFragments scope resources = if Set.member (AdminExportsResource scope.adminVenueId) resources then [adminExportsFragment] else []
adminShiftTypesAffectedFragments scope resources = if Set.member (AdminShiftTypesResource scope.adminVenueId) resources then [adminShiftTypesFragment] else []
adminRosterGroupsAffectedFragments scope resources = if Set.member (AdminRosterGroupsResource scope.adminVenueId) resources then [adminRosterGroupsFragment] else []
adminXeroAffectedFragments scope resources =
    concat
        [ [adminXeroShellFragment | any (`Set.member` resources) [XeroConnectionResource scope.adminVenueId]]
        , [adminXeroStaffMappingsFragment | Set.member (XeroMappingsResource scope.adminVenueId) resources]
        , [adminXeroPayItemsFragment | Set.member (XeroPayItemsResource scope.adminVenueId) resources]
        , [adminXeroTimesheetsFragment | Set.member (XeroTimesheetsResource scope.adminVenueId) resources]
        ]

setAdminXeroActorRefresh :: (?context :: ControllerContext, ?request :: Request) => [FrontendSurfaceMountedFragment] -> IO ()
setAdminXeroActorRefresh fragments =
    setHeader
        ( "HX-Trigger"
        , cs (Aeson.encode (liveUpdateWireRefreshTriggerPayload (adminSurfaceWireFragments fragments)))
        )

liveUpdateWireRefreshTriggerPayload :: [LiveUpdateWireFragment] -> Aeson.Value
liveUpdateWireRefreshTriggerPayload fragments =
    Aeson.object
        [ AesonKey.fromText canonicalAppEvents.appLiveFragmentsRefreshEventName Aeson..= Aeson.object
            [ "fragments" Aeson..= coalesceLiveUpdateWireFragments fragments
            ]
        ]

adminSurfaceWireFragments :: [FrontendSurfaceMountedFragment] -> [LiveUpdateWireFragment]
adminSurfaceWireFragments = map \fragment -> LiveUpdateWireFragment
    { fragmentKey = adminLiveFragmentKey fragment.mountedFragmentKey.fragmentKind
    , targetId = fragment.mountedFragmentTargetId
    , url = fragment.mountedFragmentUrl
    , deferUntilBlur = False
    , protectionPolicy = protection fragment.mountedFragmentProtection
    }

adminLiveFragmentKey :: Text -> LiveFragmentKey
adminLiveFragmentKey = \case
    "admin-venue-config" -> AdminVenueConfigFragment
    "admin-invites" -> AdminInvitesFragment
    "admin-exports" -> AdminExportsFragment
    "admin-shift-types" -> AdminShiftTypesFragment
    "admin-roster-groups" -> AdminRosterGroupsFragment
    "admin-xero" -> AdminXeroFragment
    "admin-xero-staff-mappings" -> AdminXeroStaffMappingsFragment
    "admin-xero-pay-items" -> AdminXeroPayItemsFragment
    "admin-xero-timesheets" -> AdminXeroTimesheetsFragment
    _ -> AdminVenueConfigFragment

protection :: FrontendSurfaceProtection -> LiveFragmentProtection
protection = \case
    FrontendSurfaceReplace -> NoProtection
    FrontendSurfaceFocusedField -> NoProtection
    FrontendSurfaceFocusedFieldConfig config -> FocusedFieldProtection FocusedFieldProtectionConfig
        { activeSelector = config.focusedProtectionActiveSelector
        , fieldKeyAttr = config.focusedProtectionFieldKeyAttr
        , fieldNameFallback = config.focusedProtectionFieldNameFallback
        , containerSelector = config.focusedProtectionContainerSelector
        }

adminVenueSettingsFragment, adminExportsFragment, adminShiftTypesFragment, adminRosterGroupsFragment, adminXeroShellFragment, adminXeroStaffMappingsFragment, adminXeroPayItemsFragment, adminXeroTimesheetsFragment :: FrontendSurfaceMountedFragment
adminVenueSettingsFragment = fragment "admin-venue-config" "admin-venue-settings-fragment" (pathTo ShowAdminVenueSettingsFragmentAction) FrontendSurfaceReplace
adminExportsFragment = fragment "admin-exports" "admin-exports-fragment" (pathTo ShowAdminExportsFragmentAction) FrontendSurfaceReplace
adminShiftTypesFragment = fragment "admin-shift-types" "admin-shift-types-fragment" (pathTo ShowAdminShiftTypesFragmentAction) (FrontendSurfaceFocusedFieldConfig FrontendSurfaceFocusedFieldProtectionConfig { focusedProtectionActiveSelector = "input[data-admin-shift-type-field-key]:focus", focusedProtectionFieldKeyAttr = "data-admin-shift-type-field-key", focusedProtectionFieldNameFallback = True, focusedProtectionContainerSelector = Just "form[data-admin-shift-type-row]" })
adminRosterGroupsFragment = fragment "admin-roster-groups" "admin-roster-groups-fragment" (pathTo ShowAdminRosterGroupsFragmentAction) FrontendSurfaceReplace
adminXeroShellFragment = fragment "admin-xero" "admin-xero-fragment" (pathTo ShowAdminXeroFragmentAction) FrontendSurfaceReplace
adminXeroStaffMappingsFragment = fragment "admin-xero-staff-mappings" "xero-staff-mappings-data" (pathTo ShowAdminXeroStaffMappingsFragmentAction) FrontendSurfaceReplace
adminXeroPayItemsFragment = fragment "admin-xero-pay-items" "xero-pay-items-data" (pathTo ShowAdminXeroPayItemsFragmentAction) FrontendSurfaceReplace
adminXeroTimesheetsFragment = fragment "admin-xero-timesheets" "xero-timesheets-data" (pathTo ShowAdminXeroTimesheetsFragmentAction) FrontendSurfaceReplace

adminInvitesFragment :: Maybe UUID.UUID -> FrontendSurfaceMountedFragment
adminInvitesFragment maybeRosterGroupId =
    fragment "admin-invites" "admin-invites-fragment" (appendQueryParams (pathTo ShowAdminInvitesFragmentAction) (maybe [] (\rg -> [("rosterGroupId", tshow rg)]) maybeRosterGroupId)) FrontendSurfaceReplace

fragment :: Text -> Text -> Text -> FrontendSurfaceProtection -> FrontendSurfaceMountedFragment
fragment kind targetId url prot = FrontendSurfaceMountedFragment
    { mountedFragmentKey = FrontendSurfaceFragmentKey kind Aeson.Null
    , mountedFragmentTargetId = targetId
    , mountedFragmentUrl = url
    , mountedFragmentProtection = prot
    , mountedFragmentLoadPolicy = "eager"
    }
