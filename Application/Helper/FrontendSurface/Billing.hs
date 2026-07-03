{-# LANGUAGE DataKinds     #-}
{-# LANGUAGE TypeOperators #-}

module Application.Helper.FrontendSurface.Billing
    ( BillingResource
    , BillingStatus
    , BillingSurface
    , BillingVenue
    , VenueId
    ) where

import Application.Helper.FrontendSurface.DSL

data Billing

data BillingVenue
data VenueId

data BillingStatus

type BillingResource = Resource Billing '[ Field VenueId 'WireUUID ]

type BillingSurface =
    Surface Billing
        '[ Scope BillingVenue
            '[ Field VenueId 'WireUUID
             ]
            '[ 'Authorize 'CurrentVenueOwner '[ VenueId ] ]
         , Fragment BillingStatus '[] '[ 'Eager, 'Live, 'DependsOn BillingResource '[ 'FromScope VenueId ] ]
         ]
