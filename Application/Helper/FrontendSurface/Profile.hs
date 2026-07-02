{-# LANGUAGE DataKinds     #-}
{-# LANGUAGE TypeOperators #-}

module Application.Helper.FrontendSurface.Profile
    ( ProfileDetailsSection
    , ProfileLeaveSection
    , ProfilePreferencesSection
    , ProfileRsaSection
    , ProfileSecuritySection
    , ProfileScope
    , ProfileSurface
    , StaffId
    , VenueId
    ) where

import Application.Helper.FrontendSurface.DSL

data Profile

data ProfileScope
data VenueId
data StaffId

data ProfileDetailsSection
data ProfilePreferencesSection
data ProfileSecuritySection
data ProfileLeaveSection
data ProfileRsaSection
type ProfileSurface =
    Surface Profile
        '[ Scope ProfileScope
            '[ Field VenueId 'WireUUID
             , Field StaffId 'WireUUID
             ]
         , Fragment ProfileDetailsSection '[] '[ 'Eager ]
         , Fragment ProfilePreferencesSection '[] '[ 'Eager ]
         , Fragment ProfileSecuritySection '[] '[ 'Eager ]
         , Fragment ProfileLeaveSection '[] '[ 'Eager ]
         , Fragment ProfileRsaSection '[] '[ 'Eager ]
         ]
