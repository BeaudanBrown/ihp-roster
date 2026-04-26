module Web.Controller.Admin where

import Application.Helper.Export
import Application.Helper.LiveUpdate
import Application.Helper.Pay
import Application.Helper.RosterGroups
import Application.Helper.VenueInvitation
import Application.Helper.WeekBoundaries (defaultWeekOffsetEpochForStartDay,
                                          validRosterWeekStartDays,
                                          weekdayIndexLabel)
import Control.Concurrent (forkIO)
import Control.Monad (void)
import qualified Data.List as List
import qualified Data.Text as Text
import Web.Controller.Prelude
import Web.View.Admin.Index

instance Controller AdminController where
    beforeAction = do
        ensureIsUser
        ensureCurrentVenueOrSupportRedirect
        ensureProfileCompleted
        ensureAdminRole

    action AdminAction = do
        syncVenueDefaultRosterGroupToTopActive currentVenueId
        rosterGroups <- fetchCurrentVenueRosterGroups
        currentRosterGroup <- fetchCurrentVenueRosterGroupOrDefault (paramOrNothing "rosterGroupId")
        shiftTypes <- fetchCurrentVenueShiftTypes
        awardLevels <- fetchActiveAwardLevels
        awardLevelBaseRates <- fetchCurrentAwardLevelBaseRates
        slotNames <- fetchActiveCurrentVenueSlotNames
        activeReportDefinitions <- fetchCurrentVenueReportDefinitions
        currentWeekOffset <- currentReportWeekOffset
        reportWeekSelection <- fetchReportWeekSelection currentWeekOffset
        let staffPayReportDefinition = findReportDefinitionByEngine StaffPayCsvReport activeReportDefinitions
        let hourlyBreakdownReportDefinition = findReportDefinitionByEngine HourlyBreakdownZipReport activeReportDefinitions
        let payrollEarningsReportDefinition = findReportDefinitionByEngine PayrollEarningsCsvReport activeReportDefinitions
        let showInactiveRosterGroups = parseShowInactiveParam "showInactiveRosterGroups"
        let showInactiveShiftTypes = parseShowInactiveParam "showInactiveShiftTypes"
        invitations <- fetchCurrentVenueInvitations
        let invitesLiveUpdateScope = Just (adminInvitesScope currentVenueId)
        render IndexView { .. }

    action UpdateVenueConfigAction = do
        venueConfig <- fetchVenueConfig
        requestedRosterWeekStartsOn <- parseRosterWeekStartsOn
        case requestedRosterWeekStartsOn of
            Nothing -> redirectToAdminFor (paramOrNothing "rosterGroupId")
            Just rosterWeekStartsOn -> do
                isLocked <- isVenueRosterWeekStartLocked
                if isLocked
                    then do
                        setErrorMessage "Roster week start can only be configured before roster, timesheet, leave, export, or payroll snapshot data exists."
                        redirectToAdminFor (paramOrNothing "rosterGroupId")
                    else do
                        _ <- withTransaction do
                            updatedVenueConfig <-
                                venueConfig
                                    |> set #rosterWeekStartsOn rosterWeekStartsOn
                                    |> set #weekOffsetEpoch (defaultWeekOffsetEpochForStartDay rosterWeekStartsOn)
                                    |> updateRecord
                            _ <- syncCurrentVenuePayConfigSnapshot
                            pure updatedVenueConfig
                        setSuccessMessage ("Roster week will start on " <> weekdayIndexLabel rosterWeekStartsOn)
                        redirectToAdminFor (paramOrNothing "rosterGroupId")

    action ShowAdminSlotNamesFragmentAction = do
        currentRosterGroup <- fetchCurrentVenueRosterGroupOrDefault (paramOrNothing "rosterGroupId")
        slotNames <- fetchActiveRosterGroupSlotNames currentRosterGroup.id
        respondHtml (renderRosterGroupSlotNamesFragment currentRosterGroup slotNames)

    action ShowAdminInvitesFragmentAction = do
        currentRosterGroup <- fetchCurrentVenueRosterGroupOrDefault (paramOrNothing "rosterGroupId")
        invitations <- fetchCurrentVenueInvitations
        respondHtml (renderInvitesSectionFragment invitations currentRosterGroup.id)

    action ShowAdminShiftTypesFragmentAction = do
        shiftTypes <- fetchCurrentVenueShiftTypes
        awardLevels <- fetchActiveAwardLevels
        awardLevelBaseRates <- fetchCurrentAwardLevelBaseRates
        let showInactiveShiftTypes = parseShowInactiveParam "showInactiveShiftTypes"
        respondHtml (renderShiftTypesSectionFragment shiftTypes showInactiveShiftTypes awardLevels awardLevelBaseRates)

    action ShowAdminRosterGroupsFragmentAction = do
        syncVenueDefaultRosterGroupToTopActive currentVenueId
        rosterGroups <- fetchCurrentVenueRosterGroups
        slotNames <- fetchActiveCurrentVenueSlotNames
        let showInactiveRosterGroups = parseShowInactiveParam "showInactiveRosterGroups"
        respondHtml (renderRosterGroupsSectionFragment rosterGroups slotNames showInactiveRosterGroups)

    action CreateVenueInvitationAction = do
        currentRosterGroup <- fetchCurrentVenueRosterGroupOrDefault (paramOrNothing "rosterGroupId")
        maybeEmail <- parseRequiredEmail "email" "Invite email is required."
        case maybeEmail of
            Just email -> do
                now <- getCurrentTime
                invitation <- newRecord @VenueInvitation
                    |> set #venueId (unpackId currentVenueId)
                    |> set #invitedByUserId (Just (unpackId currentUser.id))
                    |> set #email email
                    |> set #inviteRole (venueRoleToEnum WorkerRole)
                    |> set #status (unsafeEnumFromText @InvitationStatusEnum "pending")
                    |> set #deliveryStatus (unsafeEnumFromText @InvitationDeliveryStatusEnum "queued")
                    |> set #expiresAt (Just (addUTCTime venueInvitationLifetime now))
                    |> createRecord
                broadcastAdminInvitesInvalidation currentVenueId
                if isHtmxRequest
                    then do
                        invitations <- fetchCurrentVenueInvitations
                        queueVenueInvitationDelivery invitation
                        setSuccessMessage ("Invitation queued for " <> email)
                        respondHtml (renderInvitesSectionFragment invitations currentRosterGroup.id)
                    else do
                        queueVenueInvitationDelivery invitation
                        respondToInvitesSectionMutation ("Invitation queued for " <> email) currentRosterGroup.id
            _ ->
                respondToInvitesSectionMutation "" currentRosterGroup.id

    action RevokeVenueInvitationAction { venueInvitationId } = do
        currentRosterGroup <- fetchCurrentVenueRosterGroupOrDefault (paramOrNothing "rosterGroupId")
        invitation <- fetch venueInvitationId
        ensureRecordInCurrentVenue invitation.venueId
        if invitation.status /= unsafeEnumFromText @InvitationStatusEnum "pending"
            then respondToInvitesSectionMutation "Only pending invitations can be revoked." currentRosterGroup.id
            else do
                _ <- invitation
                    |> set #status (unsafeEnumFromText @InvitationStatusEnum "revoked")
                    |> updateRecord
                broadcastAdminInvitesInvalidation currentVenueId
                respondToInvitesSectionMutation "Invitation revoked." currentRosterGroup.id

    action CreateRosterGroupAction = do
        venue <- fetch currentVenueId
        maybeName <- parseRequiredName "name" "Roster group name is required."
        case maybeName of
            Nothing -> respondToRosterGroupsSectionMutation Nothing
            Just name -> do
                let isActive = parseIsActiveParam
                sortOrder <- nextRosterGroupSortOrder
                rosterGroup <- createVenueRosterGroupWithDefaults venue name sortOrder isActive
                syncVenueDefaultRosterGroupToTopActive currentVenueId
                setSuccessMessage "Roster group added"
                broadcastAdminRosterGroupsInvalidation currentVenueId
                respondToRosterGroupsSectionMutation (Just rosterGroup.id)

    action UpdateRosterGroupAction { rosterGroupId } = do
        venue <- fetch currentVenueId
        rosterGroup <- fetch rosterGroupId
        ensureRecordInCurrentVenue rosterGroup.venueId
        maybeName <- parseRequiredName "name" "Roster group name is required."
        case maybeName of
            Nothing -> respondToRosterGroupsSectionMutation (Just rosterGroup.id)
            Just name -> do
                let isActive = parseIsActiveParam
                rosterGroups <- fetchCurrentVenueRosterGroups
                let otherActiveGroups = filter (\group -> group.id /= rosterGroup.id && group.isActive) rosterGroups
                if not isActive && null otherActiveGroups
                    then do
                        setErrorMessage "Each venue needs at least one active roster group."
                        respondToRosterGroupsSectionMutation (Just rosterGroup.id)
                    else do
                        sortOrder <-
                            if not rosterGroup.isActive && isActive
                                then nextRosterGroupSortOrder
                                else pure rosterGroup.sortOrder
                        updatedRosterGroup <-
                            rosterGroup
                                |> set #name name
                                |> set #sortOrder sortOrder
                                |> set #isActive isActive
                                |> updateRecord
                        when isActive do
                            _ <- ensureDefaultRosterSlots venue updatedRosterGroup
                            pure ()
                        syncVenueDefaultRosterGroupToTopActive currentVenueId
                        setSuccessMessage "Roster group updated"
                        broadcastAdminRosterGroupsInvalidation currentVenueId
                        respondToRosterGroupsSectionMutation (Just updatedRosterGroup.id)

    action MoveRosterGroupUpAction { rosterGroupId } = do
        rosterGroup <- fetch rosterGroupId
        ensureRecordInCurrentVenue rosterGroup.venueId
        withTransaction do
            reorderActiveRosterGroups rosterGroup.id (-1)
            syncVenueDefaultRosterGroupToTopActive currentVenueId
        setSuccessMessage "Roster group order updated"
        broadcastAdminRosterGroupsInvalidation currentVenueId
        redirectToAdminFor (Just rosterGroup.id)

    action MoveRosterGroupDownAction { rosterGroupId } = do
        rosterGroup <- fetch rosterGroupId
        ensureRecordInCurrentVenue rosterGroup.venueId
        withTransaction do
            reorderActiveRosterGroups rosterGroup.id 1
            syncVenueDefaultRosterGroupToTopActive currentVenueId
        setSuccessMessage "Roster group order updated"
        broadcastAdminRosterGroupsInvalidation currentVenueId
        redirectToAdminFor (Just rosterGroup.id)

    action CreateShiftTypeAction = do
        maybeName <- parseRequiredName "name" "Shift type name is required."
        case maybeName of
            Nothing -> respondToShiftTypesSectionMutation
            Just name -> do
                let isActive = parseIsActiveParam
                sortOrder <- nextShiftTypeSortOrder
                maybeOverrideAwardLevelId <- parseSubmittedOverrideAwardLevelId
                case maybeOverrideAwardLevelId of
                    Nothing -> respondToShiftTypesSectionMutation
                    Just overrideAwardLevelId -> do
                        _ <- withTransaction do
                            shiftType <-
                                newRecord @ShiftType
                                    |> set #venueId (unpackId currentVenueId)
                                    |> set #name name
                                    |> set #sortOrder sortOrder
                                    |> set #overrideAwardLevelId overrideAwardLevelId
                                    |> set #isActive isActive
                                    |> createRecord
                            _ <- syncCurrentVenuePayConfigSnapshot
                            pure shiftType
                        setSuccessMessage "Shift type added"
                        broadcastAdminShiftTypesInvalidation currentVenueId
                        respondToShiftTypesSectionMutation

    action UpdateShiftTypeAction { shiftTypeId } = do
        shiftType <- fetch shiftTypeId
        ensureRecordInCurrentVenue shiftType.venueId
        maybeName <- parseRequiredName "name" "Shift type name is required."
        case maybeName of
            Nothing -> respondToShiftTypesSectionMutation
            Just name -> do
                let isActive = parseIsActiveParam
                maybeOverrideAwardLevelId <- parseSubmittedOverrideAwardLevelId
                case maybeOverrideAwardLevelId of
                    Nothing -> respondToShiftTypesSectionMutation
                    Just overrideAwardLevelId -> do
                        sortOrder <-
                            if not shiftType.isActive && isActive
                                then nextShiftTypeSortOrder
                                else pure shiftType.sortOrder
                        _ <- withTransaction do
                            updatedShiftType <-
                                shiftType
                                    |> set #name name
                                    |> set #sortOrder sortOrder
                                    |> set #overrideAwardLevelId overrideAwardLevelId
                                    |> set #isActive isActive
                                    |> updateRecord
                            _ <- syncCurrentVenuePayConfigSnapshot
                            pure updatedShiftType
                        setSuccessMessage "Shift type updated"
                        broadcastAdminShiftTypesInvalidation currentVenueId
                        respondToShiftTypesSectionMutation

    action MoveShiftTypeUpAction { shiftTypeId } = do
        shiftType <- fetch shiftTypeId
        ensureRecordInCurrentVenue shiftType.venueId
        withTransaction do
            reorderActiveShiftTypes shiftType.id (-1)
            _ <- syncCurrentVenuePayConfigSnapshot
            pure ()
        setSuccessMessage "Shift type order updated"
        broadcastAdminShiftTypesInvalidation currentVenueId
        redirectToAdminFor (paramOrNothing "rosterGroupId")

    action MoveShiftTypeDownAction { shiftTypeId } = do
        shiftType <- fetch shiftTypeId
        ensureRecordInCurrentVenue shiftType.venueId
        withTransaction do
            reorderActiveShiftTypes shiftType.id 1
            _ <- syncCurrentVenuePayConfigSnapshot
            pure ()
        setSuccessMessage "Shift type order updated"
        broadcastAdminShiftTypesInvalidation currentVenueId
        redirectToAdminFor (paramOrNothing "rosterGroupId")

    action CreateSlotNameAction = do
        maybeName <- parseRequiredName "name" "Slot name is required."
        case maybeName of
            Nothing -> redirectToAdminFor (paramOrNothing "rosterGroupId")
            Just name -> do
                rosterGroup <- fetchCurrentVenueRosterGroupOrDefault (paramOrNothing "rosterGroupId")
                _ <- do
                    nextSortOrder <- nextSlotNameSortOrder rosterGroup.id
                    newRecord @SlotName
                        |> set #venueId (unpackId currentVenueId)
                        |> set #rosterGroupId (unpackId rosterGroup.id)
                        |> set #name name
                        |> set #sortOrder nextSortOrder
                        |> set #isActive True
                        |> createRecord
                broadcastAdminSlotNamesInvalidation rosterGroup.id
                respondToSlotNameSectionMutation "Slot name added" rosterGroup.id

    action UpdateSlotNameAction { slotNameId } = do
        slotName <- fetch slotNameId
        ensureRecordInCurrentVenue slotName.venueId
        maybeName <- parseRequiredName "name" "Slot name is required."
        case maybeName of
            Nothing -> redirectToAdminFor (Just (Id slotName.rosterGroupId :: Id RosterGroup))
            Just name -> do
                _ <- slotName
                    |> set #name name
                    |> updateRecord
                broadcastAdminSlotNamesInvalidation (Id slotName.rosterGroupId :: Id RosterGroup)
                broadcastSlotNameInvalidation (Id slotName.rosterGroupId :: Id RosterGroup)
                respondToSlotNameMutation "Slot name updated" (Id slotName.rosterGroupId :: Id RosterGroup)

    action MoveSlotNameUpAction { slotNameId } = do
        slotName <- fetch slotNameId
        ensureRecordInCurrentVenue slotName.venueId
        let rosterGroupId = Id slotName.rosterGroupId :: Id RosterGroup
        withTransaction do
            reorderActiveSlotNames rosterGroupId slotName.id (-1)
        broadcastAdminSlotNamesInvalidation rosterGroupId
        respondToSlotNameSectionMutation "Slot order updated" rosterGroupId

    action MoveSlotNameDownAction { slotNameId } = do
        slotName <- fetch slotNameId
        ensureRecordInCurrentVenue slotName.venueId
        let rosterGroupId = Id slotName.rosterGroupId :: Id RosterGroup
        withTransaction do
            reorderActiveSlotNames rosterGroupId slotName.id 1
        broadcastAdminSlotNamesInvalidation rosterGroupId
        respondToSlotNameSectionMutation "Slot order updated" rosterGroupId

    action DeleteSlotNameAction { slotNameId } = do
        slotName <- fetch slotNameId
        ensureRecordInCurrentVenue slotName.venueId
        let rosterGroupId = Id slotName.rosterGroupId :: Id RosterGroup
        _ <- slotName
            |> set #isActive False
            |> updateRecord
        broadcastAdminSlotNamesInvalidation rosterGroupId
        respondToSlotNameSectionMutation "Slot deleted" rosterGroupId

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
