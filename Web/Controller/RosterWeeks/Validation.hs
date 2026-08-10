{-# LANGUAGE BlockArguments      #-}
{-# LANGUAGE OverloadedLabels    #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE TypeApplications    #-}

module Web.Controller.RosterWeeks.Validation
    ( ensureRosterWeekIsDraftForEdit
    , firstAvailableDefaultName
    , invalidRosterSlotTimingMessage
    , normalizeRosterSlotDefinitionName
    ) where

import Application.Helper.Controller
import Application.Helper.ControllerContext (currentVenueId)
import Application.Helper.WeekBoundaries (venueWeekStartDate)
import Data.Coerce (coerce)
import Data.Maybe (fromMaybe)
import qualified Data.Text as Text
import qualified Data.UUID as UUID
import Web.Controller.Prelude
import Web.RosterWeeks.Paths (rosterWindowUrl)
import Web.RosterWeeks.Responses (respondWithRosterToast)
import Web.RosterWeeks.Service (rosterSlotHasValidStartEnd)
import Web.RosterWeeks.Types


invalidRosterSlotTimingMessage :: Text
invalidRosterSlotTimingMessage = "Choose an end time after the start time within the 6:00 AM to 5:45 AM roster day."


ensureRosterWeekIsDraftForEdit :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterWeek -> IO ()
ensureRosterWeekIsDraftForEdit rosterWeek =
    when rosterWeek.isLive do
        let rosterGroupId = coerce rosterWeek.rosterGroupId
        venueConfig <- fetchVenueConfig
        let targetPath = rosterWindowUrl (venueWeekStartDate venueConfig rosterWeek.weekOffset) rosterGroupId
        let errorMessage = "Published roster windows are read-only. Return it to Draft to make changes."
        if isHtmxRequest
            then respondWithRosterToast errorMessage "app-toast-error"
            else do
                setErrorMessage errorMessage
                redirectToPath targetPath

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
    fromMaybe "New column" (head (filter (`notElem` existingNames) candidateNames))
  where
    candidateNames =
        "New column" : map (\index -> "New column " <> tshow index) [2 :: Int ..]
