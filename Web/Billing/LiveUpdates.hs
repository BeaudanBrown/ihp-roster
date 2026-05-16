module Web.Billing.LiveUpdates
    ( BillingLiveFragment (..)
    , BillingSurfaceKey (..)
    , billingLiveSurfaceDefinition
    , broadcastBillingInvalidation
    , broadcastBillingInvalidationForVenue
    , currentBillingSurfaceKey
    ) where

import Application.Helper.Controller (currentVenueOrNothing)
import Application.Helper.LiveSurface
import Application.Helper.LiveUpdate
import Web.Controller.Prelude

data BillingSurface

data BillingSurfaceKey = BillingSurfaceKey
    { billingSurfaceVenueId :: !UUID
    }
    deriving (Eq, Show)

data BillingLiveFragment
    = BillingStatusLiveFragment
    deriving (Eq, Show)

currentBillingSurfaceKey :: (?context :: ControllerContext) => BillingSurfaceKey
currentBillingSurfaceKey =
    BillingSurfaceKey { billingSurfaceVenueId = currentVenueScopeId }

billingLiveSurfaceDefinition :: TypedLiveSurfaceDefinition BillingSurface BillingSurfaceKey BillingLiveFragment
billingLiveSurfaceDefinition =
    TypedLiveSurfaceDefinition
        { typedSurfaceFeature = "billing"
        , typedSurfaceScope = \key -> SurfaceScope BillingScope { venueId = key.billingSurfaceVenueId }
        , typedSurfaceScopeFromWire = \case
            BillingScope { venueId } -> Just BillingSurfaceKey { billingSurfaceVenueId = venueId }
            _ -> Nothing
        , typedSurfaceDefaultFragments = const [BillingStatusLiveFragment]
        , typedSurfaceFragmentRef = const billingLiveFragmentRef
        , typedSurfaceDecorateRequestsWithin = const ["#billing-live-surface", "#billing-status-fragment"]
        , typedSurfaceAuthorize = liveSurfaceAuthorizationByRequirement (\key -> RequireCurrentVenueOwner key.billingSurfaceVenueId)
        }

billingLiveFragmentRef :: BillingLiveFragment -> SurfaceFragmentRef BillingSurface
billingLiveFragmentRef BillingStatusLiveFragment =
    mkSurfaceFragmentRef
        BillingStatusFragment
        "billing-status-fragment"
        (pathTo ShowBillingStatusFragmentAction)

currentVenueScopeId :: (?context :: ControllerContext) => UUID
currentVenueScopeId =
    case currentVenueOrNothing of
        Just venue -> unpackId venue.id
        Nothing -> error "Billing live surface requires a current venue"

broadcastBillingInvalidation :: (?context :: ControllerContext, ?request :: Request) => IO ()
broadcastBillingInvalidation =
    broadcastSurfaceFragments
        billingLiveSurfaceDefinition
        currentBillingSurfaceKey
        [BillingStatusLiveFragment]

broadcastBillingInvalidationForVenue :: BillingSurfaceKey -> IO ()
broadcastBillingInvalidationForVenue surfaceKey = do
    _ <- broadcastSurfaceFragmentsWithoutContext
        billingLiveSurfaceDefinition
        surfaceKey
        Nothing
        [BillingStatusLiveFragment]
    pure ()
