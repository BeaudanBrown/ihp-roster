{-# LANGUAGE BlockArguments      #-}
{-# LANGUAGE OverloadedLabels    #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE TypeApplications    #-}

module Web.Controller.RosterWeeks.Validation
    ( activeRosterWeekSlotDefinitionWithName
    , ensureOptionalShiftTypeInCurrentVenue
    , ensureRosterSlotTimingValidForSave
    , ensureRosterWeekIsDraftForEdit
    , firstAvailableDefaultName
    , invalidRosterSlotTimingMessage
    , nextDefaultRosterSlotDefinitionName
    , normalizeRosterSlotDefinitionName
    , resolveRosterSlotDefinitionNameForCreate
    ) where

import Application.Helper.Controller
import Application.Helper.ControllerContext (currentVenueId)
import Data.Coerce (coerce)
import Data.Maybe (fromMaybe)
import qualified Data.Text as Text
import qualified Data.UUID as UUID
import Web.Controller.Prelude
import Web.RosterWeeks.Paths (rosterWeekUrl)
import Web.RosterWeeks.Responses (respondWithRosterToast)
import Web.RosterWeeks.Service (rosterSlotHasValidStartEnd)
import Web.RosterWeeks.Types

ensureRosterSlotTimingValidForSave :: (?context :: ControllerContext, ?request :: Request) => RosterWeek -> RosterSlot -> IO ()
ensureRosterSlotTimingValidForSave rosterWeek slot =
    case (slot.startsAt, slot.endsAt) of
        (Just _, Just _)
            | not (rosterSlotHasValidStartEnd slot) ->
                let rosterGroupId = coerce rosterWeek.rosterGroupId
                    errorMessage = invalidRosterSlotTimingMessage
                 in if isHtmxRequest
                        then respondWithRosterToast errorMessage "app-toast-error"
                        else do
                            setErrorMessage errorMessage
                            redirectToPath (rosterWeekUrl rosterWeek.weekOffset rosterGroupId)
        _ -> pure ()

invalidRosterSlotTimingMessage :: Text
invalidRosterSlotTimingMessage = "Choose an end time after the start time within the 6:00 AM to 5:45 AM roster day."

ensureOptionalShiftTypeInCurrentVenue :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Maybe UUID.UUID -> IO ()
ensureOptionalShiftTypeInCurrentVenue Nothing = pure ()
ensureOptionalShiftTypeInCurrentVenue (Just shiftTypeId) = do
    exists <-
        query @ShiftType
            |> filterWhere (#id, Id shiftTypeId)
            |> filterWhere (#venueId, unpackId currentVenueId)
            |> filterWhere (#archivedAt, Nothing)
            |> fetchExists
    accessDeniedUnless exists

ensureRosterWeekIsDraftForEdit :: (?context :: ControllerContext, ?request :: Request) => RosterWeek -> IO ()
ensureRosterWeekIsDraftForEdit rosterWeek =
    when rosterWeek.isLive do
        let rosterGroupId = coerce rosterWeek.rosterGroupId
        let targetPath = rosterWeekUrl rosterWeek.weekOffset rosterGroupId
        let errorMessage = "Live roster weeks are read-only. Move it back to draft to make changes."
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

resolveRosterSlotDefinitionNameForCreate :: (?modelContext :: ModelContext, ?request :: Request) => RosterWeek -> IO (Either Text Text)
resolveRosterSlotDefinitionNameForCreate rosterWeek =
    case Text.strip (paramOrDefault @Text "" "name") of
        "" -> Right <$> nextDefaultRosterSlotDefinitionName rosterWeek
        submittedName -> pure (normalizeRosterSlotDefinitionName submittedName)

nextDefaultRosterSlotDefinitionName :: (?modelContext :: ModelContext) => RosterWeek -> IO Text
nextDefaultRosterSlotDefinitionName rosterWeek = do
    activeDefinitions <- query @RosterWeekSlotDefinition
        |> filterWhere (#rosterWeekId, unpackId rosterWeek.id)
        |> filterWhere (#deletedAt, Nothing)
        |> fetch
    let existingNames = map (.name) activeDefinitions
    pure (firstAvailableDefaultName existingNames)

firstAvailableDefaultName :: [Text] -> Text
firstAvailableDefaultName existingNames =
    fromMaybe "New column" (head (filter (`notElem` existingNames) candidateNames))
  where
    candidateNames =
        "New column" : map (\index -> "New column " <> tshow index) [2 :: Int ..]

activeRosterWeekSlotDefinitionWithName :: (?modelContext :: ModelContext) => RosterWeek -> Text -> IO (Maybe RosterWeekSlotDefinition)
activeRosterWeekSlotDefinitionWithName rosterWeek slotName =
    query @RosterWeekSlotDefinition
        |> filterWhere (#rosterWeekId, unpackId rosterWeek.id)
        |> filterWhere (#name, slotName)
        |> filterWhere (#deletedAt, Nothing)
        |> fetchOneOrNothing

