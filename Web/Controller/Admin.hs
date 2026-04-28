module Web.Controller.Admin where

import Application.Helper.Export
import Application.Helper.Xero
import Application.Helper.LiveUpdate
import Application.Helper.Pay
import Application.Helper.Profiling
import Application.Helper.RosterGroups
import Application.Helper.View (ToastOverlayConfig (..),
                                ToastOverlayPosition (ToastBottomCenter),
                                renderToastOverlayHostOob)
import Application.Helper.VenueInvitation
import Application.Helper.WeekBoundaries (defaultWeekOffsetEpochForStartDay,
                                          validRosterWeekStartDays,
                                          weekdayIndexLabel)
import Application.Helper.XeroAdminTypes
import Application.Xero.Connection
import Control.Concurrent (forkIO)
import Control.Monad (void)
import qualified Data.Aeson as Aeson
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
        xeroConnection <- fetchCurrentVenueXeroConnection
        xeroConnectedByUser <- fetchXeroConnectedByUser xeroConnection
        xeroLatestSyncRun <- fetchLatestCurrentVenueXeroSyncRun
        xeroEmployeeCount <- fetchCurrentVenueXeroEmployeeCount xeroConnection
        xeroEarningsRateCount <- fetchCurrentVenueXeroEarningsRateCount xeroConnection
        xeroPayrollCalendarCount <- fetchCurrentVenueXeroPayrollCalendarCount xeroConnection
        xeroEmployees <- fetchCurrentVenueXeroEmployees xeroConnection
        xeroStaffMappingRows <- fetchCurrentVenueXeroStaffMappingRows xeroConnection
        let xeroStaffMappingCounts = xeroStaffMappingCountsFor xeroStaffMappingRows
        xeroEarningsRates <- fetchCurrentVenueXeroEarningsRates xeroConnection
        xeroEarningsBucketRows <- fetchCurrentVenueXeroEarningsBucketRows xeroConnection
        let xeroEarningsRateMappingCounts = xeroEarningsRateMappingCountsFor xeroEarningsBucketRows
        xeroPayrollCalendars <- fetchCurrentVenueXeroPayrollCalendars xeroConnection
        xeroPayrollCalendarSelection <- fetchCurrentVenueXeroPayrollCalendarSelection xeroConnection
        let xeroReadyChecklist = buildXeroReadyChecklist xeroConnection xeroLatestSyncRun xeroStaffMappingRows xeroEarningsBucketRows xeroPayrollCalendarSelection
        let xeroConnectionActionsAllowed = currentUserIsCurrentVenueOwner
        render IndexView { .. }

    action StartXeroConnectionAction = do
        requireCurrentVenueOwnerForXero do
            readXeroConfig >>= \case
                Left message -> do
                    setErrorMessage message
                    redirectTo AdminAction
                Right xeroConfig -> do
                    now <- getCurrentTime
                    stateToken <- generateXeroStateToken
                    oauthState <- newRecord @XeroOauthState
                        |> set #venueId (unpackId currentVenueId)
                        |> set #userId (unpackId currentUser.id)
                        |> set #stateToken stateToken
                        |> set #requestedScopes requiredXeroScopesText
                        |> set #redirectUri xeroConfig.redirectUri
                        |> set #expiresAt (addUTCTime (15 * 60) now)
                        |> createRecord
                    void $ recordCurrentUserAuditEvent
                        "xero_connection_started"
                        "xero_oauth_states"
                        (unpackId oauthState.id)
                        (Aeson.object
                            [ "scopes" Aeson..= requiredXeroScopes
                            , "redirectUri" Aeson..= xeroConfig.redirectUri
                            ]
                        )
                    redirectToUrl (buildXeroAuthorizationUrl xeroConfig stateToken)

    action XeroOAuthCallbackAction = do
        requireCurrentVenueOwnerForXero do
            now <- getCurrentTime
            let maybeStateToken = paramOrNothing @Text "state"
            let maybeXeroError = paramOrNothing @Text "error"
            let maybeCode = paramOrNothing @Text "code"
            validatedState <- validateXeroOAuthState now currentUser.id maybeStateToken
            case validatedState of
                Left message -> failXeroConnectionAttempt message Nothing
                Right oauthState ->
                    case maybeXeroError of
                        Just xeroError -> do
                            markXeroOAuthStateConsumed oauthState now
                            failXeroConnectionAttempt ("Xero authorization failed: " <> xeroError) (Just oauthState)
                        Nothing ->
                            case maybeCode of
                                Nothing -> failXeroConnectionAttempt "Xero did not return an authorization code." (Just oauthState)
                                Just code -> completeXeroOAuthCallback now currentUser.id oauthState code

    action DisconnectXeroConnectionAction = do
        requireCurrentVenueOwnerForXero do
            maybeConnection <- fetchCurrentVenueXeroConnection
            case maybeConnection of
                Nothing -> do
                    setErrorMessage "Xero is not connected for this venue."
                    redirectTo AdminAction
                Just connection -> do
                    disconnectXeroConnection connection

    action SyncXeroPayrollReferenceDataAction = do
        maybeConnection <- fetchActiveCurrentVenueXeroConnection
        case maybeConnection of
            Nothing -> do
                setErrorMessage "Connect Xero before syncing payroll reference data."
                if isHtmxRequest
                    then respondWithXeroSectionFragment
                    else redirectTo AdminAction
            Just connection -> syncXeroPayrollReferenceData connection

    action SaveXeroStaffMappingAction = do
        maybeConnection <- fetchCurrentVenueXeroConnection
        case maybeConnection of
            Nothing -> do
                setErrorMessage "Connect Xero before mapping staff to Xero employees."
                if isHtmxRequest
                    then respondWithXeroSectionFragment
                    else redirectTo AdminAction
            Just connection -> do
                let staffId = param @(Id Staff) "staffId"
                let selection = Text.strip (paramOrDefault @Text "" "xeroEmployeeSelection")
                saveXeroStaffMapping connection staffId selection

    action SaveXeroEarningsRateMappingAction = do
        maybeConnection <- fetchCurrentVenueXeroConnection
        case maybeConnection of
            Nothing -> do
                setErrorMessage "Connect Xero before mapping earning buckets to Xero earnings rates."
                if isHtmxRequest
                    then respondWithXeroSectionFragment
                    else redirectTo AdminAction
            Just connection -> do
                let localBucketKey = Text.strip (paramOrDefault @Text "" "localBucketKey")
                let selection = Text.strip (paramOrDefault @Text "" "xeroEarningsRateSelection")
                saveXeroEarningsRateMapping connection localBucketKey selection

    action SaveXeroPayrollCalendarSelectionAction = do
        maybeConnection <- fetchCurrentVenueXeroConnection
        case maybeConnection of
            Nothing -> do
                setErrorMessage "Connect Xero before selecting a payroll calendar."
                if isHtmxRequest
                    then respondWithXeroSectionFragment
                    else redirectTo AdminAction
            Just connection -> do
                let selection = Text.strip (paramOrDefault @Text "" "xeroPayrollCalendarSelection")
                saveXeroPayrollCalendarSelection connection selection

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

    action ShowAdminXeroFragmentAction = do
        respondWithXeroSectionFragment

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

broadcastAdminXeroInvalidation ::
    (?context :: ControllerContext, ?request :: Request) =>
    Id Venue ->
    IO ()
broadcastAdminXeroInvalidation venueId =
    broadcastLiveResync
        (adminXeroScope venueId)
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

adminXeroScope :: Id Venue -> LiveUpdateScope
adminXeroScope venueId =
    AdminXeroScope
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

fetchActiveCurrentVenueXeroConnection :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO (Maybe XeroConnection)
fetchActiveCurrentVenueXeroConnection =
    query @XeroConnection
        |> filterWhere (#venueId, unpackId currentVenueId)
        |> filterWhere (#connectionStatus, "active" :: Text)
        |> orderByDesc #connectedAt
        |> fetchOneOrNothing

fetchCurrentVenueXeroConnection :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO (Maybe XeroConnection)
fetchCurrentVenueXeroConnection =
    query @XeroConnection
        |> filterWhere (#venueId, unpackId currentVenueId)
        |> filterWhereIn (#connectionStatus, ["active" :: Text, "reauthorization_required", "error"])
        |> orderByDesc #connectedAt
        |> fetchOneOrNothing

fetchXeroConnectedByUser :: (?modelContext :: ModelContext) => Maybe XeroConnection -> IO (Maybe User)
fetchXeroConnectedByUser maybeConnection =
    case maybeConnection >>= (.connectedByUserId) of
        Nothing -> pure Nothing
        Just userId ->
            query @User
                |> filterWhere (#id, Id userId)
                |> fetchOneOrNothing

fetchLatestCurrentVenueXeroSyncRun :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO (Maybe XeroSyncRun)
fetchLatestCurrentVenueXeroSyncRun =
    query @XeroSyncRun
        |> filterWhere (#venueId, unpackId currentVenueId)
        |> filterWhere (#syncKind, "payroll_reference_data" :: Text)
        |> orderByDesc #startedAt
        |> fetchOneOrNothing

fetchCurrentVenueXeroEmployeeCount :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Maybe XeroConnection -> IO Int
fetchCurrentVenueXeroEmployeeCount maybeConnection =
    case maybeConnection of
        Nothing -> pure 0
        Just connection ->
            query @XeroEmployee
                |> filterWhere (#venueId, unpackId currentVenueId)
                |> filterWhere (#xeroConnectionId, unpackId connection.id)
                |> fetchCount

fetchCurrentVenueXeroEarningsRateCount :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Maybe XeroConnection -> IO Int
fetchCurrentVenueXeroEarningsRateCount maybeConnection =
    case maybeConnection of
        Nothing -> pure 0
        Just connection ->
            query @XeroEarningsRate
                |> filterWhere (#venueId, unpackId currentVenueId)
                |> filterWhere (#xeroConnectionId, unpackId connection.id)
                |> fetchCount

fetchCurrentVenueXeroPayrollCalendarCount :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Maybe XeroConnection -> IO Int
fetchCurrentVenueXeroPayrollCalendarCount maybeConnection =
    case maybeConnection of
        Nothing -> pure 0
        Just connection ->
            query @XeroPayrollCalendar
                |> filterWhere (#venueId, unpackId currentVenueId)
                |> filterWhere (#xeroConnectionId, unpackId connection.id)
                |> fetchCount

fetchCurrentVenueXeroEmployees :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Maybe XeroConnection -> IO [XeroEmployee]
fetchCurrentVenueXeroEmployees maybeConnection =
    case maybeConnection of
        Nothing -> pure []
        Just connection ->
            query @XeroEmployee
                |> filterWhere (#venueId, unpackId currentVenueId)
                |> filterWhere (#xeroConnectionId, unpackId connection.id)
                |> orderBy #displayName
                |> fetch

fetchCurrentVenueXeroEarningsRates :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Maybe XeroConnection -> IO [XeroEarningsRate]
fetchCurrentVenueXeroEarningsRates maybeConnection =
    case maybeConnection of
        Nothing -> pure []
        Just connection ->
            query @XeroEarningsRate
                |> filterWhere (#venueId, unpackId currentVenueId)
                |> filterWhere (#xeroConnectionId, unpackId connection.id)
                |> filterWhere (#isActive, True)
                |> orderBy #name
                |> fetch

fetchCurrentVenueXeroPayrollCalendars :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Maybe XeroConnection -> IO [XeroPayrollCalendar]
fetchCurrentVenueXeroPayrollCalendars maybeConnection =
    case maybeConnection of
        Nothing -> pure []
        Just connection ->
            query @XeroPayrollCalendar
                |> filterWhere (#venueId, unpackId currentVenueId)
                |> filterWhere (#xeroConnectionId, unpackId connection.id)
                |> orderBy #name
                |> fetch

fetchCurrentVenueXeroPayrollCalendarSelection :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Maybe XeroConnection -> IO (Maybe XeroPayrollCalendarSelection)
fetchCurrentVenueXeroPayrollCalendarSelection maybeConnection =
    case maybeConnection of
        Nothing -> pure Nothing
        Just connection ->
            query @XeroPayrollCalendarSelection
                |> filterWhere (#venueId, unpackId currentVenueId)
                |> filterWhere (#xeroConnectionId, unpackId connection.id)
                |> fetchOneOrNothing

fetchCurrentVenueXeroEarningsBucketRows :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Maybe XeroConnection -> IO [XeroEarningsBucketRow]
fetchCurrentVenueXeroEarningsBucketRows maybeConnection =
    case maybeConnection of
        Nothing -> pure []
        Just connection -> do
            buckets <- currentVenueLocalXeroEarningsBuckets
            mappings <-
                query @XeroEarningsRateMapping
                    |> filterWhere (#venueId, unpackId currentVenueId)
                    |> filterWhere (#xeroConnectionId, unpackId connection.id)
                    |> fetch
            pure $
                buckets
                    |> map (\bucket ->
                        XeroEarningsBucketRow
                            { earningsBucketRowBucket = bucket
                            , earningsBucketRowMapping = List.find (\mapping -> mapping.localBucketKey == bucket.localBucketKey) mappings
                            }
                    )

currentVenueLocalXeroEarningsBuckets :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO [XeroLocalEarningsBucket]
currentVenueLocalXeroEarningsBuckets = do
    awardLevels <-
        query @AwardLevel
            |> filterWhere (#isActive, True)
            |> orderBy #classification
            |> fetch
    pure (concatMap bucketsForAwardLevel awardLevels)
    where
        bucketsForAwardLevel :: AwardLevel -> [XeroLocalEarningsBucket]
        bucketsForAwardLevel awardLevel =
            map (bucketFor awardLevel) xeroPayrollPenaltyBuckets

        bucketFor :: AwardLevel -> (Text, Text) -> XeroLocalEarningsBucket
        bucketFor awardLevel (penaltyKind, penaltyLabel) =
            XeroLocalEarningsBucket
                { localBucketKey = "award:" <> tshow (awardLevel.awardFixedId) <> ":classification:" <> tshow (awardLevel.classificationFixedId) <> ":penalty:" <> penaltyKind
                , localBucketLabel = awardLevel.classification <> " - " <> penaltyLabel
                }

xeroPayrollPenaltyBuckets :: [(Text, Text)]
xeroPayrollPenaltyBuckets =
    [ ("ordinary", "Ordinary")
    , ("evening_after_7pm", "Evening After 7pm")
    , ("late_night_after_midnight", "Late Night After Midnight")
    , ("saturday_penalty", "Saturday")
    , ("sunday_penalty", "Sunday")
    , ("public_holiday_penalty", "Public Holiday")
    ]

fetchCurrentVenueXeroStaffMappingRows :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Maybe XeroConnection -> IO [XeroStaffMappingRow]
fetchCurrentVenueXeroStaffMappingRows maybeConnection =
    case maybeConnection of
        Nothing -> pure []
        Just connection -> do
            staffMembers <-
                query @Staff
                    |> filterWhere (#venueId, unpackId currentVenueId)
                    |> filterWhere (#isActive, True)
                    |> filterWhere (#archivedAt, Nothing)
                    |> orderBy #lastName
                    |> orderBy #firstName
                    |> fetch
            mappings <-
                query @XeroStaffMapping
                    |> filterWhere (#venueId, unpackId currentVenueId)
                    |> filterWhere (#xeroConnectionId, unpackId connection.id)
                    |> fetch
            forM staffMembers \staff -> do
                maybeUser <- fetchStaffLinkedUser staff
                let maybeMapping = List.find (\mapping -> mapping.staffId == unpackId staff.id) mappings
                pure XeroStaffMappingRow
                    { mappingRowStaff = staff
                    , mappingRowUser = maybeUser
                    , mappingRowMapping = maybeMapping
                    }

fetchStaffLinkedUser :: (?modelContext :: ModelContext) => Staff -> IO (Maybe User)
fetchStaffLinkedUser staff =
    case staff.userId of
        Nothing -> pure Nothing
        Just userId ->
            query @User
                |> filterWhere (#id, Id userId)
                |> fetchOneOrNothing

xeroStaffMappingCountsFor :: [XeroStaffMappingRow] -> XeroStaffMappingCounts
xeroStaffMappingCountsFor rows =
    XeroStaffMappingCounts
        { xeroStaffVerifiedCount = countStatus "verified"
        , xeroStaffUnmappedCount = length (filter isUnmapped rows)
        , xeroStaffNotApplicableCount = countStatus "not_applicable"
        , xeroStaffStaleCount = countStatus "stale"
        }
    where
        mappingStatus row = (.mappingStatus) <$> row.mappingRowMapping
        countStatus status = length (filter (\row -> mappingStatus row == Just status) rows)
        isUnmapped row =
            case mappingStatus row of
                Nothing         -> True
                Just "unmapped" -> True
                _               -> False

xeroEarningsRateMappingCountsFor :: [XeroEarningsBucketRow] -> XeroEarningsRateMappingCounts
xeroEarningsRateMappingCountsFor rows =
    XeroEarningsRateMappingCounts
        { xeroEarningsVerifiedCount = countStatus "verified"
        , xeroEarningsUnmappedCount = length (filter isUnmapped rows)
        , xeroEarningsStaleCount = countStatus "stale"
        }
    where
        mappingStatus row = (.mappingStatus) <$> row.earningsBucketRowMapping
        countStatus status = length (filter (\row -> mappingStatus row == Just status) rows)
        isUnmapped row =
            case mappingStatus row of
                Nothing         -> True
                Just "unmapped" -> True
                _               -> False

buildXeroReadyChecklist :: Maybe XeroConnection -> Maybe XeroSyncRun -> [XeroStaffMappingRow] -> [XeroEarningsBucketRow] -> Maybe XeroPayrollCalendarSelection -> XeroReadyChecklist
buildXeroReadyChecklist maybeConnection maybeSyncRun staffRows earningsRows maybeCalendarSelection =
    XeroReadyChecklist
        { xeroReadyConnection = maybe False (\connection -> connection.connectionStatus == "active") maybeConnection
        , xeroReadyReferenceSync = maybe False (\syncRun -> syncRun.syncStatus == "succeeded") maybeSyncRun
        , xeroReadyStaffMappings = not (null staffRows) && all staffRowReady staffRows
        , xeroReadyEarningsMappings = not (null earningsRows) && all earningsRowReady earningsRows
        , xeroReadyPayrollCalendar = maybe False (\selection -> selection.calendarStatus == "verified" && isJust selection.xeroPayrollCalendarId) maybeCalendarSelection
        }
    where
        staffRowReady row =
            maybe False (\mapping -> mapping.mappingStatus == "verified" || mapping.mappingStatus == "not_applicable") row.mappingRowMapping
        earningsRowReady row =
            maybe False (\mapping -> mapping.mappingStatus == "verified") row.earningsBucketRowMapping

respondWithXeroSectionFragment ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    IO ()
respondWithXeroSectionFragment =
    respondWithXeroSectionFragmentAndToast Nothing

respondWithXeroSectionFragmentAndToast ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Maybe ToastOverlayConfig ->
    IO ()
respondWithXeroSectionFragmentAndToast maybeToast = do
    xeroConnection <- profileActionSpan "admin.xero.fragment.load_connection" fetchCurrentVenueXeroConnection
    xeroConnectedByUser <- profileActionSpan "admin.xero.fragment.load_connected_user" (fetchXeroConnectedByUser xeroConnection)
    xeroLatestSyncRun <- profileActionSpan "admin.xero.fragment.load_latest_sync" fetchLatestCurrentVenueXeroSyncRun
    (xeroEmployeeCount, xeroEarningsRateCount, xeroPayrollCalendarCount) <- profileActionSpan "admin.xero.fragment.fetch_reference_counts" do
        (,,)
            <$> fetchCurrentVenueXeroEmployeeCount xeroConnection
            <*> fetchCurrentVenueXeroEarningsRateCount xeroConnection
            <*> fetchCurrentVenueXeroPayrollCalendarCount xeroConnection
    xeroEmployees <- profileActionSpan "admin.xero.staff_mapping.fetch_employees" (fetchCurrentVenueXeroEmployees xeroConnection)
    xeroStaffMappingRows <- profileActionSpan "admin.xero.staff_mapping.fetch_rows" (fetchCurrentVenueXeroStaffMappingRows xeroConnection)
    let xeroStaffMappingCounts = xeroStaffMappingCountsFor xeroStaffMappingRows
    xeroEarningsRates <- profileActionSpan "admin.xero.earnings_mapping.fetch_rates" (fetchCurrentVenueXeroEarningsRates xeroConnection)
    xeroEarningsBucketRows <- profileActionSpan "admin.xero.earnings_mapping.fetch_rows" (fetchCurrentVenueXeroEarningsBucketRows xeroConnection)
    let xeroEarningsRateMappingCounts = xeroEarningsRateMappingCountsFor xeroEarningsBucketRows
    xeroPayrollCalendars <- profileActionSpan "admin.xero.calendar.fetch_calendars" (fetchCurrentVenueXeroPayrollCalendars xeroConnection)
    xeroPayrollCalendarSelection <- profileActionSpan "admin.xero.calendar.fetch_selection" (fetchCurrentVenueXeroPayrollCalendarSelection xeroConnection)
    let xeroReadyChecklist = buildXeroReadyChecklist xeroConnection xeroLatestSyncRun xeroStaffMappingRows xeroEarningsBucketRows xeroPayrollCalendarSelection
    let xeroConnectionActionsAllowed = currentUserIsCurrentVenueOwner
    fragmentHtml <- profileActionSpan "admin.xero.fragment.render" do
        pure $
            renderXeroSectionFragment xeroConnection xeroConnectedByUser xeroLatestSyncRun xeroEmployeeCount xeroEarningsRateCount xeroPayrollCalendarCount xeroEmployees xeroStaffMappingRows xeroStaffMappingCounts xeroEarningsRates xeroEarningsBucketRows xeroEarningsRateMappingCounts xeroPayrollCalendars xeroPayrollCalendarSelection xeroReadyChecklist xeroConnectionActionsAllowed
    respondHtmlProfiled $
        mconcat
            [ fragmentHtml
            , maybe mempty (\toast -> renderToastOverlayHostOob ToastBottomCenter [toast]) maybeToast
            ]

respondWithXeroStaffMappingControlsAndToast ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    XeroConnection ->
    Maybe (Id Staff) ->
    Maybe ToastOverlayConfig ->
    IO ()
respondWithXeroStaffMappingControlsAndToast connection maybeUnchangedStaffId maybeToast = do
    xeroEmployees <- profileActionSpan "admin.xero.staff_mapping.fetch_employees" (fetchCurrentVenueXeroEmployees (Just connection))
    xeroStaffMappingRows <- profileActionSpan "admin.xero.staff_mapping.fetch_rows" (fetchCurrentVenueXeroStaffMappingRows (Just connection))
    let xeroStaffMappingCounts = xeroStaffMappingCountsFor xeroStaffMappingRows
    controlsHtml <- profileActionSpan "admin.xero.staff_mapping.render_controls" do
        pure (renderXeroStaffMappingControlsOob maybeUnchangedStaffId xeroEmployees xeroStaffMappingRows xeroStaffMappingCounts)
    respondHtmlProfiled $
        mconcat
            [ controlsHtml
            , maybe mempty (\toast -> renderToastOverlayHostOob ToastBottomCenter [toast]) maybeToast
            ]

xeroSuccessToast :: Text -> ToastOverlayConfig
xeroSuccessToast message =
    ToastOverlayConfig
        { toastOverlayTitle = Just "Success"
        , toastOverlayMessage = message
        , toastOverlayClass = "app-toast-success"
        , toastOverlayAutoHideMs = 3200
        }

xeroErrorToast :: Text -> ToastOverlayConfig
xeroErrorToast message =
    ToastOverlayConfig
        { toastOverlayTitle = Just "Error"
        , toastOverlayMessage = message
        , toastOverlayClass = "app-toast-error"
        , toastOverlayAutoHideMs = 4200
        }

currentUserIsCurrentVenueOwner :: (?context :: ControllerContext) => Bool
currentUserIsCurrentVenueOwner =
    currentVenueRoleOrNothing == Just VenueOwnerRole

requireCurrentVenueOwnerForXero :: (?context :: ControllerContext, ?request :: Request) => IO () -> IO ()
requireCurrentVenueOwnerForXero action =
    if currentUserIsCurrentVenueOwner
        then action
        else do
            setErrorMessage "Only the venue owner can connect or disconnect Xero for this venue."
            redirectTo AdminAction

disconnectXeroConnection ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    XeroConnection ->
    IO ()
disconnectXeroConnection connection = do
    readXeroConfig >>= \case
        Left message -> do
            setErrorMessage message
            redirectTo AdminAction
        Right xeroConfig -> do
            refreshResult <- refreshXeroConnectionAccess xeroConfig connection
            case refreshResult of
                Left message -> do
                    setErrorMessage message
                    redirectTo AdminAction
                Right (refreshedConnection, accessToken) -> do
                    xeroClient <- currentXeroClient
                    remoteIdResult <- resolveXeroRemoteConnectionId xeroClient refreshedConnection accessToken
                    case remoteIdResult of
                        Left message -> do
                            markXeroConnectionError refreshedConnection message
                            setErrorMessage message
                            redirectTo AdminAction
                        Right remoteConnectionId -> do
                            deleteResult <- deleteXeroConnection xeroClient accessToken remoteConnectionId
                            case deleteResult of
                                Left err -> do
                                    let message = "Xero disconnect failed: " <> xeroClientErrorText err
                                    markXeroConnectionError refreshedConnection message
                                    setErrorMessage message
                                    redirectTo AdminAction
                                Right () -> completeLocalXeroDisconnect refreshedConnection remoteConnectionId

completeLocalXeroDisconnect ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    XeroConnection ->
    Text ->
    IO ()
completeLocalXeroDisconnect connection remoteConnectionId = do
    now <- getCurrentTime
    updatedConnection <- withTransaction do
        updated <- connection
            |> set #connectionStatus "disconnected"
            |> set #disconnectedByUserId (Just (unpackId currentUser.id))
            |> set #disconnectedAt (Just now)
            |> set #encryptedAccessToken Nothing
            |> set #xeroConnectionRemoteId (Just remoteConnectionId)
            |> set #lastError Nothing
            |> updateRecord
        void $ recordCurrentUserAuditEvent
            "xero_connection_disconnected"
            "xero_connections"
            (unpackId updated.id)
            (Aeson.object
                [ "tenantId" Aeson..= updated.tenantId
                , "tenantName" Aeson..= updated.tenantName
                , "xeroConnectionId" Aeson..= remoteConnectionId
                ]
            )
        pure updated
    broadcastAdminXeroInvalidation currentVenueId
    setSuccessMessage ("Disconnected Xero tenant " <> fromMaybe updatedConnection.tenantId updatedConnection.tenantName <> ".")
    redirectTo AdminAction

resolveXeroRemoteConnectionId ::
    (?modelContext :: ModelContext) =>
    XeroClient ->
    XeroConnection ->
    Text ->
    IO (Either Text Text)
resolveXeroRemoteConnectionId xeroClient connection accessToken =
    case connection.xeroConnectionRemoteId of
        Just remoteConnectionId -> pure (Right remoteConnectionId)
        Nothing -> do
            tenantsResult <- fetchConnectedTenants xeroClient accessToken
            case tenantsResult of
                Left err -> pure (Left ("Could not look up Xero connections before disconnecting: " <> xeroClientErrorText err))
                Right tenants ->
                    case List.find (\tenant -> tenant.tenantId == connection.tenantId) tenants of
                        Nothing -> pure (Left "Could not find the linked Xero organisation in Xero. The connection may already be disconnected.")
                        Just tenant -> do
                            _ <- connection
                                |> set #xeroConnectionRemoteId (Just tenant.xeroConnectionId)
                                |> updateRecord
                            pure (Right tenant.xeroConnectionId)

saveXeroStaffMapping ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    XeroConnection ->
    Id Staff ->
    Text ->
    IO ()
saveXeroStaffMapping connection staffId selection = do
    maybeStaff <- profileActionSpan "admin.xero.staff_mapping.persist.validate_staff" $
        query @Staff
            |> filterWhere (#id, staffId)
            |> filterWhere (#venueId, unpackId currentVenueId)
            |> fetchOneOrNothing
    case maybeStaff of
        Nothing -> respondWithXeroStaffMappingError connection "Choose a staff member from the current venue."
        Just staff ->
            case selection of
                "" -> persistXeroStaffMapping connection staff "unmapped" Nothing
                "not_applicable" -> persistXeroStaffMapping connection staff "not_applicable" Nothing
                xeroEmployeeId -> do
                    maybeEmployee <- profileActionSpan "admin.xero.staff_mapping.persist.validate_employee" $
                        query @XeroEmployee
                            |> filterWhere (#venueId, unpackId currentVenueId)
                            |> filterWhere (#xeroConnectionId, unpackId connection.id)
                            |> filterWhere (#xeroEmployeeId, xeroEmployeeId)
                            |> fetchOneOrNothing
                    case maybeEmployee of
                        Nothing -> respondWithXeroStaffMappingError connection "Choose a synced Xero employee from this venue."
                        Just employee -> do
                            duplicateMapping <- profileActionSpan "admin.xero.staff_mapping.persist.validate_duplicate" $
                                query @XeroStaffMapping
                                    |> filterWhere (#venueId, unpackId currentVenueId)
                                    |> filterWhere (#xeroConnectionId, unpackId connection.id)
                                    |> filterWhere (#xeroEmployeeId, Just xeroEmployeeId)
                                    |> filterWhere (#mappingStatus, "verified")
                                    |> filterWhereNot (#staffId, unpackId staff.id)
                                    |> fetchOneOrNothing
                            case duplicateMapping of
                                Just _ -> respondWithXeroStaffMappingError connection "That Xero employee is already mapped to another staff member."
                                Nothing -> persistXeroStaffMapping connection staff "verified" (Just employee)

persistXeroStaffMapping ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    XeroConnection ->
    Staff ->
    Text ->
    Maybe XeroEmployee ->
    IO ()
persistXeroStaffMapping connection staff mappingStatus maybeEmployee = do
    now <- getCurrentTime
    mapping <- profileActionSpan "admin.xero.staff_mapping.persist.upsert" $ withTransaction do
        existingMapping <-
            query @XeroStaffMapping
                |> filterWhere (#staffId, unpackId staff.id)
                |> filterWhere (#xeroConnectionId, unpackId connection.id)
                |> fetchOneOrNothing
        let prepared record =
                record
                    |> set #venueId (unpackId currentVenueId)
                    |> set #staffId (unpackId staff.id)
                    |> set #xeroConnectionId (unpackId connection.id)
                    |> set #xeroEmployeeId ((.xeroEmployeeId) <$> maybeEmployee)
                    |> set #xeroEmployeeName ((.displayName) <$> maybeEmployee)
                    |> set #xeroEmployeeEmail (maybeEmployee >>= (.email))
                    |> set #mappingStatus mappingStatus
                    |> set #lastVerifiedAt (if mappingStatus == "verified" then Just now else Nothing)
                    |> set #updatedByUserId (Just (unpackId currentUser.id))
        savedMapping <-
            case existingMapping of
                Just existing ->
                    prepared existing
                        |> updateRecord
                Nothing ->
                    prepared (newRecord @XeroStaffMapping)
                        |> set #createdByUserId (Just (unpackId currentUser.id))
                        |> createRecord
        void $ recordCurrentUserAuditEvent
            "xero_staff_mapping_saved"
            "xero_staff_mappings"
            (unpackId savedMapping.id)
            (Aeson.object
                [ "staffId" Aeson..= tshow staff.id
                , "mappingStatus" Aeson..= mappingStatus
                , "xeroEmployeeId" Aeson..= ((.xeroEmployeeId) <$> maybeEmployee)
                ]
            )
        pure savedMapping
    let message =
            case mapping.mappingStatus of
                "verified"       -> "Saved Xero employee mapping for " <> staff.firstName <> " " <> staff.lastName <> "."
                "not_applicable" -> "Marked " <> staff.firstName <> " " <> staff.lastName <> " as not paid through Xero."
                _                -> "Cleared Xero employee mapping for " <> staff.firstName <> " " <> staff.lastName <> "."
    profileActionSpan "admin.xero.staff_mapping.persist.broadcast" $
        broadcastAdminXeroInvalidation currentVenueId
    if isHtmxRequest
        then respondWithXeroStaffMappingControlsAndToast connection (Just staff.id) (Just (xeroSuccessToast message))
        else do
            setSuccessMessage message
            redirectTo AdminAction

respondWithXeroStaffMappingError ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    XeroConnection ->
    Text ->
    IO ()
respondWithXeroStaffMappingError connection message = do
    if isHtmxRequest
        then respondWithXeroStaffMappingControlsAndToast connection Nothing (Just (xeroErrorToast message))
        else do
            setErrorMessage message
            redirectTo AdminAction

saveXeroEarningsRateMapping ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    XeroConnection ->
    Text ->
    Text ->
    IO ()
saveXeroEarningsRateMapping connection localBucketKey selection = do
    buckets <- currentVenueLocalXeroEarningsBuckets
    case List.find (\bucket -> bucket.localBucketKey == localBucketKey) buckets of
        Nothing -> respondWithXeroMappingMutationError "Choose a local earning bucket from the current venue."
        Just bucket ->
            case selection of
                "" -> persistXeroEarningsRateMapping connection bucket "unmapped" Nothing
                xeroEarningsRateId -> do
                    maybeEarningsRate <-
                        query @XeroEarningsRate
                            |> filterWhere (#venueId, unpackId currentVenueId)
                            |> filterWhere (#xeroConnectionId, unpackId connection.id)
                            |> filterWhere (#xeroEarningsRateId, xeroEarningsRateId)
                            |> filterWhere (#isActive, True)
                            |> fetchOneOrNothing
                    case maybeEarningsRate of
                        Nothing -> respondWithXeroMappingMutationError "Choose a synced active Xero earnings rate from this venue."
                        Just earningsRate -> persistXeroEarningsRateMapping connection bucket "verified" (Just earningsRate)

persistXeroEarningsRateMapping ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    XeroConnection ->
    XeroLocalEarningsBucket ->
    Text ->
    Maybe XeroEarningsRate ->
    IO ()
persistXeroEarningsRateMapping connection bucket mappingStatus maybeEarningsRate = do
    now <- getCurrentTime
    mapping <- withTransaction do
        existingMapping <-
            query @XeroEarningsRateMapping
                |> filterWhere (#xeroConnectionId, unpackId connection.id)
                |> filterWhere (#localBucketKey, bucket.localBucketKey)
                |> fetchOneOrNothing
        let prepared record =
                record
                    |> set #venueId (unpackId currentVenueId)
                    |> set #xeroConnectionId (unpackId connection.id)
                    |> set #localBucketKey bucket.localBucketKey
                    |> set #localBucketLabel bucket.localBucketLabel
                    |> set #xeroEarningsRateId ((.xeroEarningsRateId) <$> maybeEarningsRate)
                    |> set #xeroEarningsRateName ((.name) <$> maybeEarningsRate)
                    |> set #mappingStatus mappingStatus
                    |> set #lastVerifiedAt (if mappingStatus == "verified" then Just now else Nothing)
                    |> set #updatedByUserId (Just (unpackId currentUser.id))
        savedMapping <-
            case existingMapping of
                Just existing -> prepared existing |> updateRecord
                Nothing ->
                    prepared (newRecord @XeroEarningsRateMapping)
                        |> set #createdByUserId (Just (unpackId currentUser.id))
                        |> createRecord
        void $ recordCurrentUserAuditEvent
            "xero_earnings_rate_mapping_saved"
            "xero_earnings_rate_mappings"
            (unpackId savedMapping.id)
            (Aeson.object
                [ "localBucketKey" Aeson..= bucket.localBucketKey
                , "localBucketLabel" Aeson..= bucket.localBucketLabel
                , "mappingStatus" Aeson..= mappingStatus
                , "xeroEarningsRateId" Aeson..= ((.xeroEarningsRateId) <$> maybeEarningsRate)
                ]
            )
        pure savedMapping
    let message =
            if mapping.mappingStatus == "verified"
                then "Saved Xero earnings-rate mapping for " <> bucket.localBucketLabel <> "."
                else "Cleared Xero earnings-rate mapping for " <> bucket.localBucketLabel <> "."
    broadcastAdminXeroInvalidation currentVenueId
    respondToXeroMappingMutationSuccess message

saveXeroPayrollCalendarSelection ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    XeroConnection ->
    Text ->
    IO ()
saveXeroPayrollCalendarSelection connection selection =
    case selection of
        "" -> persistXeroPayrollCalendarSelection connection "none" Nothing
        xeroPayrollCalendarId -> do
            maybePayrollCalendar <-
                query @XeroPayrollCalendar
                    |> filterWhere (#venueId, unpackId currentVenueId)
                    |> filterWhere (#xeroConnectionId, unpackId connection.id)
                    |> filterWhere (#xeroPayrollCalendarId, xeroPayrollCalendarId)
                    |> fetchOneOrNothing
            case maybePayrollCalendar of
                Nothing -> respondWithXeroMappingMutationError "Choose a synced Xero payroll calendar from this venue."
                Just payrollCalendar -> persistXeroPayrollCalendarSelection connection "verified" (Just payrollCalendar)

persistXeroPayrollCalendarSelection ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    XeroConnection ->
    Text ->
    Maybe XeroPayrollCalendar ->
    IO ()
persistXeroPayrollCalendarSelection connection calendarStatus maybePayrollCalendar = do
    now <- getCurrentTime
    selection <- withTransaction do
        existingSelection <-
            query @XeroPayrollCalendarSelection
                |> filterWhere (#xeroConnectionId, unpackId connection.id)
                |> fetchOneOrNothing
        let prepared record =
                record
                    |> set #venueId (unpackId currentVenueId)
                    |> set #xeroConnectionId (unpackId connection.id)
                    |> set #xeroPayrollCalendarId ((.xeroPayrollCalendarId) <$> maybePayrollCalendar)
                    |> set #xeroPayrollCalendarName ((.name) <$> maybePayrollCalendar)
                    |> set #calendarStatus calendarStatus
                    |> set #lastVerifiedAt (if calendarStatus == "verified" then Just now else Nothing)
                    |> set #updatedByUserId (Just (unpackId currentUser.id))
        savedSelection <-
            case existingSelection of
                Just existing -> prepared existing |> updateRecord
                Nothing ->
                    prepared (newRecord @XeroPayrollCalendarSelection)
                        |> set #createdByUserId (Just (unpackId currentUser.id))
                        |> createRecord
        void $ recordCurrentUserAuditEvent
            "xero_payroll_calendar_selected"
            "xero_payroll_calendar_selections"
            (unpackId savedSelection.id)
            (Aeson.object
                [ "calendarStatus" Aeson..= calendarStatus
                , "xeroPayrollCalendarId" Aeson..= ((.xeroPayrollCalendarId) <$> maybePayrollCalendar)
                ]
            )
        pure savedSelection
    let message =
            if selection.calendarStatus == "verified"
                then "Saved Xero payroll calendar selection."
                else "Cleared Xero payroll calendar selection."
    broadcastAdminXeroInvalidation currentVenueId
    respondToXeroMappingMutationSuccess message

respondToXeroMappingMutationSuccess ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Text ->
    IO ()
respondToXeroMappingMutationSuccess message =
    if isHtmxRequest
        then respondWithXeroSectionFragmentAndToast (Just (xeroSuccessToast message))
        else do
            setSuccessMessage message
            redirectTo AdminAction

respondWithXeroMappingMutationError ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Text ->
    IO ()
respondWithXeroMappingMutationError message =
    if isHtmxRequest
        then respondWithXeroSectionFragmentAndToast (Just (xeroErrorToast message))
        else do
            setErrorMessage message
            redirectTo AdminAction

validateXeroOAuthState ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    UTCTime ->
    Id User ->
    Maybe Text ->
    IO (Either Text XeroOauthState)
validateXeroOAuthState _ _ Nothing =
    pure (Left "Xero did not return OAuth state. Start the connection again.")
validateXeroOAuthState now actorUserId (Just stateToken) = do
    maybeState <-
        query @XeroOauthState
            |> filterWhere (#stateToken, stateToken)
            |> fetchOneOrNothing
    pure case maybeState of
        Nothing -> Left "Xero OAuth state is invalid. Start the connection again."
        Just oauthState
            | oauthState.venueId /= unpackId currentVenueId ->
                Left "Xero OAuth state does not match the current venue. Start the connection again."
            | oauthState.userId /= unpackId actorUserId ->
                Left "Xero OAuth state does not match the current user. Start the connection again."
            | isJust oauthState.consumedAt ->
                Left "Xero OAuth state has already been used. Start the connection again."
            | oauthState.expiresAt <= now ->
                Left "Xero OAuth state has expired. Start the connection again."
            | otherwise -> Right oauthState

completeXeroOAuthCallback ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    UTCTime ->
    Id User ->
    XeroOauthState ->
    Text ->
    IO ()
completeXeroOAuthCallback now actorUserId oauthState code =
    readXeroConfig >>= \case
        Left message -> failXeroConnectionAttempt message (Just oauthState)
        Right xeroConfig -> do
            xeroClient <- currentXeroClient
            tokenResult <- exchangeCodeForToken xeroClient xeroConfig code
            case tokenResult of
                Left err -> do
                    markXeroOAuthStateConsumed oauthState now
                    failXeroConnectionAttempt ("Xero token exchange failed: " <> xeroClientErrorText err) (Just oauthState)
                Right tokenResponse -> do
                    tenantsResult <- fetchConnectedTenants xeroClient tokenResponse.accessToken
                    case tenantsResult of
                        Left err -> do
                            markXeroOAuthStateConsumed oauthState now
                            failXeroConnectionAttempt ("Xero tenant lookup failed: " <> xeroClientErrorText err) (Just oauthState)
                        Right [] -> do
                            markXeroOAuthStateConsumed oauthState now
                            failXeroConnectionAttempt "Xero returned no connected tenants." (Just oauthState)
                        Right tenants -> do
                            tenant <- chooseXeroTenantForOAuth tenants
                            connection <- persistCompletedXeroConnection now actorUserId xeroConfig oauthState tokenResponse tenant
                            setSuccessMessage ("Connected Xero tenant " <> fromMaybe connection.tenantId connection.tenantName <> ".")
                            redirectTo AdminAction

persistCompletedXeroConnection ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    UTCTime ->
    Id User ->
    XeroConfig ->
    XeroOauthState ->
    XeroTokenResponse ->
    XeroTenant ->
    IO XeroConnection
persistCompletedXeroConnection now actorUserId xeroConfig oauthState tokenResponse tenant = do
    encryptedRefreshToken <- encryptXeroToken xeroConfig.tokenEncryptionKey tokenResponse.refreshToken
    encryptedAccessToken <- encryptXeroToken xeroConfig.tokenEncryptionKey tokenResponse.accessToken
    let accessTokenExpiresAt = addUTCTime (fromIntegral tokenResponse.expiresIn) now
    withTransaction do
        existingSameTenant <-
            query @XeroConnection
                |> filterWhere (#venueId, unpackId currentVenueId)
                |> filterWhere (#tenantId, tenant.tenantId)
                |> orderByDesc #connectedAt
                |> fetchOneOrNothing
        activeConnections <-
            query @XeroConnection
                |> filterWhere (#venueId, unpackId currentVenueId)
                |> filterWhere (#connectionStatus, "active" :: Text)
                |> fetch
        forM_ activeConnections \connection ->
            when (Just connection.id /= ((.id) <$> existingSameTenant)) do
                connection
                    |> set #connectionStatus "disconnected"
                    |> set #disconnectedByUserId (Just (unpackId actorUserId))
                    |> set #disconnectedAt (Just now)
                    |> set #lastError (Just "Superseded by reconnect")
                    |> updateRecord
                    |> void
        updatedState <- oauthState
            |> set #consumedAt (Just now)
            |> updateRecord
        let fillConnection record =
                record
                    |> set #venueId (unpackId currentVenueId)
                    |> set #tenantId tenant.tenantId
                    |> set #tenantName tenant.tenantName
                    |> set #xeroConnectionRemoteId (Just tenant.xeroConnectionId)
                    |> set #connectionStatus ("active" :: Text)
                    |> set #scopes (fromMaybe updatedState.requestedScopes tokenResponse.scope)
                    |> set #encryptedRefreshToken encryptedRefreshToken
                    |> set #encryptedAccessToken (Just encryptedAccessToken)
                    |> set #accessTokenExpiresAt (Just accessTokenExpiresAt)
                    |> set #lastRefreshedAt (Just now)
                    |> set #lastError Nothing
                    |> set #connectedByUserId (Just (unpackId actorUserId))
                    |> set #connectedAt now
                    |> set #disconnectedByUserId Nothing
                    |> set #disconnectedAt Nothing
        connection <-
            case existingSameTenant of
                Just existing -> fillConnection existing |> updateRecord
                Nothing       -> fillConnection (newRecord @XeroConnection) |> createRecord
        void $ recordCurrentUserAuditEvent
            "xero_connection_completed"
            "xero_connections"
            (unpackId connection.id)
            (Aeson.object
                [ "tenantId" Aeson..= connection.tenantId
                , "tenantName" Aeson..= connection.tenantName
                , "xeroConnectionId" Aeson..= connection.xeroConnectionRemoteId
                , "scopes" Aeson..= connection.scopes
                , "stateId" Aeson..= unpackId updatedState.id
                ]
            )
        pure connection

chooseXeroTenantForOAuth ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    [XeroTenant] ->
    IO XeroTenant
chooseXeroTenantForOAuth tenants = do
    existingConnection <- fetchCurrentVenueXeroConnection
    pure case (existingConnection >>= \connection -> List.find (\tenant -> tenant.tenantId == connection.tenantId) tenants, tenants) of
        (Just tenant, _) -> tenant
        (Nothing, tenant : _) -> tenant
        (Nothing, []) -> error "chooseXeroTenantForOAuth called without tenants"

markXeroOAuthStateConsumed ::
    (?modelContext :: ModelContext) =>
    XeroOauthState ->
    UTCTime ->
    IO XeroOauthState
markXeroOAuthStateConsumed oauthState now =
    oauthState
        |> set #consumedAt (Just now)
        |> updateRecord

failXeroConnectionAttempt ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Text ->
    Maybe XeroOauthState ->
    IO ()
failXeroConnectionAttempt message maybeState = do
    void $ recordCurrentUserAuditEvent
        "xero_connection_failed"
        "xero_connections"
        (maybe (unpackId currentVenueId) (unpackId . (.id)) maybeState)
        (Aeson.object
            [ "failure" Aeson..= message
            , "stateId" Aeson..= fmap (unpackId . (.id)) maybeState
            ]
        )
    setErrorMessage message
    redirectTo AdminAction

syncXeroPayrollReferenceData ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    XeroConnection ->
    IO ()
syncXeroPayrollReferenceData connection = do
    now <- getCurrentTime
    syncRun <-
        newRecord @XeroSyncRun
            |> set #venueId (unpackId currentVenueId)
            |> set #xeroConnectionId (unpackId connection.id)
            |> set #syncStatus ("running" :: Text)
            |> set #syncKind ("payroll_reference_data" :: Text)
            |> set #startedAt now
            |> createRecord
    readXeroConfig >>= \case
        Left message -> failXeroReferenceSync syncRun connection message
        Right xeroConfig -> do
            refreshResult <- refreshXeroConnectionAccess xeroConfig connection
            case refreshResult of
                Left message -> failXeroReferenceSync syncRun connection message
                Right (refreshedConnection, accessToken) -> do
                    xeroClient <- currentXeroClient
                    employeesResult <- fetchPayrollEmployees xeroClient accessToken refreshedConnection.tenantId
                    earningsRatesResult <- fetchEarningsRates xeroClient accessToken refreshedConnection.tenantId
                    payrollCalendarsResult <- fetchPayrollCalendars xeroClient accessToken refreshedConnection.tenantId
                    case (employeesResult, earningsRatesResult, payrollCalendarsResult) of
                        (Right employees, Right earningsRates, Right payrollCalendars) -> do
                            completeXeroReferenceSync syncRun refreshedConnection employees earningsRates payrollCalendars
                        (Left err, _, _) ->
                            failXeroReferenceSync syncRun refreshedConnection ("Xero employee sync failed: " <> xeroClientErrorText err)
                        (_, Left err, _) ->
                            failXeroReferenceSync syncRun refreshedConnection ("Xero earnings-rate sync failed: " <> xeroClientErrorText err)
                        (_, _, Left err) ->
                            failXeroReferenceSync syncRun refreshedConnection ("Xero payroll-calendar sync failed: " <> xeroClientErrorText err)

completeXeroReferenceSync ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    XeroSyncRun ->
    XeroConnection ->
    [XeroEmployeeRef] ->
    [XeroEarningsRateRef] ->
    [XeroPayrollCalendarRef] ->
    IO ()
completeXeroReferenceSync syncRun connection employees earningsRates payrollCalendars = do
    now <- getCurrentTime
    withTransaction do
        mapM_ (upsertXeroEmployee connection now) employees
        mapM_ (upsertXeroEarningsRate connection now) earningsRates
        mapM_ (upsertXeroPayrollCalendar connection now) payrollCalendars
        markStaleXeroStaffMappings connection employees
        markStaleXeroEarningsRateMappings connection earningsRates
        markStaleXeroPayrollCalendarSelection connection payrollCalendars
        _ <- syncRun
            |> set #syncStatus ("succeeded" :: Text)
            |> set #employeesCount (length employees)
            |> set #earningsRatesCount (length earningsRates)
            |> set #payrollCalendarsCount (length payrollCalendars)
            |> set #finishedAt (Just now)
            |> updateRecord
        _ <- connection
            |> set #lastSyncAt (Just now)
            |> set #lastError Nothing
            |> updateRecord
        void $ recordCurrentUserAuditEvent
            "xero_reference_sync_succeeded"
            "xero_sync_runs"
            (unpackId syncRun.id)
            (Aeson.object
                [ "tenantId" Aeson..= connection.tenantId
                , "employeesCount" Aeson..= length employees
                , "earningsRatesCount" Aeson..= length earningsRates
                , "payrollCalendarsCount" Aeson..= length payrollCalendars
                ]
            )
    setSuccessMessage ("Synced Xero payroll reference data: " <> tshow (length employees) <> " employees, " <> tshow (length earningsRates) <> " earnings rates, " <> tshow (length payrollCalendars) <> " payroll calendars.")
    broadcastAdminXeroInvalidation currentVenueId
    if isHtmxRequest
        then respondWithXeroSectionFragment
        else redirectTo AdminAction

markStaleXeroStaffMappings ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    XeroConnection ->
    [XeroEmployeeRef] ->
    IO ()
markStaleXeroStaffMappings connection employees = do
    let activeEmployeeIds = map (\employee -> employee.xeroEmployeeId) employees
    mappings <-
        query @XeroStaffMapping
            |> filterWhere (#venueId, unpackId currentVenueId)
            |> filterWhere (#xeroConnectionId, unpackId connection.id)
            |> filterWhere (#mappingStatus, "verified" :: Text)
            |> fetch
    forM_ mappings \mapping ->
        case mapping.xeroEmployeeId of
            Just employeeId | employeeId `elem` activeEmployeeIds -> pure ()
            _ ->
                mapping
                    |> set #mappingStatus "stale"
                    |> set #lastVerifiedAt Nothing
                    |> updateRecord
                    |> void

markStaleXeroEarningsRateMappings ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    XeroConnection ->
    [XeroEarningsRateRef] ->
    IO ()
markStaleXeroEarningsRateMappings connection earningsRates = do
    let activeEarningsRateIds = map (\earningsRate -> earningsRate.xeroEarningsRateId) earningsRates
    mappings <-
        query @XeroEarningsRateMapping
            |> filterWhere (#venueId, unpackId currentVenueId)
            |> filterWhere (#xeroConnectionId, unpackId connection.id)
            |> filterWhere (#mappingStatus, "verified" :: Text)
            |> fetch
    forM_ mappings \mapping ->
        case mapping.xeroEarningsRateId of
            Just earningsRateId | earningsRateId `elem` activeEarningsRateIds -> pure ()
            _ ->
                mapping
                    |> set #mappingStatus "stale"
                    |> set #lastVerifiedAt Nothing
                    |> updateRecord
                    |> void

markStaleXeroPayrollCalendarSelection ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    XeroConnection ->
    [XeroPayrollCalendarRef] ->
    IO ()
markStaleXeroPayrollCalendarSelection connection payrollCalendars = do
    let activePayrollCalendarIds = map (\payrollCalendar -> payrollCalendar.xeroPayrollCalendarId) payrollCalendars
    maybeSelection <-
        query @XeroPayrollCalendarSelection
            |> filterWhere (#venueId, unpackId currentVenueId)
            |> filterWhere (#xeroConnectionId, unpackId connection.id)
            |> filterWhere (#calendarStatus, "verified" :: Text)
            |> fetchOneOrNothing
    case maybeSelection of
        Just selection ->
            case selection.xeroPayrollCalendarId of
                Just payrollCalendarId
                    | payrollCalendarId `notElem` activePayrollCalendarIds ->
                        selection
                            |> set #calendarStatus "stale"
                            |> set #lastVerifiedAt Nothing
                            |> updateRecord
                            |> void
                _ -> pure ()
        Nothing -> pure ()

failXeroReferenceSync ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    XeroSyncRun ->
    XeroConnection ->
    Text ->
    IO ()
failXeroReferenceSync syncRun connection message = do
    now <- getCurrentTime
    withTransaction do
        latestConnection <- fetch connection.id
        _ <- syncRun
            |> set #syncStatus ("failed" :: Text)
            |> set #errorMessage (Just message)
            |> set #finishedAt (Just now)
            |> updateRecord
        _ <- latestConnection
            |> set #lastError (Just message)
            |> updateRecord
        void $ recordCurrentUserAuditEvent
            "xero_reference_sync_failed"
            "xero_sync_runs"
            (unpackId syncRun.id)
            (Aeson.object
                [ "tenantId" Aeson..= connection.tenantId
                , "failure" Aeson..= message
                ]
            )
    setErrorMessage message
    broadcastAdminXeroInvalidation currentVenueId
    if isHtmxRequest
        then respondWithXeroSectionFragment
        else redirectTo AdminAction

upsertXeroEmployee :: (?context :: ControllerContext, ?modelContext :: ModelContext) => XeroConnection -> UTCTime -> XeroEmployeeRef -> IO XeroEmployee
upsertXeroEmployee connection syncedAt employee = do
    existing <-
        query @XeroEmployee
            |> filterWhere (#xeroConnectionId, unpackId connection.id)
            |> filterWhere (#xeroEmployeeId, employee.xeroEmployeeId)
            |> fetchOneOrNothing
    let fillRecord record =
            record
                |> set #venueId (unpackId currentVenueId)
                |> set #xeroConnectionId (unpackId connection.id)
                |> set #xeroEmployeeId employee.xeroEmployeeId
                |> set #displayName employee.xeroEmployeeName
                |> set #email employee.xeroEmployeeEmail
                |> set #status employee.xeroEmployeeStatus
                |> set #payrollCalendarId employee.xeroEmployeeCalendarId
                |> set #rawPayload employee.xeroEmployeeRaw
                |> set #syncedAt syncedAt
    case existing of
        Just record -> fillRecord record |> updateRecord
        Nothing     -> fillRecord (newRecord @XeroEmployee) |> createRecord

upsertXeroEarningsRate :: (?context :: ControllerContext, ?modelContext :: ModelContext) => XeroConnection -> UTCTime -> XeroEarningsRateRef -> IO XeroEarningsRate
upsertXeroEarningsRate connection syncedAt earningsRate = do
    existing <-
        query @XeroEarningsRate
            |> filterWhere (#xeroConnectionId, unpackId connection.id)
            |> filterWhere (#xeroEarningsRateId, earningsRate.xeroEarningsRateId)
            |> fetchOneOrNothing
    let fillRecord record =
            record
                |> set #venueId (unpackId currentVenueId)
                |> set #xeroConnectionId (unpackId connection.id)
                |> set #xeroEarningsRateId earningsRate.xeroEarningsRateId
                |> set #name earningsRate.xeroEarningsRateName
                |> set #earningsType earningsRate.xeroEarningsRateType
                |> set #rateType earningsRate.xeroEarningsRateRateType
                |> set #accountCode earningsRate.xeroEarningsRateAccountCode
                |> set #isActive earningsRate.xeroEarningsRateIsActive
                |> set #rawPayload earningsRate.xeroEarningsRateRaw
                |> set #syncedAt syncedAt
    case existing of
        Just record -> fillRecord record |> updateRecord
        Nothing     -> fillRecord (newRecord @XeroEarningsRate) |> createRecord

upsertXeroPayrollCalendar :: (?context :: ControllerContext, ?modelContext :: ModelContext) => XeroConnection -> UTCTime -> XeroPayrollCalendarRef -> IO XeroPayrollCalendar
upsertXeroPayrollCalendar connection syncedAt payrollCalendar = do
    existing <-
        query @XeroPayrollCalendar
            |> filterWhere (#xeroConnectionId, unpackId connection.id)
            |> filterWhere (#xeroPayrollCalendarId, payrollCalendar.xeroPayrollCalendarId)
            |> fetchOneOrNothing
    let fillRecord record =
            record
                |> set #venueId (unpackId currentVenueId)
                |> set #xeroConnectionId (unpackId connection.id)
                |> set #xeroPayrollCalendarId payrollCalendar.xeroPayrollCalendarId
                |> set #name payrollCalendar.xeroPayrollCalendarName
                |> set #calendarType payrollCalendar.xeroPayrollCalendarType
                |> set #startDate payrollCalendar.xeroPayrollCalendarStartDate
                |> set #paymentDate payrollCalendar.xeroPayrollCalendarPaymentDate
                |> set #rawPayload payrollCalendar.xeroPayrollCalendarRaw
                |> set #syncedAt syncedAt
    case existing of
        Just record -> fillRecord record |> updateRecord
        Nothing     -> fillRecord (newRecord @XeroPayrollCalendar) |> createRecord

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
