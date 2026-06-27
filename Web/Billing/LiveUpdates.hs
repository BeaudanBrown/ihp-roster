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
    descriptorToTypedLiveSurfaceDefinition
        ( liveSurfaceDescriptor
            "billing"
            (\key -> SurfaceScope BillingScope { venueId = key.billingSurfaceVenueId })
            (\case
                BillingScope { venueId } -> Just BillingSurfaceKey { billingSurfaceVenueId = venueId }
                _ -> Nothing)
            (liveSurfaceAuthorizationByRequirement (\key -> RequireCurrentVenueOwner key.billingSurfaceVenueId))
            [ liveFragmentDescriptor
                BillingStatusLiveFragment
                (const (billingLiveFragmentRef BillingStatusLiveFragment))
                (\key -> liveFragmentDependsOn (BillingResource key.billingSurfaceVenueId) [])
            ]
            |> liveSurfaceDescriptorWithDecorateRequestsWithin (const ["#billing-live-surface", "#billing-status-fragment"])
        )

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

