{-# OPTIONS_GHC -Werror=incomplete-patterns #-}

module Web.Profiles.LiveUpdates
    ( ProfileContentFragment (..)
    , ProfileContentSurfaceKey (..)
    , ProfileLeaveFragment (..)
    , ProfileLeaveSurfaceKey (..)
    , currentProfileContentSurfaceKey
    , currentProfileLeaveSurfaceKey
    , profileContentFragment
    , profileContentFragmentSectionParam
    , profileContentLiveSurfaceDefinition
    , profileLeaveRequestsFragment
    , profileLeaveRequestsLiveSurfaceDefinition
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
    = ProfileDetailsContentFragment
    | ProfileRsaContentFragment
    | ProfileLeaveContentFragment
    | ProfileSecurityContentFragment
    deriving (Eq, Show)

currentProfileContentSurfaceKey :: (?context :: ControllerContext) => Staff -> Text -> ProfileContentSurfaceKey
currentProfileContentSurfaceKey staff openSection =
    ProfileContentSurfaceKey
        { profileContentVenueId = currentVenueScopeId
        , profileContentStaffId = unpackId staff.id
        , profileContentOpenSection = openSection
        }

profileContentLiveSurfaceDefinition :: (?context :: ControllerContext) => TypedLiveSurfaceDefinition ProfileContentSurface ProfileContentSurfaceKey ProfileContentFragment EmptyInteractionLayer EmptyInteractionSession EmptyInteractionIntent
profileContentLiveSurfaceDefinition =
    TypedLiveSurfaceDefinition
        { typedSurfaceFeature = "profile"
        , typedSurfaceScope = \key -> SurfaceScope ProfileScope { venueId = key.profileContentVenueId, staffId = key.profileContentStaffId }
        , typedSurfaceScopeFromWire = \case
            ProfileScope { venueId, staffId } ->
                Just ProfileContentSurfaceKey { profileContentVenueId = venueId, profileContentStaffId = staffId, profileContentOpenSection = "profile" }
            _ -> Nothing
        , typedSurfaceDefaultFragments = \key -> [profileContentFragment key.profileContentOpenSection]
        , typedSurfaceFragmentContract = \key fragment ->
            mkSurfaceFragmentContract
                (profileContentFragmentRef fragment)
                (profileContentDependsOn key fragment)
        , typedSurfaceDecorateRequestsWithin = const ["#" <> profileDetailsFormId]
        , typedSurfaceAuthorize = liveSurfaceAuthorizationByRequirement (\key -> RequireCurrentVenueStaff key.profileContentVenueId key.profileContentStaffId)
        , typedSurfaceInteraction = const emptyInteractionCapability
        }

profileContentFragment :: Text -> ProfileContentFragment
profileContentFragment section =
    case section of
        "rsa"      -> ProfileRsaContentFragment
        "leave"    -> ProfileLeaveContentFragment
        "security" -> ProfileSecurityContentFragment
        _          -> ProfileDetailsContentFragment

profileContentFragmentSectionParam :: ProfileContentFragment -> Text
profileContentFragmentSectionParam ProfileDetailsContentFragment =
    "profile"
profileContentFragmentSectionParam ProfileRsaContentFragment =
    "rsa"
profileContentFragmentSectionParam ProfileLeaveContentFragment =
    "leave"
profileContentFragmentSectionParam ProfileSecurityContentFragment =
    "security"

profileContentDependsOn :: ProfileContentSurfaceKey -> ProfileContentFragment -> FragmentDependencies
profileContentDependsOn key ProfileDetailsContentFragment =
    liveFragmentDependsOn (StaffProfileResource key.profileContentStaffId) [StaffPreferencesResource key.profileContentStaffId]
profileContentDependsOn key ProfileRsaContentFragment =
    liveFragmentDependsOn (StaffRsaDocumentsResource key.profileContentStaffId) []
profileContentDependsOn key ProfileLeaveContentFragment =
    liveFragmentDependsOn (StaffLeaveRequestsResource key.profileContentStaffId) []
profileContentDependsOn _ ProfileSecurityContentFragment =
    liveFragmentResyncOnly "security profile section has no passive live-resource dependency"

profileContentFragmentRef :: (?context :: ControllerContext) => ProfileContentFragment -> SurfaceFragmentRef ProfileContentSurface
profileContentFragmentRef fragment =
    mkSurfaceFragmentRef
        ProfileContentFragment
        profileContentFragmentId
        (appendQueryParams (pathTo ShowProfileContentFragmentAction) [("section", profileContentFragmentSectionParam fragment)])

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

profileLeaveRequestsLiveSurfaceDefinition :: (?context :: ControllerContext) => TypedLiveSurfaceDefinition ProfileLeaveSurface ProfileLeaveSurfaceKey ProfileLeaveFragment EmptyInteractionLayer EmptyInteractionSession EmptyInteractionIntent
profileLeaveRequestsLiveSurfaceDefinition =
    TypedLiveSurfaceDefinition
        { typedSurfaceFeature = "profile-leave-requests"
        , typedSurfaceScope = \key -> SurfaceScope ProfileScope { venueId = key.profileLeaveVenueId, staffId = key.profileLeaveStaffId }
        , typedSurfaceScopeFromWire = \case
            ProfileScope { venueId, staffId } ->
                Just ProfileLeaveSurfaceKey { profileLeaveVenueId = venueId, profileLeaveStaffId = staffId }
            _ -> Nothing
        , typedSurfaceDefaultFragments = const [profileLeaveRequestsFragment]
        , typedSurfaceFragmentContract = \key fragment ->
            mkSurfaceFragmentContract
                (profileLeaveRequestsContentFragmentRef fragment)
                (liveFragmentDependsOn (StaffLeaveRequestsResource key.profileLeaveStaffId) [])
        , typedSurfaceDecorateRequestsWithin = const ["#" <> profileLeaveRequestsContentFragmentId]
        , typedSurfaceAuthorize = liveSurfaceAuthorizationByRequirement (\key -> RequireCurrentVenueStaff key.profileLeaveVenueId key.profileLeaveStaffId)
        , typedSurfaceInteraction = const emptyInteractionCapability
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
        Nothing    -> error "Profile live surface requires a current venue"

