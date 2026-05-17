module Web.Profiles.LiveUpdates
    ( ProfileContentFragment (..)
    , ProfileContentSurfaceKey (..)
    , ProfileLeaveFragment (..)
    , ProfileLeaveSurfaceKey (..)
    , currentProfileContentSurfaceKey
    , currentProfileLeaveSurfaceKey
    , profileContentFragment
    , profileContentLiveSurfaceDefinition
    , profileLeaveRequestsFragment
    , profileLeaveRequestsLiveSurfaceDefinition
    , refreshProfileContent
    , refreshProfileContentForStaffId
    , refreshProfileLeaveRequests
    , refreshProfileLeaveRequestsForStaffId
    ) where

import Application.Helper.Controller (currentVenueOrNothing)
import Application.Helper.ControllerContext (authenticatedCurrentUser)
import Application.Helper.LiveSurface
import Application.Helper.LiveUpdate
import Application.Helper.Url (appendQueryParams)
import Web.Controller.Prelude

profileContentFragmentId :: Text
profileContentFragmentId = "profile-content-fragment"

profileDetailsFormId :: Text
profileDetailsFormId = "profile-details-form"

profileLeaveRequestsContentFragmentId :: Text
profileLeaveRequestsContentFragmentId = "profile-leave-requests-content"

data ProfileContentSurface

data ProfileContentSurfaceKey = ProfileContentSurfaceKey
    { profileContentVenueId     :: !UUID
    , profileContentUserId      :: !UUID
    , profileContentOpenSection :: !Text
    }
    deriving (Eq, Show)

data ProfileContentFragment
    = ProfileContentLiveFragment !Text
    deriving (Eq, Show)

currentProfileContentSurfaceKey :: (?context :: ControllerContext) => Text -> ProfileContentSurfaceKey
currentProfileContentSurfaceKey openSection =
    ProfileContentSurfaceKey
        { profileContentVenueId = currentVenueScopeId
        , profileContentUserId = unpackId authenticatedCurrentUser.id
        , profileContentOpenSection = openSection
        }

profileContentLiveSurfaceDefinition :: (?context :: ControllerContext) => TypedLiveSurfaceDefinition ProfileContentSurface ProfileContentSurfaceKey ProfileContentFragment
profileContentLiveSurfaceDefinition =
    TypedLiveSurfaceDefinition
        { typedSurfaceFeature = "profile"
        , typedSurfaceScope = \key -> SurfaceScope ProfileScope { venueId = key.profileContentVenueId, userId = key.profileContentUserId }
        , typedSurfaceScopeFromWire = \case
            ProfileScope { venueId, userId } ->
                Just ProfileContentSurfaceKey { profileContentVenueId = venueId, profileContentUserId = userId, profileContentOpenSection = "profile" }
            _ -> Nothing
        , typedSurfaceDefaultFragments = \key -> [profileContentFragment key.profileContentOpenSection]
        , typedSurfaceFragmentRef = const profileContentFragmentRef
        , typedSurfaceDecorateRequestsWithin = const ["#" <> profileDetailsFormId]
        , typedSurfaceDependsOn = \_ _ -> []
        , typedSurfaceAuthorize = liveSurfaceAuthorizationByRequirement (\key -> RequireCurrentVenueUser key.profileContentVenueId key.profileContentUserId)
        }

profileContentFragment :: Text -> ProfileContentFragment
profileContentFragment =
    ProfileContentLiveFragment

profileContentFragmentRef :: (?context :: ControllerContext) => ProfileContentFragment -> SurfaceFragmentRef ProfileContentSurface
profileContentFragmentRef (ProfileContentLiveFragment openSection) =
    mkSurfaceFragmentRef
        ProfileContentFragment
        profileContentFragmentId
        (appendQueryParams (pathTo ShowProfileContentFragmentAction) [("section", openSection)])

data ProfileLeaveSurface

data ProfileLeaveSurfaceKey = ProfileLeaveSurfaceKey
    { profileLeaveVenueId :: !UUID
    , profileLeaveUserId  :: !UUID
    }
    deriving (Eq, Show)

data ProfileLeaveFragment
    = ProfileLeaveRequestsLiveFragment
    deriving (Eq, Show)

currentProfileLeaveSurfaceKey :: (?context :: ControllerContext) => ProfileLeaveSurfaceKey
currentProfileLeaveSurfaceKey =
    ProfileLeaveSurfaceKey
        { profileLeaveVenueId = currentVenueScopeId
        , profileLeaveUserId = unpackId authenticatedCurrentUser.id
        }

profileLeaveRequestsLiveSurfaceDefinition :: (?context :: ControllerContext) => TypedLiveSurfaceDefinition ProfileLeaveSurface ProfileLeaveSurfaceKey ProfileLeaveFragment
profileLeaveRequestsLiveSurfaceDefinition =
    TypedLiveSurfaceDefinition
        { typedSurfaceFeature = "profile-leave-requests"
        , typedSurfaceScope = \key -> SurfaceScope ProfileScope { venueId = key.profileLeaveVenueId, userId = key.profileLeaveUserId }
        , typedSurfaceScopeFromWire = \case
            ProfileScope { venueId, userId } ->
                Just ProfileLeaveSurfaceKey { profileLeaveVenueId = venueId, profileLeaveUserId = userId }
            _ -> Nothing
        , typedSurfaceDefaultFragments = const [profileLeaveRequestsFragment]
        , typedSurfaceFragmentRef = const profileLeaveRequestsContentFragmentRef
        , typedSurfaceDecorateRequestsWithin = const ["#" <> profileLeaveRequestsContentFragmentId]
        , typedSurfaceDependsOn = \_ _ -> []
        , typedSurfaceAuthorize = liveSurfaceAuthorizationByRequirement (\key -> RequireCurrentVenueUser key.profileLeaveVenueId key.profileLeaveUserId)
        }

profileLeaveRequestsFragment :: ProfileLeaveFragment
profileLeaveRequestsFragment =
    ProfileLeaveRequestsLiveFragment

profileLeaveRequestsContentFragmentRef :: (?context :: ControllerContext) => ProfileLeaveFragment -> SurfaceFragmentRef ProfileLeaveSurface
profileLeaveRequestsContentFragmentRef ProfileLeaveRequestsLiveFragment =
    mkSurfaceFragmentRef
        ProfileLeaveRequestsContentFragment
        profileLeaveRequestsContentFragmentId
        (pathTo ShowProfileLeaveRequestsContentFragmentAction)

currentVenueScopeId :: (?context :: ControllerContext) => UUID
currentVenueScopeId =
    case currentVenueOrNothing of
        Just venue -> unpackId venue.id
        Nothing -> error "Profile live surface requires a current venue"

refreshProfileContent :: (?context :: ControllerContext, ?request :: Request) => Text -> IO ()
refreshProfileContent openSection =
    broadcastSurfaceFragments
        profileContentLiveSurfaceDefinition
        (currentProfileContentSurfaceKey openSection)
        [profileContentFragment openSection]

refreshProfileContentForStaffId :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => UUID -> Text -> IO ()
refreshProfileContentForStaffId staffId openSection = do
    maybeStaff <-
        query @Staff
            |> filterWhere (#id, Id staffId :: Id Staff)
            |> filterWhere (#venueId, unpackId currentVenueId)
            |> fetchOneOrNothing
    forM_ (maybeStaff >>= (.userId)) \staffUserId ->
        broadcastSurfaceFragments
            profileContentLiveSurfaceDefinition
            ProfileContentSurfaceKey
                { profileContentVenueId = unpackId currentVenueId
                , profileContentUserId = staffUserId
                , profileContentOpenSection = openSection
                }
            [profileContentFragment openSection]

refreshProfileLeaveRequests :: (?context :: ControllerContext, ?request :: Request) => IO ()
refreshProfileLeaveRequests =
    broadcastSurfaceFragments
        profileLeaveRequestsLiveSurfaceDefinition
        currentProfileLeaveSurfaceKey
        [profileLeaveRequestsFragment]

refreshProfileLeaveRequestsForStaffId :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => UUID -> IO ()
refreshProfileLeaveRequestsForStaffId staffId = do
    maybeStaff <-
        query @Staff
            |> filterWhere (#id, Id staffId :: Id Staff)
            |> filterWhere (#venueId, unpackId currentVenueId)
            |> fetchOneOrNothing
    forM_ (maybeStaff >>= (.userId)) \staffUserId ->
        broadcastSurfaceFragments
            profileLeaveRequestsLiveSurfaceDefinition
            ProfileLeaveSurfaceKey
                { profileLeaveVenueId = unpackId currentVenueId
                , profileLeaveUserId = staffUserId
                }
            [profileLeaveRequestsFragment]
