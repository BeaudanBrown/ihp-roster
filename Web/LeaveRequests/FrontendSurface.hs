{-# LANGUAGE DataKinds        #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators    #-}

module Web.LeaveRequests.FrontendSurface
    ( LeaveRequestsScopeValue (..)
    , leaveRequestsCandidateMountedFragments
    , leaveRequestsSurfaceScope
    , leaveRequestsSurfaceImpl
    , leaveRequestsSurfaceMountConfig
    , leaveRequestsSurfaceScopeKey
    , leaveRequestsSurfaceWireFragments
    ) where

import Application.Helper.FrontendSurface.DSL
import qualified Application.Helper.FrontendSurface.LeaveRequests as Surface
import Application.Helper.FrontendSurface.Runtime
import Application.Helper.LiveUpdate.Runtime
import qualified Data.Aeson as Aeson
import qualified Data.UUID as UUID
import Web.Controller.Prelude
import Web.View.LeaveRequests.Index (leaveRequestsContentFragmentId)

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
    [leaveRequestsContentMountedFragment]

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
            FrontendSurfaceFragmentHandler
                { fragmentHandlerDefaultParams = frontendSurfaceFieldValues Aeson.Null
                , fragmentHandlerMountedFragment = const leaveRequestsContentMountedFragment
                , fragmentHandlerRender = const mempty
                }
                `HandlerCons` HandlerNil
        , surfaceActionHandlers = HandlerNil
        , surfaceIntentHandlers = HandlerNil
        }

leaveRequestsScopeFields :: LeaveRequestsScopeValue -> FrontendSurfaceFieldValues '[ 'Field Surface.VenueId 'WireUUID]
leaveRequestsScopeFields scope =
    frontendSurfaceFieldValues (Aeson.object ["venueId" Aeson..= tshow scope.leaveRequestsVenueId])

leaveRequestsContentMountedFragment :: FrontendSurfaceMountedFragment
leaveRequestsContentMountedFragment =
    FrontendSurfaceMountedFragment
        { mountedFragmentKey = FrontendSurfaceFragmentKey "leave-requests-content" Aeson.Null
        , mountedFragmentTargetId = leaveRequestsContentFragmentId
        , mountedFragmentUrl = pathTo ShowleaveRequestsContentLiveFragmentAction
        , mountedFragmentProtection = FrontendSurfaceReplace
        , mountedFragmentLoadPolicy = "eager"
        }
