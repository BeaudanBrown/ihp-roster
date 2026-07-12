{-# LANGUAGE DataKinds        #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators    #-}

module Web.Billing.FrontendSurface
    ( BillingCheckoutReturnState (..)
    , BillingScopeValue (..)
    , billingCandidateMountedFragments
    , billingSurfaceScope
    , billingSurfaceImpl
    , billingSurfaceMountConfig
    , billingSurfaceScopeKey
    , billingSurfaceFragmentKeys
    , currentBillingCheckoutReturnState
    , currentBillingScopeValue
    ) where

import Application.Helper.Controller (currentVenueOrNothing)
import qualified Application.Helper.FrontendContract.Surface.Billing as Surface
import Application.Helper.FrontendContract.Surface.DSL
import Application.Helper.FrontendContract.Surface.Runtime
import Application.Helper.LiveUpdate.Runtime
import Application.Helper.Url (appendQueryParams)
import qualified Data.Aeson as Aeson
import qualified Data.UUID as UUID
import Web.Controller.Prelude

data BillingScopeValue = BillingScopeValue
    { billingVenueId :: !UUID.UUID
    }
    deriving (Eq, Show)

data BillingCheckoutReturnState = BillingCheckoutReturnState
    { billingCheckoutReturned  :: !Bool
    , billingCheckoutSessionId :: !(Maybe Text)
    }
    deriving (Eq, Show)

currentBillingCheckoutReturnState :: BillingCheckoutReturnState
currentBillingCheckoutReturnState =
    BillingCheckoutReturnState
        { billingCheckoutReturned = False
        , billingCheckoutSessionId = Nothing
        }

currentBillingScopeValue :: (?context :: ControllerContext) => BillingScopeValue
currentBillingScopeValue =
    BillingScopeValue { billingVenueId = currentVenueScopeId }

billingSurfaceImpl :: BillingScopeValue -> BillingCheckoutReturnState -> SurfaceImpl Surface.BillingSurface
billingSurfaceImpl scope checkoutReturnState =
    mkSurfaceImpl "billing" (billingSurfaceMountConfig scope checkoutReturnState) (billingSurfaceHandlers scope checkoutReturnState)
        |> surfaceImplWithMountedFragments (billingCandidateMountedFragments checkoutReturnState)

billingSurfaceMountConfig :: BillingScopeValue -> BillingCheckoutReturnState -> FrontendSurfaceMountConfig
billingSurfaceMountConfig scope checkoutReturnState =
    FrontendSurfaceMountConfig
        { mountSurfaceName = "billing"
        , mountScopeKey = billingSurfaceScopeKey scope
        , mountKey = "primary"
        , mountScope = Aeson.Null
        , mountSubscription = Nothing
        , mountState = (billingMountStateFields checkoutReturnState).fieldValuesJson
        , mountFragments = billingCandidateMountedFragments checkoutReturnState
        }

billingSurfaceScopeKey :: BillingScopeValue -> Text
billingSurfaceScopeKey scope =
    "billing:" <> tshow scope.billingVenueId

billingSurfaceScope :: BillingScopeValue -> SurfaceScope
billingSurfaceScope scope =
    billingLiveScope scope.billingVenueId

billingCandidateMountedFragments :: BillingCheckoutReturnState -> [FrontendSurfaceMountedFragment]
billingCandidateMountedFragments checkoutReturnState =
    [billingStatusMountedFragment (billingStatusFragmentUrl checkoutReturnState)]

billingSurfaceFragmentKeys :: [FrontendSurfaceMountedFragment] -> [SurfaceFragmentKey]
billingSurfaceFragmentKeys =
    frontendSurfaceMountedFragmentsToKeys "billing"

billingSurfaceHandlers :: BillingScopeValue -> BillingCheckoutReturnState -> SurfaceImplHandlers Surface.BillingSurface
billingSurfaceHandlers scope checkoutReturnState =
    SurfaceImplHandlers
        { surfaceScopeHandlers =
            FrontendSurfaceScopeHandler
                { scopeHandlerDefaultValue = billingScopeFields scope
                , scopeHandlerKey = \fields ->
                    let venueId = fromMaybe (tshow scope.billingVenueId) (getSurfaceField @Surface.VenueId fields)
                     in "billing:" <> venueId
                }
                `HandlerCons` HandlerNil
        , surfaceMountStateHandlers =
            FrontendSurfaceMountStateHandler
                { mountStateHandlerDefaultValue = billingMountStateFields checkoutReturnState
                }
                `HandlerCons` HandlerNil
        , surfaceFragmentHandlers =
            FrontendSurfaceFragmentHandler
                { fragmentHandlerDefaultParams = frontendSurfaceFieldValues Aeson.Null
                , fragmentHandlerMountedFragment = const (billingStatusMountedFragment (billingStatusFragmentUrl checkoutReturnState))
                , fragmentHandlerRender = const mempty
                }
                `HandlerCons` HandlerNil
        , surfaceActionHandlers = HandlerNil
        , surfaceIntentHandlers = HandlerNil
        }

billingScopeFields :: BillingScopeValue -> FrontendSurfaceFieldValues '[ 'Field Surface.VenueId 'WireUUID]
billingScopeFields scope =
    frontendSurfaceFieldValues (Aeson.object ["venueId" Aeson..= tshow scope.billingVenueId])

billingMountStateFields :: BillingCheckoutReturnState -> FrontendSurfaceFieldValues '[ 'Field Surface.CheckoutReturned 'WireBool, 'Field Surface.CheckoutSessionId ('WireOptional 'WireText)]
billingMountStateFields checkoutReturnState =
    frontendSurfaceFieldValues (Aeson.object
        [ "checkoutReturned" Aeson..= checkoutReturnState.billingCheckoutReturned
        , "checkoutSessionId" Aeson..= checkoutReturnState.billingCheckoutSessionId
        ])

billingStatusFragmentUrl :: BillingCheckoutReturnState -> Text
billingStatusFragmentUrl BillingCheckoutReturnState { billingCheckoutReturned = False } =
    pathTo ShowbillingStatusLiveFragmentAction
billingStatusFragmentUrl BillingCheckoutReturnState { billingCheckoutReturned = True, billingCheckoutSessionId } =
    appendQueryParams (pathTo ShowbillingStatusLiveFragmentAction) $
        ("checkout", "success") : maybe [] (\sessionId -> [("session_id", sessionId)]) billingCheckoutSessionId

billingStatusMountedFragment :: Text -> FrontendSurfaceMountedFragment
billingStatusMountedFragment statusUrl =
    FrontendSurfaceMountedFragment
        { mountedFragmentKey = FrontendSurfaceFragmentKey "billing-status" Aeson.Null
        , mountedFragmentTargetId = "billing-status-fragment"
        , mountedFragmentUrl = statusUrl
        , mountedFragmentProtection = FrontendSurfaceReplace
        , mountedFragmentLazyTrigger = Nothing
        , mountedFragmentPlaceholderKind = Nothing
        }

currentVenueScopeId :: (?context :: ControllerContext) => UUID.UUID
currentVenueScopeId =
    case currentVenueOrNothing of
        Just venue -> unpackId venue.id
        Nothing    -> error "Billing live surface requires a current venue"
