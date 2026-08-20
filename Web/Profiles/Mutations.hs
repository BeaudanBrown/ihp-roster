module Web.Profiles.Mutations
    ( ProfileUpdateMutationResult (..)
    , fetchProfileRosterInvalidationTargets
    , fetchProfileRosterInvalidationTargetsForScopes
    , profileUpdateTouchedResources
    , updateCurrentUserProfile
    ) where

import Application.Helper.FrontendContract.Surface.LeaveRequests.Resource (leaveAvailabilityWarningsResource)
import Application.Helper.FrontendContract.Surface.Profile.Resource
import Application.Helper.FrontendContract.Surface.Roster.Live (activeRosterWindowScopes)
import Application.Helper.RosterGroups (fetchCurrentVenueDefaultRosterGroup,
                                        fetchStaffRosterGroupIds,
                                        syncStaffRosterGroupAssignments)
import Application.Helper.StaffShiftPreferences (ShiftPreferenceSelection,
                                                 replaceStaffShiftPreferences)
import Application.Helper.SurfaceResource
import Application.Staff.Mutations (withStaffOperationalLocksInCurrentTransaction)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Time.Calendar (Day)
import qualified Data.UUID as UUID
import Web.Controller.Prelude
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
        pure $
            fmap
                (\profileUpdate -> liveMutationResult profileUpdate (profileUpdateTouchedResources profileUpdate.profileUpdatedStaff))
                maybeProfileUpdate
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

fetchProfileRosterInvalidationTargets :: (?modelContext :: ModelContext) => Id Venue -> Staff -> IO [(Id RosterGroup, Day, Day, [(UUID.UUID, Int)])]
fetchProfileRosterInvalidationTargets venueId staff = do
    activeScopes <- activeRosterWindowScopes
    fetchProfileRosterInvalidationTargetsForScopes venueId staff activeScopes

fetchProfileRosterInvalidationTargetsForScopes ::
    (?modelContext :: ModelContext) =>
    Id Venue ->
    Staff ->
    [(UUID.UUID, UUID.UUID, Day, Day, Int)] ->
    IO [(Id RosterGroup, Day, Day, [(UUID.UUID, Int)])]
fetchProfileRosterInvalidationTargetsForScopes venueId staff activeScopes = do
    rosterGroupIds <- fetchStaffRosterGroupIds staff
    let rosterGroupUuidSet = Set.fromList (map unpackId rosterGroupIds)
    let activeWindows =
            Set.toList $ Set.fromList
                [ (rosterGroupUuid, windowStart, windowEnd)
                | (venueUuid, rosterGroupUuid, windowStart, windowEnd, _calendarRevision) <- activeScopes
                , venueUuid == unpackId venueId
                , rosterGroupUuid `Set.member` rosterGroupUuidSet
                ]
    if null activeWindows
        then pure []
        else do
            let earliestWindowStart = minimum (map (\(_, windowStart, _) -> windowStart) activeWindows)
            let latestWindowEnd = maximum (map (\(_, _, windowEnd) -> windowEnd) activeWindows)
            rosterDays <-
                query @RosterDay
                    |> filterWhere (#venueId, unpackId venueId)
                    |> filterWhereIn (#rosterGroupId, Set.toList rosterGroupUuidSet)
                    |> filterWhereGreaterThanOrEqualTo (#operationalDate, earliestWindowStart)
                    |> filterWhereLessThan (#operationalDate, latestWindowEnd)
                    |> fetch
            assignedSlots <-
                if null rosterDays
                    then pure []
                    else
                        query @RosterSlot
                            |> filterWhere (#staffId, Just (unpackId staff.id))
                            |> filterWhereIn (#rosterDayId, map (unpackId . (.id)) rosterDays)
                            |> filterWhere (#deletedAt, Nothing)
                            |> fetch
            let rosterDayById = Map.fromList (map (\rosterDay -> (unpackId rosterDay.id, rosterDay)) rosterDays)
            let assignedRows =
                    [ (rosterDay.rosterGroupId, rosterDay.operationalDate, rosterSlot.rosterDayId, rosterSlot.rowIndex)
                    | rosterSlot <- assignedSlots
                    , Just rosterDay <- [Map.lookup rosterSlot.rosterDayId rosterDayById]
                    ]
            pure
                [ ( Id rosterGroupUuid
                  , windowStart
                  , windowEnd
                  , [ (rosterDayId, rowIndex)
                    | (assignedGroupUuid, operationalDate, rosterDayId, rowIndex) <- assignedRows
                    , assignedGroupUuid == rosterGroupUuid
                    , operationalDate >= windowStart
                    , operationalDate < windowEnd
                    ]
                  )
                | (rosterGroupUuid, windowStart, windowEnd) <- activeWindows
                ]

