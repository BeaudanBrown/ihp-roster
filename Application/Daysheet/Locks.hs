-- | Narrow serialization primitive. All business reads/writes remain in the
-- typed QueryBuilder. Lock venue first, then membership, for every lifecycle
-- mutation including the first configuration/capture creation.
module Application.Daysheet.Locks (lockDaysheetAuthority) where

import Database.PostgreSQL.Simple (Only (..))
import Generated.Types
import IHP.ModelSupport (unsafeSqlQuery, unpackId)
import IHP.Prelude

lockDaysheetAuthority :: (?modelContext :: ModelContext) => VenueMembership -> IO Bool
lockDaysheetAuthority membership = do
    venues :: [Only UUID] <- unsafeSqlQuery "SELECT id FROM venues WHERE id = ? FOR UPDATE" (Only membership.venueId)
    members :: [Only UUID] <- unsafeSqlQuery
        "SELECT id FROM venue_memberships WHERE id = ? AND venue_id = ? AND user_id = ? FOR UPDATE"
        (unpackId membership.id, membership.venueId, membership.userId)
    pure (venues == [Only membership.venueId] && members == [Only (unpackId membership.id)])
