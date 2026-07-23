module Application.Billing.Persistence
    ( lockVenueForCheckout
    )
where

import Data.Tuple.Only (Only (..))
import IHP.ControllerPrelude
import IHP.ModelSupport (sqlQuery)

-- IHP QueryBuilder does not expose SELECT ... FOR UPDATE. Keep the unavoidable
-- locking SQL isolated here rather than embedding it in controllers or the
-- Checkout state machine.
lockVenueForCheckout :: (?modelContext :: ModelContext) => UUID -> IO ()
lockVenueForCheckout venueId = do
    lockedVenueIds :: [Only UUID] <-
        sqlQuery
            "SELECT id FROM venues WHERE id = ? FOR UPDATE"
            (Only venueId)
    unless (length lockedVenueIds == 1) do
        error "Unable to lock the venue for Checkout"
