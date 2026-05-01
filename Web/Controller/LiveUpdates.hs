module Web.Controller.LiveUpdates where

import Application.Helper.Controller
import Application.Helper.LiveUpdate
import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Lazy as LByteString
import Data.Coerce (coerce)
import qualified Data.UUID as UUID
import qualified Data.UUID.V4 as UUIDv4
import qualified Network.WebSockets as WebSocket
import Web.Controller.Prelude

instance WSApp LiveUpdatesWSApp where
    initialState = LiveUpdatesWSApp { subscriptionIds = [] }

    run = do
        ensureIsUser
        ensureProfileCompleted

        forever do
            message <- receiveData @LByteString.ByteString
            case Aeson.decode message of
                Nothing ->
                    sendJSON
                        LiveUpdatesError
                            { message = "Could not decode live update command"
                            }
                Just command ->
                    handleCommand command

    onClose = do
        LiveUpdatesWSApp { subscriptionIds } <- getState
        mapM_ (unregisterLiveSubscription . fst) subscriptionIds

handleCommand ::
    ( ?state :: IORef LiveUpdatesWSApp
    , ?connection :: WebSocket.Connection
    , ?context :: ControllerContext
    , ?modelContext :: ModelContext
    ) =>
    LiveUpdateCommand ->
    IO ()
handleCommand command =
    case command of
        SubscribeLiveUpdates { scope, lastSeenVersion } -> do
            authorized <- isAuthorizedScope scope
            if authorized
                then do
                    unregisterScopeSubscription scope
                    subscriptionId <- UUIDv4.nextRandom
                    registerLiveSubscription subscriptionId scope ?connection
                    addScopeSubscription subscriptionId scope
                    currentVersion <- liftIO (currentLiveUpdateVersion scope)
                    sendJSON
                        LiveUpdatesSubscribed
                            { scope
                            , scopeKey = liveUpdateScopeKey scope
                            , currentVersion
                            , resync = maybe False (/= currentVersion) lastSeenVersion
                            }
                else
                    sendJSON
                        LiveUpdatesError
                            { message = "Not authorized for requested live update scope"
                            }
        UnsubscribeLiveUpdates { scope } ->
            unregisterScopeSubscription scope

unregisterScopeSubscription ::
    (?state :: IORef LiveUpdatesWSApp) =>
    LiveUpdateScope ->
    IO ()
unregisterScopeSubscription scope = do
    LiveUpdatesWSApp { subscriptionIds } <- getState
    let (removed, kept) = partition (\(_, encodedScope) -> encodedScope == encodeScopeKey scope) subscriptionIds
    mapM_ (unregisterLiveSubscription . fst) removed
    setState LiveUpdatesWSApp { subscriptionIds = kept }

addScopeSubscription ::
    (?state :: IORef LiveUpdatesWSApp) =>
    UUID.UUID ->
    LiveUpdateScope ->
    IO ()
addScopeSubscription subscriptionId scope = do
    LiveUpdatesWSApp { subscriptionIds } <- getState
    setState
        LiveUpdatesWSApp
            { subscriptionIds = (subscriptionId, encodeScopeKey scope) : subscriptionIds
            }

encodeScopeKey :: LiveUpdateScope -> Text
encodeScopeKey = cs . Aeson.encode

isAuthorizedScope ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    LiveUpdateScope ->
    IO Bool
isAuthorizedScope =
    authorizeScopeRequirement . scopeAuthorizationRequirement

data ScopeAuthorizationRequirement
    = RequireCurrentVenue UUID.UUID
    | RequireCurrentVenueRosterGroup UUID.UUID UUID.UUID
    | RequireCurrentVenueAdmin UUID.UUID
    | RequireCurrentVenueAdminRosterGroup UUID.UUID UUID.UUID
    | RequireSupportSuperAdmin

scopeAuthorizationRequirement :: LiveUpdateScope -> ScopeAuthorizationRequirement
scopeAuthorizationRequirement RosterWeekScope { venueId, rosterGroupId } =
    RequireCurrentVenueRosterGroup venueId rosterGroupId
scopeAuthorizationRequirement AdminInvitesScope { venueId } =
    RequireCurrentVenueAdmin venueId
scopeAuthorizationRequirement AdminShiftTypesScope { venueId } =
    RequireCurrentVenueAdmin venueId
scopeAuthorizationRequirement AdminRosterGroupsScope { venueId } =
    RequireCurrentVenueAdmin venueId
scopeAuthorizationRequirement AdminXeroScope { venueId } =
    RequireCurrentVenueAdmin venueId
scopeAuthorizationRequirement LeaveRequestsScope { venueId } =
    RequireCurrentVenue venueId
scopeAuthorizationRequirement TimesheetWeekScope { venueId } =
    RequireCurrentVenue venueId
scopeAuthorizationRequirement SupportPlatformScope =
    RequireSupportSuperAdmin

authorizeScopeRequirement ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    ScopeAuthorizationRequirement ->
    IO Bool
authorizeScopeRequirement (RequireCurrentVenue venueId) =
    pure (currentVenueMatches venueId)
authorizeScopeRequirement (RequireCurrentVenueRosterGroup venueId rosterGroupId) =
    if currentVenueMatches venueId
        then isAuthorizedCurrentVenueRosterGroupScope rosterGroupId
        else pure False
authorizeScopeRequirement (RequireCurrentVenueAdmin venueId) =
    pure (currentVenueMatches venueId && hasRole VenueAdminRole)
authorizeScopeRequirement (RequireCurrentVenueAdminRosterGroup venueId rosterGroupId) =
    if currentVenueMatches venueId
        then do
            hasRosterGroupAccess <- isAuthorizedCurrentVenueRosterGroupScope rosterGroupId
            pure (hasRosterGroupAccess && hasRole VenueAdminRole)
        else pure False
authorizeScopeRequirement RequireSupportSuperAdmin =
    pure currentUserIsSuperAdmin

currentVenueMatches :: (?context :: ControllerContext) => UUID.UUID -> Bool
currentVenueMatches venueId =
    maybe False (\venue -> venueId == unpackId venue.id) currentVenueOrNothing

isAuthorizedCurrentVenueRosterGroupScope ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    UUID.UUID ->
    IO Bool
isAuthorizedCurrentVenueRosterGroupScope rosterGroupId = do
    case currentVenueOrNothing of
        Nothing -> pure False
        Just venue -> do
            rosterGroupOrNothing <-
                query @RosterGroup
                    |> filterWhere (#id, coerce rosterGroupId)
                    |> filterWhere (#venueId, unpackId venue.id)
                    |> fetchOneOrNothing
            pure (isJust rosterGroupOrNothing)
