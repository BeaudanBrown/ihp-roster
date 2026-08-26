{-# LANGUAGE ConstraintKinds  #-}
{-# LANGUAGE FlexibleContexts #-}

module Web.Staff.ProfileSurfaceRequest
    ( StaffProfileDetailsSubmission (..)
    , StaffProfileSurfaceSubmission (..)
    , StaffShiftPreferencesSubmission (..)
    , parseProfileSurfaceSubmission
    , parseStaffSurfaceSubmission
    ) where

import Application.Helper.FrontendContract.Surface.Profile (StaffProfileSectionValue (..))
import qualified Application.Helper.FrontendContract.Surface.Profile as Surface
import qualified Application.Helper.FrontendContract.Surface.Profile.Action as ProfileAction
import Application.Helper.FrontendContract.Surface.Request (SurfaceRequestFieldError)
import Application.Helper.FrontendContract.Surface.Values (LookupSurfaceFieldBundle,
                                                           SurfaceFieldBundleOf,
                                                           surfaceFieldValue)
import Application.PayRateSelection (StaffPayRateSelection)
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
    , submittedProfileSection        :: !StaffProfileSectionValue
    , submittedVenueRole             :: !(Maybe VenueRoleEnum)
    , submittedEmploymentBasis       :: !(Maybe StaffEmploymentBasisEnum)
    , submittedPayRateSelection      :: !(Maybe StaffPayRateSelection)
    , submittedRosterGroupIds        :: !(Maybe [UUID.UUID])
    }

data StaffShiftPreferencesSubmission = StaffShiftPreferencesSubmission
    { submittedPreferencesSection  :: !StaffProfileSectionValue
    , submittedShiftPreferenceKeys :: ![Text]
    }

data StaffProfileSurfaceSubmission
    = SubmittedStaffProfileDetails !StaffProfileDetailsSubmission
    | SubmittedStaffShiftPreferences !StaffShiftPreferencesSubmission

parseProfileSurfaceSubmission :: (?request :: Request) => Either [SurfaceRequestFieldError] StaffProfileSurfaceSubmission
parseProfileSurfaceSubmission =
    chooseSubmission
        ProfileAction.parseUpdateProfileShiftPreferencesActionParams
        ProfileAction.parseUpdateProfileDetailsActionParams

parseStaffSurfaceSubmission :: (?request :: Request) => Either [SurfaceRequestFieldError] StaffProfileSurfaceSubmission
parseStaffSurfaceSubmission =
    chooseSubmission
        ProfileAction.parseUpdateStaffShiftPreferencesActionParams
        ProfileAction.parseUpdateStaffProfileActionParams

chooseSubmission ::
    ( SurfaceFieldBundleOf Surface.StaffShiftPreferenceFields preferenceFields
    , LookupSurfaceFieldBundle Surface.SectionField preferenceFields
    , LookupSurfaceFieldBundle Surface.ShiftPreferenceKeysField preferenceFields
    , SurfaceFieldBundleOf Surface.StaffProfileFields detailsFields
    , StaffProfileFieldLookups detailsFields
    ) =>
    Either [SurfaceRequestFieldError] preferenceFields ->
    Either [SurfaceRequestFieldError] detailsFields ->
    Either [SurfaceRequestFieldError] StaffProfileSurfaceSubmission
chooseSubmission preferenceResult detailsResult = do
    preferenceFields <- preferenceResult
    if surfaceFieldValue @Surface.SectionField preferenceFields == StaffProfilePreferencesSection
        then Right (SubmittedStaffShiftPreferences (preferencesSubmission preferenceFields))
        else SubmittedStaffProfileDetails . detailsSubmission <$> detailsResult

preferencesSubmission ::
    ( SurfaceFieldBundleOf Surface.StaffShiftPreferenceFields fields
    , LookupSurfaceFieldBundle Surface.SectionField fields
    , LookupSurfaceFieldBundle Surface.ShiftPreferenceKeysField fields
    ) => fields -> StaffShiftPreferencesSubmission
preferencesSubmission fields =
    StaffShiftPreferencesSubmission
        { submittedPreferencesSection = surfaceFieldValue @Surface.SectionField fields
        , submittedShiftPreferenceKeys = fromMaybe [] (surfaceFieldValue @Surface.ShiftPreferenceKeysField fields)
        }

type StaffProfileFieldLookups fields =
    ( LookupSurfaceFieldBundle Surface.FirstNameField fields
    , LookupSurfaceFieldBundle Surface.LastNameField fields
    , LookupSurfaceFieldBundle Surface.PreferredNameField fields
    , LookupSurfaceFieldBundle Surface.PhoneField fields
    , LookupSurfaceFieldBundle Surface.IdealShiftsPerWeekField fields
    , LookupSurfaceFieldBundle Surface.EmergencyContactNameField fields
    , LookupSurfaceFieldBundle Surface.EmergencyContactPhoneField fields
    , LookupSurfaceFieldBundle Surface.SectionField fields
    , LookupSurfaceFieldBundle Surface.VenueRoleField fields
    , LookupSurfaceFieldBundle Surface.EmploymentBasisField fields
    , LookupSurfaceFieldBundle Surface.PayRateSelectionField fields
    , LookupSurfaceFieldBundle Surface.RosterGroupIdsField fields
    )

detailsSubmission :: (SurfaceFieldBundleOf Surface.StaffProfileFields fields, StaffProfileFieldLookups fields) => fields -> StaffProfileDetailsSubmission
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
        , submittedRosterGroupIds = surfaceFieldValue @Surface.RosterGroupIdsField fields
        }
