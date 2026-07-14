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
    , CreateProfileLeaveRequest
    , ProfileScope
    , ProfileSurface
    , StaffDetailsSection
    , StaffLeaveSection
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
    ) where

import Application.Helper.FrontendContract.Surface.DSL

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
data StaffLeaveRequests
data StaffRsaDocuments

data CreateProfileLeaveRequest
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
data IsActiveField
data RosterGroupIdsField
data ShiftPreferenceKeysField
data StaffProfileSectionHtmxAttrs

data StaffLeaveRequestFormFragment
data StartDate
data EndDate
data Reason
data ProfileLeaveRequestFormFragment
data OuterHTML

type StaffProfileResource = Resource StaffProfile '[ Field StaffId 'WireUUID ]
type StaffPreferencesResource = Resource StaffPreferences '[ Field StaffId 'WireUUID ]
type StaffLeaveRequestsResource = Resource StaffLeaveRequests '[ Field StaffId 'WireUUID ]
type StaffRsaDocumentsResource = Resource StaffRsaDocuments '[ Field StaffId 'WireUUID ]

type StaffProfileFields =
    '[ Field FirstNameField 'WireText
     , Field LastNameField 'WireText
     , Field PreferredNameField 'WireText
     , Field PhoneField 'WireText
     , Field IdealShiftsPerWeekField 'WireText
     , Field EmergencyContactNameField 'WireText
     , Field EmergencyContactPhoneField 'WireText
     , Field SectionField 'WireText
     , Field WeekOffsetField 'WireText
     , Field RosterGroupIdField 'WireText
     , Field VenueRoleField 'WireText
     , Field EmploymentBasisField 'WireText
     , Field PayRateSelectionField 'WireText
     , Field IsActiveField 'WireText
     , Field RosterGroupIdsField 'WireText
     ]

type StaffShiftPreferenceFields =
    '[ Field SectionField 'WireText
     , Field WeekOffsetField 'WireText
     , Field RosterGroupIdField 'WireText
     , Field ShiftPreferenceKeysField 'WireText
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
         , Fragment ProfileLeaveSection '[] '[ 'MountTarget ProfileLeave '[], 'Eager, 'Live, 'DependsOn StaffLeaveRequestsResource '[ 'FromScope StaffId ] ]
         , Fragment ProfileRsaSection '[] '[ 'MountTarget ProfileRsa '[], 'Eager, 'Live, 'DependsOn StaffRsaDocumentsResource '[ 'FromScope StaffId ] ]
         , Action CreateProfileLeaveRequest
            '[ Field StartDate 'WireDay
             , Field EndDate 'WireDay
             , Field Reason 'WireText
             ]
            '[ 'HtmxMethod 'HtmxPost
             , 'HtmxTarget ('HtmxId ProfileLeaveRequestFormFragment)
             , 'HtmxSwap 'HtmxOuterHTML
             , 'HtmxPushUrl 'HtmxPushUrlFalse
             ]
         , DomToken ProfileLeaveRequestFormFragment
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
         , Fragment StaffLeaveSection '[] '[ 'MountTarget StaffProfileLeave '[], 'Eager, 'Live, 'DependsOn StaffLeaveRequestsResource '[ 'FromScope StaffId ] ]
         , Action UpdateStaffProfile StaffProfileFields StaffProfileSubmitOptions
         , Action UpdateStaffShiftPreferences StaffShiftPreferenceFields StaffProfileSubmitOptions
         , Action CreateStaffLeaveRequest
            '[ Field StartDate 'WireDay
             , Field EndDate 'WireDay
             , Field Reason 'WireText
             ]
            '[ 'HtmxMethod 'HtmxPost
             , 'HtmxTarget ('HtmxId StaffLeaveRequestFormFragment)
             , 'HtmxSwap 'HtmxOuterHTML
             , 'HtmxPushUrl 'HtmxPushUrlFalse
             ]
         , DomToken StaffLeaveRequestFormFragment
         ]
