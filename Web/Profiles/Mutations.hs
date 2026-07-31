module Web.Profiles.Mutations
    ( ProfileUpdateMutationResult (..)
    , fetchProfileRosterInvalidationTargets
    , fetchProfileRosterInvalidationTargetsForScopes
    , profileUpdateTouchedResources
    , updateCurrentUserProfile
    ) where

import Application.Helper.FrontendContract.Surface.Profile.Resource
import Application.Helper.FrontendContract.Surface.Roster.Live (activeRosterWeekScopes)
import Application.Helper.RosterGroups (fetchCurrentVenueDefaultRosterGroup,
                                        fetchStaffRosterGroupIds,
                                        syncStaffRosterGroupAssignments)
import Application.Helper.StaffShiftPreferences (ShiftPreferenceSelection,
                                                 replaceStaffShiftPreferences)
import Application.Helper.SurfaceResource
import Application.Staff.Mutations (withStaffOperationalLock)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified Data.UUID as UUID
import Web.Controller.Prelude
import Web.SurfaceInvalidation (invalidateTouchedResources)

data ProfileUpdateMutationResult = ProfileUpdateMutationResult
    { profileUpdatedStaff       :: !Staff
    , profileWasCompletedBefore :: !Bool
    , profileIsCompletedNow     :: !Bool
    }
    deriving (Eq, Show)

updateCurrentUserProfile :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Text -> Staff -> [ShiftPreferenceSelection] -> IO (Maybe (LiveMutationResult ProfileUpdateMutationResult))
updateCurrentUserProfile openSection staffInput submittedSelections = do
    maybeExistingStaff <- fetchCurrentUserStaff
    let performUpdate = do
            staff <- upsertCurrentUserStaff staffInput
            replaceStaffShiftPreferences staff submittedSelections
            let isProfileCompleted = requiredProfileFieldsCompleted staff
            let wasProfileCompleted = currentUser.isProfileCompleted
            currentUser
                |> set #isProfileCompleted isProfileCompleted
                |> updateRecord
            pure ProfileUpdateMutationResult
                { profileUpdatedStaff = staff
                , profileWasCompletedBefore = wasProfileCompleted
                , profileIsCompletedNow = isProfileCompleted
                }
    maybeProfileUpdate <- case maybeExistingStaff of
        Nothing -> Just <$> withTransaction performUpdate
        Just existingStaff -> fmap join $ withStaffOperationalLock (unpackId existingStaff.id) do
            lockedStaff <- fetch existingStaff.id
            if not lockedStaff.isActive || isJust lockedStaff.archivedAt
                then pure Nothing
                else Just <$> performUpdate
    forM maybeProfileUpdate \profileUpdate ->
        invalidateTouchedResources ("profile.update." <> openSection) $
            liveMutationResult profileUpdate (profileUpdateTouchedResources profileUpdate.profileUpdatedStaff)

profileUpdateTouchedResources :: Staff -> [SurfaceResourceValue]
profileUpdateTouchedResources staff =
    [ staffProfileResource (unpackId staff.id)
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
                    |> set #userId (Just (unpackId (get #id currentUser)))
                    |> createRecord
            defaultRosterGroup <- fetchCurrentVenueDefaultRosterGroup
            syncStaffRosterGroupAssignments createdStaff [defaultRosterGroup.id]
            pure createdStaff

fetchProfileRosterInvalidationTargets :: (?modelContext :: ModelContext) => Id Venue -> Staff -> IO [(Id RosterGroup, Int, [(UUID.UUID, Int)])]
fetchProfileRosterInvalidationTargets venueId staff = do
    activeScopes <- activeRosterWeekScopes
    fetchProfileRosterInvalidationTargetsForScopes venueId staff activeScopes

fetchProfileRosterInvalidationTargetsForScopes ::
    (?modelContext :: ModelContext) =>
    Id Venue ->
    Staff ->
    [(UUID.UUID, UUID.UUID, Int)] ->
    IO [(Id RosterGroup, Int, [(UUID.UUID, Int)])]
fetchProfileRosterInvalidationTargetsForScopes venueId staff activeScopes = do
    rosterGroupIds <- fetchStaffRosterGroupIds staff
    let activeWeekKeys =
            Set.fromList
                [ (rosterGroupUuid, weekOffset)
                | (venueUuid, rosterGroupUuid, weekOffset) <- activeScopes
                , venueUuid == unpackId venueId
                , rosterGroupUuid `elem` map unpackId rosterGroupIds
                ]
    if null rosterGroupIds || Set.null activeWeekKeys
        then pure []
        else do
            rosterWeeks <-
                query @RosterWeek
                    |> filterWhere (#venueId, unpackId venueId)
                    |> filterWhereIn (#rosterGroupId, map unpackId rosterGroupIds)
                    |> filterWhereIn (#weekOffset, Set.toList (Set.map snd activeWeekKeys))
                    |> fetch
            let activeRosterWeeks =
                    filter
                        (\rosterWeek -> (rosterWeek.rosterGroupId, rosterWeek.weekOffset) `Set.member` activeWeekKeys)
                        rosterWeeks
            rosterDays <-
                if null activeRosterWeeks
                    then pure []
                    else
                        query @RosterDay
                            |> filterWhereIn (#rosterWeekId, map (unpackId . (.id)) activeRosterWeeks)
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

            let rosterWeekById = Map.fromList (map (\rosterWeek -> (unpackId rosterWeek.id, rosterWeek)) activeRosterWeeks)
            let rosterDayById = Map.fromList (map (\rosterDay -> (unpackId rosterDay.id, rosterDay)) rosterDays)
            let assignedRowKeysByWeek =
                    Map.fromListWith (<>)
                        [ ((Id rosterWeek.rosterGroupId :: Id RosterGroup, rosterWeek.weekOffset), [(rosterSlot.rosterDayId, rosterSlot.rowIndex)])
                        | rosterSlot <- assignedSlots
                        , Just rosterDay <- [Map.lookup rosterSlot.rosterDayId rosterDayById]
                        , Just rosterWeek <- [Map.lookup rosterDay.rosterWeekId rosterWeekById]
                        ]

            pure
                [ let rosterGroupId = Id rosterWeek.rosterGroupId :: Id RosterGroup
                   in ( rosterGroupId
                      , rosterWeek.weekOffset
                      , Map.findWithDefault [] (rosterGroupId, rosterWeek.weekOffset) assignedRowKeysByWeek
                      )
                | rosterWeek <- activeRosterWeeks
                ]

