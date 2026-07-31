{-# LANGUAGE DataKinds     #-}
{-# LANGUAGE TypeOperators #-}

module Application.Helper.FrontendContract.Surface.Profile
    ( ProfileDetailsSection
    , ProfileLeaveSection
    , ProfilePreferencesSection
    , ProfileRsaSection
    , ProfileSecuritySection
    , StaffLeaveRequests
    , StaffPreferences
    , StaffProfile
    , StaffRsaDocuments
    , ProfileScope
    , ProfileSurface
    , StaffDetailsSection
    , StaffLeaveSection
    , StaffVisibleUnavailabilityBlackouts
    , StaffPreferencesSection
    , StaffScope
    , StaffSurface
    , UpdateProfileDetails
    , UpdateProfileShiftPreferences
    , UpdateStaffProfile
    , UpdateStaffShiftPreferences
    , CreateStaffLeaveRequest
    , StaffId
    , VenueId
    , FirstNameField
    , LastNameField
    , PreferredNameField
    , PhoneField
    , IdealShiftsPerWeekField
    , EmergencyContactNameField
    , EmergencyContactPhoneField
    , SectionField
    , WeekOffsetField
    , RosterGroupIdField
    , VenueRoleField
    , EmploymentBasisField
    , PayRateSelectionField
    , RosterGroupIdsField
    , ShiftPreferenceKeysField
    , StartDate
    , EndDate
    , Notes
    , StaffProfileFields
    , StaffShiftPreferenceFields
    ) where

import Application.Helper.FrontendContract.Surface.DSL
import qualified Application.Helper.FrontendContract.Surface.SelfServiceLeave as SelfServiceLeave

data Profile
data Staff

data ProfileScope
data StaffScope
data VenueId
data StaffId

data ProfileDetailsSection
data ProfilePreferencesSection
data StaffDetailsSection
data StaffPreferencesSection
data StaffLeaveSection
data StaffVisibleUnavailabilityBlackouts
data ProfileDetails
data ProfilePreferences
data ProfileSecurity
data ProfileLeave
data ProfileRsa
data StaffProfileDetails
data StaffProfilePreferences
data StaffProfileLeave
data ProfileSecuritySection
data ProfileLeaveSection
data ProfileRsaSection

data StaffProfile
data StaffPreferences
type StaffLeaveRequests = SelfServiceLeave.StaffLeaveRequests
data StaffRsaDocuments

data UpdateProfileDetails
data UpdateProfileShiftPreferences
data UpdateStaffProfile
data UpdateStaffShiftPreferences
data CreateStaffLeaveRequest

data FirstNameField
data LastNameField
data PreferredNameField
data PhoneField
data IdealShiftsPerWeekField
data EmergencyContactNameField
data EmergencyContactPhoneField
data SectionField
data WeekOffsetField
data RosterGroupIdField
data VenueRoleField
data EmploymentBasisField
data PayRateSelectionField
data RosterGroupIdsField
data ShiftPreferenceKeysField
data StaffProfileSectionHtmxAttrs

data StaffLeaveRequestFormFragment
data StartDate
data EndDate
data Notes
data OuterHTML

type StaffProfileResource = Resource StaffProfile '[ Field StaffId 'WireUUID ]
type StaffPreferencesResource = Resource StaffPreferences '[ Field StaffId 'WireUUID ]
type StaffLeaveRequestsResource = SelfServiceLeave.StaffLeaveRequestsResource
type StaffRsaDocumentsResource = Resource StaffRsaDocuments '[ Field StaffId 'WireUUID ]

type StaffProfileFields =
    '[ Field FirstNameField 'WireText
     , Field LastNameField 'WireText
     , Field PreferredNameField 'WireText
     , Field PhoneField 'WireText
     , Field IdealShiftsPerWeekField 'WireInt
     , Field EmergencyContactNameField 'WireText
     , Field EmergencyContactPhoneField 'WireText
     , Field SectionField 'WireText
     , OptionalField VenueRoleField 'WireText
     , OptionalField EmploymentBasisField 'WireText
     , OptionalField PayRateSelectionField 'WireText
     , OptionalField RosterGroupIdsField ('WireList 'WireUUID)
     ]

type StaffShiftPreferenceFields =
    '[ Field SectionField 'WireText
     , OptionalField ShiftPreferenceKeysField ('WireList 'WireText)
     ]

type StaffProfileSubmitOptions =
    '[ 'HtmxMethod 'HtmxPost
     , 'HtmxPushUrl 'HtmxPushUrlFalse
     , 'CustomHtmx StaffProfileSectionHtmxAttrs "profile and staff forms provide their concrete section target and swap modifier at the route boundary"
     ]

type ProfileSurface =
    Surface Profile
        '[ Scope ProfileScope
            '[ Field VenueId 'WireUUID
             , Field StaffId 'WireUUID
             ]
            '[ 'Authorize 'CurrentVenueStaff '[ VenueId, StaffId ] ]
         , Fragment ProfileDetailsSection
            '[]
            '[ 'MountTarget ProfileDetails '[]
             , 'Eager
             , 'Live
             , 'DependsOn StaffProfileResource '[ 'FromScope StaffId ]
             , 'DependsOn StaffPreferencesResource '[ 'FromScope StaffId ]
             ]
         , Fragment ProfilePreferencesSection '[] '[ 'MountTarget ProfilePreferences '[], 'Eager, 'Live, 'DependsOn StaffPreferencesResource '[ 'FromScope StaffId ] ]
         , Action UpdateProfileDetails StaffProfileFields StaffProfileSubmitOptions
         , Action UpdateProfileShiftPreferences StaffShiftPreferenceFields StaffProfileSubmitOptions
         , Fragment ProfileSecuritySection '[] '[ 'MountTarget ProfileSecurity '[], 'Eager, 'Live, 'ResyncOnly ]
         , Fragment ProfileLeaveSection
            '[]
            '[ 'MountTarget ProfileLeave '[]
             , 'Eager
             , 'Live
             , 'ResyncOnly
             , ContainsSurface SelfServiceLeave.SelfServiceLeave
             ]
         , Fragment ProfileRsaSection '[] '[ 'MountTarget ProfileRsa '[], 'Eager, 'Live, 'DependsOn StaffRsaDocumentsResource '[ 'FromScope StaffId ] ]
         ]

type StaffSurface =
    Surface Staff
        '[ Scope StaffScope
            '[ Field VenueId 'WireUUID
             , Field StaffId 'WireUUID
             ]
            '[ 'Authorize 'CurrentVenueManager '[ VenueId ] ]
         , Fragment StaffDetailsSection
            '[]
            '[ 'MountTarget StaffProfileDetails '[]
             , 'Eager
             , 'Live
             , 'DependsOn StaffProfileResource '[ 'FromScope StaffId ]
             , 'DependsOn StaffPreferencesResource '[ 'FromScope StaffId ]
             ]
         , Fragment StaffPreferencesSection '[] '[ 'MountTarget StaffProfilePreferences '[], 'Eager, 'Live, 'DependsOn StaffPreferencesResource '[ 'FromScope StaffId ] ]
         , Fragment StaffVisibleUnavailabilityBlackouts
            '[]
            '[ 'MountTarget StaffVisibleUnavailabilityBlackouts '[]
             , 'Eager
             , 'Live
             , 'DependsOn SelfServiceLeave.UnavailabilityBlackoutsResource '[ 'FromScope VenueId ]
             ]
         , Fragment StaffLeaveSection '[] '[ 'MountTarget StaffProfileLeave '[], 'Eager, 'Live, 'DependsOn StaffLeaveRequestsResource '[ 'FromScope StaffId ] ]
         , Action UpdateStaffProfile StaffProfileFields StaffProfileSubmitOptions
         , Action UpdateStaffShiftPreferences StaffShiftPreferenceFields StaffProfileSubmitOptions
         , Action CreateStaffLeaveRequest
            '[ Field StartDate 'WireDay
             , Field EndDate 'WireDay
             , Field Notes 'WireText
             ]
            '[ 'HtmxMethod 'HtmxPost
             , 'HtmxTarget ('HtmxId StaffLeaveRequestFormFragment)
             , 'HtmxSwap 'HtmxOuterHTML
             , 'HtmxPushUrl 'HtmxPushUrlFalse
             ]
         , DomToken StaffLeaveRequestFormFragment
         ]
