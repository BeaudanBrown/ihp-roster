module Web.Controller.Admin.Support where

import Application.Helper.Export
import Application.Helper.Pay
import Application.Helper.RosterGroups
import Application.Helper.VenueInvitation
import Application.Helper.WeekBoundaries (defaultWeekOffsetEpochForStartDay,
                                          sortDayNamesForVenueWeek,
                                          validRosterWeekStartDays,
                                          weekdayIndexLabel)
import Control.Monad (void)
import Data.Functor ((<&>))
import qualified Data.List as List
import qualified Data.Text as Text
import Data.Time.Clock (NominalDiffTime, UTCTime, addUTCTime, getCurrentTime)
import qualified Text.Blaze.Html as Blaze
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

fetchActiveImportedXeroPayItems :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO [XeroImportedPayItem]
fetchActiveImportedXeroPayItems =
    query @XeroImportedPayItem
        |> filterWhere (#venueId, unpackId currentVenueId)
        |> filterWhere (#archivedAt, Nothing :: Maybe UTCTime)
        |> orderByAsc #name
        |> fetch

nextRosterGroupSortOrder :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO Int
nextRosterGroupSortOrder =
    query @RosterGroup
        |> filterWhere (#venueId, unpackId currentVenueId)
        |> filterWhere (#archivedAt, Nothing)
        |> orderByDesc #sortOrder
        |> fetchOneOrNothing
        <&> maybe 0 ((+ 1) . get #sortOrder)

nextShiftTypeSortOrder :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO Int
nextShiftTypeSortOrder =
    query @ShiftType
        |> filterWhere (#venueId, unpackId currentVenueId)
        |> filterWhere (#archivedAt, Nothing)
        |> orderByDesc #sortOrder
        |> fetchOneOrNothing
        <&> maybe 0 ((+ 1) . get #sortOrder)

data AdminSectionMutationResponse = AdminSectionMutationResponse
    { adminSectionSuccessMessage :: !(Maybe Text)
    , adminSectionRedirectGroup  :: !(Maybe (Id RosterGroup))
    , adminSectionRenderFragment :: !(IO Blaze.Html)
    }

respondToAdminSectionMutation ::
    (?context :: ControllerContext, ?request :: Request) =>
    AdminSectionMutationResponse ->
    IO ()
respondToAdminSectionMutation AdminSectionMutationResponse { .. } =
    if isHtmxRequest
        then do
            maybeSetFlashSuccess adminSectionSuccessMessage
            adminSectionRenderFragment >>= respondHtml
        else do
            maybeSetFlashSuccess adminSectionSuccessMessage
            redirectToAdminFor adminSectionRedirectGroup
    where
        maybeSetFlashSuccess =
            maybe (pure ()) setSuccessMessage

respondToInvitesSectionMutation ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Text ->
    Id RosterGroup ->
    IO ()
respondToInvitesSectionMutation successMessage rosterGroupId =
    respondToAdminSectionMutation AdminSectionMutationResponse
        { adminSectionSuccessMessage = nonEmptySuccessMessage successMessage
        , adminSectionRedirectGroup = Just rosterGroupId
        , adminSectionRenderFragment = do
            invitations <- fetchCurrentVenueInvitations
            pure (renderInvitesSectionFragment invitations rosterGroupId)
        }

respondToShiftTypesSectionMutation ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    IO ()
respondToShiftTypesSectionMutation =
    respondToAdminSectionMutation AdminSectionMutationResponse
        { adminSectionSuccessMessage = Nothing
        , adminSectionRedirectGroup = paramOrNothing "rosterGroupId"
        , adminSectionRenderFragment = do
            shiftTypes <- fetchCurrentVenueShiftTypes
            awardLevels <- fetchActiveAwardLevels
            awardLevelBaseRates <- fetchCurrentAwardLevelBaseRates
            importedPayItems <- fetchActiveImportedXeroPayItems
            let showInactiveShiftTypes = parseShowInactiveParam "showInactiveShiftTypes"
            pure (renderShiftTypesSectionFragment shiftTypes showInactiveShiftTypes awardLevels awardLevelBaseRates importedPayItems)
        }

respondToRosterGroupsSectionMutation ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Maybe (Id RosterGroup) ->
    IO ()
respondToRosterGroupsSectionMutation maybeRosterGroupId =
    respondToAdminSectionMutation AdminSectionMutationResponse
        { adminSectionSuccessMessage = Nothing
        , adminSectionRedirectGroup = maybeRosterGroupId
        , adminSectionRenderFragment = do
            rosterGroups <- fetchCurrentVenueRosterGroups
            let showInactiveRosterGroups = parseShowInactiveParam "showInactiveRosterGroups"
            pure (renderRosterGroupsSectionFragment rosterGroups showInactiveRosterGroups)
        }

nonEmptySuccessMessage :: Text -> Maybe Text
nonEmptySuccessMessage message
    | Text.null message = Nothing
    | otherwise = Just message


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
fetchCurrentVenueInvitations = do
    now <- getCurrentTime
    let retentionCutoff = addUTCTime (negate venueInvitationHistoryRetentionSeconds) now
    invitations <-
        query @VenueInvitation
            |> filterWhere (#venueId, unpackId currentVenueId)
            |> orderByDesc #createdAt
            |> fetch
    pure (filter (shouldShowVenueInvitation now retentionCutoff) invitations)

venueInvitationHistoryRetentionSeconds :: NominalDiffTime
venueInvitationHistoryRetentionSeconds = 7 * 24 * 60 * 60

shouldShowVenueInvitation :: UTCTime -> UTCTime -> VenueInvitation -> Bool
shouldShowVenueInvitation now retentionCutoff invitation =
    case inputValue invitation.status of
        "pending" -> maybe True (> now) invitation.expiresAt || maybe False (>= retentionCutoff) invitation.expiresAt
        "accepted" -> fromMaybe invitation.updatedAt invitation.acceptedAt >= retentionCutoff
        "revoked" -> invitation.updatedAt >= retentionCutoff
        _ -> invitation.updatedAt >= retentionCutoff

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
    staffPayVersionCount <-
        query @StaffPayVersion
            |> filterWhere (#venueId, unpackId currentVenueId)
            |> fetchCount
    shiftTypePayVersionCount <-
        query @ShiftTypePayVersion
            |> filterWhere (#venueId, unpackId currentVenueId)
            |> fetchCount
    pure (any (> 0) [rosterWeekCount, timesheetEntryCount, leaveRequestCount, exportJobCount, staffPayVersionCount, shiftTypePayVersionCount])

parseRequiredName :: (?context :: ControllerContext, ?request :: Request) => ByteString -> Text -> IO (Maybe Text)
parseRequiredName paramName errorMessage =
    let value = Text.strip (paramOrDefault "" paramName)
     in if Text.null value
            then do
                setErrorMessage errorMessage
                pure Nothing
            else if Text.length value > 120
                then do
                    setErrorMessage "Name must be 120 characters or fewer."
                    pure Nothing
            else pure (Just value)

parseRequiredEmail :: (?context :: ControllerContext, ?request :: Request) => ByteString -> Text -> IO (Maybe Text)
parseRequiredEmail paramName emptyMessage =
    case Text.strip (paramOrDefault "" paramName) of
        value | Text.null value -> do
            setErrorMessage emptyMessage
            pure Nothing
        value ->
            if Text.length value > 254
                then do
                    setErrorMessage "Email must be 254 characters or fewer."
                    pure Nothing
                else
                    case isEmail value of
                        Success -> pure (Just value)
                        Failure _ -> do
                            setErrorMessage "Enter a valid email address."
                            pure Nothing
                        FailureHtml _ -> do
                            setErrorMessage "Enter a valid email address."
                            pure Nothing

parseIsActiveParam :: (?context :: ControllerContext, ?request :: Request) => Bool
parseIsActiveParam =
    case paramList @Text "isActive" of
        []     -> True
        values -> "true" `elem` values

parseShowInactiveParam :: (?context :: ControllerContext, ?request :: Request) => ByteString -> Bool
parseShowInactiveParam paramName = paramOrDefault "false" paramName == ("true" :: Text)

parseSubmittedShiftTypeColourKey :: (?context :: ControllerContext, ?request :: Request) => Maybe Text
parseSubmittedShiftTypeColourKey = paramOrNothing "colourKey"

data SubmittedPayRateSelection = SubmittedPayRateSelection
    { submittedAwardLevelId          :: !(Maybe (Id AwardLevel))
    , submittedImportedXeroPayItemId :: !(Maybe (Id XeroImportedPayItem))
    }

emptySubmittedPayRateSelection :: SubmittedPayRateSelection
emptySubmittedPayRateSelection = SubmittedPayRateSelection Nothing Nothing

parseSubmittedPayRateSelection ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    ByteString ->
    IO (Maybe SubmittedPayRateSelection)
parseSubmittedPayRateSelection paramName =
    case paramOrNothing @Text paramName of
        Nothing -> parseLegacySubmittedPayRateSelection
        Just "" -> pure (Just emptySubmittedPayRateSelection)
        Just value
            | Just rawAwardLevelId <- Text.stripPrefix "award:" value ->
                validateSubmittedAwardLevelId rawAwardLevelId
            | Just rawImportedPayItemId <- Text.stripPrefix "xero:" value ->
                validateSubmittedImportedPayItemId rawImportedPayItemId
            | otherwise -> do
                setErrorMessage "Choose a pay rate from the list, or leave the default selected."
                pure Nothing

parseLegacySubmittedPayRateSelection ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    IO (Maybe SubmittedPayRateSelection)
parseLegacySubmittedPayRateSelection = do
    let maybeAwardLevelText =
            case paramOrNothing @Text "overrideAwardLevelId" of
                Just value -> Just value
                Nothing    -> paramOrNothing @Text "defaultAwardLevelId"
    case maybeAwardLevelText of
        Just ""             -> parseLegacyImportedPayItemSelection
        Just awardLevelText -> validateSubmittedAwardLevelId awardLevelText
        Nothing             -> parseLegacyImportedPayItemSelection

parseLegacyImportedPayItemSelection ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    IO (Maybe SubmittedPayRateSelection)
parseLegacyImportedPayItemSelection =
    case paramOrNothing @Text "importedXeroPayItemId" of
        Just "" -> pure (Just emptySubmittedPayRateSelection)
        Just importedPayItemText -> validateSubmittedImportedPayItemId importedPayItemText
        Nothing -> pure (Just emptySubmittedPayRateSelection)

validateSubmittedAwardLevelId ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Text ->
    IO (Maybe SubmittedPayRateSelection)
validateSubmittedAwardLevelId rawAwardLevelId =
    case Id <$> parseUUIDText rawAwardLevelId of
        Nothing -> invalidAwardLevel
        Just awardLevelId -> do
            maybeAwardLevel <-
                query @AwardLevel
                    |> filterWhere (#id, awardLevelId)
                    |> filterWhere (#isActive, True)
                    |> fetchOneOrNothing
            case maybeAwardLevel of
                Just _ -> pure (Just emptySubmittedPayRateSelection { submittedAwardLevelId = Just awardLevelId })
                Nothing -> invalidAwardLevel
    where
        invalidAwardLevel = do
            setErrorMessage "Choose an active FWC pay rate, or leave the default selected."
            pure Nothing

validateSubmittedImportedPayItemId ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Text ->
    IO (Maybe SubmittedPayRateSelection)
validateSubmittedImportedPayItemId rawImportedPayItemId =
    case Id <$> parseUUIDText rawImportedPayItemId of
        Nothing -> invalidImportedPayItem
        Just importedPayItemId -> do
            maybeImportedPayItem <-
                query @XeroImportedPayItem
                    |> filterWhere (#id, importedPayItemId)
                    |> filterWhere (#venueId, unpackId currentVenueId)
                    |> filterWhere (#archivedAt, Nothing :: Maybe UTCTime)
                    |> fetchOneOrNothing
            case maybeImportedPayItem of
                Just _ -> pure (Just emptySubmittedPayRateSelection { submittedImportedXeroPayItemId = Just importedPayItemId })
                Nothing -> invalidImportedPayItem
    where
        invalidImportedPayItem = do
            setErrorMessage "Choose an active imported Xero pay item, or leave the default selected."
            pure Nothing

parseSubmittedImportedXeroPayItemId ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    IO (Maybe (Maybe (Id XeroImportedPayItem)))
parseSubmittedImportedXeroPayItemId =
    case paramOrNothing @(Id XeroImportedPayItem) "importedXeroPayItemId" of
        Nothing -> pure (Just Nothing)
        Just importedPayItemId -> do
            maybeImportedPayItem <-
                query @XeroImportedPayItem
                    |> filterWhere (#id, importedPayItemId)
                    |> filterWhere (#venueId, unpackId currentVenueId)
                    |> filterWhere (#archivedAt, Nothing :: Maybe UTCTime)
                    |> fetchOneOrNothing
            case maybeImportedPayItem of
                Just _ -> pure (Just (Just importedPayItemId))
                Nothing -> do
                    setErrorMessage "Choose an active imported Xero pay item, or leave Bepis award pay selected."
                    pure Nothing

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
venueRoleLabel SupervisorRole = "Supervisor"
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
findReportDefinitionByEngine engine =
    List.find (\reportDefinition -> reportDefinition.engine == engine)
