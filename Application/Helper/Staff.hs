module Application.Helper.Staff
    ( isTrialStaff
    ) where

import Generated.Types
import IHP.Prelude

-- | True when a staff record is a trial placeholder (no linked user account).
isTrialStaff :: Staff -> Bool
isTrialStaff staff = isNothing staff.userId
