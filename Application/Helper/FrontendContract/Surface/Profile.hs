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
    , StaffId
    , VenueId
    ) where

import Application.Helper.FrontendContract.Surface.DSL

data Profile

data ProfileScope
data VenueId
data StaffId

data ProfileDetailsSection
data ProfilePreferencesSection
data ProfileSecuritySection
data ProfileLeaveSection
data ProfileRsaSection

data StaffProfile
data StaffPreferences
data StaffLeaveRequests
data StaffRsaDocuments

type StaffProfileResource = Resource StaffProfile '[ Field StaffId 'WireUUID ]
type StaffPreferencesResource = Resource StaffPreferences '[ Field StaffId 'WireUUID ]
type StaffLeaveRequestsResource = Resource StaffLeaveRequests '[ Field StaffId 'WireUUID ]
type StaffRsaDocumentsResource = Resource StaffRsaDocuments '[ Field StaffId 'WireUUID ]

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
         , Fragment ProfileSecuritySection '[] '[ 'Eager, 'Live, 'ResyncOnly ]
         , Fragment ProfileLeaveSection '[] '[ 'Eager, 'Live, 'DependsOn StaffLeaveRequestsResource '[ 'FromScope StaffId ] ]
         , Fragment ProfileRsaSection '[] '[ 'Eager, 'Live, 'DependsOn StaffRsaDocumentsResource '[ 'FromScope StaffId ] ]
         ]
