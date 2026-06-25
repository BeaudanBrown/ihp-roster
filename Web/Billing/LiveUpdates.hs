{-# OPTIONS_GHC -Werror=incomplete-patterns #-}

module Web.Billing.LiveUpdates
    ( BillingLiveFragment (..)
    , BillingSurfaceKey (..)
    , billingLiveSurfaceDefinition
    , currentBillingSurfaceKey
    ) where

import Application.Helper.Controller (currentVenueOrNothing)
import Application.Helper.LiveResource (LiveResource (..))
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

billingLiveSurfaceDefinition :: TypedLiveSurfaceDefinition BillingSurface BillingSurfaceKey BillingLiveFragment EmptyInteractionLayer EmptyInteractionSession EmptyInteractionIntent
billingLiveSurfaceDefinition =
    TypedLiveSurfaceDefinition
        { typedSurfaceFeature = "billing"
        , typedSurfaceScope = \key -> SurfaceScope BillingScope { venueId = key.billingSurfaceVenueId }
        , typedSurfaceScopeFromWire = \case
            BillingScope { venueId } -> Just BillingSurfaceKey { billingSurfaceVenueId = venueId }
            _ -> Nothing
        , typedSurfaceDefaultFragments = const [BillingStatusLiveFragment]
        , typedSurfaceFragmentContract = \key fragment ->
            mkSurfaceFragmentContract
                (billingLiveFragmentRef fragment)
                (liveFragmentDependsOn (BillingResource key.billingSurfaceVenueId) [])
        , typedSurfaceDecorateRequestsWithin = const ["#billing-live-surface", "#billing-status-fragment"]
        , typedSurfaceAuthorize = liveSurfaceAuthorizationByRequirement (\key -> RequireCurrentVenueOwner key.billingSurfaceVenueId)
        , typedSurfaceInteractionSchema = emptyInteractionStaticSchema
        , typedSurfaceInteraction = const emptyInteractionCapability
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
        Nothing    -> error "Billing live surface requires a current venue"

