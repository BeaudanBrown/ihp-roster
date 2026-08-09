module Application.StaffDefaults
    ( applyVenueDefaultStaffPayAssignment
    , validateStaffAwardRateAvailability
    ) where

import qualified Data.Set as Set
import Generated.Types
import IHP.ControllerPrelude

applyVenueDefaultStaffPayAssignment :: VenueConfig -> Staff -> Staff
applyVenueDefaultStaffPayAssignment venueConfig staff =
    staff
        |> set #payAssignmentMode venueConfig.defaultStaffPayAssignmentMode
        |> set #defaultAwardLevelId venueConfig.defaultStaffAwardLevelId
        |> set #importedXeroPayItemId Nothing

validateStaffAwardRateAvailability ::
    [AwardLevel] ->
    [AwardLevelBaseRate] ->
    Text ->
    Staff ->
    Staff
validateStaffAwardRateAvailability activeAwardLevels currentBaseRates failureMessage staff =
    case (staff.payAssignmentMode, staff.defaultAwardLevelId) of
        (AwardRate, Just awardLevelId)
            | awardLevelId `Set.member` activeAwardLevelIds
                && any (rateApplies awardLevelId staff.employmentBasis) currentBaseRates -> staff
            | otherwise -> staff |> attachFailure #defaultAwardLevelId failureMessage
        _ -> staff
  where
    activeAwardLevelIds = Set.fromList (map (.id) activeAwardLevels)
    rateApplies awardLevelId employmentBasis rate =
        rate.awardLevelId == unpackId awardLevelId
            && rate.employmentBasis == employmentBasis
