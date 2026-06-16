module Application.Helper.Staff
    ( adoptableTrialStaff
    , isAdoptableTrialStaff
    , isLinkedActiveStaff
    , isRosterableStaff
    , isTrialStaff
    , linkedActiveStaff
    , rosterableStaff
    ) where

import Generated.Types
import IHP.Prelude

-- | True when a staff record is a trial placeholder (no linked user account).
isTrialStaff :: Staff -> Bool
isTrialStaff staff = isNothing staff.userId

-- | Rosterable staff are active, not archived, and may be either linked staff or
-- trial placeholders. Use this vocabulary for roster planning surfaces.
isRosterableStaff :: Staff -> Bool
isRosterableStaff staff = staff.isActive && isNothing staff.archivedAt

-- | Linked active staff are active, not archived, and have a user account. Use
-- this for timesheet, payroll, Xero, and readiness eligibility.
isLinkedActiveStaff :: Staff -> Bool
isLinkedActiveStaff staff = isRosterableStaff staff && isJust staff.userId

-- | Adoptable trial staff can be claimed by a new invitation-created account.
-- They must be active, not archived, and still have no linked user account.
isAdoptableTrialStaff :: Staff -> Bool
isAdoptableTrialStaff staff = isRosterableStaff staff && isTrialStaff staff

rosterableStaff :: [Staff] -> [Staff]
rosterableStaff = filter isRosterableStaff

linkedActiveStaff :: [Staff] -> [Staff]
linkedActiveStaff = filter isLinkedActiveStaff

adoptableTrialStaff :: [Staff] -> [Staff]
adoptableTrialStaff = filter isAdoptableTrialStaff
