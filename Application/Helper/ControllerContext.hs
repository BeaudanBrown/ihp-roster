{-# LANGUAGE TypeApplications #-}

module Application.Helper.ControllerContext where

import Data.Coerce (coerce)
import Data.List (find, sortOn)
import Generated.Types
import IHP.Controller.Context (maybeFromContext, putContext)
import IHP.ControllerPrelude
import Network.Wai (Request)
import System.IO.Unsafe (unsafePerformIO)
import Web.Routes ()
import Web.Types ()

import Application.Helper.ControllerSupport

currentVenueSessionKey :: ByteString
currentVenueSessionKey = "currentVenueId"

withRequestContext :: (?context :: ControllerContext) => ((?request :: Request) => value) -> value
withRequestContext action =
    let ?request = ?context.request
    in action
{-# INLINE withRequestContext #-}

authenticatedCurrentUser :: (?context :: ControllerContext) => User
authenticatedCurrentUser =
    fromMaybe
        (error "authenticatedCurrentUser: initAuthentication has not populated the current user")
        (currentUserOrNothing @User)
{-# INLINE authenticatedCurrentUser #-}

newtype SupportVenueOptions = SupportVenueOptions { supportVenueOptions :: [Venue] }

currentVenueOrNothing :: (?context :: ControllerContext) => Maybe Venue
currentVenueOrNothing = unsafePerformIO (join <$> maybeFromContext @(Maybe Venue))
{-# NOINLINE currentVenueOrNothing #-}

currentVenue :: (?context :: ControllerContext) => Venue
currentVenue =
    fromMaybe (error "currentVenue: no active venue in controller context") currentVenueOrNothing

currentVenueId :: (?context :: ControllerContext) => Id Venue
currentVenueId = get #id currentVenue

currentVenueMembershipOrNothing :: (?context :: ControllerContext) => Maybe VenueMembership
currentVenueMembershipOrNothing = unsafePerformIO (join <$> maybeFromContext @(Maybe VenueMembership))
{-# NOINLINE currentVenueMembershipOrNothing #-}

currentVenueMembership :: (?context :: ControllerContext) => VenueMembership
currentVenueMembership =
    fromMaybe (error "currentVenueMembership: no active venue membership in controller context") currentVenueMembershipOrNothing

currentVenueRoleOrNothing :: (?context :: ControllerContext) => Maybe VenueRole
currentVenueRoleOrNothing = unsafePerformIO (join <$> maybeFromContext @(Maybe VenueRole))
{-# NOINLINE currentVenueRoleOrNothing #-}

currentSupportVenueOptionsOrNothing :: (?context :: ControllerContext) => Maybe [Venue]
currentSupportVenueOptionsOrNothing =
    case unsafePerformIO (maybeFromContext @SupportVenueOptions) of
        Nothing                           -> Nothing
        Just (SupportVenueOptions venues) -> Just venues
{-# NOINLINE currentSupportVenueOptionsOrNothing #-}

currentSupportVenueOptions :: (?context :: ControllerContext) => [Venue]
currentSupportVenueOptions = fromMaybe [] currentSupportVenueOptionsOrNothing

currentVenueRole :: (?context :: ControllerContext) => VenueRole
currentVenueRole =
    fromMaybe (error "currentVenueRole: no active venue role in controller context") currentVenueRoleOrNothing

currentUserPlatformRoleOrNothing :: (?context :: ControllerContext) => Maybe PlatformRole
currentUserPlatformRoleOrNothing =
    currentUserOrNothing @User >>= \user ->
        platformRoleEnumToRole <$> user.platformRole

currentUserIsSuperAdmin :: (?context :: ControllerContext) => Bool
currentUserIsSuperAdmin = currentUserPlatformRoleOrNothing == Just SuperAdminRole

selectCurrentVenueMembership :: Maybe (Id Venue) -> [VenueMembership] -> Maybe VenueMembership
selectCurrentVenueMembership sessionVenueId memberships =
    let orderedMemberships = sortOn (.createdAt) memberships
     in case sessionVenueId >>= \venueId -> find (\membership -> membership.venueId == coerce venueId) orderedMemberships of
            Just membership -> Just membership
            Nothing         -> listToMaybe orderedMemberships

initCurrentVenueContext :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO ()
initCurrentVenueContext = do
    supportVenues <-
        query @Venue
            |> filterWhere (#status, unsafeEnumFromText @VenueStatusEnum "active")
            |> orderByAsc #createdAt
            |> fetch

    putContext (Nothing :: Maybe Venue)
    putContext (Nothing :: Maybe VenueMembership)
    putContext (Nothing :: Maybe VenueRole)
    putContext (SupportVenueOptions supportVenues)

    forM_ (currentUserOrNothing @User) \user -> do
        sessionVenueId <- withRequestContext (getSession @(Id Venue) currentVenueSessionKey)
        maybeVenueContext <- resolveVenueContextForUser sessionVenueId user
        case maybeVenueContext of
            Nothing -> withRequestContext (deleteSession currentVenueSessionKey)
            Just (membership, venue, role) -> do
                putContext (Just venue)
                putContext membership
                putContext role
                withRequestContext (setSession currentVenueSessionKey (get #id venue))

resolveVenueContextForUser :: (?modelContext :: ModelContext) => Maybe (Id Venue) -> User -> IO (Maybe (Maybe VenueMembership, Venue, Maybe VenueRole))
resolveVenueContextForUser sessionVenueId user = do
    memberships <- query @VenueMembership
        |> filterWhere (#userId, unpackId (get #id user))
        |> filterWhere (#isActive, True)
        |> orderByAsc #createdAt
        |> fetch

    let venueIds = map (Id . (.venueId)) memberships
    venues <-
        if null venueIds
            then pure []
            else query @Venue
                |> filterWhereIn (#id, venueIds)
                |> filterWhere (#status, unsafeEnumFromText @VenueStatusEnum "active")
                |> fetch

    let activeVenueIds = map (coerce . (.id)) venues
    let activeMemberships = filter (\membership -> membership.venueId `elem` activeVenueIds) memberships

    let selectedMembership =
            selectCurrentVenueMembership sessionVenueId activeMemberships
    let selectedMembershipVenue =
            selectedMembership >>= \membership ->
                find (\candidate -> coerce (get #id candidate) == membership.venueId) venues

    if user.platformRole == Just (platformRoleToEnum SuperAdminRole)
        then do
            activeVenues <- query @Venue
                |> filterWhere (#status, unsafeEnumFromText @VenueStatusEnum "active")
                |> orderByAsc #createdAt
                |> fetch

            let selectedVenue =
                    (sessionVenueId >>= \venueId -> find (\candidate -> get #id candidate == venueId) activeVenues)
                        <|> selectedMembershipVenue
                        <|> listToMaybe activeVenues

            pure do
                venue <- selectedVenue
                let membership = find (\candidate -> candidate.venueId == unpackId (get #id venue)) activeMemberships
                let role = membership >>= parseVenueRole . (.venueRole)
                pure (membership, venue, role)
        else
            pure do
                membership <- selectedMembership
                venue <- selectedMembershipVenue
                role <- parseVenueRole membership.venueRole
                pure (Just membership, venue, Just role)
