module Application.Helper.Impersonation
    ( clearImpersonationSession
    , effectiveUserSessionKey
    , enterCurrentVenueImpersonation
    , exitCurrentImpersonation
    , impersonationReturnFallbackMessage
    , markImpersonationReturnFallback
    , clearImpersonationReturnFallback
    , impersonationSessionIdSessionKey
    , initImpersonationContext
    , initSupportImpersonationOptions
    ) where

import Control.Monad (void)
import qualified Data.Aeson as Aeson
import Data.List (sortOn)
import qualified Data.Map.Strict as Map
import qualified Data.Text as Text
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
import Application.VenueRole (venueRoleLabel)

effectiveUserSessionKey :: ByteString
effectiveUserSessionKey = "supportImpersonationEffectiveUserId"

impersonationSessionIdSessionKey :: ByteString
impersonationSessionIdSessionKey = "supportImpersonationSessionId"

impersonationReturnFallbackSessionKey :: ByteString
impersonationReturnFallbackSessionKey = "supportImpersonationReturnFallback"

impersonationReturnFallbackMessage :: Text
impersonationReturnFallbackMessage =
    "That page is not available for the resulting account. Showing its Roster instead."

markImpersonationReturnFallback :: (?context :: ControllerContext, ?request :: Request) => IO ()
markImpersonationReturnFallback =
    setSession impersonationReturnFallbackSessionKey True

clearImpersonationReturnFallback :: (?context :: ControllerContext, ?request :: Request) => IO ()
clearImpersonationReturnFallback =
    deleteSession impersonationReturnFallbackSessionKey

initSupportImpersonationOptions :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO ()
initSupportImpersonationOptions = do
    putContext (SupportImpersonationOptions [])
    when (currentUserIsSuperAdmin && isJust currentVenueOrNothing) do
        memberships <- query @VenueMembership
            |> filterWhere (#venueId, unpackId currentVenueId)
            |> filterWhere (#isActive, True)
            |> filterWhere (#archivedAt, Nothing)
            |> fetch
        let selectableMemberships = memberships
        unless (null selectableMemberships) do
            users <- query @User
                |> filterWhereIn (#id, map (Id . (.userId)) selectableMemberships)
                |> filterWhere (#deactivatedAt, Nothing)
                |> fetch
            staffRows <- query @Staff
                |> filterWhere (#venueId, unpackId currentVenueId)
                |> filterWhereIn (#userId, map (Just . (.userId)) selectableMemberships)
                |> filterWhere (#isActive, True)
                |> filterWhere (#archivedAt, Nothing)
                |> fetch
            let usersById = Map.fromList [(unpackId user.id, user) | user <- users]
            let staffByUserId = Map.fromList [(userId, staff) | staff <- staffRows, Just userId <- [staff.userId]]
            let candidates = mapMaybe (supportImpersonationCandidate usersById staffByUserId) selectableMemberships
            let nameCounts = Map.fromListWith (+) [(Text.toCaseFold baseName, 1 :: Int) | (_, _, baseName, _) <- candidates]
            let options =
                    candidates
                        |> map (supportImpersonationOption nameCounts)
                        |> sortOn (Text.toCaseFold . (.supportImpersonationLabel))
            putContext (SupportImpersonationOptions options)

supportImpersonationCandidate
    :: Map.Map UUID User
    -> Map.Map UUID Staff
    -> VenueMembership
    -> Maybe (Id User, VenueRoleEnum, Text, Maybe Text)
supportImpersonationCandidate usersById staffByUserId membership = do
    user <- Map.lookup membership.userId usersById
    let maybeStaff = Map.lookup membership.userId staffByUserId
    let baseName = maybe "Venue user" (\staff -> fromMaybe staff.firstName staff.preferredName) maybeStaff
    pure (user.id, membership.venueRole, baseName, (.lastName) <$> maybeStaff)

supportImpersonationOption
    :: Map.Map Text Int
    -> (Id User, VenueRoleEnum, Text, Maybe Text)
    -> SupportImpersonationOption
supportImpersonationOption nameCounts (userId, venueRole, baseName, maybeLastName) =
    SupportImpersonationOption
        { supportImpersonationUserId = userId
        , supportImpersonationLabel = disambiguatedName <> " — " <> venueRoleLabel venueRole
        , supportImpersonationRole = venueRole
        }
    where
        disambiguatedName
            | Map.findWithDefault 0 (Text.toCaseFold baseName) nameCounts > 1
            , Just lastName <- maybeLastName =
                baseName <> " " <> Text.take 1 lastName <> "."
            | otherwise = baseName

initImpersonationContext :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO ()
initImpersonationContext = do
    putContext (Nothing :: Maybe ImpersonationRequestContext)
    fallbackVisible <- withRequestContext (getSession @Bool impersonationReturnFallbackSessionKey)
    putContext ImpersonationReturnFallbackContext
        { impersonationReturnFallbackVisible = fallbackVisible == Just True }
    initAuthenticatedEffectiveStaffContext
    maybeEffectiveUserId <- withRequestContext (getSession @(Id User) effectiveUserSessionKey)
    maybeSessionIdText <- withRequestContext (getSession @Text impersonationSessionIdSessionKey)
    let maybeSessionId = maybeSessionIdText >>= UUID.fromText
    case (maybeEffectiveUserId, maybeSessionId) of
        (Nothing, Nothing) | isNothing maybeSessionIdText -> pure ()
        (Just effectiveUserId, Just sessionId)
            | currentUserIsSuperAdmin && currentVenueSelectionIsExact ->
                resolveImpersonationRequestContext effectiveUserId sessionId >>= \case
                    Just impersonationContext -> activateImpersonationContext impersonationContext
                    Nothing -> expireImpersonationSession effectiveUserId sessionId "target_unavailable"
            | currentUserIsSuperAdmin ->
                expireInvalidVenueImpersonation effectiveUserId sessionId
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

expireInvalidVenueImpersonation ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    Id User ->
    UUID ->
    IO ()
expireInvalidVenueImpersonation effectiveUserId sessionId = do
    recordImpersonationExpiry
        effectiveUserId
        (Aeson.toJSON effectiveUserId)
        (Aeson.toJSON sessionId)
        "selected_venue_unavailable"
    clearImpersonationSession
    withRequestContext (setErrorMessage "Support impersonation ended because the selected venue is no longer available.")

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
recordImpersonationExpiry targetUserId effectiveUserIdValue sessionIdValue reason = do
    maybeRequestedAuditVenueId <-
        case currentVenueSelection.requestedVenueId of
            Nothing -> pure Nothing
            Just requestedVenueId ->
                query @Venue
                    |> filterWhere (#id, requestedVenueId)
                    |> fetchOneOrNothing
                    |> fmap (fmap (.id))
    forM_ (maybeRequestedAuditVenueId <|> fmap (.id) currentVenueOrNothing) \auditVenueId ->
        void $
            recordAuditEvent
                (unpackId auditVenueId)
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
        clearImpersonationReturnFallback
    putContext (Nothing :: Maybe ImpersonationRequestContext)
    initAuthenticatedEffectiveStaffContext
