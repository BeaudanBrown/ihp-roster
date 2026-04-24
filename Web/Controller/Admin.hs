module Web.Controller.Admin where

import Application.Helper.Export
import Application.Helper.LiveUpdate
import Application.Helper.Pay
import Application.Helper.RosterGroups
import Application.Helper.VenueInvitation
import Application.Helper.WeekBoundaries
    ( defaultWeekOffsetEpochForStartDay, validRosterWeekStartDays,
      weekdayIndexLabel )
import Control.Concurrent (forkIO)
import Control.Monad (void)
import qualified Data.List as List
import Data.Scientific (Scientific)
import qualified Data.Text as Text
import Web.Controller.Prelude
import Web.View.Admin.Index

instance Controller AdminController where
    beforeAction = do
        ensureIsUser
        ensureCurrentVenue
        ensureProfileCompleted
        ensureAdminRole

    action AdminAction = do
        venueConfig <- fetchVenueConfig
        recentSnapshots <- fetchCurrentVenuePayConfigSnapshots
        rosterGroups <- fetchCurrentVenueRosterGroups
        currentRosterGroup <- fetchCurrentVenueRosterGroupOrDefault (paramOrNothing "rosterGroupId")
        payLevels <- fetchCurrentVenuePayLevels
        payLevelDayRules <- fetchCurrentVenuePayLevelDayRules
        shiftTypes <- fetchCurrentVenueShiftTypes
        slotNames <- fetchActiveRosterGroupSlotNames currentRosterGroup.id
        weekdays <- fetchCurrentVenueDayNames
        activeReportDefinitions <- fetchCurrentVenueReportDefinitions
        currentWeekOffset <- currentReportWeekOffset
        reportWeekSelection <- fetchReportWeekSelection currentWeekOffset
        let staffPayReportDefinition = findReportDefinitionByEngine StaffPayCsvReport activeReportDefinitions
        let hourlyBreakdownReportDefinition = findReportDefinitionByEngine HourlyBreakdownZipReport activeReportDefinitions
        let latestSnapshot = listToMaybe recentSnapshots
        invitations <- fetchCurrentVenueInvitations
        venueRosterWeekStartLocked <- isVenueRosterWeekStartLocked
        let slotNamesLiveUpdateScope = Just (adminSlotNamesScope currentRosterGroup.id)
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
        respondHtml (renderSlotNamesSectionFragment currentRosterGroup slotNames)

    action ShowAdminInvitesFragmentAction = do
        currentRosterGroup <- fetchCurrentVenueRosterGroupOrDefault (paramOrNothing "rosterGroupId")
        invitations <- fetchCurrentVenueInvitations
        respondHtml (renderInvitesSectionFragment invitations currentRosterGroup.id)

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
            Nothing -> redirectToAdminFor Nothing
            Just name -> do
                let isActive = parseIsActiveParam
                let sortOrder = parseSortOrderParam
                rosterGroup <- createVenueRosterGroupWithDefaults venue name sortOrder isActive
                setSuccessMessage "Roster group added"
                redirectToAdminFor (Just rosterGroup.id)

    action UpdateRosterGroupAction { rosterGroupId } = do
        venue <- fetch currentVenueId
        rosterGroup <- fetch rosterGroupId
        ensureRecordInCurrentVenue rosterGroup.venueId
        maybeName <- parseRequiredName "name" "Roster group name is required."
        case maybeName of
            Nothing -> redirectToAdminFor (Just rosterGroup.id)
            Just name -> do
                let isActive = parseIsActiveParam
                let sortOrder = parseSortOrderParam
                rosterGroups <- fetchCurrentVenueRosterGroups
                let otherActiveGroups = filter (\group -> group.id /= rosterGroup.id && group.isActive) rosterGroups
                if not isActive && null otherActiveGroups
                    then do
                        setErrorMessage "Each venue needs at least one active roster group."
                        redirectToAdminFor (Just rosterGroup.id)
                    else do
                        updatedRosterGroup <-
                            rosterGroup
                                |> set #name name
                                |> set #sortOrder sortOrder
                                |> set #isActive isActive
                                |> updateRecord
                        when isActive do
                            _ <- ensureDefaultRosterSlots venue updatedRosterGroup
                            pure ()
                        when (rosterGroup.isDefault && not isActive) do
                            case listToMaybe otherActiveGroups of
                                Nothing -> pure ()
                                Just fallbackGroup -> do
                                    _ <- setVenueDefaultRosterGroup currentVenueId fallbackGroup.id
                                    pure ()
                        setSuccessMessage "Roster group updated"
                        redirectToAdminFor (Just updatedRosterGroup.id)

    action MakeDefaultRosterGroupAction { rosterGroupId } = do
        rosterGroup <- fetch rosterGroupId
        ensureRecordInCurrentVenue rosterGroup.venueId
        if not rosterGroup.isActive
            then do
                setErrorMessage "Only active roster groups can be the default."
                redirectToAdminFor (Just rosterGroup.id)
            else do
                _ <- setVenueDefaultRosterGroup currentVenueId rosterGroup.id
                setSuccessMessage "Default roster group updated"
                redirectToAdminFor (Just rosterGroup.id)

    action CreatePayLevelAction = do
        maybeName <- parseRequiredName "name" "Pay level name is required."
        case maybeName of
            Nothing -> redirectToAdminFor (paramOrNothing "rosterGroupId")
            Just name -> do
                let isActive = parseIsActiveParam
                let (baseRate, eveningPenalty, after12Penalty, weekdayMultiplier, saturdayMultiplier, sundayMultiplier) = parsePayLevelRateParams
                _ <- withTransaction do
                    payLevel <-
                        newRecord @PayLevel
                            |> set #venueId (unpackId currentVenueId)
                            |> set #name name
                            |> set #baseRate baseRate
                            |> set #eveningPenalty eveningPenalty
                            |> set #after12Penalty after12Penalty
                            |> set #weekdayMultiplier weekdayMultiplier
                            |> set #saturdayMultiplier saturdayMultiplier
                            |> set #sundayMultiplier sundayMultiplier
                            |> set #isActive isActive
                            |> createRecord
                    _ <- syncCurrentVenuePayConfigSnapshot
                    pure payLevel
                setSuccessMessage "Pay level added"
                redirectToAdminFor (paramOrNothing "rosterGroupId")

    action UpdatePayLevelAction { payLevelId } = do
        payLevel <- fetch payLevelId
        ensureRecordInCurrentVenue payLevel.venueId
        maybeName <- parseRequiredName "name" "Pay level name is required."
        case maybeName of
            Nothing -> redirectToAdminFor (paramOrNothing "rosterGroupId")
            Just name -> do
                let isActive = parseIsActiveParam
                let (baseRate, eveningPenalty, after12Penalty, weekdayMultiplier, saturdayMultiplier, sundayMultiplier) = parsePayLevelRateParams
                _ <- withTransaction do
                    updatedPayLevel <-
                        payLevel
                            |> set #name name
                            |> set #baseRate baseRate
                            |> set #eveningPenalty eveningPenalty
                            |> set #after12Penalty after12Penalty
                            |> set #weekdayMultiplier weekdayMultiplier
                            |> set #saturdayMultiplier saturdayMultiplier
                            |> set #sundayMultiplier sundayMultiplier
                            |> set #isActive isActive
                            |> updateRecord
                    _ <- syncCurrentVenuePayConfigSnapshot
                    pure updatedPayLevel
                setSuccessMessage "Pay level updated"
                redirectToAdminFor (paramOrNothing "rosterGroupId")

    action CreatePayLevelDayRuleAction = do
        maybeRuleParams <- parsePayLevelDayRuleParams Nothing
        case maybeRuleParams of
            Nothing -> redirectToAdminFor (paramOrNothing "rosterGroupId")
            Just (shiftTypeId, dayNameId, payLevelId) -> do
                _ <- withTransaction do
                    payLevelDayRule <-
                        newRecord @PayLevelDayRule
                            |> set #shiftTypeId (unpackId shiftTypeId)
                            |> set #dayNameId (unpackId dayNameId)
                            |> set #payLevelId (unpackId payLevelId)
                            |> createRecord
                    _ <- syncCurrentVenuePayConfigSnapshot
                    pure payLevelDayRule
                setSuccessMessage "Pay override added"
                redirectToAdminFor (paramOrNothing "rosterGroupId")

    action UpdatePayLevelDayRuleAction { payLevelDayRuleId } = do
        payLevelDayRule <- fetch payLevelDayRuleId
        ensurePayLevelDayRuleInCurrentVenue payLevelDayRule
        maybeRuleParams <- parsePayLevelDayRuleParams (Just payLevelDayRule)
        case maybeRuleParams of
            Nothing -> redirectToAdminFor (paramOrNothing "rosterGroupId")
            Just (shiftTypeId, dayNameId, payLevelId) -> do
                _ <- withTransaction do
                    updatedRule <-
                        payLevelDayRule
                            |> set #shiftTypeId (unpackId shiftTypeId)
                            |> set #dayNameId (unpackId dayNameId)
                            |> set #payLevelId (unpackId payLevelId)
                            |> updateRecord
                    _ <- syncCurrentVenuePayConfigSnapshot
                    pure updatedRule
                setSuccessMessage "Pay override updated"
                redirectToAdminFor (paramOrNothing "rosterGroupId")

    action CreateShiftTypeAction = do
        payLevels <- fetchCurrentVenuePayLevels
        if null payLevels
            then do
                setErrorMessage "Add at least one pay level before creating a shift type."
                redirectToAdminFor (paramOrNothing "rosterGroupId")
            else do
                maybeName <- parseRequiredName "name" "Shift type name is required."
                case maybeName of
                    Nothing -> redirectToAdminFor (paramOrNothing "rosterGroupId")
                    Just name -> do
                        let isActive = parseIsActiveParam
                        let sortOrder = parseSortOrderParam
                        maybePayLevel <- parseDefaultPayLevelId
                        case maybePayLevel of
                            Nothing -> redirectToAdminFor (paramOrNothing "rosterGroupId")
                            Just defaultPayLevelId -> do
                                _ <- withTransaction do
                                    shiftType <-
                                        newRecord @ShiftType
                                            |> set #venueId (unpackId currentVenueId)
                                            |> set #name name
                                            |> set #sortOrder sortOrder
                                            |> set #defaultPayLevelId (unpackId defaultPayLevelId)
                                            |> set #isActive isActive
                                            |> createRecord
                                    _ <- syncCurrentVenuePayConfigSnapshot
                                    pure shiftType
                                setSuccessMessage "Shift type added"
                                redirectToAdminFor (paramOrNothing "rosterGroupId")

    action UpdateShiftTypeAction { shiftTypeId } = do
        shiftType <- fetch shiftTypeId
        ensureRecordInCurrentVenue shiftType.venueId
        maybeName <- parseRequiredName "name" "Shift type name is required."
        case maybeName of
            Nothing -> redirectToAdminFor (paramOrNothing "rosterGroupId")
            Just name -> do
                let isActive = parseIsActiveParam
                let sortOrder = parseSortOrderParam
                maybePayLevel <- parseDefaultPayLevelId
                case maybePayLevel of
                    Nothing -> redirectToAdminFor (paramOrNothing "rosterGroupId")
                    Just defaultPayLevelId -> do
                        _ <- withTransaction do
                            updatedShiftType <-
                                shiftType
                                    |> set #name name
                                    |> set #sortOrder sortOrder
                                    |> set #defaultPayLevelId (unpackId defaultPayLevelId)
                                    |> set #isActive isActive
                                    |> updateRecord
                            _ <- syncCurrentVenuePayConfigSnapshot
                            pure updatedShiftType
                        setSuccessMessage "Shift type updated"
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

fetchCurrentVenuePayLevels :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO [PayLevel]
fetchCurrentVenuePayLevels =
    query @PayLevel
        |> filterWhere (#venueId, unpackId currentVenueId)
        |> orderByAsc #createdAt
        |> fetch

fetchCurrentVenueShiftTypes :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO [ShiftType]
fetchCurrentVenueShiftTypes =
    query @ShiftType
        |> filterWhere (#venueId, unpackId currentVenueId)
        |> orderByAsc #sortOrder
        |> orderByAsc #createdAt
        |> fetch

fetchCurrentVenuePayLevelDayRules :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO [PayLevelDayRule]
fetchCurrentVenuePayLevelDayRules = do
    shiftTypes <- fetchCurrentVenueShiftTypes
    let shiftTypeIds = map (unpackId . get #id) shiftTypes
    if null shiftTypeIds
        then pure []
        else
            query @PayLevelDayRule
                |> filterWhereIn (#shiftTypeId, shiftTypeIds)
                |> orderByAsc #createdAt
                |> fetch

nextSlotNameSortOrder :: (?modelContext :: ModelContext) => Id RosterGroup -> IO Int
nextSlotNameSortOrder rosterGroupId =
    query @SlotName
        |> filterWhere (#rosterGroupId, unpackId rosterGroupId)
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
            respondHtml (renderSlotNamesSectionFragment currentRosterGroup slotNames)
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

broadcastSlotNameInvalidation ::
    (?context :: ControllerContext, ?request :: Request) =>
    Id RosterGroup ->
    IO ()
broadcastSlotNameInvalidation rosterGroupId =
    broadcastLiveInvalidation
        (slotNamesScope rosterGroupId)
        (cs <$> getHeader "X-Live-Update-Client-Id")
        []

broadcastAdminSlotNamesInvalidation ::
    (?context :: ControllerContext, ?request :: Request) =>
    Id RosterGroup ->
    IO ()
broadcastAdminSlotNamesInvalidation rosterGroupId =
    broadcastLiveInvalidation
        (adminSlotNamesScope rosterGroupId)
        (cs <$> getHeader "X-Live-Update-Client-Id")
        []

broadcastAdminInvitesInvalidation ::
    (?context :: ControllerContext, ?request :: Request) =>
    Id Venue ->
    IO ()
broadcastAdminInvitesInvalidation venueId =
    broadcastLiveInvalidation
        (adminInvitesScope venueId)
        (cs <$> getHeader "X-Live-Update-Client-Id")
        []

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

parseSortOrderParam :: (?context :: ControllerContext, ?request :: Request) => Int
parseSortOrderParam = paramOrDefault @Int 0 "sortOrder"

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

parsePayLevelRateParams ::
    (?context :: ControllerContext, ?request :: Request) =>
    (Scientific, Scientific, Scientific, Scientific, Scientific, Scientific)
parsePayLevelRateParams =
    ( paramOrDefault @Scientific 0 "baseRate"
    , paramOrDefault @Scientific 0 "eveningPenalty"
    , paramOrDefault @Scientific 0 "after12Penalty"
    , paramOrDefault @Scientific 1 "weekdayMultiplier"
    , paramOrDefault @Scientific 1 "saturdayMultiplier"
    , paramOrDefault @Scientific 1 "sundayMultiplier"
    )

parseDefaultPayLevelId :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => IO (Maybe (Id PayLevel))
parseDefaultPayLevelId =
    case paramOrNothing @(Id PayLevel) "defaultPayLevelId" of
        Nothing -> do
            setErrorMessage "Choose a default pay level."
            pure Nothing
        Just payLevelId -> do
            maybePayLevel <-
                query @PayLevel
                    |> filterWhere (#venueId, unpackId currentVenueId)
                    |> filterWhere (#id, payLevelId)
                    |> fetchOneOrNothing
            case maybePayLevel of
                Nothing -> do
                    setErrorMessage "Choose a default pay level from the current venue."
                    pure Nothing
                Just _ ->
                    pure (Just payLevelId)

parsePayLevelDayRuleParams ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Maybe PayLevelDayRule ->
    IO (Maybe (Id ShiftType, Id DayName, Id PayLevel))
parsePayLevelDayRuleParams existingRule = do
    maybeShiftTypeId <- parseShiftTypeId "Choose a shift type from the current venue."
    case maybeShiftTypeId of
        Nothing -> pure Nothing
        Just shiftTypeId -> do
            maybeDayNameId <- parseDayNameId "Choose a day name from the current venue."
            case maybeDayNameId of
                Nothing -> pure Nothing
                Just dayNameId -> do
                    maybePayLevelId <- parsePayLevelId "Choose a pay level from the current venue."
                    case maybePayLevelId of
                        Nothing -> pure Nothing
                        Just payLevelId -> do
                            payLevelDayRules <- fetchCurrentVenuePayLevelDayRules
                            let conflicts =
                                    any
                                        (\rule ->
                                            rule.shiftTypeId == unpackId shiftTypeId
                                                && rule.dayNameId == unpackId dayNameId
                                                && maybe True (\existing -> get #id existing /= get #id rule) existingRule
                                        )
                                        payLevelDayRules
                            if conflicts
                                then do
                                    setErrorMessage "That shift type already has an override for the selected weekday."
                                    pure Nothing
                                else pure (Just (shiftTypeId, dayNameId, payLevelId))

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

parsePayLevelId ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Text ->
    IO (Maybe (Id PayLevel))
parsePayLevelId errorMessage =
    case paramOrNothing @(Id PayLevel) "payLevelId" of
        Nothing -> do
            setErrorMessage errorMessage
            pure Nothing
        Just payLevelId -> do
            maybePayLevel <-
                query @PayLevel
                    |> filterWhere (#venueId, unpackId currentVenueId)
                    |> filterWhere (#id, payLevelId)
                    |> fetchOneOrNothing
            case maybePayLevel of
                Nothing -> do
                    setErrorMessage errorMessage
                    pure Nothing
                Just _ ->
                    pure (Just payLevelId)

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

ensurePayLevelDayRuleInCurrentVenue ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    PayLevelDayRule ->
    IO ()
ensurePayLevelDayRuleInCurrentVenue payLevelDayRule = do
    shiftType <- fetch (Id payLevelDayRule.shiftTypeId :: Id ShiftType)
    payLevel <- fetch (Id payLevelDayRule.payLevelId :: Id PayLevel)
    dayName <- fetch (Id payLevelDayRule.dayNameId :: Id DayName)
    ensureRecordInCurrentVenue shiftType.venueId
    ensureRecordInCurrentVenue payLevel.venueId
    ensureRecordInCurrentVenue dayName.venueId

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
