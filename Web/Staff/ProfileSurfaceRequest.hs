module Web.Staff.ProfileSurfaceRequest
    ( StaffProfileDetailsSubmission (..)
    , StaffProfileSurfaceSubmission (..)
    , StaffShiftPreferencesSubmission (..)
    , parseProfileSurfaceSubmission
    , parseStaffSurfaceSubmission
    ) where

import qualified Application.Helper.FrontendContract.Surface.Profile as Surface
import Application.Helper.FrontendContract.Surface.Request (SurfaceRequestFieldError,
                                                            parseSurfaceActionParams)
import Application.Helper.FrontendContract.Surface.Values (SurfaceFields,
                                                           surfaceFieldValue)
import qualified Data.UUID as UUID
import Web.Controller.Prelude

data StaffProfileDetailsSubmission = StaffProfileDetailsSubmission
    { submittedFirstName             :: !Text
    , submittedLastName              :: !Text
    , submittedPreferredName         :: !Text
    , submittedPhone                 :: !Text
    , submittedIdealShiftsPerWeek    :: !Int
    , submittedEmergencyContactName  :: !Text
    , submittedEmergencyContactPhone :: !Text
    , submittedProfileSection        :: !Text
    , submittedVenueRole             :: !(Maybe Text)
    , submittedEmploymentBasis       :: !(Maybe Text)
    , submittedPayRateSelection      :: !(Maybe Text)
    , submittedIsActive              :: !(Maybe Bool)
    , submittedRosterGroupIds        :: !(Maybe [UUID.UUID])
    }

data StaffShiftPreferencesSubmission = StaffShiftPreferencesSubmission
    { submittedPreferencesSection  :: !Text
    , submittedShiftPreferenceKeys :: ![Text]
    }

data StaffProfileSurfaceSubmission
    = SubmittedStaffProfileDetails !StaffProfileDetailsSubmission
    | SubmittedStaffShiftPreferences !StaffShiftPreferencesSubmission

parseProfileSurfaceSubmission :: (?request :: Request) => Either [SurfaceRequestFieldError] StaffProfileSurfaceSubmission
parseProfileSurfaceSubmission =
    chooseSubmission
        (parseSurfaceActionParams @Surface.ProfileSurface @Surface.UpdateProfileShiftPreferences)
        (parseSurfaceActionParams @Surface.ProfileSurface @Surface.UpdateProfileDetails)

parseStaffSurfaceSubmission :: (?request :: Request) => Either [SurfaceRequestFieldError] StaffProfileSurfaceSubmission
parseStaffSurfaceSubmission =
    chooseSubmission
        (parseSurfaceActionParams @Surface.StaffSurface @Surface.UpdateStaffShiftPreferences)
        (parseSurfaceActionParams @Surface.StaffSurface @Surface.UpdateStaffProfile)

chooseSubmission ::
    Either [SurfaceRequestFieldError] (SurfaceFields Surface.StaffShiftPreferenceFields) ->
    Either [SurfaceRequestFieldError] (SurfaceFields Surface.StaffProfileFields) ->
    Either [SurfaceRequestFieldError] StaffProfileSurfaceSubmission
chooseSubmission preferenceResult detailsResult = do
    preferenceFields <- preferenceResult
    if surfaceFieldValue @Surface.SectionField preferenceFields == "preferences"
        then Right (SubmittedStaffShiftPreferences (preferencesSubmission preferenceFields))
        else SubmittedStaffProfileDetails . detailsSubmission <$> detailsResult

preferencesSubmission :: SurfaceFields Surface.StaffShiftPreferenceFields -> StaffShiftPreferencesSubmission
preferencesSubmission fields =
    StaffShiftPreferencesSubmission
        { submittedPreferencesSection = surfaceFieldValue @Surface.SectionField fields
        , submittedShiftPreferenceKeys = fromMaybe [] (surfaceFieldValue @Surface.ShiftPreferenceKeysField fields)
        }

detailsSubmission :: SurfaceFields Surface.StaffProfileFields -> StaffProfileDetailsSubmission
detailsSubmission fields =
    StaffProfileDetailsSubmission
        { submittedFirstName = surfaceFieldValue @Surface.FirstNameField fields
        , submittedLastName = surfaceFieldValue @Surface.LastNameField fields
        , submittedPreferredName = surfaceFieldValue @Surface.PreferredNameField fields
        , submittedPhone = surfaceFieldValue @Surface.PhoneField fields
        , submittedIdealShiftsPerWeek = surfaceFieldValue @Surface.IdealShiftsPerWeekField fields
        , submittedEmergencyContactName = surfaceFieldValue @Surface.EmergencyContactNameField fields
        , submittedEmergencyContactPhone = surfaceFieldValue @Surface.EmergencyContactPhoneField fields
        , submittedProfileSection = surfaceFieldValue @Surface.SectionField fields
        , submittedVenueRole = surfaceFieldValue @Surface.VenueRoleField fields
        , submittedEmploymentBasis = surfaceFieldValue @Surface.EmploymentBasisField fields
        , submittedPayRateSelection = surfaceFieldValue @Surface.PayRateSelectionField fields
        , submittedIsActive = surfaceFieldValue @Surface.IsActiveField fields
        , submittedRosterGroupIds = surfaceFieldValue @Surface.RosterGroupIdsField fields
        }
