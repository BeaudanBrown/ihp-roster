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
import Application.Helper.LiveResource (LiveResource (..))
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
    , profileContentStaffId     :: !UUID
    , profileContentOpenSection :: !Text
    }
    deriving (Eq, Show)

data ProfileContentFragment
    = ProfileContentLiveFragment !Text
    deriving (Eq, Show)

currentProfileContentSurfaceKey :: (?context :: ControllerContext) => Staff -> Text -> ProfileContentSurfaceKey
currentProfileContentSurfaceKey staff openSection =
    ProfileContentSurfaceKey
        { profileContentVenueId = currentVenueScopeId
        , profileContentStaffId = unpackId staff.id
        , profileContentOpenSection = openSection
        }

profileContentLiveSurfaceDefinition :: (?context :: ControllerContext) => TypedLiveSurfaceDefinition ProfileContentSurface ProfileContentSurfaceKey ProfileContentFragment
profileContentLiveSurfaceDefinition =
    TypedLiveSurfaceDefinition
        { typedSurfaceFeature = "profile"
        , typedSurfaceScope = \key -> SurfaceScope ProfileScope { venueId = key.profileContentVenueId, staffId = key.profileContentStaffId }
        , typedSurfaceScopeFromWire = \case
            ProfileScope { venueId, staffId } ->
                Just ProfileContentSurfaceKey { profileContentVenueId = venueId, profileContentStaffId = staffId, profileContentOpenSection = "profile" }
            _ -> Nothing
        , typedSurfaceDefaultFragments = \key -> [profileContentFragment key.profileContentOpenSection]
        , typedSurfaceFragmentRef = const profileContentFragmentRef
        , typedSurfaceDecorateRequestsWithin = const ["#" <> profileDetailsFormId]
        , typedSurfaceDependsOn = profileContentDependsOn
        , typedSurfaceAuthorize = liveSurfaceAuthorizationByRequirement (\key -> RequireCurrentVenueStaff key.profileContentVenueId key.profileContentStaffId)
        }

profileContentFragment :: Text -> ProfileContentFragment
profileContentFragment =
    ProfileContentLiveFragment

profileContentDependsOn :: ProfileContentSurfaceKey -> ProfileContentFragment -> [LiveResource]
profileContentDependsOn key (ProfileContentLiveFragment openSection) =
    case openSection of
        "rsa" -> [StaffRsaDocumentsResource key.profileContentStaffId]
        "leave" -> [StaffLeaveRequestsResource key.profileContentStaffId]
        "security" -> []
        _ -> [StaffProfileResource key.profileContentStaffId, StaffPreferencesResource key.profileContentStaffId]

profileContentFragmentRef :: (?context :: ControllerContext) => ProfileContentFragment -> SurfaceFragmentRef ProfileContentSurface
profileContentFragmentRef (ProfileContentLiveFragment openSection) =
    mkSurfaceFragmentRef
        ProfileContentFragment
        profileContentFragmentId
        (appendQueryParams (pathTo ShowProfileContentFragmentAction) [("section", openSection)])

data ProfileLeaveSurface

data ProfileLeaveSurfaceKey = ProfileLeaveSurfaceKey
    { profileLeaveVenueId :: !UUID
    , profileLeaveStaffId :: !UUID
    }
    deriving (Eq, Show)

data ProfileLeaveFragment
    = ProfileLeaveRequestsLiveFragment
    deriving (Eq, Show)

currentProfileLeaveSurfaceKey :: (?context :: ControllerContext) => Staff -> ProfileLeaveSurfaceKey
currentProfileLeaveSurfaceKey staff =
    ProfileLeaveSurfaceKey
        { profileLeaveVenueId = currentVenueScopeId
        , profileLeaveStaffId = unpackId staff.id
        }

profileLeaveRequestsLiveSurfaceDefinition :: (?context :: ControllerContext) => TypedLiveSurfaceDefinition ProfileLeaveSurface ProfileLeaveSurfaceKey ProfileLeaveFragment
profileLeaveRequestsLiveSurfaceDefinition =
    TypedLiveSurfaceDefinition
        { typedSurfaceFeature = "profile-leave-requests"
        , typedSurfaceScope = \key -> SurfaceScope ProfileScope { venueId = key.profileLeaveVenueId, staffId = key.profileLeaveStaffId }
        , typedSurfaceScopeFromWire = \case
            ProfileScope { venueId, staffId } ->
                Just ProfileLeaveSurfaceKey { profileLeaveVenueId = venueId, profileLeaveStaffId = staffId }
            _ -> Nothing
        , typedSurfaceDefaultFragments = const [profileLeaveRequestsFragment]
        , typedSurfaceFragmentRef = const profileLeaveRequestsContentFragmentRef
        , typedSurfaceDecorateRequestsWithin = const ["#" <> profileLeaveRequestsContentFragmentId]
        , typedSurfaceDependsOn = \key _ -> [StaffLeaveRequestsResource key.profileLeaveStaffId]
        , typedSurfaceAuthorize = liveSurfaceAuthorizationByRequirement (\key -> RequireCurrentVenueStaff key.profileLeaveVenueId key.profileLeaveStaffId)
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

refreshProfileContent :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Text -> IO ()
refreshProfileContent openSection = do
    maybeStaff <- fetchCurrentUserStaff
    forM_ maybeStaff \staff ->
        broadcastSurfaceFragments
            profileContentLiveSurfaceDefinition
            (currentProfileContentSurfaceKey staff openSection)
            [profileContentFragment openSection]

refreshProfileContentForStaffId :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => UUID -> Text -> IO ()
refreshProfileContentForStaffId staffId openSection = do
    maybeStaff <-
        query @Staff
            |> filterWhere (#id, Id staffId :: Id Staff)
            |> filterWhere (#venueId, unpackId currentVenueId)
            |> fetchOneOrNothing
    forM_ maybeStaff \staff ->
        broadcastSurfaceFragments
            profileContentLiveSurfaceDefinition
            ProfileContentSurfaceKey
                { profileContentVenueId = unpackId currentVenueId
                , profileContentStaffId = unpackId staff.id
                , profileContentOpenSection = openSection
                }
            [profileContentFragment openSection]

refreshProfileLeaveRequests :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => IO ()
refreshProfileLeaveRequests = do
    maybeStaff <- fetchCurrentUserStaff
    forM_ maybeStaff \staff ->
        broadcastSurfaceFragments
            profileLeaveRequestsLiveSurfaceDefinition
            (currentProfileLeaveSurfaceKey staff)
            [profileLeaveRequestsFragment]

refreshProfileLeaveRequestsForStaffId :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => UUID -> IO ()
refreshProfileLeaveRequestsForStaffId staffId = do
    maybeStaff <-
        query @Staff
            |> filterWhere (#id, Id staffId :: Id Staff)
            |> filterWhere (#venueId, unpackId currentVenueId)
            |> fetchOneOrNothing
    forM_ maybeStaff \staff ->
        broadcastSurfaceFragments
            profileLeaveRequestsLiveSurfaceDefinition
            ProfileLeaveSurfaceKey
                { profileLeaveVenueId = unpackId currentVenueId
                , profileLeaveStaffId = unpackId staff.id
                }
            [profileLeaveRequestsFragment]
