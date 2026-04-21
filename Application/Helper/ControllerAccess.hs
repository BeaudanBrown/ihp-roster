module Application.Helper.ControllerAccess where

import Data.Coerce (coerce)
import Generated.Types
import IHP.ControllerPrelude
import Web.Routes ()
import Web.Types (ProfilesController (EditProfileAction))

import Application.Helper.ControllerContext
import Application.Helper.ControllerSupport

fetchVenueConfig :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO VenueConfig
fetchVenueConfig =
    query @VenueConfig
        |> filterWhere (#venueId, unpackId currentVenueId)
        |> fetchOne

requiredProfileFieldsCompleted :: Staff -> Bool
requiredProfileFieldsCompleted staff =
    not
        ( any
            isEmpty
            [ staff.firstName
            , staff.lastName
            , staff.phone
            , staff.emergencyContactName
            , staff.emergencyContactPhone
            ]
        )

isOperationallyActive :: User -> Bool
isOperationallyActive user = user.isProfileCompleted

ensureProfileCompleted :: (?context :: ControllerContext) => IO ()
ensureProfileCompleted =
    unless (isOperationallyActive authenticatedCurrentUser) do
        withRequestContext do
            setErrorMessage "Please complete your profile to continue."
            redirectTo EditProfileAction

hasVenueRole :: VenueRole -> VenueRole -> Bool
hasVenueRole actualRole minimumRole = actualRole >= minimumRole

hasRole :: (?context :: ControllerContext) => VenueRole -> Bool
hasRole minimumRole =
    currentUserIsSuperAdmin || maybe False (`hasVenueRole` minimumRole) currentVenueRoleOrNothing

ensureCurrentVenue :: (?context :: ControllerContext) => IO ()
ensureCurrentVenue = accessDeniedUnless (isJust currentVenueOrNothing)

ensureManagerRole :: (?context :: ControllerContext) => IO ()
ensureManagerRole = accessDeniedUnless (hasRole ManagerRole')

ensureAdminRole :: (?context :: ControllerContext) => IO ()
ensureAdminRole = accessDeniedUnless (hasRole VenueAdminRole)

fetchCurrentUserStaff :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO (Maybe Staff)
fetchCurrentUserStaff =
    query @Staff
        |> filterWhere (#venueId, unpackId currentVenueId)
        |> filterWhere (#userId, Just (coerce (get #id authenticatedCurrentUser)))
        |> fetchOneOrNothing

staffInCurrentVenueOrNothing :: (?context :: ControllerContext, ?modelContext :: ModelContext) => UUID -> IO (Maybe Staff)
staffInCurrentVenueOrNothing staffId =
    query @Staff
        |> filterWhere (#venueId, unpackId currentVenueId)
        |> filterWhere (#id, Id staffId)
        |> fetchOneOrNothing

ensureOptionalStaffInCurrentVenue :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Maybe UUID -> IO ()
ensureOptionalStaffInCurrentVenue maybeStaffId =
    forM_ maybeStaffId \staffId -> do
        maybeStaff <- staffInCurrentVenueOrNothing staffId
        accessDeniedUnless (isJust maybeStaff)

ensureRecordInCurrentVenue :: (?context :: ControllerContext) => UUID -> IO ()
ensureRecordInCurrentVenue venueId =
    accessDeniedUnless (venueId == unpackId currentVenueId)
