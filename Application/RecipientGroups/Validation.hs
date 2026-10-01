module Application.RecipientGroups.Validation (validateRecipientAddresses) where

import qualified Data.List as List
import qualified Data.Text as Text
import IHP.ControllerPrelude

-- Syntax/normalisation only, not verification or permission to share data.
-- Legacy disabled payroll settings allow an empty list; saved groups do not.
validateRecipientAddresses :: [Text] -> Either Text [Text]
validateRecipientAddresses values
    | length (take 51 unique) > 50 = Left "Use at most 50 recipients."
    | any invalidAddress normalized = Left "Enter valid email addresses without display names."
    | otherwise = Right unique
  where
    -- Bound distinct recipients, not repeated draft entries. Stop deduplicating
    -- once the limit is exceeded rather than traversing an unbounded unique list.
    unique = List.nub normalized
    normalized = map (Text.toLower . Text.strip) values
    invalidAddress address = Text.null address || Text.length address > 254
        || Text.any (`elem` ['\r', '\n', ',', ';', '<', '>']) address
        || case isEmail address of
            Success -> False
            Failure _ -> True
            FailureHtml _ -> True
