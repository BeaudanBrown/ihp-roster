module Web.Controller.Admin where

import Application.Helper.Pay
import Application.Helper.RosterGroups
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
        payLevels <- fetchCurrentVenuePayLevels
        payLevelDayRules <- fetchCurrentVenuePayLevelDayRules
        shiftTypes <- fetchCurrentVenueShiftTypes
        slotNames <- fetchCurrentVenueSlotNames
        dayNames <- fetchCurrentVenueDayNames
        let latestSnapshot = listToMaybe recentSnapshots
        render IndexView { .. }

    action CreatePayConfigSnapshotAction = do
        snapshot <- createCurrentVenuePayConfigSnapshot
        setSuccessMessage ("Saved pay/config snapshot " <> snapshot.versionLabel)
        redirectTo AdminAction

    action CreatePayLevelAction = do
        maybeName <- parseRequiredName "name" "Pay level name is required."
        case maybeName of
            Nothing -> redirectTo AdminAction
            Just name -> do
                let isActive = parseIsActiveParam
                let (baseRate, eveningPenalty, after12Penalty, weekdayMultiplier, saturdayMultiplier, sundayMultiplier) = parsePayLevelRateParams
                _ <- newRecord @PayLevel
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
                setSuccessMessage "Pay level added"
                redirectTo AdminAction

    action UpdatePayLevelAction { payLevelId } = do
        payLevel <- fetch payLevelId
        ensureRecordInCurrentVenue payLevel.venueId
        maybeName <- parseRequiredName "name" "Pay level name is required."
        case maybeName of
            Nothing -> redirectTo AdminAction
            Just name -> do
                let isActive = parseIsActiveParam
                let (baseRate, eveningPenalty, after12Penalty, weekdayMultiplier, saturdayMultiplier, sundayMultiplier) = parsePayLevelRateParams
                _ <- payLevel
                    |> set #name name
                    |> set #baseRate baseRate
                    |> set #eveningPenalty eveningPenalty
                    |> set #after12Penalty after12Penalty
                    |> set #weekdayMultiplier weekdayMultiplier
                    |> set #saturdayMultiplier saturdayMultiplier
                    |> set #sundayMultiplier sundayMultiplier
                    |> set #isActive isActive
                    |> updateRecord
                setSuccessMessage "Pay level updated"
                redirectTo AdminAction

    action CreatePayLevelDayRuleAction = do
        maybeRuleParams <- parsePayLevelDayRuleParams Nothing
        case maybeRuleParams of
            Nothing -> redirectTo AdminAction
            Just (shiftTypeId, dayNameId, payLevelId) -> do
                _ <- newRecord @PayLevelDayRule
                    |> set #shiftTypeId (unpackId shiftTypeId)
                    |> set #dayNameId (unpackId dayNameId)
                    |> set #payLevelId (unpackId payLevelId)
                    |> createRecord
                setSuccessMessage "Pay override added"
                redirectTo AdminAction

    action UpdatePayLevelDayRuleAction { payLevelDayRuleId } = do
        payLevelDayRule <- fetch payLevelDayRuleId
        ensurePayLevelDayRuleInCurrentVenue payLevelDayRule
        maybeRuleParams <- parsePayLevelDayRuleParams (Just payLevelDayRule)
        case maybeRuleParams of
            Nothing -> redirectTo AdminAction
            Just (shiftTypeId, dayNameId, payLevelId) -> do
                _ <- payLevelDayRule
                    |> set #shiftTypeId (unpackId shiftTypeId)
                    |> set #dayNameId (unpackId dayNameId)
                    |> set #payLevelId (unpackId payLevelId)
                    |> updateRecord
                setSuccessMessage "Pay override updated"
                redirectTo AdminAction

    action CreateShiftTypeAction = do
        payLevels <- fetchCurrentVenuePayLevels
        if null payLevels
            then do
                setErrorMessage "Add at least one pay level before creating a shift type."
                redirectTo AdminAction
            else do
                maybeName <- parseRequiredName "name" "Shift type name is required."
                case maybeName of
                    Nothing -> redirectTo AdminAction
                    Just name -> do
                        let isActive = parseIsActiveParam
                        let sortOrder = parseSortOrderParam
                        maybePayLevel <- parseDefaultPayLevelId
                        case maybePayLevel of
                            Nothing -> redirectTo AdminAction
                            Just defaultPayLevelId -> do
                                _ <- newRecord @ShiftType
                                    |> set #venueId (unpackId currentVenueId)
                                    |> set #name name
                                    |> set #sortOrder sortOrder
                                    |> set #defaultPayLevelId (unpackId defaultPayLevelId)
                                    |> set #isActive isActive
                                    |> createRecord
                                setSuccessMessage "Shift type added"
                                redirectTo AdminAction

    action UpdateShiftTypeAction { shiftTypeId } = do
        shiftType <- fetch shiftTypeId
        ensureRecordInCurrentVenue shiftType.venueId
        maybeName <- parseRequiredName "name" "Shift type name is required."
        case maybeName of
            Nothing -> redirectTo AdminAction
            Just name -> do
                let isActive = parseIsActiveParam
                let sortOrder = parseSortOrderParam
                maybePayLevel <- parseDefaultPayLevelId
                case maybePayLevel of
                    Nothing -> redirectTo AdminAction
                    Just defaultPayLevelId -> do
                        _ <- shiftType
                            |> set #name name
                            |> set #sortOrder sortOrder
                            |> set #defaultPayLevelId (unpackId defaultPayLevelId)
                            |> set #isActive isActive
                            |> updateRecord
                        setSuccessMessage "Shift type updated"
                        redirectTo AdminAction

    action CreateSlotNameAction = do
        maybeName <- parseRequiredName "name" "Slot name is required."
        case maybeName of
            Nothing -> redirectTo AdminAction
            Just name -> do
                let isActive = parseIsActiveParam
                rosterGroup <- fetchCurrentVenueDefaultRosterGroup
                _ <- newRecord @SlotName
                    |> set #venueId (unpackId currentVenueId)
                    |> set #rosterGroupId (unpackId rosterGroup.id)
                    |> set #name name
                    |> set #isActive isActive
                    |> createRecord
                setSuccessMessage "Slot name added"
                redirectTo AdminAction

    action UpdateSlotNameAction { slotNameId } = do
        slotName <- fetch slotNameId
        ensureRecordInCurrentVenue slotName.venueId
        maybeName <- parseRequiredName "name" "Slot name is required."
        case maybeName of
            Nothing -> redirectTo AdminAction
            Just name -> do
                let isActive = parseIsActiveParam
                _ <- slotName
                    |> set #name name
                    |> set #isActive isActive
                    |> updateRecord
                setSuccessMessage "Slot name updated"
                redirectTo AdminAction

    action CreateDayNameAction = do
        maybeDayNameParams <- parseDayNameParams Nothing
        case maybeDayNameParams of
            Nothing -> redirectTo AdminAction
            Just (weekdayIndex, name, isActive) -> do
                _ <- newRecord @DayName
                    |> set #venueId (unpackId currentVenueId)
                    |> set #weekdayIndex weekdayIndex
                    |> set #name name
                    |> set #isActive isActive
                    |> createRecord
                setSuccessMessage "Day name added"
                redirectTo AdminAction

    action UpdateDayNameAction { dayNameId } = do
        dayName <- fetch dayNameId
        ensureRecordInCurrentVenue dayName.venueId
        maybeDayNameParams <- parseDayNameParams (Just dayName)
        case maybeDayNameParams of
            Nothing -> redirectTo AdminAction
            Just (weekdayIndex, name, isActive) -> do
                _ <- dayName
                    |> set #weekdayIndex weekdayIndex
                    |> set #name name
                    |> set #isActive isActive
                    |> updateRecord
                setSuccessMessage "Day name updated"
                redirectTo AdminAction

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

fetchCurrentVenueSlotNames :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO [SlotName]
fetchCurrentVenueSlotNames = do
    rosterGroup <- fetchCurrentVenueDefaultRosterGroup
    fetchRosterGroupSlotNames rosterGroup.id

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

parseDayNameParams ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    Maybe DayName ->
    IO (Maybe (Int, Text, Bool))
parseDayNameParams existingDayName = do
    let maybeWeekdayIndex = paramOrNothing @Int "weekdayIndex"
    case maybeWeekdayIndex of
        Nothing -> do
            setErrorMessage "Choose a weekday."
            pure Nothing
        Just weekdayIndex
            | weekdayIndex < 0 || weekdayIndex > 6 -> do
                setErrorMessage "Weekday must be between 0 and 6."
                pure Nothing
            | otherwise -> do
                maybeName <- parseRequiredName "name" "Day name is required."
                case maybeName of
                    Nothing -> pure Nothing
                    Just name -> do
                        dayNames <- fetchCurrentVenueDayNames
                        let conflicts =
                                any
                                    (\dayName ->
                                        dayName.weekdayIndex == weekdayIndex
                                            && maybe True (\existing -> get #id existing /= get #id dayName) existingDayName
                                    )
                                    dayNames
                        if conflicts
                            then do
                                setErrorMessage "That weekday already has a configured day name for this venue."
                                pure Nothing
                            else pure (Just (weekdayIndex, name, parseIsActiveParam))

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
