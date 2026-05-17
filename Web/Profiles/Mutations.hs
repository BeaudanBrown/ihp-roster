module Web.Profiles.Mutations
    ( ProfileUpdateMutationResult (..)
    , fetchProfileRosterInvalidationTargets
    , fetchProfileRosterInvalidationTargetsForScopes
    , profileUpdateTouchedResources
    , updateCurrentUserProfile
    ) where

import Application.Helper.LiveResource
import Application.Helper.LiveUpdate (activeRosterWeekScopes)
import Application.Helper.RosterGroups (fetchCurrentVenueDefaultRosterGroup,
                                        fetchStaffRosterGroupIds,
                                        syncStaffRosterGroupAssignments)
import Application.Helper.StaffShiftPreferences (ShiftPreferenceSelection,
                                                 replaceStaffShiftPreferences)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified Data.UUID as UUID
import Web.Controller.Prelude
import Web.Profiles.LiveUpdates (refreshProfileContent)
import Web.RosterWeeks.LiveUpdates (refreshRosterFragments)
import Web.RosterWeeks.Projection (rosterContentFragment)
import Web.RosterWeeks.Types (RosterProjectionFragment)

data ProfileUpdateMutationResult = ProfileUpdateMutationResult
    { profileUpdatedStaff       :: !Staff
    , profileWasCompletedBefore :: !Bool
    , profileIsCompletedNow     :: !Bool
    }
    deriving (Eq, Show)

updateCurrentUserProfile :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Text -> Staff -> [ShiftPreferenceSelection] -> IO (LiveMutationResult ProfileUpdateMutationResult)
updateCurrentUserProfile openSection staffInput submittedSelections = do
    staff <- upsertCurrentUserStaff staffInput
    replaceStaffShiftPreferences staff submittedSelections
    invalidationTargets <- fetchProfileRosterInvalidationTargets currentVenueId staff
    let invalidations = buildProfileRosterInvalidations invalidationTargets
    forM_ invalidations \(rosterGroupId, weekOffset, fragments) ->
        refreshRosterFragments rosterGroupId weekOffset fragments
    let isProfileCompleted = requiredProfileFieldsCompleted staff
    let wasProfileCompleted = currentUser.isProfileCompleted
    currentUser
        |> set #isProfileCompleted isProfileCompleted
        |> updateRecord
    refreshProfileContent openSection
    pure $
        liveMutationResult
            ProfileUpdateMutationResult
                { profileUpdatedStaff = staff
                , profileWasCompletedBefore = wasProfileCompleted
                , profileIsCompletedNow = isProfileCompleted
                }
            (profileUpdateTouchedResources staff)

profileUpdateTouchedResources :: Staff -> [LiveResource]
profileUpdateTouchedResources staff =
    [ StaffProfileResource (unpackId staff.id)
    , StaffPreferencesResource (unpackId staff.id)
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

buildProfileRosterInvalidations :: [(Id RosterGroup, Int, [(UUID.UUID, Int)])] -> [(Id RosterGroup, Int, [RosterProjectionFragment])]
buildProfileRosterInvalidations =
    map \(rosterGroupId, weekOffset, _rowKeys) ->
        ( rosterGroupId
        , weekOffset
        , [rosterContentFragment]
        )
