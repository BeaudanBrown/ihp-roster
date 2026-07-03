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
            '[ 'NoAuth ]
         , Fragment ProfileDetailsSection '[] '[ 'Eager, 'Live, 'ResyncOnly ]
         , Fragment ProfilePreferencesSection '[] '[ 'Eager, 'Live, 'ResyncOnly ]
         , Fragment ProfileSecuritySection '[] '[ 'Eager, 'Live, 'ResyncOnly ]
         , Fragment ProfileLeaveSection '[] '[ 'Eager, 'Live, 'ResyncOnly ]
         , Fragment ProfileRsaSection '[] '[ 'Eager, 'Live, 'ResyncOnly ]
         ]
