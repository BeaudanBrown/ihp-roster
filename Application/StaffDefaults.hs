module Application.StaffDefaults
    ( applyVenueDefaultStaffPayAssignment
    , staffAwardRateIsAvailable
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

staffAwardRateIsAvailable ::
    [AwardLevel] ->
    [AwardLevelBaseRate] ->
    StaffEmploymentBasisEnum ->
    Id AwardLevel ->
    Bool
staffAwardRateIsAvailable activeAwardLevels currentBaseRates employmentBasis awardLevelId =
    awardLevelId `Set.member` Set.fromList (map (.id) activeAwardLevels)
        && any rateApplies currentBaseRates
  where
    rateApplies rate =
        rate.awardLevelId == unpackId awardLevelId
            && rate.employmentBasis == employmentBasis

validateStaffAwardRateAvailability ::
    [AwardLevel] ->
    [AwardLevelBaseRate] ->
    Text ->
    Staff ->
    Staff
validateStaffAwardRateAvailability activeAwardLevels currentBaseRates failureMessage staff =
    case (staff.payAssignmentMode, staff.defaultAwardLevelId) of
        (AwardRate, Just awardLevelId)
            | staffAwardRateIsAvailable activeAwardLevels currentBaseRates staff.employmentBasis awardLevelId -> staff
            | otherwise -> staff |> attachFailure #defaultAwardLevelId failureMessage
        _ -> staff
