module Web.Staff.Mutations
    ( staffUpdateTouchedResources
    , staffXeroPayItemScopeChanged
    , updateStaffMember
    ) where

import Application.Helper.LiveResource
import Application.Helper.LiveSurface (broadcastSurfaceResync)
import Application.Helper.Pay (ensureStaffPayVersionForStaff)
import Application.Helper.RosterGroups (syncStaffRosterGroupAssignments)
import Application.Helper.StaffShiftPreferences (ShiftPreferenceSelection,
                                                 replaceStaffShiftPreferences)
import Control.Monad (void)
import Data.Time.Clock (getCurrentTime, utctDay)
import Web.Controller.Prelude
import Web.View.Admin.Xero (adminXeroLiveSurfaceDefinition)

staffXeroPayItemScopeChanged :: Staff -> Staff -> Bool
staffXeroPayItemScopeChanged oldStaff newStaff =
    staffXeroPayItemScope oldStaff /= staffXeroPayItemScope newStaff

staffXeroPayItemScope :: Staff -> Maybe (Id AwardLevel, StaffEmploymentBasisEnum)
staffXeroPayItemScope staff
    | staff.isActive && isNothing staff.archivedAt = do
        awardLevelId <- staff.defaultAwardLevelId
        pure (awardLevelId, staff.employmentBasis)
    | otherwise = Nothing

updateStaffMember :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Staff -> Staff -> [Id RosterGroup] -> [ShiftPreferenceSelection] -> IO (LiveMutationResult Staff)
updateStaffMember originalStaff staff selectedRosterGroupIds submittedSelections = do
    updatedStaff <- withTransaction do
        updatedStaff <- staff |> updateRecord
        syncStaffRosterGroupAssignments updatedStaff selectedRosterGroupIds
        replaceStaffShiftPreferences updatedStaff submittedSelections
        when (staffXeroPayItemScopeChanged originalStaff updatedStaff) do
            today <- utctDay <$> getCurrentTime
            void (ensureStaffPayVersionForStaff currentUser.id updatedStaff today)
        pure updatedStaff
    let payScopeChanged = staffXeroPayItemScopeChanged originalStaff updatedStaff
    when payScopeChanged do
        broadcastSurfaceResync adminXeroLiveSurfaceDefinition ()
    pure (liveMutationResult updatedStaff (staffUpdateTouchedResources payScopeChanged updatedStaff))

staffUpdateTouchedResources :: Bool -> Staff -> [LiveResource]
staffUpdateTouchedResources payScopeChanged staff =
    [ StaffProfileResource (unpackId staff.id)
    , StaffPreferencesResource (unpackId staff.id)
    , StaffRosterMembershipResource (unpackId staff.id)
    ]
        <> [StaffPayProfileResource (unpackId staff.id) | payScopeChanged]
