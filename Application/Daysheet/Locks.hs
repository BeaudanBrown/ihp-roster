-- | Narrow serialization primitive. All business reads/writes remain in the
-- typed QueryBuilder. Lock venue first, then membership, for every lifecycle
-- mutation including the first configuration/capture creation.
module Application.Daysheet.Locks (lockDaysheetAuthority, lockDaysheetVenue) where

import Database.PostgreSQL.Simple (Only (..))
import Generated.Types
import IHP.ModelSupport (unsafeSqlQuery, unpackId)
import IHP.Prelude

lockDaysheetAuthority :: (?modelContext :: ModelContext) => VenueMembership -> IO Bool
lockDaysheetAuthority membership = do
    venueLocked <- lockDaysheetVenue membership.venueId
    members :: [Only UUID] <- unsafeSqlQuery
        "SELECT id FROM venue_memberships WHERE id = ? AND venue_id = ? AND user_id = ? FOR UPDATE"
        (unpackId membership.id, membership.venueId, membership.userId)
    pure (venueLocked && members == [Only (unpackId membership.id)])

-- Scheduled capture has no fabricated user/membership. It shares precisely the
-- same venue serialization boundary as daily edits and recipient management.
lockDaysheetVenue :: (?modelContext :: ModelContext) => UUID -> IO Bool
lockDaysheetVenue venueId = do
    venues :: [Only UUID] <- unsafeSqlQuery "SELECT id FROM venues WHERE id = ? FOR UPDATE" (Only venueId)
    pure (venues == [Only venueId])
