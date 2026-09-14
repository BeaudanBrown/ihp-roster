{-# LANGUAGE TypeApplications #-}
{-# OPTIONS_GHC -fno-cse -fno-full-laziness #-}

module Application.Helper.ControllerContext where

import Application.Error.Runtime (ExternalRuntimeCategory (..), externalRuntimeInvariantFailure)
import Data.Coerce (coerce)
import Generated.Types
import qualified Data.Vault.Lazy as Vault
import IHP.RequestVault.Helper (insertNewIORefVaultMiddleware, lookupRequestVault)
import IHP.ControllerPrelude
import Network.Wai (Middleware)
import System.IO.Unsafe (unsafePerformIO)
import Web.Routes ()
import Web.Types ()

import Application.Helper.Profiling (profileActionSpan)
import Application.Helper.Telemetry (withTelemetrySpan)

-- Mutable application state is allocated once per request, never globally.
-- Auth identity remains in IHP's immutable vault entries and is validated before
-- this state is populated; venue/support mutations cannot replace auth identity.
data RequestVenueState = RequestVenueState
    { venue :: !(Maybe Venue)
    , membership :: !(Maybe VenueMembership)
    , role :: !(Maybe VenueRoleEnum)
    , selection :: !CurrentVenueSelection
    , supportVenues :: !SupportVenueOptions
    , supportUsers :: !SupportImpersonationOptions
    , impersonation :: !(Maybe ImpersonationRequestContext)
    , effectiveStaff :: !EffectiveStaffContext
    , returnFallback :: !ImpersonationReturnFallbackContext
    , billingNavigation :: !BillingNavigationContext
    , privateFeedback :: !Int
    }

-- Navigation facts, not a Stripe client dependency: generators also consume
-- this context module and must not acquire provider IO through these fields.
data BillingNavigationContext = BillingNavigationContext
    { ownerBillingNavigationVisible :: !Bool
    , ownerBillingSubscriptionIsLive :: !Bool
    }
    deriving (Eq, Show)

requestVenueStateKey :: Vault.Key (IORef RequestVenueState)
requestVenueStateKey = unsafePerformIO Vault.newKey
{-# NOINLINE requestVenueStateKey #-}

venueRequestStateMiddleware :: Middleware
venueRequestStateMiddleware = insertNewIORefVaultMiddleware requestVenueStateKey RequestVenueState
    { venue = Nothing
    , membership = Nothing
    , role = Nothing
    , selection = CurrentVenueSelection Nothing Nothing
    , supportVenues = SupportVenueOptions []
    , supportUsers = SupportImpersonationOptions []
    , impersonation = Nothing
    , effectiveStaff = EffectiveStaffContext Nothing
    , returnFallback = ImpersonationReturnFallbackContext False
    , billingNavigation = BillingNavigationContext False False
    , privateFeedback = 0
    }

requestVenueState :: (?context :: ControllerContext) => RequestVenueState
requestVenueState = unsafePerformIO (readIORef (lookupRequestVault requestVenueStateKey ?context))
{-# NOINLINE requestVenueState #-}

modifyRequestVenueState :: (?context :: ControllerContext) => (RequestVenueState -> RequestVenueState) -> IO ()
modifyRequestVenueState update =
    atomicModifyIORef' (lookupRequestVault requestVenueStateKey ?context) (\state -> (update state, ()))

currentVenueSessionKey :: ByteString
currentVenueSessionKey = "currentVenueId"

withRequestContext :: (?context :: ControllerContext) => ((?request :: Request) => value) -> value
withRequestContext action =
    let ?request = ?context
    in action
{-# INLINE withRequestContext #-}

authenticatedCurrentUser :: (?context :: ControllerContext) => User
authenticatedCurrentUser =
    fromMaybe
        (externalRuntimeInvariantFailure AuthorizedFrameworkInvariant "authenticatedCurrentUser: authentication middleware has not populated the current user")
        (withRequestContext (currentUserOrNothing @User))
{-# INLINE authenticatedCurrentUser #-}

newtype SupportVenueOptions = SupportVenueOptions { supportVenueOptions :: [Venue] }

newtype SupportImpersonationOptions = SupportImpersonationOptions { supportImpersonationOptions :: [SupportImpersonationOption] }

data SupportImpersonationOption = SupportImpersonationOption
    { supportImpersonationUserId :: !(Id User)
    , supportImpersonationLabel  :: !Text
    , supportImpersonationRole   :: !VenueRoleEnum
    }
    deriving (Eq, Show)

data CurrentVenueSelection = CurrentVenueSelection
    { requestedVenueId :: !(Maybe (Id Venue))
    , resolvedVenueId  :: !(Maybe (Id Venue))
    }

currentVenueSelection :: (?context :: ControllerContext) => CurrentVenueSelection
currentVenueSelection = requestVenueState.selection
{-# NOINLINE currentVenueSelection #-}

currentVenueSelectionIsExact :: (?context :: ControllerContext) => Bool
currentVenueSelectionIsExact =
    case currentVenueSelection of
        CurrentVenueSelection { requestedVenueId = Just requested, resolvedVenueId = Just resolved } -> requested == resolved
        _ -> False

newtype ActualUser = ActualUser { actualUserRecord :: User }
    deriving (Eq, Show)

newtype EffectiveUser = EffectiveUser { effectiveUserRecord :: User }
    deriving (Eq, Show)

newtype EffectiveStaffContext = EffectiveStaffContext { effectiveStaffContextValue :: Maybe Staff }

newtype ImpersonationReturnFallbackContext = ImpersonationReturnFallbackContext
    { impersonationReturnFallbackVisible :: Bool
    }

data ImpersonationRequestContext = ImpersonationRequestContext
    { impersonationSessionId       :: !UUID
    , impersonationEffectiveUser   :: !EffectiveUser
    , impersonationVenueMembership :: !VenueMembership
    , impersonationVenueRole       :: !VenueRoleEnum
    , impersonationStaff           :: !(Maybe Staff)
    }
    deriving (Eq, Show)

actualAuthenticatedUser :: (?context :: ControllerContext) => ActualUser
actualAuthenticatedUser = ActualUser authenticatedCurrentUser

effectiveCurrentUser :: (?context :: ControllerContext) => User
effectiveCurrentUser = effectiveUserRecord effectiveRequestUser

effectiveRequestUser :: (?context :: ControllerContext) => EffectiveUser
effectiveRequestUser =
    maybe
        (EffectiveUser authenticatedCurrentUser)
        (.impersonationEffectiveUser)
        currentImpersonationOrNothing

currentImpersonationOrNothing :: (?context :: ControllerContext) => Maybe ImpersonationRequestContext
currentImpersonationOrNothing = requestVenueState.impersonation
{-# NOINLINE currentImpersonationOrNothing #-}

currentUserIsImpersonating :: (?context :: ControllerContext) => Bool
currentUserIsImpersonating = isJust currentImpersonationOrNothing

currentUserIsUnimpersonatedSuperAdmin :: (?context :: ControllerContext) => Bool
currentUserIsUnimpersonatedSuperAdmin = currentUserIsSuperAdmin && not currentUserIsImpersonating

effectiveVenueMembershipOrNothing :: (?context :: ControllerContext) => Maybe VenueMembership
effectiveVenueMembershipOrNothing =
    (.impersonationVenueMembership) <$> currentImpersonationOrNothing
        <|> currentVenueMembershipOrNothing

effectiveVenueRoleOrNothing :: (?context :: ControllerContext) => Maybe VenueRoleEnum
effectiveVenueRoleOrNothing =
    (.impersonationVenueRole) <$> currentImpersonationOrNothing
        <|> currentVenueRoleOrNothing

currentImpersonationReturnFallbackVisible :: (?context :: ControllerContext) => Bool
currentImpersonationReturnFallbackVisible =
    requestVenueState.returnFallback.impersonationReturnFallbackVisible
{-# NOINLINE currentImpersonationReturnFallbackVisible #-}

effectiveStaffOrNothing :: (?context :: ControllerContext) => Maybe Staff
effectiveStaffOrNothing =
    requestVenueState.effectiveStaff.effectiveStaffContextValue
{-# NOINLINE effectiveStaffOrNothing #-}

currentVenueOrNothing :: (?context :: ControllerContext) => Maybe Venue
currentVenueOrNothing = requestVenueState.venue
{-# NOINLINE currentVenueOrNothing #-}

currentVenue :: (?context :: ControllerContext) => Venue
currentVenue =
    fromMaybe (externalRuntimeInvariantFailure AuthorizedFrameworkInvariant "currentVenue: no active venue in controller context") currentVenueOrNothing

currentVenueId :: (?context :: ControllerContext) => Id Venue
currentVenueId = get #id currentVenue

currentVenueMembershipOrNothing :: (?context :: ControllerContext) => Maybe VenueMembership
currentVenueMembershipOrNothing = requestVenueState.membership
{-# NOINLINE currentVenueMembershipOrNothing #-}


currentVenueRoleOrNothing :: (?context :: ControllerContext) => Maybe VenueRoleEnum
currentVenueRoleOrNothing = requestVenueState.role
{-# NOINLINE currentVenueRoleOrNothing #-}

currentSupportVenueOptionsOrNothing :: (?context :: ControllerContext) => Maybe [Venue]
currentSupportVenueOptionsOrNothing =
    Just requestVenueState.supportVenues.supportVenueOptions
{-# NOINLINE currentSupportVenueOptionsOrNothing #-}

currentSupportVenueOptions :: (?context :: ControllerContext) => [Venue]
currentSupportVenueOptions = fromMaybe [] currentSupportVenueOptionsOrNothing

currentSupportImpersonationOptions :: (?context :: ControllerContext) => [SupportImpersonationOption]
currentSupportImpersonationOptions =
    requestVenueState.supportUsers.supportImpersonationOptions
{-# NOINLINE currentSupportImpersonationOptions #-}

currentUserPlatformRoleOrNothing :: (?context :: ControllerContext) => Maybe PlatformRoleEnum
currentUserPlatformRoleOrNothing =
    withRequestContext (currentUserOrNothing @User) >>= \user ->
        user.platformRole

currentUserIsSuperAdmin :: (?context :: ControllerContext) => Bool
currentUserIsSuperAdmin = currentUserPlatformRoleOrNothing == Just SuperAdmin

selectCurrentVenueMembership :: Maybe (Id Venue) -> [VenueMembership] -> Maybe VenueMembership
selectCurrentVenueMembership sessionVenueId memberships =
    let orderedMemberships = sortOn (.createdAt) memberships
     in case sessionVenueId >>= \venueId -> find (\membership -> membership.venueId == coerce venueId) orderedMemberships of
            Just membership -> Just membership
            Nothing         -> listToMaybe orderedMemberships

initCurrentVenueContext :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO ()
initCurrentVenueContext =
    profileActionSpan "context.current_venue.init" do
        supportVenues <-
            profileActionSpan "context.current_venue.fetch_support_options" do
                query @Venue
                    |> filterWhere (#status, Active)
                    |> orderByAsc #createdAt
                    |> fetch

        modifyRequestVenueState \state -> state
            { venue = Nothing
            , membership = Nothing
            , role = Nothing
            , supportVenues = SupportVenueOptions supportVenues
            , selection = CurrentVenueSelection Nothing Nothing
            }

        forM_ (withRequestContext (currentUserOrNothing @User)) \user -> do
            sessionVenueId <- withRequestContext (getSession @(Id Venue) currentVenueSessionKey)
            maybeVenueContext <- profileActionSpan "context.current_venue.resolve_for_user" (resolveVenueContextForUser sessionVenueId user)
            case maybeVenueContext of
                Nothing -> do
                    modifyRequestVenueState \state -> state { selection = CurrentVenueSelection sessionVenueId Nothing }
                    withRequestContext (deleteSession currentVenueSessionKey)
                Just (membership, venue, role) -> do
                    modifyRequestVenueState \state -> state
                        { selection = CurrentVenueSelection sessionVenueId (Just venue.id)
                        , venue = Just venue
                        , membership = membership
                        , role = role
                        }
                    withRequestContext (setSession currentVenueSessionKey (get #id venue))

resolveVenueContextForUser :: (?modelContext :: ModelContext) => Maybe (Id Venue) -> User -> IO (Maybe (Maybe VenueMembership, Venue, Maybe VenueRoleEnum))
resolveVenueContextForUser sessionVenueId user = do
    memberships <- withTelemetrySpan "context.current_venue.fetch_memberships" do
        query @VenueMembership
            |> filterWhere (#userId, unpackId (get #id user))
            |> filterWhere (#isActive, True)
            |> orderByAsc #createdAt
            |> fetch

    let venueIds = map (Id . (.venueId)) memberships
    venues <-
        withTelemetrySpan "context.current_venue.fetch_member_venues" do
            if null venueIds
                then pure []
                else query @Venue
                    |> filterWhereIn (#id, venueIds)
                    |> filterWhere (#status, Active)
                    |> fetch

    let activeVenueIds = map (coerce . (.id)) venues
    let activeMemberships = filter (\membership -> membership.venueId `elem` activeVenueIds) memberships

    let selectedMembership =
            selectCurrentVenueMembership sessionVenueId activeMemberships
    let selectedMembershipVenue =
            selectedMembership >>= \membership ->
                find (\candidate -> coerce (get #id candidate) == membership.venueId) venues

    if user.platformRole == Just (SuperAdmin)
        then do
            activeVenues <- withTelemetrySpan "context.current_venue.fetch_super_admin_venues" do
                query @Venue
                    |> filterWhere (#status, Active)
                    |> orderByAsc #createdAt
                    |> fetch

            let selectedVenue =
                    (sessionVenueId >>= \venueId -> find (\candidate -> get #id candidate == venueId) activeVenues)
                        <|> selectedMembershipVenue
                        <|> listToMaybe activeVenues

            pure do
                venue <- selectedVenue
                let membership = find (\candidate -> candidate.venueId == unpackId (get #id venue)) activeMemberships
                let role = (.venueRole) <$> membership
                pure (membership, venue, role)
        else
            pure do
                membership <- selectedMembership
                venue <- selectedMembershipVenue
                pure (Just membership, venue, Just membership.venueRole)
