{-# LANGUAGE RankNTypes #-}
module Application.Daysheet.Authority (withAuthority) where

import Application.Daysheet.Locks
import Application.Daysheet.StorageError (StorageError (AccessDenied))
import Application.Error.Domain (projectDomainError)
import Application.Error.Transaction (withAppResultTransaction)
import Application.Error.Types
import Control.Monad.Trans.Except (ExceptT, runExceptT, throwE)
import Generated.Types
import IHP.Fetch (fetchOneOrNothing)
import IHP.ModelSupport
import IHP.Prelude
import IHP.QueryBuilder

-- | The caller supplies its current authenticated membership, never a
-- request-selected actor. Re-read authority inside the lifecycle transaction.
withAuthority :: (?modelContext :: ModelContext) => VenueMembership -> [VenueRoleEnum] -> ((?modelContext :: ModelContext) => ExceptT AppError IO a) -> IO (AppResult a)
withAuthority expected roles action = withAppResultTransaction $ runExceptT do
    locked <- liftIO (lockDaysheetAuthority expected)
    unless locked denied
    current <- liftIO (query @VenueMembership |> filterWhere (#id, expected.id) |> fetchOneOrNothing)
    venue <- liftIO (query @Venue |> filterWhere (#id, Id expected.venueId) |> fetchOneOrNothing)
    user <- liftIO (query @User |> filterWhere (#id, Id expected.userId) |> fetchOneOrNothing)
    case (current, venue, user) of
        (Just member, Just currentVenue, Just currentUser)
            | member.isActive && isNothing member.archivedAt
              && member.venueRole `elem` roles && currentVenue.status == Active
              && isNothing currentVenue.closedAt && isNothing currentUser.deactivatedAt -> action
        _ -> denied
  where
    denied = throwE (projectDomainError AccessDenied)
