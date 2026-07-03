{-# LANGUAGE DataKinds        #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators    #-}

module Web.Billing.FrontendSurface
    ( BillingScopeValue (..)
    , billingAffectedMountedFragments
    , billingCandidateMountedFragments
    , billingFragmentDependencies
    , billingLiveUpdateScope
    , billingSurfaceImpl
    , billingSurfaceMountConfig
    , billingSurfaceScopeKey
    , billingSurfaceWireFragments
    , currentBillingScopeValue
    ) where

import Application.Helper.Controller (currentVenueOrNothing)
import qualified Application.Helper.FrontendSurface.Billing as Surface
import Application.Helper.FrontendSurface.DSL
import Application.Helper.FrontendSurface.Runtime
import Application.Helper.LiveResource
import Application.Helper.LiveUpdate.Runtime (LiveUpdateScope (..),
                                              LiveUpdateWireFragment)
import qualified Data.Aeson as Aeson
import qualified Data.Set as Set
import qualified Data.UUID as UUID
import Web.Controller.Prelude

data BillingScopeValue = BillingScopeValue
    { billingVenueId :: !UUID.UUID
    }
    deriving (Eq, Show)

currentBillingScopeValue :: (?context :: ControllerContext) => BillingScopeValue
currentBillingScopeValue =
    BillingScopeValue { billingVenueId = currentVenueScopeId }

billingSurfaceImpl :: BillingScopeValue -> Text -> SurfaceImpl Surface.BillingSurface
billingSurfaceImpl scope statusUrl =
    let impl = mkSurfaceImpl "billing" (billingSurfaceMountConfig scope statusUrl) (billingSurfaceHandlers scope statusUrl)
     in impl { surfaceImplMountConfig = impl.surfaceImplMountConfig { mountFragments = billingCandidateMountedFragments statusUrl } }

billingSurfaceMountConfig :: BillingScopeValue -> Text -> FrontendSurfaceMountConfig
billingSurfaceMountConfig scope statusUrl =
    FrontendSurfaceMountConfig
        { mountSurfaceName = "billing"
        , mountScopeKey = billingSurfaceScopeKey scope
        , mountKey = "primary"
        , mountScope = Aeson.Null
        , mountSubscription = Nothing
        , mountState = Aeson.Null
        , mountFragments = billingCandidateMountedFragments statusUrl
        }

billingSurfaceScopeKey :: BillingScopeValue -> Text
billingSurfaceScopeKey scope =
    "billing:" <> tshow scope.billingVenueId

billingLiveUpdateScope :: BillingScopeValue -> LiveUpdateScope
billingLiveUpdateScope scope =
    BillingScope { venueId = scope.billingVenueId }

billingCandidateMountedFragments :: Text -> [FrontendSurfaceMountedFragment]
billingCandidateMountedFragments statusUrl =
    [billingStatusMountedFragment statusUrl]

billingAffectedMountedFragments :: BillingScopeValue -> Set.Set LiveResource -> [FrontendSurfaceMountedFragment]
billingAffectedMountedFragments scope touchedResources =
    billingCandidateMountedFragments (pathTo ShowBillingStatusFragmentAction)
        |> filter (not . Set.null . Set.intersection touchedResources . Set.fromList . billingFragmentDependencies scope)

billingFragmentDependencies :: BillingScopeValue -> FrontendSurfaceMountedFragment -> [LiveResource]
billingFragmentDependencies scope _ =
    [billingResource scope.billingVenueId]

billingSurfaceWireFragments :: [FrontendSurfaceMountedFragment] -> [LiveUpdateWireFragment]
billingSurfaceWireFragments =
    frontendSurfaceMountedFragmentsToWire "billing"

billingSurfaceHandlers :: BillingScopeValue -> Text -> SurfaceImplHandlers Surface.BillingSurface
billingSurfaceHandlers scope statusUrl =
    SurfaceImplHandlers
        { surfaceScopeHandlers =
            FrontendSurfaceScopeHandler
                { scopeHandlerDefaultValue = billingScopeFields scope
                , scopeHandlerKey = \fields ->
                    let venueId = fromMaybe (tshow scope.billingVenueId) (getSurfaceField @Surface.VenueId fields)
                     in "billing:" <> venueId
                }
                `HandlerCons` HandlerNil
        , surfaceMountStateHandlers = HandlerNil
        , surfaceFragmentHandlers =
            FrontendSurfaceFragmentHandler
                { fragmentHandlerDefaultParams = frontendSurfaceFieldValues Aeson.Null
                , fragmentHandlerMountedFragment = const (billingStatusMountedFragment statusUrl)
                , fragmentHandlerRender = const mempty
                }
                `HandlerCons` HandlerNil
        , surfaceActionHandlers = HandlerNil
        , surfaceIntentHandlers = HandlerNil
        }

billingScopeFields :: BillingScopeValue -> FrontendSurfaceFieldValues '[ 'Field Surface.VenueId 'WireUUID]
billingScopeFields scope =
    frontendSurfaceFieldValues (Aeson.object ["venueId" Aeson..= tshow scope.billingVenueId])

billingStatusMountedFragment :: Text -> FrontendSurfaceMountedFragment
billingStatusMountedFragment statusUrl =
    FrontendSurfaceMountedFragment
        { mountedFragmentKey = FrontendSurfaceFragmentKey "billing-status" Aeson.Null
        , mountedFragmentTargetId = "billing-status-fragment"
        , mountedFragmentUrl = statusUrl
        , mountedFragmentProtection = FrontendSurfaceReplace
        , mountedFragmentLoadPolicy = "eager"
        }

currentVenueScopeId :: (?context :: ControllerContext) => UUID.UUID
currentVenueScopeId =
    case currentVenueOrNothing of
        Just venue -> unpackId venue.id
        Nothing    -> error "Billing live surface requires a current venue"
