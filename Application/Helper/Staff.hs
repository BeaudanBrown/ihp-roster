module Application.Helper.Staff
    ( adoptableTrialStaff
    , isAdoptableTrialStaff
    , isLinkedActiveStaff
    , isRosterableStaff
    , isTrialStaff
    , linkedActiveStaff
    , rosterableStaff
    , sortStaffForDisplay
    , staffDisplayBaseName
    ) where

import qualified Data.Text as Text
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

-- | Canonical presentation order for staff selection and inventory lists.
-- Preferred names lead when present; legal names and ids make ties stable.
sortStaffForDisplay :: [Staff] -> [Staff]
sortStaffForDisplay = sortBy compareStaff
  where
    compareStaff left right =
        compare (staffSortKey left) (staffSortKey right)

    staffSortKey staff =
        ( Text.toCaseFold (staffDisplayBaseName staff)
        , Text.toCaseFold (Text.strip staff.lastName)
        , Text.toCaseFold (Text.strip staff.firstName)
        , tshow staff.id
        )

staffDisplayBaseName :: Staff -> Text
staffDisplayBaseName staff =
    fromMaybe staff.firstName (nonBlankText =<< staff.preferredName)
  where
    nonBlankText text =
        let stripped = Text.strip text
         in if Text.null stripped then Nothing else Just stripped
