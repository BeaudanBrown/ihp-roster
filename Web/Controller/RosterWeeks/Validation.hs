{-# LANGUAGE BlockArguments      #-}
{-# LANGUAGE OverloadedLabels    #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE TypeApplications    #-}

module Web.Controller.RosterWeeks.Validation
    ( firstAvailableDefaultName
    , invalidRosterSlotTimingMessage
    , normalizeRosterSlotDefinitionName
    ) where

import qualified Data.Text as Text
import Web.Controller.Prelude


invalidRosterSlotTimingMessage :: Text
invalidRosterSlotTimingMessage = "Choose an end time after the start time within the 6:00 AM to 5:45 AM roster day."


normalizeRosterSlotDefinitionName :: Text -> Either Text Text
normalizeRosterSlotDefinitionName submittedName =
    let normalized = Text.strip submittedName
     in if Text.null normalized
            then Left "Roster column name is required."
            else
                if Text.length normalized > 120
                    then Left "Roster column name must be 120 characters or fewer."
                    else Right normalized

firstAvailableDefaultName :: [Text] -> Text
firstAvailableDefaultName existingNames =
    fromMaybe "New column" (listToMaybe (filter (`notElem` existingNames) candidateNames))
  where
    candidateNames =
        "New column" : map (\index -> "New column " <> tshow index) [2 :: Int ..]
