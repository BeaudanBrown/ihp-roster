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
    , adminVenueSettingsAction
    , adminInvitesAction
    , adminExportsAction
    , adminVenueSettingsFragment
    , adminInvitesFragment
    , adminExportsFragment
    , adminShiftTypesFragment
    , adminRosterGroupsFragment
    , adminSurfaceWireFragments
    , adminXeroShellFragment
    , adminXeroStaffMappingsFragment
    , adminXeroPayItemsFragment
    , adminXeroTimesheetsFragment
    , adminShiftTypesAction
    , adminRosterGroupsAction
    , adminXeroAction
    ) where

import qualified Application.Helper.FrontendContract.Surface.Admin as Surface
import qualified Application.Helper.FrontendContract.Surface.ContractIR as SurfaceIR
import Application.Helper.FrontendContract.Surface.Contracts (registeredFrontendSurfaceContractIR)
import Application.Helper.FrontendContract.Surface.DSL
import Application.Helper.FrontendContract.Surface.Runtime
import Application.Helper.LiveUpdate.Runtime
import Application.Helper.SurfaceResource
import Application.Helper.Url (appendQueryParams)
import qualified Data.Aeson as Aeson
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
        impl = mkSurfaceImpl "admin-venue-config" config (venueSettingsHandlers scope adminVenueSettingsFragment)
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
        impl = mkSurfaceImpl "admin-exports" config (exportsHandlers scope adminExportsFragment)
     in impl

adminShiftTypesSurfaceImpl :: AdminVenueScopeValue -> SurfaceImpl Surface.AdminShiftTypesSurface
adminShiftTypesSurfaceImpl scope =
    let config = mountConfig "admin-shift-types" scope [adminShiftTypesFragment]
        impl = mkSurfaceImpl "admin-shift-types" config (shiftTypesHandlers scope adminShiftTypesFragment)
     in impl

adminRosterGroupsSurfaceImpl :: AdminVenueScopeValue -> SurfaceImpl Surface.AdminRosterGroupsSurface
adminRosterGroupsSurfaceImpl scope =
    let config = mountConfig "admin-roster-groups" scope [adminRosterGroupsFragment]
        impl = mkSurfaceImpl "admin-roster-groups" config (rosterGroupsHandlers scope adminRosterGroupsFragment)
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

unitHandlers :: KnownFragmentOptions policies => AdminVenueScopeValue -> FrontendSurfaceMountedFragment -> SurfaceImplHandlers ('Surface marker '[ 'Scope scopeMarker '[ 'Field Surface.VenueId 'WireUUID ] auth, 'Fragment fragment '[] policies])
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

venueSettingsHandlers :: AdminVenueScopeValue -> FrontendSurfaceMountedFragment -> SurfaceImplHandlers Surface.AdminVenueSettingsSurface
venueSettingsHandlers scope fragment =
    SurfaceImplHandlers
        { surfaceScopeHandlers = scopeHandler scope `HandlerCons` HandlerNil
        , surfaceMountStateHandlers = HandlerNil
        , surfaceFragmentHandlers = FrontendSurfaceFragmentHandler
            { fragmentHandlerDefaultParams = frontendSurfaceFieldValues Aeson.Null
            , fragmentHandlerMountedFragment = const fragment
            , fragmentHandlerRender = const mempty
            } `HandlerCons` HandlerNil
        , surfaceActionHandlers = adminActionHandler "update-venue-config" (pathTo UpdateVenueConfigAction) `HandlerCons` HandlerNil
        , surfaceIntentHandlers = HandlerNil
        }

exportsHandlers :: AdminVenueScopeValue -> FrontendSurfaceMountedFragment -> SurfaceImplHandlers Surface.AdminExportsSurface
exportsHandlers scope fragment =
    SurfaceImplHandlers
        { surfaceScopeHandlers = scopeHandler scope `HandlerCons` HandlerNil
        , surfaceMountStateHandlers = HandlerNil
        , surfaceFragmentHandlers = FrontendSurfaceFragmentHandler
            { fragmentHandlerDefaultParams = frontendSurfaceFieldValues Aeson.Null
            , fragmentHandlerMountedFragment = const fragment
            , fragmentHandlerRender = const mempty
            } `HandlerCons` HandlerNil
        , surfaceActionHandlers = adminActionHandler "create-export-job" (pathTo CreateExportJobAction) `HandlerCons` HandlerNil
        , surfaceIntentHandlers = HandlerNil
        }

shiftTypesHandlers :: AdminVenueScopeValue -> FrontendSurfaceMountedFragment -> SurfaceImplHandlers Surface.AdminShiftTypesSurface
shiftTypesHandlers scope fragment =
    SurfaceImplHandlers
        { surfaceScopeHandlers = scopeHandler scope `HandlerCons` HandlerNil
        , surfaceMountStateHandlers = HandlerNil
        , surfaceFragmentHandlers = FrontendSurfaceFragmentHandler
            { fragmentHandlerDefaultParams = frontendSurfaceFieldValues Aeson.Null
            , fragmentHandlerMountedFragment = const fragment
            , fragmentHandlerRender = const mempty
            } `HandlerCons` HandlerNil
        , surfaceActionHandlers =
            adminActionHandler "create-shift-type" (pathTo CreateShiftTypeAction) `HandlerCons`
            adminActionHandler "update-shift-type" (pathTo (UpdateShiftTypeAction (Id UUID.nil))) `HandlerCons`
            adminActionHandler "move-shift-type-up" (pathTo (MoveShiftTypeUpAction (Id UUID.nil))) `HandlerCons`
            adminActionHandler "move-shift-type-down" (pathTo (MoveShiftTypeDownAction (Id UUID.nil))) `HandlerCons`
            adminActionHandler "autosave-shift-type-name" (pathTo (UpdateShiftTypeAction (Id UUID.nil))) `HandlerCons`
            adminActionHandler "autosave-shift-type-selection" (pathTo (UpdateShiftTypeAction (Id UUID.nil))) `HandlerCons`
            adminActionHandler "toggle-inactive-shift-types" (pathTo ShowadminShiftTypesLiveFragmentAction) `HandlerCons`
            HandlerNil
        , surfaceIntentHandlers = HandlerNil
        }

rosterGroupsHandlers :: AdminVenueScopeValue -> FrontendSurfaceMountedFragment -> SurfaceImplHandlers Surface.AdminRosterGroupsSurface
rosterGroupsHandlers scope fragment =
    SurfaceImplHandlers
        { surfaceScopeHandlers = scopeHandler scope `HandlerCons` HandlerNil
        , surfaceMountStateHandlers = HandlerNil
        , surfaceFragmentHandlers = FrontendSurfaceFragmentHandler
            { fragmentHandlerDefaultParams = frontendSurfaceFieldValues Aeson.Null
            , fragmentHandlerMountedFragment = const fragment
            , fragmentHandlerRender = const mempty
            } `HandlerCons` HandlerNil
        , surfaceActionHandlers =
            adminActionHandler "create-roster-group" (pathTo CreateRosterGroupAction) `HandlerCons`
            adminActionHandler "update-roster-group" (pathTo (UpdateRosterGroupAction (Id UUID.nil))) `HandlerCons`
            adminActionHandler "move-roster-group-up" (pathTo (MoveRosterGroupUpAction (Id UUID.nil))) `HandlerCons`
            adminActionHandler "move-roster-group-down" (pathTo (MoveRosterGroupDownAction (Id UUID.nil))) `HandlerCons`
            adminActionHandler "toggle-inactive-roster-groups" (pathTo ShowadminRosterGroupsLiveFragmentAction) `HandlerCons`
            HandlerNil
        , surfaceIntentHandlers = HandlerNil
        }

adminActionHandler :: Text -> Text -> FrontendSurfaceActionHandler ('Action marker fields options)
adminActionHandler actionName actionUrl = FrontendSurfaceActionHandler
    { actionHandlerDefaultFields = frontendSurfaceFieldValues Aeson.Null
    , actionHandlerRequest = const FrontendSurfaceHtmxRequest
        { htmxRequestName = actionName
        , htmxRequestMethod = FrontendSurfacePost
        , htmxRequestUrl = actionUrl
        , htmxRequestTarget = "#admin-roster-groups-fragment"
        , htmxRequestSwap = "none"
        , htmxRequestFields = []
        }
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
        , surfaceActionHandlers =
            adminActionHandler "create-venue-invitation" (pathTo CreateVenueInvitationAction) `HandlerCons`
            adminActionHandler "revoke-venue-invitation" (pathTo (RevokeVenueInvitationAction (Id UUID.nil))) `HandlerCons`
            HandlerNil
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
        , surfaceActionHandlers =
            adminActionHandler "sync-xero-payroll-reference-data" (pathTo SyncXeroPayrollReferenceDataAction) `HandlerCons`
            adminActionHandler "save-xero-payroll-calendar-selection" (pathTo SaveXeroPayrollCalendarSelectionAction) `HandlerCons`
            adminActionHandler "save-xero-pay-item-account-code-selection" (pathTo SaveXeroPayItemAccountCodeSelectionAction) `HandlerCons`
            adminActionHandler "create-missing-xero-pay-items" (pathTo CreateMissingXeroPayItemsAction) `HandlerCons`
            adminActionHandler "archive-xero-imported-pay-item" (pathTo (ArchiveXeroImportedPayItemAction (Id UUID.nil))) `HandlerCons`
            adminActionHandler "save-xero-staff-mapping" (pathTo SaveXeroStaffMappingAction) `HandlerCons`
            adminActionHandler "suggest-xero-staff-mapping" (pathTo (SuggestXeroStaffMappingAction (Id UUID.nil))) `HandlerCons`
            adminActionHandler "show-xero-timesheet-preparation-staff-mappings" (pathTo (ShowXeroTimesheetPreparationStaffMappingsFragmentAction (Id UUID.nil))) `HandlerCons`
            HandlerNil
        , surfaceIntentHandlers = HandlerNil
        }

fh :: KnownFragmentOptions policies => FrontendSurfaceMountedFragment -> FrontendSurfaceFragmentHandler ('Fragment marker '[] policies)
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

invitesScopeHandler :: AdminVenueScopeValue -> FrontendSurfaceScopeHandler ('Scope Surface.AdminInvitesScope '[ 'Field Surface.VenueId 'WireUUID] auth)
invitesScopeHandler scope = FrontendSurfaceScopeHandler
    { scopeHandlerDefaultValue = frontendSurfaceFieldValues (Aeson.object ["venueId" Aeson..= tshow scope.adminVenueId])
    , scopeHandlerKey = \fields -> fromMaybe (tshow scope.adminVenueId) (getSurfaceField @Surface.VenueId fields)
    }

adminSurfaceWireFragments :: [FrontendSurfaceMountedFragment] -> [SurfaceWireFragment]
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

adminVenueSettingsAction :: Text -> SurfaceIR.HtmxActionIR
adminVenueSettingsAction = adminSurfaceAction "admin-venue-config"

adminInvitesAction :: Text -> SurfaceIR.HtmxActionIR
adminInvitesAction = adminSurfaceAction "admin-invites"

adminExportsAction :: Text -> SurfaceIR.HtmxActionIR
adminExportsAction = adminSurfaceAction "admin-exports"

adminShiftTypesAction :: Text -> SurfaceIR.HtmxActionIR
adminShiftTypesAction = adminSurfaceAction "admin-shift-types"

adminRosterGroupsAction :: Text -> SurfaceIR.HtmxActionIR
adminRosterGroupsAction = adminSurfaceAction "admin-roster-groups"

adminXeroAction :: Text -> SurfaceIR.HtmxActionIR
adminXeroAction = adminSurfaceAction "admin-xero"

adminSurfaceAction :: Text -> Text -> SurfaceIR.HtmxActionIR
adminSurfaceAction surfaceName actionName =
    case [action | surface <- registeredFrontendSurfaceContractIR.contractSurfaces, surface.surfaceName == surfaceName, action <- surface.surfaceHtmxActions, action.htmxActionName == actionName] of
        action : _ -> action
        [] -> error ("missing " <> cs surfaceName <> " action contract: " <> cs actionName)

fragment :: Text -> Text -> Text -> FrontendSurfaceProtection -> FrontendSurfaceMountedFragment
fragment kind targetId url prot = FrontendSurfaceMountedFragment
    { mountedFragmentKey = FrontendSurfaceFragmentKey kind Aeson.Null
    , mountedFragmentTargetId = targetId
    , mountedFragmentUrl = url
    , mountedFragmentProtection = prot
    , mountedFragmentLoadPolicy = "eager"
    , mountedFragmentLazyTrigger = Nothing
    , mountedFragmentPlaceholderKind = Nothing
    }
