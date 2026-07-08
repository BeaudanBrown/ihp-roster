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
    , StaffPreferencesSection
    , StaffScope
    , StaffSurface
    , UpdateProfileDetails
    , UpdateProfileShiftPreferences
    , UpdateStaffProfile
    , UpdateStaffShiftPreferences
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
data ProfileDetails
data ProfilePreferences
data StaffDetailsTarget
data StaffPreferencesTarget
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
            '[ 'Eager
             , 'Live
             , 'DependsOn StaffProfileResource '[ 'FromScope StaffId ]
             , 'DependsOn StaffPreferencesResource '[ 'FromScope StaffId ]
             ]
         , Fragment ProfilePreferencesSection '[] '[ 'Eager, 'Live, 'DependsOn StaffPreferencesResource '[ 'FromScope StaffId ] ]
         , Action UpdateProfileDetails StaffProfileFields StaffProfileSubmitOptions
         , Action UpdateProfileShiftPreferences StaffShiftPreferenceFields StaffProfileSubmitOptions
         , Fragment ProfileSecuritySection '[] '[ 'Eager, 'Live, 'ResyncOnly ]
         , Fragment ProfileLeaveSection '[] '[ 'Eager, 'Live, 'DependsOn StaffLeaveRequestsResource '[ 'FromScope StaffId ] ]
         , Fragment ProfileRsaSection '[] '[ 'Eager, 'Live, 'DependsOn StaffRsaDocumentsResource '[ 'FromScope StaffId ] ]
         , Action CreateProfileLeaveRequest
            '[ Field StartDate 'WireDay
             , Field EndDate 'WireDay
             , Field Reason 'WireText
             ]
            '[ 'HtmxMethod 'HtmxPost
             , 'HtmxTarget ProfileLeaveRequestFormFragment
             , 'HtmxSwap OuterHTML
             , 'HtmxPushUrl 'HtmxPushUrlFalse
             ]
         , DomToken ProfileDetails
         , DomToken ProfilePreferences
         , DomToken ProfileLeaveRequestFormFragment
         ]

type StaffSurface =
    Surface Staff
        '[ Scope StaffScope
            '[ Field VenueId 'WireUUID
             , Field StaffId 'WireUUID
             ]
            '[ 'Authorize 'CurrentVenueStaff '[ VenueId, StaffId ] ]
         , Fragment StaffDetailsSection
            '[]
            '[ 'Eager
             , 'Live
             , 'DependsOn StaffProfileResource '[ 'FromScope StaffId ]
             , 'DependsOn StaffPreferencesResource '[ 'FromScope StaffId ]
             ]
         , Fragment StaffPreferencesSection '[] '[ 'Eager, 'Live, 'DependsOn StaffPreferencesResource '[ 'FromScope StaffId ] ]
         , Action UpdateStaffProfile StaffProfileFields StaffProfileSubmitOptions
         , Action UpdateStaffShiftPreferences StaffShiftPreferenceFields StaffProfileSubmitOptions
         , DomToken StaffDetailsTarget
         , DomToken StaffPreferencesTarget
         ]
