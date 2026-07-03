{-# LANGUAGE DataKinds     #-}
{-# LANGUAGE TypeOperators #-}

module Application.Helper.FrontendSurface.Billing
    ( BillingStatus
    , BillingSurface
    , BillingVenue
    , VenueId
    ) where

import Application.Helper.FrontendSurface.DSL

data Billing

data BillingVenue
data VenueId

data BillingStatus

type BillingSurface =
    Surface Billing
        '[ Scope BillingVenue
            '[ Field VenueId 'WireUUID
             ]
         , Fragment BillingStatus '[] '[ 'Eager, 'Live ]
         ]
