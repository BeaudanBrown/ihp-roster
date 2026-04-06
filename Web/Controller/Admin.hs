module Web.Controller.Admin where

import Application.Helper.Export
import Application.Helper.LiveUpdate
import Application.Helper.Pay
import Application.Helper.RosterGroups
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
        let slotNamesLiveUpdateScope = Just (slotNamesScope currentRosterGroup.id)
        render IndexView { .. }

    action ShowAdminSlotNamesFragmentAction = do
        currentRosterGroup <- fetchCurrentVenueRosterGroupOrDefault (paramOrNothing "rosterGroupId")
        slotNames <- fetchActiveRosterGroupSlotNames currentRosterGroup.id
        respondHtml (renderSlotNamesSectionFragment currentRosterGroup slotNames)

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
                nextSortOrder <- nextSlotNameSortOrder rosterGroup.id
                _ <- newRecord @SlotName
                    |> set #venueId (unpackId currentVenueId)
                    |> set #rosterGroupId (unpackId rosterGroup.id)
                    |> set #name name
                    |> set #sortOrder nextSortOrder
                    |> set #isActive True
                    |> createRecord
                broadcastSlotNameInvalidation rosterGroup.id
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
                broadcastSlotNameInvalidation (Id slotName.rosterGroupId :: Id RosterGroup)
                respondToSlotNameMutation "Slot name updated" (Id slotName.rosterGroupId :: Id RosterGroup)

    action MoveSlotNameUpAction { slotNameId } = do
        slotName <- fetch slotNameId
        ensureRecordInCurrentVenue slotName.venueId
        let rosterGroupId = Id slotName.rosterGroupId :: Id RosterGroup
        withTransaction do
            reorderActiveSlotNames rosterGroupId slotName.id (-1)
        broadcastSlotNameInvalidation rosterGroupId
        respondToSlotNameSectionMutation "Slot order updated" rosterGroupId

    action MoveSlotNameDownAction { slotNameId } = do
        slotName <- fetch slotNameId
        ensureRecordInCurrentVenue slotName.venueId
        let rosterGroupId = Id slotName.rosterGroupId :: Id RosterGroup
        withTransaction do
            reorderActiveSlotNames rosterGroupId slotName.id 1
        broadcastSlotNameInvalidation rosterGroupId
        respondToSlotNameSectionMutation "Slot order updated" rosterGroupId

    action DeleteSlotNameAction { slotNameId } = do
        slotName <- fetch slotNameId
        ensureRecordInCurrentVenue slotName.venueId
        let rosterGroupId = Id slotName.rosterGroupId :: Id RosterGroup
        _ <- slotName
            |> set #isActive False
            |> updateRecord
        broadcastSlotNameInvalidation rosterGroupId
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

respondToSlotNameMutation :: (?context :: ControllerContext) => Text -> Id RosterGroup -> IO ()
respondToSlotNameMutation successMessage rosterGroupId =
    if isHtmxRequest
        then renderPlain ""
        else do
            setSuccessMessage successMessage
            redirectToAdminFor (Just rosterGroupId)

respondToSlotNameSectionMutation ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
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

broadcastSlotNameInvalidation ::
    (?context :: ControllerContext) =>
    Id RosterGroup ->
    IO ()
broadcastSlotNameInvalidation rosterGroupId =
    broadcastLiveInvalidation
        (slotNamesScope rosterGroupId)
        (cs <$> getHeader "X-Live-Update-Client-Id")
        []

slotNamesScope :: (?context :: ControllerContext) => Id RosterGroup -> LiveUpdateScope
slotNamesScope rosterGroupId =
    RosterGroupConfigScope
        { venueId = unpackId currentVenueId
        , rosterGroupId = unpackId rosterGroupId
        }

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
fetchCurrentVenueDayNames =
    query @DayName
        |> filterWhere (#venueId, unpackId currentVenueId)
        |> orderByAsc #weekdayIndex
        |> fetch

parseRequiredName :: (?context :: ControllerContext) => ByteString -> Text -> IO (Maybe Text)
parseRequiredName paramName errorMessage =
    let value = Text.strip (paramOrDefault "" paramName)
     in if Text.null value
            then do
                setErrorMessage errorMessage
                pure Nothing
            else pure (Just value)

parseIsActiveParam :: (?context :: ControllerContext) => Bool
parseIsActiveParam = paramOrDefault "true" "isActive" == ("true" :: Text)

parseSortOrderParam :: (?context :: ControllerContext) => Int
parseSortOrderParam = paramOrDefault @Int 0 "sortOrder"

parsePayLevelRateParams ::
    (?context :: ControllerContext) =>
    (Scientific, Scientific, Scientific, Scientific, Scientific, Scientific)
parsePayLevelRateParams =
    ( paramOrDefault @Scientific 0 "baseRate"
    , paramOrDefault @Scientific 0 "eveningPenalty"
    , paramOrDefault @Scientific 0 "after12Penalty"
    , paramOrDefault @Scientific 1 "weekdayMultiplier"
    , paramOrDefault @Scientific 1 "saturdayMultiplier"
    , paramOrDefault @Scientific 1 "sundayMultiplier"
    )

parseDefaultPayLevelId :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO (Maybe (Id PayLevel))
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
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
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
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
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
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
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
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
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

redirectToAdminFor :: (?context :: ControllerContext) => Maybe (Id RosterGroup) -> IO ()
redirectToAdminFor maybeRosterGroupId =
    redirectToPath $
        maybe
            (pathTo AdminAction)
            (\rosterGroupId -> pathTo AdminAction <> "?rosterGroupId=" <> tshow rosterGroupId)
            maybeRosterGroupId

findReportDefinitionByEngine :: ReportDefinitionEngine -> [VenueReportDefinition] -> Maybe VenueReportDefinition
findReportDefinitionByEngine engine reportDefinitions =
    List.find (\reportDefinition -> reportDefinition.engine == engine) reportDefinitions
