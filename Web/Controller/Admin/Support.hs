module Web.Controller.Admin.Support where

import Application.Helper.Export
import Application.Helper.LiveUpdate
import Application.Helper.Pay
import Application.Helper.RosterGroups
import Application.Helper.VenueInvitation
import Application.Helper.WeekBoundaries (defaultWeekOffsetEpochForStartDay,
                                          validRosterWeekStartDays,
                                          weekdayIndexLabel,
                                          sortDayNamesForVenueWeek)
import Control.Concurrent (forkIO)
import Control.Monad (void)
import qualified Data.List as List
import qualified Data.Text as Text
import Web.Controller.Prelude
import Web.View.Admin.Invites
import Web.View.Admin.RosterGroups
import Web.View.Admin.ShiftTypes

fetchCurrentVenueShiftTypes :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO [ShiftType]
fetchCurrentVenueShiftTypes =
    query @ShiftType
        |> filterWhere (#venueId, unpackId currentVenueId)
        |> filterWhere (#archivedAt, Nothing)
        |> orderByAsc #sortOrder
        |> orderByAsc #createdAt
        |> fetch

fetchActiveCurrentVenueSlotNames :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO [SlotName]
fetchActiveCurrentVenueSlotNames =
    query @SlotName
        |> filterWhere (#venueId, unpackId currentVenueId)
        |> filterWhere (#isActive, True)
        |> filterWhere (#archivedAt, Nothing)
        |> orderByAsc #sortOrder
        |> orderByAsc #createdAt
        |> fetch

fetchActiveAwardLevels :: (?modelContext :: ModelContext) => IO [AwardLevel]
fetchActiveAwardLevels =
    query @AwardLevel
        |> filterWhere (#isActive, True)
        |> orderByAsc #classification
        |> orderByAsc #classificationLevel
        |> fetch

fetchCurrentAwardLevelBaseRates :: (?modelContext :: ModelContext) => IO [AwardLevelBaseRate]
fetchCurrentAwardLevelBaseRates =
    query @AwardLevelBaseRate
        |> filterWhere (#operativeTo, Nothing :: Maybe Day)
        |> orderByAsc #createdAt
        |> fetch

nextSlotNameSortOrder :: (?modelContext :: ModelContext) => Id RosterGroup -> IO Int
nextSlotNameSortOrder rosterGroupId =
    query @SlotName
        |> filterWhere (#rosterGroupId, unpackId rosterGroupId)
        |> filterWhere (#archivedAt, Nothing)
        |> orderByDesc #sortOrder
        |> fetchOneOrNothing
        >>= pure . maybe 0 ((+ 1) . get #sortOrder)

nextRosterGroupSortOrder :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO Int
nextRosterGroupSortOrder =
    query @RosterGroup
        |> filterWhere (#venueId, unpackId currentVenueId)
        |> filterWhere (#archivedAt, Nothing)
        |> orderByDesc #sortOrder
        |> fetchOneOrNothing
        >>= pure . maybe 0 ((+ 1) . get #sortOrder)

nextShiftTypeSortOrder :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO Int
nextShiftTypeSortOrder =
    query @ShiftType
        |> filterWhere (#venueId, unpackId currentVenueId)
        |> filterWhere (#archivedAt, Nothing)
        |> orderByDesc #sortOrder
        |> fetchOneOrNothing
        >>= pure . maybe 0 ((+ 1) . get #sortOrder)

respondToSlotNameMutation :: (?context :: ControllerContext, ?request :: Request) => Text -> Id RosterGroup -> IO ()
respondToSlotNameMutation successMessage rosterGroupId =
    if isHtmxRequest
        then renderPlain ""
        else do
            setSuccessMessage successMessage
            redirectToAdminFor (Just rosterGroupId)

respondToSlotNameSectionMutation ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Text ->
    Id RosterGroup ->
    IO ()
respondToSlotNameSectionMutation successMessage rosterGroupId =
    if isHtmxRequest
        then do
            currentRosterGroup <- fetchCurrentVenueRosterGroupOrDefault (Just rosterGroupId)
            slotNames <- fetchActiveRosterGroupSlotNames currentRosterGroup.id
            respondHtml (renderRosterGroupSlotNamesFragment currentRosterGroup slotNames)
        else do
            setSuccessMessage successMessage
            redirectToAdminFor (Just rosterGroupId)

respondToInvitesSectionMutation ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Text ->
    Id RosterGroup ->
    IO ()
respondToInvitesSectionMutation successMessage rosterGroupId =
    if isHtmxRequest
        then do
            unless (Text.null successMessage) (setSuccessMessage successMessage)
            invitations <- fetchCurrentVenueInvitations
            respondHtml (renderInvitesSectionFragment invitations rosterGroupId)
        else do
            unless (Text.null successMessage) (setSuccessMessage successMessage)
            redirectToAdminFor (Just rosterGroupId)

respondToShiftTypesSectionMutation ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    IO ()
respondToShiftTypesSectionMutation =
    if isHtmxRequest
        then do
            shiftTypes <- fetchCurrentVenueShiftTypes
            awardLevels <- fetchActiveAwardLevels
            awardLevelBaseRates <- fetchCurrentAwardLevelBaseRates
            let showInactiveShiftTypes = parseShowInactiveParam "showInactiveShiftTypes"
            respondHtml (renderShiftTypesSectionFragment shiftTypes showInactiveShiftTypes awardLevels awardLevelBaseRates)
        else redirectToAdminFor (paramOrNothing "rosterGroupId")

respondToRosterGroupsSectionMutation ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Maybe (Id RosterGroup) ->
    IO ()
respondToRosterGroupsSectionMutation maybeRosterGroupId =
    if isHtmxRequest
        then do
            rosterGroups <- fetchCurrentVenueRosterGroups
            slotNames <- fetchActiveCurrentVenueSlotNames
            let showInactiveRosterGroups = parseShowInactiveParam "showInactiveRosterGroups"
            respondHtml (renderRosterGroupsSectionFragment rosterGroups slotNames showInactiveRosterGroups)
        else redirectToAdminFor maybeRosterGroupId

broadcastSlotNameInvalidation ::
    (?context :: ControllerContext, ?request :: Request) =>
    Id RosterGroup ->
    IO ()
broadcastSlotNameInvalidation rosterGroupId =
    broadcastLiveResync
        (slotNamesScope rosterGroupId)
        liveUpdateSourceClientId

broadcastAdminSlotNamesInvalidation ::
    (?context :: ControllerContext, ?request :: Request) =>
    Id RosterGroup ->
    IO ()
broadcastAdminSlotNamesInvalidation rosterGroupId =
    broadcastLiveResync
        (adminSlotNamesScope rosterGroupId)
        liveUpdateSourceClientId

broadcastAdminInvitesInvalidation ::
    (?context :: ControllerContext, ?request :: Request) =>
    Id Venue ->
    IO ()
broadcastAdminInvitesInvalidation venueId =
    broadcastLiveResync
        (adminInvitesScope venueId)
        liveUpdateSourceClientId

broadcastAdminShiftTypesInvalidation ::
    (?context :: ControllerContext, ?request :: Request) =>
    Id Venue ->
    IO ()
broadcastAdminShiftTypesInvalidation venueId =
    broadcastLiveResync
        (adminShiftTypesScope venueId)
        liveUpdateSourceClientId

broadcastAdminRosterGroupsInvalidation ::
    (?context :: ControllerContext, ?request :: Request) =>
    Id Venue ->
    IO ()
broadcastAdminRosterGroupsInvalidation venueId =
    broadcastLiveResync
        (adminRosterGroupsScope venueId)
        liveUpdateSourceClientId

slotNamesScope :: (?context :: ControllerContext) => Id RosterGroup -> LiveUpdateScope
slotNamesScope rosterGroupId =
    RosterGroupConfigScope
        { venueId = unpackId currentVenueId
        , rosterGroupId = unpackId rosterGroupId
        }

adminSlotNamesScope :: (?context :: ControllerContext) => Id RosterGroup -> LiveUpdateScope
adminSlotNamesScope rosterGroupId =
    AdminSlotNamesScope
        { venueId = unpackId currentVenueId
        , rosterGroupId = unpackId rosterGroupId
        }

adminInvitesScope :: Id Venue -> LiveUpdateScope
adminInvitesScope venueId =
    AdminInvitesScope
        { venueId = unpackId venueId
        }

adminShiftTypesScope :: Id Venue -> LiveUpdateScope
adminShiftTypesScope venueId =
    AdminShiftTypesScope
        { venueId = unpackId venueId
        }

adminRosterGroupsScope :: Id Venue -> LiveUpdateScope
adminRosterGroupsScope venueId =
    AdminRosterGroupsScope
        { venueId = unpackId venueId
        }

queueVenueInvitationDelivery ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    VenueInvitation ->
    IO ()
queueVenueInvitationDelivery invitation = do
    let currentContext = ?context
    let currentModelContext = ?modelContext
    let currentRequest = ?request
    void $
        forkIO do
            let ?context = currentContext
            let ?modelContext = currentModelContext
            let ?request = currentRequest
            _ <- deliverVenueInvitationEmail invitation
            broadcastAdminInvitesInvalidation (Id invitation.venueId :: Id Venue)
            pure ()

reorderActiveSlotNames :: (?modelContext :: ModelContext) => Id RosterGroup -> Id SlotName -> Int -> IO ()
reorderActiveSlotNames rosterGroupId slotNameId direction = do
    activeSlotNames <- fetchActiveRosterGroupSlotNames rosterGroupId
    let currentIndex = List.findIndex (\slotName -> slotName.id == slotNameId) activeSlotNames
    case currentIndex of
        Nothing -> pure ()
        Just index -> do
            let targetIndex = index + direction
            if targetIndex < 0 || targetIndex >= length activeSlotNames
                then pure ()
                else do
                    let reordered = moveListItem index targetIndex activeSlotNames
                    forM_ (zip [0 :: Int ..] reordered) \(sortOrder, slotName) ->
                        when (slotName.sortOrder /= sortOrder) do
                            _ <- slotName
                                |> set #sortOrder sortOrder
                                |> updateRecord
                            pure ()

reorderActiveRosterGroups :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Id RosterGroup -> Int -> IO ()
reorderActiveRosterGroups rosterGroupId direction = do
    activeRosterGroups <- filter (.isActive) <$> fetchCurrentVenueRosterGroups
    let currentIndex = List.findIndex (\rosterGroup -> rosterGroup.id == rosterGroupId) activeRosterGroups
    case currentIndex of
        Nothing -> pure ()
        Just index -> do
            let targetIndex = index + direction
            if targetIndex < 0 || targetIndex >= length activeRosterGroups
                then pure ()
                else do
                    let reordered = moveListItem index targetIndex activeRosterGroups
                    forM_ (zip [0 :: Int ..] reordered) \(sortOrder, rosterGroup) ->
                        when (rosterGroup.sortOrder /= sortOrder) do
                            _ <- rosterGroup
                                |> set #sortOrder sortOrder
                                |> updateRecord
                            pure ()

reorderActiveShiftTypes :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Id ShiftType -> Int -> IO ()
reorderActiveShiftTypes shiftTypeId direction = do
    activeShiftTypes <- filter (.isActive) <$> fetchCurrentVenueShiftTypes
    let currentIndex = List.findIndex (\shiftType -> shiftType.id == shiftTypeId) activeShiftTypes
    case currentIndex of
        Nothing -> pure ()
        Just index -> do
            let targetIndex = index + direction
            if targetIndex < 0 || targetIndex >= length activeShiftTypes
                then pure ()
                else do
                    let reordered = moveListItem index targetIndex activeShiftTypes
                    forM_ (zip [0 :: Int ..] reordered) \(sortOrder, shiftType) ->
                        when (shiftType.sortOrder /= sortOrder) do
                            _ <- shiftType
                                |> set #sortOrder sortOrder
                                |> updateRecord
                            pure ()

moveListItem :: Int -> Int -> [a] -> [a]
moveListItem sourceIndex targetIndex items
    | sourceIndex == targetIndex = items
    | otherwise =
        case List.splitAt sourceIndex items of
            (before, item : after) ->
                let remaining = before <> after
                    (insertBefore, insertAfter) = List.splitAt targetIndex remaining
                 in insertBefore <> [item] <> insertAfter
            _ -> items

fetchCurrentVenueDayNames :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO [DayName]
fetchCurrentVenueDayNames = do
    venueConfig <- fetchVenueConfig
    dayNames <-
        query @DayName
            |> filterWhere (#venueId, unpackId currentVenueId)
            |> fetch
    pure (sortDayNamesForVenueWeek venueConfig dayNames)

fetchCurrentVenueInvitations :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO [VenueInvitation]
fetchCurrentVenueInvitations =
    query @VenueInvitation
        |> filterWhere (#venueId, unpackId currentVenueId)
        |> orderByDesc #createdAt
        |> fetch

isVenueRosterWeekStartLocked :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO Bool
isVenueRosterWeekStartLocked = do
    rosterWeekCount <-
        query @RosterWeek
            |> filterWhere (#venueId, unpackId currentVenueId)
            |> fetchCount
    timesheetEntryCount <-
        query @TimesheetEntry
            |> filterWhere (#venueId, unpackId currentVenueId)
            |> fetchCount
    leaveRequestCount <-
        query @LeaveRequest
            |> filterWhere (#venueId, unpackId currentVenueId)
            |> fetchCount
    exportJobCount <-
        query @ExportJob
            |> filterWhere (#venueId, unpackId currentVenueId)
            |> fetchCount
    paySnapshotCount <-
        query @PayConfigSnapshot
            |> filterWhere (#venueId, unpackId currentVenueId)
        |> fetchCount
    pure (any (> 0) [rosterWeekCount, timesheetEntryCount, leaveRequestCount, exportJobCount, paySnapshotCount])

parseRequiredName :: (?context :: ControllerContext, ?request :: Request) => ByteString -> Text -> IO (Maybe Text)
parseRequiredName paramName errorMessage =
    let value = Text.strip (paramOrDefault "" paramName)
     in if Text.null value
            then do
                setErrorMessage errorMessage
                pure Nothing
            else pure (Just value)

parseRequiredEmail :: (?context :: ControllerContext, ?request :: Request) => ByteString -> Text -> IO (Maybe Text)
parseRequiredEmail paramName emptyMessage =
    case Text.strip (paramOrDefault "" paramName) of
        value | Text.null value -> do
            setErrorMessage emptyMessage
            pure Nothing
        value ->
            case isEmail value of
                Success -> pure (Just value)
                Failure _ -> do
                    setErrorMessage "Enter a valid email address."
                    pure Nothing
                FailureHtml _ -> do
                    setErrorMessage "Enter a valid email address."
                    pure Nothing

parseIsActiveParam :: (?context :: ControllerContext, ?request :: Request) => Bool
parseIsActiveParam = paramOrDefault "true" "isActive" == ("true" :: Text)

parseShowInactiveParam :: (?context :: ControllerContext, ?request :: Request) => ByteString -> Bool
parseShowInactiveParam paramName = paramOrDefault "false" paramName == ("true" :: Text)

parseSubmittedOverrideAwardLevelId ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    IO (Maybe (Maybe (Id AwardLevel)))
parseSubmittedOverrideAwardLevelId =
    case paramOrNothing @(Id AwardLevel) "overrideAwardLevelId" of
        Nothing -> pure (Just Nothing)
        Just awardLevelId -> do
            maybeAwardLevel <-
                query @AwardLevel
                    |> filterWhere (#id, awardLevelId)
                    |> filterWhere (#isActive, True)
                    |> fetchOneOrNothing
            case maybeAwardLevel of
                Just _ -> pure (Just (Just awardLevelId))
                Nothing -> do
                    setErrorMessage "Choose a synced award level, or leave the shift type using the staff default."
                    pure Nothing

parseRosterWeekStartsOn ::
    (?context :: ControllerContext, ?request :: Request) =>
    IO (Maybe Int)
parseRosterWeekStartsOn =
    case paramOrNothing @Int "rosterWeekStartsOn" of
        Nothing -> do
            setErrorMessage "Choose the first day of the roster week."
            pure Nothing
        Just weekdayIndex
            | weekdayIndex `elem` validRosterWeekStartDays -> pure (Just weekdayIndex)
            | otherwise -> do
                setErrorMessage "Choose a valid first day of the roster week."
                pure Nothing

venueRoleLabel :: VenueRole -> Text
venueRoleLabel WorkerRole     = "Worker"
venueRoleLabel ManagerRole'   = "Manager"
venueRoleLabel VenueAdminRole = "Venue Admin"
venueRoleLabel VenueOwnerRole = "Venue Owner"

parseShiftTypeId ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Text ->
    IO (Maybe (Id ShiftType))
parseShiftTypeId errorMessage =
    case paramOrNothing @(Id ShiftType) "shiftTypeId" of
        Nothing -> do
            setErrorMessage errorMessage
            pure Nothing
        Just shiftTypeId -> do
            maybeShiftType <-
                query @ShiftType
                    |> filterWhere (#venueId, unpackId currentVenueId)
                    |> filterWhere (#id, shiftTypeId)
                    |> fetchOneOrNothing
            case maybeShiftType of
                Nothing -> do
                    setErrorMessage errorMessage
                    pure Nothing
                Just _ ->
                    pure (Just shiftTypeId)

parseDayNameId ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Text ->
    IO (Maybe (Id DayName))
parseDayNameId errorMessage =
    case paramOrNothing @(Id DayName) "dayNameId" of
        Nothing -> do
            setErrorMessage errorMessage
            pure Nothing
        Just dayNameId -> do
            maybeDayName <-
                query @DayName
                    |> filterWhere (#venueId, unpackId currentVenueId)
                    |> filterWhere (#id, dayNameId)
                    |> fetchOneOrNothing
            case maybeDayName of
                Nothing -> do
                    setErrorMessage errorMessage
                    pure Nothing
                Just _ ->
                    pure (Just dayNameId)

redirectToAdminFor :: (?context :: ControllerContext, ?request :: Request) => Maybe (Id RosterGroup) -> IO ()
redirectToAdminFor maybeRosterGroupId =
    redirectToPath $
        maybe
            (pathTo AdminAction)
            (\rosterGroupId -> pathTo AdminAction <> "?rosterGroupId=" <> tshow rosterGroupId)
            maybeRosterGroupId

findReportDefinitionByEngine :: ReportDefinitionEngine -> [VenueReportDefinition] -> Maybe VenueReportDefinition
findReportDefinitionByEngine engine reportDefinitions =
    List.find (\reportDefinition -> reportDefinition.engine == engine) reportDefinitions
