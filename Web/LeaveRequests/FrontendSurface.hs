{-# LANGUAGE DataKinds        #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators    #-}

module Web.LeaveRequests.FrontendSurface
    ( LeaveRequestsScopeValue (..)
    , leaveRequestsCandidateMountedFragments
    , leaveRequestsSurfaceScope
    , leaveRequestsSurfaceAction
    , leaveRequestsSurfaceImpl
    , leaveRequestsSurfaceMountConfig
    , leaveRequestsSurfaceScopeKey
    , leaveRequestsSurfaceWireFragments
    ) where

import qualified Application.Helper.FrontendContract.Surface.ContractIR as SurfaceIR
import Application.Helper.FrontendContract.Surface.Contracts (registeredFrontendSurfaceContractIR)
import Application.Helper.FrontendContract.Surface.DSL
import qualified Application.Helper.FrontendContract.Surface.LeaveRequests as Surface
import Application.Helper.FrontendContract.Surface.Runtime
import Application.Helper.LiveUpdate.Runtime
import Application.Helper.Url (appendQueryParams)
import qualified Data.Aeson as Aeson
import qualified Data.UUID as UUID
import Web.Controller.Prelude
import Web.View.LeaveRequests.Index (leaveApprovedSection, leaveArchiveSection,
                                     leaveDeniedSection, leavePendingSection,
                                     leaveRequestsContentFragmentId,
                                     leaveSectionCountFragmentId,
                                     leaveSectionCountFragmentKind,
                                     leaveSectionListFragmentId,
                                     leaveSectionListFragmentKind)

data LeaveRequestsScopeValue = LeaveRequestsScopeValue
    { leaveRequestsVenueId :: !UUID.UUID
    }
    deriving (Eq, Show)

leaveRequestsSurfaceImpl :: LeaveRequestsScopeValue -> SurfaceImpl Surface.LeaveRequestsSurface
leaveRequestsSurfaceImpl scope =
    let impl = mkSurfaceImpl "leave-requests" (leaveRequestsSurfaceMountConfig scope) (leaveRequestsSurfaceHandlers scope)
     in impl { surfaceImplMountConfig = impl.surfaceImplMountConfig { mountFragments = leaveRequestsCandidateMountedFragments scope } }

leaveRequestsSurfaceMountConfig :: LeaveRequestsScopeValue -> FrontendSurfaceMountConfig
leaveRequestsSurfaceMountConfig scope =
    FrontendSurfaceMountConfig
        { mountSurfaceName = "leave-requests"
        , mountScopeKey = leaveRequestsSurfaceScopeKey scope
        , mountKey = "primary"
        , mountScope = Aeson.Null
        , mountSubscription = Nothing
        , mountState = Aeson.Null
        , mountFragments = leaveRequestsCandidateMountedFragments scope
        }

leaveRequestsSurfaceScopeKey :: LeaveRequestsScopeValue -> Text
leaveRequestsSurfaceScopeKey scope =
    "leave-requests:" <> tshow scope.leaveRequestsVenueId

leaveRequestsSurfaceScope :: LeaveRequestsScopeValue -> SurfaceScope
leaveRequestsSurfaceScope scope =
    leaveRequestsLiveScope scope.leaveRequestsVenueId

leaveRequestsCandidateMountedFragments :: LeaveRequestsScopeValue -> [FrontendSurfaceMountedFragment]
leaveRequestsCandidateMountedFragments _ =
    leaveRequestsSectionMountedFragments

leaveRequestsSurfaceWireFragments :: [FrontendSurfaceMountedFragment] -> [SurfaceWireFragment]
leaveRequestsSurfaceWireFragments =
    frontendSurfaceMountedFragmentsToWire "leave-requests"

leaveRequestsSurfaceHandlers :: LeaveRequestsScopeValue -> SurfaceImplHandlers Surface.LeaveRequestsSurface
leaveRequestsSurfaceHandlers scope =
    SurfaceImplHandlers
        { surfaceScopeHandlers =
            FrontendSurfaceScopeHandler
                { scopeHandlerDefaultValue = leaveRequestsScopeFields scope
                , scopeHandlerKey = \fields ->
                    let venueId = fromMaybe (tshow scope.leaveRequestsVenueId) (getSurfaceField @Surface.VenueId fields)
                     in "leave-requests:" <> venueId
                }
                `HandlerCons` HandlerNil
        , surfaceMountStateHandlers = HandlerNil
        , surfaceFragmentHandlers =
            leaveRequestsFragmentHandler leaveSectionCountFragmentKind leavePendingSection `HandlerCons`
            leaveRequestsFragmentHandler leaveSectionListFragmentKind leavePendingSection `HandlerCons`
            HandlerNil
        , surfaceActionHandlers =
            leaveRequestsActionHandler "archive-leave-requests-page" (pathTo ShowleaveRequestsContentLiveFragmentAction) `HandlerCons`
            leaveRequestsActionHandler "approve-leave-request" (pathTo (ApproveLeaveRequestAction (Id UUID.nil))) `HandlerCons`
            leaveRequestsActionHandler "deny-leave-request" (pathTo (DenyLeaveRequestAction (Id UUID.nil))) `HandlerCons`
            HandlerNil
        , surfaceIntentHandlers = HandlerNil
        }

leaveRequestsActionHandler :: Text -> Text -> FrontendSurfaceActionHandler ('Action marker fields options)
leaveRequestsActionHandler actionName actionUrl = FrontendSurfaceActionHandler
    { actionHandlerDefaultFields = frontendSurfaceFieldValues Aeson.Null
    , actionHandlerRequest = const FrontendSurfaceHtmxRequest
        { htmxRequestName = actionName
        , htmxRequestMethod = FrontendSurfacePost
        , htmxRequestUrl = actionUrl
        , htmxRequestTarget = "#" <> leaveRequestsContentFragmentId
        , htmxRequestSwap = "none"
        , htmxRequestFields = []
        }
    }

leaveRequestsSurfaceAction :: Text -> SurfaceIR.HtmxActionIR
leaveRequestsSurfaceAction actionName =
    case [action | surface <- registeredFrontendSurfaceContractIR.contractSurfaces, surface.surfaceName == "leave-requests", action <- surface.surfaceHtmxActions, action.htmxActionName == actionName] of
        action : _ -> action
        [] -> error ("missing leave requests surface action: " <> cs actionName)

leaveRequestsScopeFields :: LeaveRequestsScopeValue -> FrontendSurfaceFieldValues '[ 'Field Surface.VenueId 'WireUUID]
leaveRequestsScopeFields scope =
    frontendSurfaceFieldValuesFromPairs ["venueId" Aeson..= tshow scope.leaveRequestsVenueId]

leaveRequestsFragmentHandler :: KnownFragmentOptions options => Text -> Text -> FrontendSurfaceFragmentHandler ('Fragment marker '[ 'Field Surface.LeaveSection 'WireText] options)
leaveRequestsFragmentHandler kind section =
    FrontendSurfaceFragmentHandler
        { fragmentHandlerDefaultParams = leaveRequestsSectionFields section
        , fragmentHandlerMountedFragment = const (leaveRequestsMountedFragment kind section)
        , fragmentHandlerRender = const mempty
        }

leaveRequestsSectionFields :: Text -> FrontendSurfaceFieldValues '[ 'Field Surface.LeaveSection 'WireText]
leaveRequestsSectionFields section =
    frontendSurfaceFieldValuesFromPairs ["leaveSection" Aeson..= section]

leaveRequestsSectionMountedFragments :: [FrontendSurfaceMountedFragment]
leaveRequestsSectionMountedFragments =
    [ leaveRequestsMountedFragment leaveSectionCountFragmentKind leavePendingSection
    , leaveRequestsMountedFragment leaveSectionListFragmentKind leavePendingSection
    , leaveRequestsMountedFragment leaveSectionCountFragmentKind leaveApprovedSection
    , leaveRequestsMountedFragment leaveSectionListFragmentKind leaveApprovedSection
    , leaveRequestsMountedFragment leaveSectionCountFragmentKind leaveDeniedSection
    , leaveRequestsMountedFragment leaveSectionListFragmentKind leaveDeniedSection
    , leaveRequestsMountedFragment leaveSectionCountFragmentKind leaveArchiveSection
    , leaveRequestsMountedFragment leaveSectionListFragmentKind leaveArchiveSection
    ]

leaveRequestsMountedFragment :: Text -> Text -> FrontendSurfaceMountedFragment
leaveRequestsMountedFragment kind section =
    frontendSurfaceMountedFragment
        kind
        (Aeson.object ["leaveSection" Aeson..= section])
        targetId
        (appendQueryParams (pathTo ShowleaveRequestsContentLiveFragmentAction) [ ("fragment", kind), ("section", section) ])
        FrontendSurfaceReplace
    where
        targetId
            | kind == leaveSectionCountFragmentKind = leaveSectionCountFragmentId section
            | otherwise = leaveSectionListFragmentId section
