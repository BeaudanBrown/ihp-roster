{-# LANGUAGE DataKinds     #-}
{-# LANGUAGE TypeOperators #-}

module Application.Helper.FrontendContract.Surface.Profile
    ( ProfileDetailsSection
    , ProfileLeaveSection
    , ProfilePreferencesSection
    , ProfileSecuritySection
    , StaffLeaveRequests
    , StaffPreferences
    , StaffProfile
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
    , StaffProfileSectionValue (..)
    ) where

import Application.Helper.FrontendContract.Surface.DSL hiding (Enum)
import qualified Application.Helper.FrontendContract.Surface.SelfServiceLeave as SelfServiceLeave
import Generated.Types (StaffEmploymentBasisEnum, VenueRoleEnum)
import IHP.ModelSupport (InputValue (..))
import IHP.Prelude

data StaffProfileSectionValue
    = StaffProfileDetailsSection
    | StaffProfilePreferencesSection
    deriving (Eq, Show, Enum, Bounded)

instance InputValue StaffProfileSectionValue where
    inputValue StaffProfileDetailsSection     = "profile"
    inputValue StaffProfilePreferencesSection = "preferences"

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
data StaffProfileDetails
data StaffProfilePreferences
data StaffProfileLeave
data ProfileSecuritySection
data ProfileLeaveSection

data StaffProfile
data StaffPreferences
type StaffLeaveRequests = SelfServiceLeave.StaffLeaveRequests

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

type StaffProfileFields =
    '[ Field FirstNameField 'WireText
     , Field LastNameField 'WireText
     , Field PreferredNameField 'WireText
     , Field PhoneField 'WireText
     , Field IdealShiftsPerWeekField 'WireInt
     , Field EmergencyContactNameField 'WireText
     , Field EmergencyContactPhoneField 'WireText
     , Field SectionField ('WireClosed StaffProfileSectionValue)
     , OptionalField VenueRoleField ('WireClosed VenueRoleEnum)
     , OptionalField EmploymentBasisField ('WireClosed StaffEmploymentBasisEnum)
     , OptionalField PayRateSelectionField 'WireText
     , OptionalField RosterGroupIdsField ('WireList 'WireUUID)
     ]

type StaffShiftPreferenceFields =
    '[ Field SectionField ('WireClosed StaffProfileSectionValue)
     , OptionalField ShiftPreferenceKeysField ('WireList 'WireText)
     ]

type StaffProfileSubmitOptions =
    '[ 'HtmxMethod 'HtmxPost
     , 'HtmxPushUrl 'HtmxPushUrlFalse
     , 'CustomHtmx StaffProfileSectionHtmxAttrs "profile and staff forms provide their concrete section target and swap modifier at the route boundary"
     ]

type StaffShiftPreferenceSubmitOptions =
    '[ 'HtmxMethod 'HtmxPost
     , 'HtmxTrigger 'HtmxChange
     , 'HtmxSync ('HtmxSyncOn 'HtmxThis 'HtmxSyncQueueLast)
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
         , Action UpdateProfileShiftPreferences StaffShiftPreferenceFields StaffShiftPreferenceSubmitOptions
         , Fragment ProfileSecuritySection '[] '[ 'MountTarget ProfileSecurity '[], 'Eager, 'Live, 'ResyncOnly ]
         , Fragment ProfileLeaveSection
            '[]
            '[ 'MountTarget ProfileLeave '[]
             , 'Eager
             , 'Live
             , 'ResyncOnly
             , ContainsSurface SelfServiceLeave.SelfServiceLeave
             ]
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
         , Action UpdateStaffShiftPreferences StaffShiftPreferenceFields StaffShiftPreferenceSubmitOptions
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
