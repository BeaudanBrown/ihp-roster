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
         , Fragment ProfileDetailsSection '[] '[ 'Eager, 'Live ]
         , Fragment ProfilePreferencesSection '[] '[ 'Eager, 'Live ]
         , Fragment ProfileSecuritySection '[] '[ 'Eager, 'Live ]
         , Fragment ProfileLeaveSection '[] '[ 'Eager, 'Live ]
         , Fragment ProfileRsaSection '[] '[ 'Eager, 'Live ]
         ]
