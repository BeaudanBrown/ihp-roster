module Application.Helper.View.Staff
    ( isTrialStaff
    , linkedActiveStaffForRosterPanel
    , rosterableStaffForRosterPanel
    , nonBlankText
    , normalizedStaffDisplayBaseName
    , renderStaffLastInitial
    , staffDisplayBaseName
    , staffDisplayName
    ) where

import Application.Helper.Staff (isTrialStaff, linkedActiveStaff,
                                 rosterableStaff, sortStaffForDisplay,
                                 staffDisplayBaseName)
import qualified Data.Char as Char
import qualified Data.Text as Text
import Generated.Types
import IHP.ViewPrelude

-- Compatibility re-export for existing views. Non-view modules should import
-- isTrialStaff from Application.Helper.Staff.
linkedActiveStaffForRosterPanel :: [Staff] -> [Staff]
linkedActiveStaffForRosterPanel =
    sortStaffForDisplay . linkedActiveStaff

rosterableStaffForRosterPanel :: [Staff] -> [Staff]
rosterableStaffForRosterPanel =
    sortStaffForDisplay . rosterableStaff

staffDisplayName :: [Staff] -> Staff -> Text
staffDisplayName staffMembers staff =
    let
        baseName = staffDisplayBaseName staff
        needsLastInitial =
            any
                (\other -> other.id /= staff.id && normalizedStaffDisplayBaseName other == normalizedStaffDisplayBaseName staff)
                staffMembers
     in
        if needsLastInitial
            then baseName <> renderStaffLastInitial staff
            else baseName

normalizedStaffDisplayBaseName :: Staff -> Text
normalizedStaffDisplayBaseName = Text.toCaseFold . staffDisplayBaseName

renderStaffLastInitial :: Staff -> Text
renderStaffLastInitial staff =
    case Text.find (not . Char.isSpace) (Text.strip staff.lastName) of
        Just char -> " " <> Text.singleton (Char.toUpper char) <> "."
        Nothing   -> ""

nonBlankText :: Text -> Maybe Text
nonBlankText text =
    let stripped = Text.strip text
     in if Text.null stripped then Nothing else Just stripped
