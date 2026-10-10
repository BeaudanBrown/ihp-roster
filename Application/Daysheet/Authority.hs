{-# LANGUAGE RankNTypes #-}
-- | Explicit Daysheet authority. Membership and founder support are distinct;
-- every operation rechecks the relevant live authority inside its transaction.
module Application.Daysheet.Authority
    ( DaysheetAccess (venueId, userId), memberAccess, currentDaysheetAccess
    , withAuthority, recordDaysheetAuditEvent
    ) where

import Application.Daysheet.Locks
import Application.Daysheet.StorageError (StorageError (AccessDenied))
import Application.Error.Domain (projectDomainError)
import Application.Error.Transaction (withAppResultTransaction)
import Application.Error.Types
import Application.Helper.ControllerContext
import Application.Helper.Audit (recordAuditEvent, attachSupportAuditRequestContext, attachImpersonationAuditRequestContext)
import Application.Helper.Audit.Vocabulary
import Control.Monad.Trans.Except (ExceptT, runExceptT, throwE)
import qualified Data.Aeson as Aeson
import Generated.Types
import IHP.ControllerPrelude

-- Constructors are private: request identity comes only from initialized context.
-- userId is always the actual actor, including while impersonating.
data DaysheetAccess = DaysheetAccess
    { venueId :: UUID
    , userId :: UUID
    , authority :: AccessMode
    }

data AccessMode
    = MemberAccess VenueMembership
    | FounderAccess
    | ImpersonatedAccess VenueMembership UUID

memberAccess :: VenueMembership -> DaysheetAccess
memberAccess member = DaysheetAccess member.venueId member.userId (MemberAccess member)

currentDaysheetAccess :: (?context :: ControllerContext) => Maybe DaysheetAccess
currentDaysheetAccess = do
    venue <- currentVenueOrNothing
    let actor = unpackId authenticatedCurrentUser.id
    case currentImpersonationOrNothing of
        Just context -> pure (DaysheetAccess (unpackId venue.id) actor
            (ImpersonatedAccess context.impersonationVenueMembership context.impersonationSessionId))
        Nothing | currentUserIsUnimpersonatedSuperAdmin -> pure (DaysheetAccess (unpackId venue.id) actor FounderAccess)
        Nothing -> do
            member <- currentVenueMembershipOrNothing
            if member.venueId == unpackId venue.id && member.userId == actor
                then Just (memberAccess member)
                else Nothing

withAuthority :: (?modelContext :: ModelContext) => DaysheetAccess -> [VenueRoleEnum] -> ((?modelContext :: ModelContext) => ExceptT AppError IO a) -> IO (AppResult a)
withAuthority expected roles action = withAppResultTransaction $ runExceptT do
    locked <- liftIO $ case expected.authority of
        FounderAccess -> lockDaysheetVenue expected.venueId
        MemberAccess member -> lockDaysheetAuthority member
        ImpersonatedAccess member _ -> lockDaysheetAuthority member
    unless locked denied
    venue <- liftIO (query @Venue |> filterWhere (#id, Id expected.venueId) |> fetchOneOrNothing)
    actor <- liftIO (query @User |> filterWhere (#id, Id expected.userId) |> fetchOneOrNothing)
    case (venue, actor) of
        (Just currentVenue, Just currentActor)
            | currentVenue.status == Active && isNothing currentVenue.closedAt && isNothing currentActor.deactivatedAt ->
                case expected.authority of
                    FounderAccess -> unless (currentActor.platformRole == Just SuperAdmin) denied
                    MemberAccess member -> do
                        unless (member.userId == expected.userId) denied
                        checkMember member
                    ImpersonatedAccess member _ -> do
                        unless (currentActor.platformRole == Just SuperAdmin) denied
                        checkMember member
        _ -> denied
    action
  where
    denied = throwE (projectDomainError AccessDenied)
    checkMember :: (?modelContext :: ModelContext) => VenueMembership -> ExceptT AppError IO ()
    checkMember member = do
        unless (member.venueId == expected.venueId) denied
        current <- liftIO (query @VenueMembership |> filterWhere (#id, member.id) |> fetchOneOrNothing)
        effective <- liftIO (query @User |> filterWhere (#id, Id member.userId) |> fetchOneOrNothing)
        case (current, effective) of
            (Just liveMember, Just liveUser)
                | liveMember.venueId == expected.venueId && liveMember.userId == member.userId
                  && liveMember.isActive && isNothing liveMember.archivedAt
                  && liveMember.venueRole `elem` roles && isNothing liveUser.deactivatedAt -> pure ()
            _ -> denied

recordDaysheetAuditEvent :: (?modelContext :: ModelContext) => DaysheetAccess -> AuditEventType -> Text -> UUID -> Aeson.Value -> AuditSourceChannel -> IO AuditEvent
recordDaysheetAuditEvent access event table key payload source =
    recordAuditEvent access.venueId access.userId event table key (annotate payload) source
  where
    annotate = case access.authority of
        MemberAccess _ -> \value -> value
        FounderAccess -> attachSupportAuditRequestContext
        ImpersonatedAccess member session -> attachImpersonationAuditRequestContext (Aeson.toJSON member.userId) (Aeson.toJSON session)
