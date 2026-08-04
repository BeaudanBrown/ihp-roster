module Application.Helper.Impersonation
    ( clearImpersonationSession
    , effectiveUserSessionKey
    , enterCurrentVenueImpersonation
    , exitCurrentImpersonation
    , impersonationSessionIdSessionKey
    , initImpersonationContext
    ) where

import Control.Monad (void)
import qualified Data.Aeson as Aeson
import qualified Data.UUID as UUID
import qualified Data.UUID.V4 as UUIDv4
import Generated.Types
import IHP.Controller.Context (putContext)
import IHP.ControllerPrelude

import Application.Helper.Audit (AuditEventType (..),
                                 attachImpersonationAuditRequestContext,
                                 recordAuditEvent, recordCurrentUserAuditEvent)
import Application.Helper.ControllerContext
import Application.Helper.Htmx (requestAuditSourceChannel)

effectiveUserSessionKey :: ByteString
effectiveUserSessionKey = "supportImpersonationEffectiveUserId"

impersonationSessionIdSessionKey :: ByteString
impersonationSessionIdSessionKey = "supportImpersonationSessionId"

initImpersonationContext :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO ()
initImpersonationContext = do
    putContext (Nothing :: Maybe ImpersonationRequestContext)
    initAuthenticatedEffectiveStaffContext
    maybeEffectiveUserId <- withRequestContext (getSession @(Id User) effectiveUserSessionKey)
    maybeSessionIdText <- withRequestContext (getSession @Text impersonationSessionIdSessionKey)
    let maybeSessionId = maybeSessionIdText >>= UUID.fromText
    case (maybeEffectiveUserId, maybeSessionId) of
        (Nothing, Nothing) | isNothing maybeSessionIdText -> pure ()
        (Just effectiveUserId, Just sessionId)
            | currentUserIsSuperAdmin && isJust currentVenueOrNothing ->
                resolveImpersonationRequestContext effectiveUserId sessionId >>= \case
                    Just impersonationContext -> activateImpersonationContext impersonationContext
                    Nothing -> expireImpersonationSession effectiveUserId sessionId "target_unavailable"
        (maybeEffectiveUserId', _) ->
            expireIncompleteImpersonationSession maybeEffectiveUserId' maybeSessionIdText

enterCurrentVenueImpersonation ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    Id User ->
    IO (Maybe ImpersonationRequestContext)
enterCurrentVenueImpersonation effectiveUserId
    | not currentUserIsSuperAdmin = pure Nothing
    | isNothing currentVenueOrNothing = pure Nothing
    | otherwise = do
        sessionId <- UUIDv4.nextRandom
        resolveImpersonationRequestContext effectiveUserId sessionId >>= \case
            Nothing -> pure Nothing
            Just impersonationContext -> do
                withRequestContext do
                    setSession effectiveUserSessionKey effectiveUserId
                    setSession impersonationSessionIdSessionKey (UUID.toText sessionId)
                activateImpersonationContext impersonationContext
                void $
                    recordCurrentUserAuditEvent
                        SupportImpersonationEnteredAudit
                        "users"
                        (unpackId effectiveUserId)
                        (Aeson.object [])
                pure (Just impersonationContext)

exitCurrentImpersonation ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    Text ->
    IO Bool
exitCurrentImpersonation reason =
    case currentImpersonationOrNothing of
        Nothing -> do
            clearImpersonationSession
            pure False
        Just impersonationContext -> do
            let effectiveUser = effectiveUserRecord impersonationContext.impersonationEffectiveUser
            void $
                recordCurrentUserAuditEvent
                    SupportImpersonationExitedAudit
                    "users"
                    (unpackId effectiveUser.id)
                    (Aeson.object ["reason" Aeson..= reason])
            clearImpersonationSession
            pure True

resolveImpersonationRequestContext ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    Id User ->
    UUID ->
    IO (Maybe ImpersonationRequestContext)
resolveImpersonationRequestContext effectiveUserId sessionId = do
    maybeEffectiveUser <-
        query @User
            |> filterWhere (#id, effectiveUserId)
            |> filterWhere (#deactivatedAt, Nothing)
            |> fetchOneOrNothing
    maybeMembership <-
        query @VenueMembership
            |> filterWhere (#venueId, unpackId currentVenueId)
            |> filterWhere (#userId, unpackId effectiveUserId)
            |> filterWhere (#isActive, True)
            |> filterWhere (#archivedAt, Nothing)
            |> fetchOneOrNothing
    maybeStaff <-
        query @Staff
            |> filterWhere (#venueId, unpackId currentVenueId)
            |> filterWhere (#userId, Just (unpackId effectiveUserId))
            |> filterWhere (#isActive, True)
            |> filterWhere (#archivedAt, Nothing)
            |> fetchOneOrNothing
    pure do
        effectiveUser <- maybeEffectiveUser
        membership <- maybeMembership
        pure ImpersonationRequestContext
            { impersonationSessionId = sessionId
            , impersonationEffectiveUser = EffectiveUser effectiveUser
            , impersonationVenueMembership = membership
            , impersonationVenueRole = membership.venueRole
            , impersonationStaff = maybeStaff
            }

activateImpersonationContext :: (?context :: ControllerContext) => ImpersonationRequestContext -> IO ()
activateImpersonationContext impersonationContext = do
    putContext (Just impersonationContext)
    putContext (EffectiveStaffContext impersonationContext.impersonationStaff)

initAuthenticatedEffectiveStaffContext ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    IO ()
initAuthenticatedEffectiveStaffContext = do
    putContext (EffectiveStaffContext Nothing)
    forM_ ((,) <$> currentUserOrNothing @User <*> currentVenueOrNothing) \(user, venue) -> do
        maybeStaff <-
            query @Staff
                |> filterWhere (#venueId, unpackId venue.id)
                |> filterWhere (#userId, Just (unpackId user.id))
                |> filterWhere (#isActive, True)
                |> filterWhere (#archivedAt, Nothing)
                |> fetchOneOrNothing
        putContext (EffectiveStaffContext maybeStaff)

expireImpersonationSession ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    Id User ->
    UUID ->
    Text ->
    IO ()
expireImpersonationSession effectiveUserId sessionId reason = do
    recordImpersonationExpiry
        effectiveUserId
        (Aeson.toJSON effectiveUserId)
        (Aeson.toJSON sessionId)
        reason
    clearImpersonationSession
    withRequestContext (setErrorMessage "Support impersonation ended because the selected user is no longer available.")

expireIncompleteImpersonationSession ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    Maybe (Id User) ->
    Maybe Text ->
    IO ()
expireIncompleteImpersonationSession maybeEffectiveUserId maybeSessionIdText = do
    let targetUserId = fromMaybe authenticatedCurrentUser.id maybeEffectiveUserId
    recordImpersonationExpiry
        targetUserId
        (maybe Aeson.Null Aeson.toJSON maybeEffectiveUserId)
        (maybe Aeson.Null Aeson.toJSON maybeSessionIdText)
        "invalid_session_state"
    clearImpersonationSession
    withRequestContext (setErrorMessage "Support impersonation ended because its session state was invalid.")

recordImpersonationExpiry ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    Id User ->
    Aeson.Value ->
    Aeson.Value ->
    Text ->
    IO ()
recordImpersonationExpiry targetUserId effectiveUserIdValue sessionIdValue reason =
    when (currentUserIsSuperAdmin && isJust currentVenueOrNothing) do
        void $
            recordAuditEvent
                (unpackId currentVenueId)
                (unpackId (get #id authenticatedCurrentUser))
                SupportImpersonationExpiredAudit
                "users"
                (unpackId targetUserId)
                ( attachImpersonationAuditRequestContext
                    effectiveUserIdValue
                    sessionIdValue
                    (Aeson.object ["reason" Aeson..= reason])
                )
                requestAuditSourceChannel

clearImpersonationSession :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO ()
clearImpersonationSession = do
    withRequestContext do
        deleteSession effectiveUserSessionKey
        deleteSession impersonationSessionIdSessionKey
    putContext (Nothing :: Maybe ImpersonationRequestContext)
    initAuthenticatedEffectiveStaffContext
