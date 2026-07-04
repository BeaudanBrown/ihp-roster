{-# LANGUAGE DataKinds     #-}
{-# LANGUAGE TypeOperators #-}

module Application.Helper.FrontendSurface.Billing
    ( BillingResource
    , BillingStatus
    , BillingMountState
    , BillingSurface
    , BillingVenue
    , CheckoutReturned
    , CheckoutSessionId
    , VenueId
    ) where

import Application.Helper.FrontendSurface.DSL

data Billing

data BillingVenue
data VenueId

data BillingStatus

data BillingMountState
data CheckoutReturned
data CheckoutSessionId

type BillingResource = Resource Billing '[ Field VenueId 'WireUUID ]

type BillingSurface =
    Surface Billing
        '[ Scope BillingVenue
            '[ Field VenueId 'WireUUID
             ]
            '[ 'Authorize 'CurrentVenueOwner '[ VenueId ] ]
         , MountState BillingMountState
            '[ Field CheckoutReturned 'WireBool
             , Field CheckoutSessionId ('WireOptional 'WireText)
             ]
         , Fragment BillingStatus '[] '[ 'Eager, 'Live, 'DependsOn BillingResource '[ 'FromScope VenueId ] ]
         ]
