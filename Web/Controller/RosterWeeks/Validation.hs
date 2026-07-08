{-# LANGUAGE BlockArguments      #-}
{-# LANGUAGE OverloadedLabels    #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE TypeApplications    #-}

module Web.Controller.RosterWeeks.Validation
    ( activeRosterWeekSlotDefinitionWithName
    , applyRosterSlotDuration
    , ensureOptionalShiftTypeInCurrentVenue
    , ensureRosterSlotTimingValidForSave
    , ensureRosterWeekIsDraftForEdit
    , firstAvailableDefaultName
    , invalidRosterSlotTimingMessage
    , nextDefaultRosterSlotDefinitionName
    , normalizeRosterSlotDefinitionName
    , publishRequiredFieldsMessage
    , resolveRosterSlotDefinitionNameForCreate
    , rosterSlotBlocksPublish
    , rosterSlotHasValidStartEnd
    , rosterSlotTimesheetSourceChanged
    , rosterStaffPanelScopeFromParams
    , validateRosterWeekCanGoLive
    ) where

import Application.Helper.Controller
import Application.Helper.ControllerContext (currentVenueId)
import Application.Helper.TimeRules (shiftDurationMinutes)
import Data.Coerce (coerce)
import Data.Maybe (fromMaybe, isNothing)
import qualified Data.Text as Text
import qualified Data.Time.Calendar as Calendar
import qualified Data.UUID as UUID
import Web.Controller.Prelude
import Web.RosterWeeks.Paths (rosterWeekUrl)
import Web.RosterWeeks.Responses (respondWithRosterToast)
import Web.RosterWeeks.Types

validateRosterWeekCanGoLive :: (?context :: ControllerContext, ?modelContext :: ModelContext) => RosterWeek -> Bool -> IO (Maybe Text)
validateRosterWeekCanGoLive _ False = pure Nothing
validateRosterWeekCanGoLive rosterWeek True = do
    rosterDays <- query @RosterDay
        |> filterWhere (#rosterWeekId, unpackId rosterWeek.id)
        |> fetch
    rosterSlots <-
        if null rosterDays
            then pure []
            else query @RosterSlot
                |> filterWhereIn (#rosterDayId, map (unpackId . (.id)) rosterDays)
                |> filterWhere (#deletedAt, Nothing)
                |> fetch
    let blockingSlots = filter rosterSlotBlocksPublish rosterSlots
    pure
        if null blockingSlots
            then Nothing
            else Just publishRequiredFieldsMessage

publishRequiredFieldsMessage :: Text
publishRequiredFieldsMessage = "Roster week cannot go live until every staffed shift has a start time, valid end time, and shift type."

rosterSlotBlocksPublish :: RosterSlot -> Bool
rosterSlotBlocksPublish slot =
    isJust slot.staffId
        && ( isNothing slot.startTime
             || isNothing slot.shiftTypeId
             || not (rosterSlotHasValidStartEnd slot)
           )

rosterSlotHasValidStartEnd :: RosterSlot -> Bool
rosterSlotHasValidStartEnd slot =
    case (slot.startTime, slot.endTime) of
        (Just startTime, Just endTime) -> isValidRosterShiftTimePair startTime endTime
        _ -> False

ensureRosterSlotTimingValidForSave :: (?context :: ControllerContext, ?request :: Request) => RosterWeek -> RosterSlot -> IO ()
ensureRosterSlotTimingValidForSave rosterWeek slot =
    case (slot.startTime, slot.endTime) of
        (Just startTime, Just endTime)
            | not (isValidRosterShiftTimePair startTime endTime) ->
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

rosterSlotTimesheetSourceChanged :: RosterSlot -> RosterSlot -> Bool
rosterSlotTimesheetSourceChanged previous next =
    previous.staffId /= next.staffId
        || previous.startTime /= next.startTime
        || previous.endTime /= next.endTime
        || previous.shiftTypeId /= next.shiftTypeId

applyRosterSlotDuration :: RosterSlot -> RosterSlot
applyRosterSlotDuration slot =
    case (slot.startTime, slot.endTime) of
        (Just startTime, Just endTime) ->
            slot |> set #durationMinutes (validRosterShiftDurationMinutes startTime endTime)
        _ ->
            slot |> set #durationMinutes Nothing

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

rosterStaffPanelScopeFromParams :: (?request :: Request) => RosterStaffPanelScope
rosterStaffPanelScopeFromParams =
    case Text.toLower (paramOrDefault @Text "group" "staffScope") of
        "all" -> RosterStaffPanelAllVenue
        _     -> RosterStaffPanelCurrentGroup

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

activeRosterWeekSlotDefinitionWithName :: (?modelContext :: ModelContext) => RosterWeek -> Text -> Maybe (Id RosterWeekSlotDefinition) -> IO (Maybe RosterWeekSlotDefinition)
activeRosterWeekSlotDefinitionWithName rosterWeek slotName maybeExceptId = do
    matches <- query @RosterWeekSlotDefinition
        |> filterWhere (#rosterWeekId, unpackId rosterWeek.id)
        |> filterWhere (#name, slotName)
        |> filterWhere (#deletedAt, Nothing)
        |> fetch
    pure (find (\slotDefinition -> Just slotDefinition.id /= maybeExceptId) matches)

