module Web.Profiles.Mutations
    ( ProfileUpdateMutationResult (..)
    , profileUpdateTouchedResources
    , updateCurrentUserProfile
    ) where

import Application.Helper.FrontendContract.Surface.LeaveRequests.Resource (leaveAvailabilityWarningsResource)
import Application.Helper.FrontendContract.Surface.Profile.Resource
import Application.Helper.RosterGroups (fetchCurrentVenueDefaultRosterGroup,
                                        fetchStaffRosterGroupIds,
                                        syncStaffRosterGroupAssignments)
import Application.Helper.StaffShiftPreferences (ShiftPreferenceSelection,
                                                 replaceStaffShiftPreferences)
import Application.Helper.SurfaceResource
import Application.Staff.Mutations (withStaffOperationalLocksInCurrentTransaction)
import Web.Controller.Prelude
import Web.RosterWeeks.SurfaceInvalidation (activeRosterResourcesForStaffGroups)
import Web.SurfaceInvalidation (withDurableLiveMutationOutcome)

data ProfileUpdateMutationResult = ProfileUpdateMutationResult
    { profileUpdatedStaff       :: !Staff
    , profileWasCompletedBefore :: !Bool
    , profileIsCompletedNow     :: !Bool
    }
    deriving (Eq, Show)

updateCurrentUserProfile :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Text -> Staff -> [ShiftPreferenceSelection] -> IO (Maybe (LiveMutationResult ProfileUpdateMutationResult))
updateCurrentUserProfile openSection staffInput submittedSelections =
    withDurableLiveMutationOutcome publicationFor do
        maybeExistingStaff <- fetchCurrentUserStaff
        let performUpdate = do
                staff <- upsertCurrentUserStaff staffInput
                replaceStaffShiftPreferences staff submittedSelections
                let isProfileCompleted = requiredProfileFieldsCompleted staff
                let wasProfileCompleted = effectiveCurrentUser.isProfileCompleted
                effectiveCurrentUser
                    |> set #isProfileCompleted isProfileCompleted
                    |> updateRecord
                pure ProfileUpdateMutationResult
                    { profileUpdatedStaff = staff
                    , profileWasCompletedBefore = wasProfileCompleted
                    , profileIsCompletedNow = isProfileCompleted
                    }
        maybeProfileUpdate <- case maybeExistingStaff of
            Nothing -> Just <$> performUpdate
            Just existingStaff -> fmap join $ withStaffOperationalLocksInCurrentTransaction [unpackId existingStaff.id] do
                lockedStaff <- fetch existingStaff.id
                if not lockedStaff.isActive || isJust lockedStaff.archivedAt
                    then pure Nothing
                    else Just <$> performUpdate
        forM maybeProfileUpdate \profileUpdate -> do
            let updatedStaff = profileUpdate.profileUpdatedStaff
            rosterGroupIds <- fetchStaffRosterGroupIds updatedStaff
            let rosterResources = activeRosterResourcesForStaffGroups updatedStaff.venueId [] rosterGroupIds
            pure (liveMutationResult profileUpdate (profileUpdateTouchedResources updatedStaff <> rosterResources))
  where
    publicationFor = fmap (\result -> ("profile.update." <> openSection, result.liveMutationTouchedResources))

profileUpdateTouchedResources :: Staff -> [SurfaceResourceValue]
profileUpdateTouchedResources staff =
    [ leaveAvailabilityWarningsResource staff.venueId
    , staffProfileResource (unpackId staff.id)
    , staffPreferencesResource (unpackId staff.id)
    ]

upsertCurrentUserStaff :: (?modelContext :: ModelContext, ?context :: ControllerContext, ?request :: Request) => Staff -> IO Staff
upsertCurrentUserStaff staff = do
    existingStaff <- fetchCurrentUserStaff

    case existingStaff of
        Just existing ->
            existing
                |> set #firstName staff.firstName
                |> set #lastName staff.lastName
                |> set #preferredName staff.preferredName
                |> set #phone staff.phone
                |> set #emergencyContactName staff.emergencyContactName
                |> set #emergencyContactPhone staff.emergencyContactPhone
                |> set #idealShiftsPerWeek staff.idealShiftsPerWeek
                |> updateRecord
        Nothing -> do
            createdStaff <-
                staff
                    |> set #venueId (unpackId currentVenueId)
                    |> set #userId (Just (unpackId (get #id effectiveCurrentUser)))
                    |> createRecord
            defaultRosterGroup <- fetchCurrentVenueDefaultRosterGroup
            syncStaffRosterGroupAssignments createdStaff [defaultRosterGroup.id]
            pure createdStaff

