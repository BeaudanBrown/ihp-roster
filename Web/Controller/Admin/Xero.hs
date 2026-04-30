module Web.Controller.Admin.Xero where

import Application.Helper.LiveUpdate
import Application.Helper.Profiling
import Application.Helper.View (ToastOverlayConfig (..),
                                ToastOverlayPosition (ToastBottomCenter),
                                errorToast, renderToastOverlayHostOob,
                                successToast)
import Application.Helper.Xero
import Application.Helper.XeroAdminTypes
import Application.Helper.XeroPayItems
import Application.Xero.Connection
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import qualified Data.Char as Char
import qualified Data.List as List
import qualified Data.Maybe as Maybe
import Data.Scientific (Scientific)
import qualified Data.Text as Text
import Data.Time.Format (defaultTimeLocale, formatTime)
import qualified Text.Blaze.Html as Blaze
import Web.Controller.Prelude
import Web.View.Admin.Xero

startXeroConnectionAction :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => IO ()
startXeroConnectionAction =
    requireCurrentVenueOwnerForXero do
        readXeroConfig >>= \case
            Left message -> do
                setErrorMessage message
                redirectTo XeroAction
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

xeroOAuthCallbackAction :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => IO ()
xeroOAuthCallbackAction =
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

disconnectXeroConnectionAction :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => IO ()
disconnectXeroConnectionAction =
    requireCurrentVenueOwnerForXero do
        maybeConnection <- fetchCurrentVenueXeroConnection
        case maybeConnection of
            Nothing -> do
                setErrorMessage "Xero is not connected for this venue."
                redirectTo XeroAction
            Just connection ->
                disconnectXeroConnection connection

syncXeroPayrollReferenceDataAction :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => IO ()
syncXeroPayrollReferenceDataAction = do
    maybeConnection <- fetchActiveCurrentVenueXeroConnection
    case maybeConnection of
        Nothing -> do
            setErrorMessage "Connect Xero before syncing payroll reference data."
            if isHtmxRequest
                then respondWithXeroSectionFragment
                else redirectTo XeroAction
        Just connection -> syncXeroPayrollReferenceData connection

createMissingXeroPayItemsAction :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => IO ()
createMissingXeroPayItemsAction =
    if not currentUserCanManageXeroIntegration
        then respondWithXeroMappingMutationError "Only the venue owner or a super admin can create pay items in Xero."
        else do
            maybeConnection <- fetchActiveCurrentVenueXeroConnection
            case maybeConnection of
                Nothing -> respondWithXeroMappingMutationError "Connect Xero before creating pay items."
                Just connection -> createMissingXeroPayItems connection

saveXeroStaffMappingAction :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => IO ()
saveXeroStaffMappingAction = do
    maybeConnection <- fetchCurrentVenueXeroConnection
    case maybeConnection of
        Nothing -> do
            setErrorMessage "Connect Xero before mapping staff to Xero employees."
            if isHtmxRequest
                then respondWithXeroSectionFragment
                else redirectTo XeroAction
        Just connection -> do
            let staffId = param @(Id Staff) "staffId"
            let selection = Text.strip (paramOrDefault @Text "" "xeroEmployeeSelection")
            saveXeroStaffMapping connection staffId selection

suggestXeroStaffMappingAction :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id Staff -> IO ()
suggestXeroStaffMappingAction staffId = do
    maybeConnection <- fetchCurrentVenueXeroConnection
    case maybeConnection of
        Nothing -> do
            setErrorMessage "Connect Xero before mapping staff to Xero employees."
            if isHtmxRequest
                then respondWithXeroSectionFragment
                else redirectTo XeroAction
        Just connection ->
            suggestXeroStaffMapping connection staffId

saveXeroEarningsRateMappingAction :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => IO ()
saveXeroEarningsRateMappingAction = do
    maybeConnection <- fetchCurrentVenueXeroConnection
    case maybeConnection of
        Nothing -> do
            setErrorMessage "Connect Xero before mapping earning buckets to Xero earnings rates."
            if isHtmxRequest
                then respondWithXeroSectionFragment
                else redirectTo XeroAction
        Just connection -> do
            let localBucketKey = Text.strip (paramOrDefault @Text "" "localBucketKey")
            let selection = Text.strip (paramOrDefault @Text "" "xeroEarningsRateSelection")
            saveXeroEarningsRateMapping connection localBucketKey selection

saveXeroPayItemAccountCodeSelectionAction :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => IO ()
saveXeroPayItemAccountCodeSelectionAction =
    if not currentUserCanManageXeroIntegration
        then respondWithXeroMappingMutationError "Only the venue owner or a super admin can choose the Xero pay item account code."
        else do
            maybeConnection <- fetchCurrentVenueXeroConnection
            case maybeConnection of
                Nothing -> do
                    setErrorMessage "Connect Xero before choosing a pay item account code."
                    if isHtmxRequest
                        then respondWithXeroSectionFragment
                        else redirectTo XeroAction
                Just connection -> do
                    let selection = Text.strip (paramOrDefault @Text "" "xeroPayItemAccountCodeSelection")
                    saveXeroPayItemAccountCodeSelection connection selection

saveXeroPayrollCalendarSelectionAction :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => IO ()
saveXeroPayrollCalendarSelectionAction = do
    maybeConnection <- fetchCurrentVenueXeroConnection
    case maybeConnection of
        Nothing -> do
            setErrorMessage "Connect Xero before selecting a payroll calendar."
            if isHtmxRequest
                then respondWithXeroSectionFragment
                else redirectTo XeroAction
        Just connection -> do
            let selection = Text.strip (paramOrDefault @Text "" "xeroPayrollCalendarSelection")
            saveXeroPayrollCalendarSelection connection selection

broadcastAdminXeroInvalidation ::
    (?context :: ControllerContext, ?request :: Request) =>
    Id Venue ->
    IO ()
broadcastAdminXeroInvalidation venueId =
    broadcastLiveResync
        (adminXeroScope venueId)
        liveUpdateSourceClientId

adminXeroScope :: Id Venue -> LiveUpdateScope
adminXeroScope venueId =
    AdminXeroScope
        { venueId = unpackId venueId
        }

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

fetchCurrentVenueXeroPayItemAccountCodeOptions :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Maybe XeroConnection -> IO [Text]
fetchCurrentVenueXeroPayItemAccountCodeOptions maybeConnection = do
    xeroEarningsRates <- fetchCurrentVenueXeroEarningsRates maybeConnection
    pure
        (xeroEarningsRates
            |> map (.accountCode)
            |> catMaybes
            |> map Text.strip
            |> filter (not . Text.null)
            |> List.nub
            |> List.sort)

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

fetchCurrentVenueXeroPayItemAccountCodeSelection :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Maybe XeroConnection -> IO (Maybe XeroPayItemAccountCodeSelection)
fetchCurrentVenueXeroPayItemAccountCodeSelection maybeConnection =
    case maybeConnection of
        Nothing -> pure Nothing
        Just connection ->
            query @XeroPayItemAccountCodeSelection
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

fetchCurrentVenueXeroPayItemRequirements :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Maybe XeroConnection -> [XeroEarningsRate] -> IO [XeroPayItemRequirement]
fetchCurrentVenueXeroPayItemRequirements maybeConnection xeroEarningsRates =
    case maybeConnection of
        Nothing -> pure []
        Just connection -> do
            today <- utctDay <$> getCurrentTime
            usedScopes <- fetchCurrentVenueXeroUsedAwardPayScopes
            awardLevels <-
                query @AwardLevel
                    |> filterWhere (#isActive, True)
                    |> orderBy #classification
                    |> fetch
            awardLevelBaseRates <-
                query @AwardLevelBaseRate
                    |> orderBy #createdAt
                    |> fetch
            awardLevelPenaltyRates <-
                query @AwardLevelPenaltyRate
                    |> orderBy #createdAt
                    |> fetch
            awardTimePenaltyAllowances <-
                query @AwardTimePenaltyAllowance
                    |> orderBy #createdAt
                    |> fetch
            let requirements = deriveXeroPayItemRequirements today usedScopes awardLevels awardLevelBaseRates awardLevelPenaltyRates awardTimePenaltyAllowances xeroEarningsRates
            syncXeroPayItemRequirementRecords connection.id currentVenueId (Just currentUser.id) requirements

currentVenueLocalXeroEarningsBuckets :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO [XeroLocalEarningsBucket]
currentVenueLocalXeroEarningsBuckets = do
    today <- utctDay <$> getCurrentTime
    usedScopes <- fetchCurrentVenueXeroUsedAwardPayScopes
    awardLevels <-
        query @AwardLevel
            |> filterWhere (#isActive, True)
            |> orderBy #classification
            |> fetch
    awardLevelBaseRates <-
        query @AwardLevelBaseRate
            |> orderBy #createdAt
            |> fetch
    awardLevelPenaltyRates <-
        query @AwardLevelPenaltyRate
            |> orderBy #createdAt
            |> fetch
    awardTimePenaltyAllowances <-
        query @AwardTimePenaltyAllowance
            |> orderBy #createdAt
            |> fetch
    pure (deriveXeroLocalEarningsBuckets today usedScopes awardLevels awardLevelBaseRates awardLevelPenaltyRates awardTimePenaltyAllowances)

fetchCurrentVenueXeroUsedAwardPayScopes :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO [XeroUsedAwardPayScope]
fetchCurrentVenueXeroUsedAwardPayScopes = do
    staffMembers <-
        query @Staff
            |> filterWhere (#venueId, unpackId currentVenueId)
            |> filterWhere (#isActive, True)
            |> filterWhere (#archivedAt, Nothing)
            |> fetch
    shiftTypes <-
        query @ShiftType
            |> filterWhere (#venueId, unpackId currentVenueId)
            |> filterWhere (#isActive, True)
            |> filterWhere (#archivedAt, Nothing)
            |> fetch
    pure (deriveXeroUsedAwardPayScopes staffMembers shiftTypes)

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
            xeroEmployees <- fetchCurrentVenueXeroEmployees (Just connection)
            rows <- forM staffMembers \staff -> do
                maybeUser <- fetchStaffLinkedUser staff
                mapping <- ensureDefaultXeroStaffMapping connection staff (List.find (\mapping -> mapping.staffId == unpackId staff.id) mappings)
                pure XeroStaffMappingRow
                    { mappingRowStaff = staff
                    , mappingRowUser = maybeUser
                    , mappingRowMapping = mapping
                    , mappingRowSuggestedEmployee = Nothing
                    }
            pure (attachXeroStaffMappingSuggestions xeroEmployees rows)

ensureDefaultXeroStaffMapping :: (?context :: ControllerContext, ?modelContext :: ModelContext) => XeroConnection -> Staff -> Maybe XeroStaffMapping -> IO XeroStaffMapping
ensureDefaultXeroStaffMapping _ _ (Just mapping) =
    pure mapping
ensureDefaultXeroStaffMapping connection staff Nothing =
    newRecord @XeroStaffMapping
        |> set #venueId (unpackId currentVenueId)
        |> set #staffId (unpackId staff.id)
        |> set #xeroConnectionId (unpackId connection.id)
        |> set #mappingStatus ("not_applicable" :: Text)
        |> createRecord

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
        , xeroStaffNotApplicableCount = countStatus "not_applicable"
        , xeroStaffStaleCount = countStatus "stale"
        , xeroStaffPossibleMatchCount = length (filter (isJust . (.mappingRowSuggestedEmployee)) rows)
        }
    where
        mappingStatus row = row.mappingRowMapping.mappingStatus
        countStatus status = length (filter (\row -> mappingStatus row == status) rows)

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

buildXeroReadyChecklist :: Maybe XeroConnection -> Maybe XeroSyncRun -> [XeroStaffMappingRow] -> [XeroEarningsBucketRow] -> [XeroPayItemRequirement] -> Maybe XeroPayrollCalendarSelection -> Maybe XeroPayItemAccountCodeSelection -> XeroReadyChecklist
buildXeroReadyChecklist maybeConnection maybeSyncRun staffRows earningsRows payItemRequirements maybeCalendarSelection maybePayItemAccountCodeSelection =
    XeroReadyChecklist
        { xeroReadyConnection = maybe False (\connection -> connection.connectionStatus == "active") maybeConnection
        , xeroReadyReferenceSync = maybe False (\syncRun -> syncRun.syncStatus == "succeeded") maybeSyncRun
        , xeroReadyStaffMappings = not (null staffRows) && all staffRowReady staffRows
        , xeroReadyEarningsMappings = not (null earningsRows) && all earningsRowReady earningsRows
        , xeroReadyManagedPayItems = not (null activeRequirements) && all payItemRequirementReady activeRequirements
        , xeroReadyPayItemAccountCode = maybe False (\selection -> selection.selectionStatus == "verified" && maybe False (not . Text.null . Text.strip) selection.accountCode) maybePayItemAccountCodeSelection
        , xeroReadyPayrollCalendar = maybe False (\selection -> selection.calendarStatus == "verified" && isJust selection.xeroPayrollCalendarId) maybeCalendarSelection
        , xeroReadyStaffVerifiedCount = length (filter staffRowReady staffRows)
        , xeroReadyStaffTotalCount = length staffRows
        , xeroReadyEarningsVerifiedCount = length (filter earningsRowReady earningsRows)
        , xeroReadyEarningsTotalCount = length earningsRows
        , xeroReadyManagedPayItemReadyCount = length (filter payItemRequirementReady activeRequirements)
        , xeroReadyManagedPayItemTotalCount = length activeRequirements
        }
    where
        staffRowReady row =
            row.mappingRowMapping.mappingStatus == "verified" || row.mappingRowMapping.mappingStatus == "not_applicable"
        earningsRowReady row =
            maybe False (\mapping -> mapping.mappingStatus == "verified" && isJust mapping.xeroEarningsRateId) row.earningsBucketRowMapping
        activeRequirements = filter (\requirement -> requirement.payItemRequirementStatus /= "ignored") payItemRequirements
        payItemRequirementReady requirement =
            requirement.payItemRequirementStatus `elem` ["matched", "created"]

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
    xeroSectionData <- fetchCurrentVenueXeroAdminSectionData
    fragmentHtml <- profileActionSpan "admin.xero.fragment.render" do
        pure (renderXeroSectionFragment xeroSectionData)
    respondHtmlProfiled $
        mconcat
            [ fragmentHtml
            , maybe mempty (\toast -> renderToastOverlayHostOob ToastBottomCenter [toast]) maybeToast
            ]

fetchCurrentVenueXeroAdminSectionData ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    IO XeroAdminSectionData
fetchCurrentVenueXeroAdminSectionData = do
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
    xeroPayItemRequirements <- profileActionSpan "admin.xero.pay_items.fetch_requirements" (fetchCurrentVenueXeroPayItemRequirements xeroConnection xeroEarningsRates)
    xeroPayrollCalendars <- profileActionSpan "admin.xero.calendar.fetch_calendars" (fetchCurrentVenueXeroPayrollCalendars xeroConnection)
    xeroPayrollCalendarSelection <- profileActionSpan "admin.xero.calendar.fetch_selection" (fetchCurrentVenueXeroPayrollCalendarSelection xeroConnection)
    xeroPayItemAccountCodeSelection <- profileActionSpan "admin.xero.pay_item_account_code.fetch_selection" (fetchCurrentVenueXeroPayItemAccountCodeSelection xeroConnection)
    let xeroReadyChecklist = buildXeroReadyChecklist xeroConnection xeroLatestSyncRun xeroStaffMappingRows xeroEarningsBucketRows xeroPayItemRequirements xeroPayrollCalendarSelection xeroPayItemAccountCodeSelection
    let xeroConnectionActionsAllowed = currentUserCanManageXeroIntegration
    pure XeroAdminSectionData { .. }

renderCurrentVenueXeroSectionFragmentOob ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    IO Blaze.Html
renderCurrentVenueXeroSectionFragmentOob = do
    xeroSectionData <- fetchCurrentVenueXeroAdminSectionData
    profileActionSpan "admin.xero.fragment.render_oob" do
        pure (renderXeroSectionFragmentOob xeroSectionData)

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
xeroSuccessToast = successToast

xeroErrorToast :: Text -> ToastOverlayConfig
xeroErrorToast = errorToast

currentUserCanManageXeroIntegration :: (?context :: ControllerContext) => Bool
currentUserCanManageXeroIntegration = hasRole VenueOwnerRole

requireCurrentVenueOwnerForXero :: (?context :: ControllerContext, ?request :: Request) => IO () -> IO ()
requireCurrentVenueOwnerForXero action =
    if currentUserCanManageXeroIntegration
        then action
        else do
            setErrorMessage "Only the venue owner or a super admin can manage Xero for this venue."
            redirectToPath permissionDeniedFallbackPath

disconnectXeroConnection ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    XeroConnection ->
    IO ()
disconnectXeroConnection connection = do
    readXeroConfig >>= \case
        Left message -> do
            setErrorMessage message
            redirectTo XeroAction
        Right xeroConfig -> do
            refreshResult <- refreshXeroConnectionAccess xeroConfig connection
            case refreshResult of
                Left message -> do
                    setErrorMessage message
                    redirectTo XeroAction
                Right (refreshedConnection, accessToken) -> do
                    xeroClient <- currentXeroClient
                    remoteIdResult <- resolveXeroRemoteConnectionId xeroClient refreshedConnection accessToken
                    case remoteIdResult of
                        Left message -> do
                            markXeroConnectionError refreshedConnection message
                            setErrorMessage message
                            redirectTo XeroAction
                        Right remoteConnectionId -> do
                            deleteResult <- deleteXeroConnection xeroClient accessToken remoteConnectionId
                            case deleteResult of
                                Left err -> do
                                    let message = "Xero disconnect failed: " <> xeroClientErrorText err
                                    markXeroConnectionError refreshedConnection message
                                    setErrorMessage message
                                    redirectTo XeroAction
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
    redirectTo XeroAction

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
                "" -> persistXeroStaffMapping connection staff "not_applicable" Nothing
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

suggestXeroStaffMapping ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    XeroConnection ->
    Id Staff ->
    IO ()
suggestXeroStaffMapping connection staffId = do
    mappingRows <- fetchCurrentVenueXeroStaffMappingRows (Just connection)
    xeroEmployees <- fetchCurrentVenueXeroEmployees (Just connection)
    case List.find (\row -> row.mappingRowStaff.id == staffId) mappingRows of
        Nothing -> respondWithXeroStaffMappingError connection "Choose a staff member from the current venue."
        Just row -> do
            let availableEmployees = filter (xeroEmployeeAvailableForStaff row.mappingRowStaff mappingRows) xeroEmployees
            case bestXeroEmployeeSuggestion row availableEmployees of
                NoXeroEmployeeSuggestion -> respondWithXeroStaffMappingError connection ("No close Xero employee match found for " <> staffFullNameText row.mappingRowStaff <> ".")
                AmbiguousXeroEmployeeSuggestion first second ->
                    respondWithXeroStaffMappingError connection ("Xero employee match for " <> staffFullNameText row.mappingRowStaff <> " is ambiguous between " <> first.displayName <> " and " <> second.displayName <> ".")
                XeroEmployeeSuggestion employee ->
                    persistXeroStaffMappingWithControlRefresh connection row.mappingRowStaff "verified" (Just employee) Nothing

persistXeroStaffMapping ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    XeroConnection ->
    Staff ->
    Text ->
    Maybe XeroEmployee ->
    IO ()
persistXeroStaffMapping connection staff mappingStatus maybeEmployee =
    persistXeroStaffMappingWithControlRefresh connection staff mappingStatus maybeEmployee (Just staff.id)

persistXeroStaffMappingWithControlRefresh ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    XeroConnection ->
    Staff ->
    Text ->
    Maybe XeroEmployee ->
    Maybe (Id Staff) ->
    IO ()
persistXeroStaffMappingWithControlRefresh connection staff mappingStatus maybeEmployee maybeUnchangedStaffId = do
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
        then respondWithXeroStaffMappingControlsAndToast connection maybeUnchangedStaffId (Just (xeroSuccessToast message))
        else do
            setSuccessMessage message
            redirectTo XeroAction

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
            redirectTo XeroAction

data XeroEmployeeSuggestionResult
    = NoXeroEmployeeSuggestion
    | AmbiguousXeroEmployeeSuggestion XeroEmployee XeroEmployee
    | XeroEmployeeSuggestion XeroEmployee

data ScoredXeroEmployeeSuggestion = ScoredXeroEmployeeSuggestion
    { scoredSuggestionEmployee :: XeroEmployee
    , scoredSuggestionScore    :: Double
    }

bestXeroEmployeeSuggestion :: XeroStaffMappingRow -> [XeroEmployee] -> XeroEmployeeSuggestionResult
bestXeroEmployeeSuggestion row employees =
    case List.sortOn (.scoredSuggestionScore) (map (scoreXeroEmployeeSuggestion row) employees) of
        [] -> NoXeroEmployeeSuggestion
        best : second : _
            | scoredSuggestionScore best > xeroEmployeeSuggestionThreshold -> NoXeroEmployeeSuggestion
            | scoredSuggestionScore second <= xeroEmployeeSuggestionThreshold
            , scoredSuggestionScore second - scoredSuggestionScore best < xeroEmployeeSuggestionAmbiguityMargin ->
                AmbiguousXeroEmployeeSuggestion best.scoredSuggestionEmployee second.scoredSuggestionEmployee
            | otherwise -> XeroEmployeeSuggestion best.scoredSuggestionEmployee
        best : _
            | scoredSuggestionScore best <= xeroEmployeeSuggestionThreshold -> XeroEmployeeSuggestion best.scoredSuggestionEmployee
            | otherwise -> NoXeroEmployeeSuggestion

attachXeroStaffMappingSuggestions :: [XeroEmployee] -> [XeroStaffMappingRow] -> [XeroStaffMappingRow]
attachXeroStaffMappingSuggestions employees rows =
    map attach rows
    where
        attach row
            | row.mappingRowMapping.mappingStatus /= "not_applicable" = row { mappingRowSuggestedEmployee = Nothing }
            | otherwise =
                let availableEmployees = filter (xeroEmployeeAvailableForStaff row.mappingRowStaff rows) employees
                 in case bestXeroEmployeeSuggestion row availableEmployees of
                        XeroEmployeeSuggestion employee -> row { mappingRowSuggestedEmployee = Just employee }
                        _ -> row { mappingRowSuggestedEmployee = Nothing }

xeroEmployeeSuggestionThreshold :: Double
xeroEmployeeSuggestionThreshold = 0.25

xeroEmployeeSuggestionAmbiguityMargin :: Double
xeroEmployeeSuggestionAmbiguityMargin = 0.08

scoreXeroEmployeeSuggestion :: XeroStaffMappingRow -> XeroEmployee -> ScoredXeroEmployeeSuggestion
scoreXeroEmployeeSuggestion row employee =
    ScoredXeroEmployeeSuggestion
        { scoredSuggestionEmployee = employee
        , scoredSuggestionScore = minimum (emailScore : nameScores)
        }
    where
        staff = row.mappingRowStaff
        staffNames =
            [ normalizeName (staff.firstName <> " " <> staff.lastName)
            , normalizeName (staff.lastName <> " " <> staff.firstName)
            ]
        employeeName = normalizeName employee.displayName
        nameScores = map (`normalizedLevenshteinDistance` employeeName) staffNames
        emailScore =
            case (row.mappingRowUser >>= normalizedEmail . (.email), employee.email >>= normalizedEmail) of
                (Just staffEmail, Just employeeEmail) | staffEmail == employeeEmail -> 0
                _ -> 1

xeroEmployeeAvailableForStaff :: Staff -> [XeroStaffMappingRow] -> XeroEmployee -> Bool
xeroEmployeeAvailableForStaff staff mappingRows employee =
    employee.xeroEmployeeId `List.notElem` usedByOtherStaff
    where
        currentStaffId = unpackId staff.id
        usedByOtherStaff =
            mappingRows
                |> mapMaybe verifiedEmployeeForOtherStaff

        verifiedEmployeeForOtherStaff row =
            let mapping = row.mappingRowMapping
             in if unpackId row.mappingRowStaff.id /= currentStaffId && mapping.mappingStatus == "verified"
                    then mapping.xeroEmployeeId
                    else Nothing

normalizedNameLength :: Text -> Int
normalizedNameLength =
    Text.length . Text.filter (/= ' ')

normalizedLevenshteinDistance :: Text -> Text -> Double
normalizedLevenshteinDistance left right
    | Text.null left || Text.null right = 1
    | otherwise = fromIntegral distance / fromIntegral denominator
    where
        distance = levenshteinDistance (Text.unpack left) (Text.unpack right)
        denominator = max 1 (max (normalizedNameLength left) (normalizedNameLength right))

levenshteinDistance :: String -> String -> Int
levenshteinDistance source target =
    List.last (List.foldl' transform [0 .. length target] source)
    where
        transform previous sourceChar =
            case previous of
                [] -> []
                firstPrevious : _ ->
                    scanl compute (firstPrevious + 1) (zip3 target previous (List.drop 1 previous))
                    where
                        compute left (targetChar, diagonal, above) =
                            minimum
                                [ left + 1
                                , above + 1
                                , diagonal + if sourceChar == targetChar then 0 else 1
                                ]

normalizeName :: Text -> Text
normalizeName =
    Text.unwords
        . Text.words
        . Text.map normalizeNameChar
        . Text.toLower
        . Text.strip

normalizeNameChar :: Char -> Char
normalizeNameChar char
    | Char.isAlphaNum char = char
    | otherwise = ' '

normalizedEmail :: Text -> Maybe Text
normalizedEmail email =
    let normalized = Text.toLower (Text.strip email)
     in if Text.null normalized then Nothing else Just normalized

staffFullNameText :: Staff -> Text
staffFullNameText staff =
    Text.strip (staff.firstName <> " " <> staff.lastName)

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

saveXeroPayItemAccountCodeSelection ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    XeroConnection ->
    Text ->
    IO ()
saveXeroPayItemAccountCodeSelection connection selection = do
    activeAccountCodes <- fetchCurrentVenueXeroPayItemAccountCodeOptions (Just connection)
    case Text.strip selection of
        "" -> persistXeroPayItemAccountCodeSelection connection "none" Nothing
        accountCode
            | Text.length accountCode > 32 ->
                respondWithXeroMappingMutationError "Use a Xero account code up to 32 characters."
            | accountCode `List.notElem` activeAccountCodes ->
                respondWithXeroMappingMutationError "Choose a synced Xero account code from the dropdown."
            | otherwise ->
                persistXeroPayItemAccountCodeSelection connection "verified" (Just accountCode)

persistXeroPayItemAccountCodeSelection ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    XeroConnection ->
    Text ->
    Maybe Text ->
    IO ()
persistXeroPayItemAccountCodeSelection connection selectionStatus maybeAccountCode = do
    now <- getCurrentTime
    selection <- withTransaction do
        existingSelection <-
            query @XeroPayItemAccountCodeSelection
                |> filterWhere (#xeroConnectionId, unpackId connection.id)
                |> fetchOneOrNothing
        let prepared record =
                record
                    |> set #venueId (unpackId currentVenueId)
                    |> set #xeroConnectionId (unpackId connection.id)
                    |> set #accountCode maybeAccountCode
                    |> set #selectionStatus selectionStatus
                    |> set #lastVerifiedAt (if selectionStatus == "verified" then Just now else Nothing)
                    |> set #updatedByUserId (Just (unpackId currentUser.id))
        savedSelection <-
            case existingSelection of
                Just existing -> prepared existing |> updateRecord
                Nothing ->
                    prepared (newRecord @XeroPayItemAccountCodeSelection)
                        |> set #createdByUserId (Just (unpackId currentUser.id))
                        |> createRecord
        void $ recordCurrentUserAuditEvent
            "xero_pay_item_account_code_selected"
            "xero_pay_item_account_code_selections"
            (unpackId savedSelection.id)
            (Aeson.object
                [ "selectionStatus" Aeson..= selectionStatus
                , "accountCode" Aeson..= maybeAccountCode
                ]
            )
        pure savedSelection
    let message =
            if selection.selectionStatus == "verified"
                then "Saved Xero pay item account code " <> fromMaybe "" selection.accountCode <> "."
                else "Cleared Xero pay item account code."
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
            redirectTo XeroAction

respondWithXeroMappingMutationError ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Text ->
    IO ()
respondWithXeroMappingMutationError message =
    if isHtmxRequest
        then respondWithXeroSectionFragmentAndToast (Just (xeroErrorToast message))
        else do
            setErrorMessage message
            redirectTo XeroAction

createMissingXeroPayItems ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    XeroConnection ->
    IO ()
createMissingXeroPayItems connection = do
    xeroEarningsRates <- fetchCurrentVenueXeroEarningsRates (Just connection)
    requirements <- fetchCurrentVenueXeroPayItemRequirements (Just connection) xeroEarningsRates
    maybeAccountCodeSelection <- fetchCurrentVenueXeroPayItemAccountCodeSelection (Just connection)
    accountCodeOptions <- fetchCurrentVenueXeroPayItemAccountCodeOptions (Just connection)
    let proposedRequirements = filter (\requirement -> requirement.payItemRequirementStatus == "proposed" && requirement.payItemRequirementIsActive) requirements
    case selectedXeroPayItemAccountCode accountCodeOptions maybeAccountCodeSelection of
        Nothing -> respondWithXeroMappingMutationError "Choose a Xero pay item account code before creating pay items."
        Just accountCode ->
            if null proposedRequirements
                then respondToXeroMappingMutationSuccess "No missing Xero pay items need to be created."
                else do
                    readXeroConfig >>= \case
                        Left message -> respondWithXeroMappingMutationError message
                        Right xeroConfig -> do
                            refreshResult <- refreshXeroConnectionAccess xeroConfig connection
                            case refreshResult of
                                Left message -> respondWithXeroMappingMutationError message
                                Right (refreshedConnection, accessToken) -> do
                                    xeroClient <- currentXeroClient
                                    now <- getCurrentTime
                                    createResult <- createProposedXeroPayItems xeroClient refreshedConnection accessToken now accountCode proposedRequirements
                                    case createResult of
                                        Left message -> respondWithXeroMappingMutationError message
                                        Right verification -> do
                                            void $ recordCurrentUserAuditEvent
                                                "xero_pay_items_created"
                                                "xero_pay_item_requirement_records"
                                                (unpackId refreshedConnection.id)
                                                (Aeson.object
                                                    [ "tenantId" Aeson..= refreshedConnection.tenantId
                                                    , "submittedCount" Aeson..= verification.submittedCount
                                                    , "failedCount" Aeson..= verification.failedCount
                                                    , "verifiedCount" Aeson..= verification.verifiedCount
                                                    , "missingCount" Aeson..= verification.missingCount
                                                    , "missingNames" Aeson..= verification.missingNames
                                                    , "submissionFailures" Aeson..= map xeroPayItemSubmissionFailurePayload verification.submissionFailures
                                                    ]
                                                )
                                            broadcastAdminXeroInvalidation currentVenueId
                                            if verification.failedCount == 0 && verification.missingCount == 0
                                                then respondToXeroMappingMutationSuccess ("Created and verified " <> tshow verification.verifiedCount <> " missing Xero pay items.")
                                                else respondWithXeroMappingMutationError (xeroPayItemVerificationFailureMessage verification)

selectedXeroPayItemAccountCode :: [Text] -> Maybe XeroPayItemAccountCodeSelection -> Maybe Text
selectedXeroPayItemAccountCode accountCodeOptions maybeSelection =
    case maybeSelection of
        Just selection | selection.selectionStatus == "verified" -> do
            accountCode <- Text.strip <$> selection.accountCode
            if Text.null accountCode || accountCode `List.notElem` accountCodeOptions then Nothing else Just accountCode
        _ -> Nothing

data CreatePayItemsVerificationResult = CreatePayItemsVerificationResult
    { submittedCount :: !Int
    , failedCount    :: !Int
    , verifiedCount  :: !Int
    , missingCount   :: !Int
    , missingNames   :: ![Text]
    , submissionFailures :: ![XeroPayItemSubmissionFailure]
    }
    deriving (Eq, Show)

data XeroPayItemSubmissionFailure = XeroPayItemSubmissionFailure
    { failureRequirementKey  :: !Text
    , failurePayItemName     :: !Text
    , failureIdempotencyKey  :: !Text
    , failureRateType        :: !Text
    , failureRatePerUnit     :: !(Maybe Scientific)
    , failureError           :: !Text
    }
    deriving (Eq, Show)

createProposedXeroPayItems ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    XeroClient ->
    XeroConnection ->
    Text ->
    UTCTime ->
    Text ->
    [XeroPayItemRequirement] ->
    IO (Either Text CreatePayItemsVerificationResult)
createProposedXeroPayItems xeroClient connection accessToken now accountCode requirements = do
    let batchKey = xeroPayItemIdempotencyBatchKey now
    initialFetchResult <- fetchEarningsRates xeroClient accessToken connection.tenantId
    case initialFetchResult of
        Left err -> pure (Left ("Xero pay item preflight pull failed before creating pay items: " <> xeroClientErrorText err))
        Right initialRates -> do
            upsertFetchedXeroEarningsRates connection now initialRates
            let existingEarningsRatePayloads = map (.xeroEarningsRateRaw) initialRates
            (submittedCount, submissionFailures) <- submitCreates batchKey (1 :: Int) 0 [] existingEarningsRatePayloads requirements
            verifySubmittedCreates submittedCount submissionFailures
    where
        verifySubmittedCreates submittedCount submissionFailures = do
            fetchResult <- fetchEarningsRates xeroClient accessToken connection.tenantId
            case fetchResult of
                Left err -> pure (Left ("Xero pay item verification failed after submitting " <> tshow submittedCount <> " pay items and receiving " <> tshow (length submissionFailures) <> " create errors: " <> xeroClientErrorText err))
                Right fetchedRates -> do
                    upsertFetchedXeroEarningsRates connection now fetchedRates
                    let verifiedPairs = Maybe.mapMaybe (verifiedRequirementRate fetchedRates) requirements
                    mapM_ (uncurry (persistCreatedXeroPayItem connection now)) verifiedPairs
                    let verifiedNames = map (payItemRequirementName . fst) verifiedPairs
                    let missingNames = filter (`List.notElem` verifiedNames) (map (.payItemRequirementName) requirements)
                    pure $
                        Right
                            CreatePayItemsVerificationResult
                                { submittedCount = submittedCount
                                , failedCount = length submissionFailures
                                , verifiedCount = length verifiedPairs
                                , missingCount = length missingNames
                                , missingNames = missingNames
                                , submissionFailures = submissionFailures
                                }

        submitCreates _ _ submittedCount failures _ [] = pure (submittedCount, reverse failures)
        submitCreates batchKey itemIndex submittedCount failures knownEarningsRates (requirement : rest) = do
            let idempotencyKey = xeroPayItemIdempotencyKey batchKey itemIndex requirement
            let body = xeroPayItemRequestPayload knownEarningsRates accountCode requirement
            createResult <-
                createPayItem
                    xeroClient
                    accessToken
                    connection.tenantId
                    idempotencyKey
                    body
            case createResult of
                Left err ->
                    submitCreates
                        batchKey
                        (itemIndex + 1)
                        submittedCount
                        ( xeroPayItemSubmissionFailure requirement idempotencyKey err : failures
                        )
                        knownEarningsRates
                        rest
                Right _ ->
                    submitCreates
                        batchKey
                        (itemIndex + 1)
                        (submittedCount + 1)
                        failures
                        (knownEarningsRates <> [xeroEarningsRatePayload accountCode requirement])
                        rest

xeroPayItemSubmissionFailure :: XeroPayItemRequirement -> Text -> XeroClientError -> XeroPayItemSubmissionFailure
xeroPayItemSubmissionFailure requirement idempotencyKey err =
    XeroPayItemSubmissionFailure
        { failureRequirementKey = requirement.payItemRequirementKey
        , failurePayItemName = requirement.payItemRequirementName
        , failureIdempotencyKey = idempotencyKey
        , failureRateType = requirement.payItemRequirementRateType
        , failureRatePerUnit = requirement.payItemRequirementRatePerUnit
        , failureError = xeroClientErrorText err
        }

xeroPayItemSubmissionFailurePayload :: XeroPayItemSubmissionFailure -> Aeson.Value
xeroPayItemSubmissionFailurePayload failure =
    Aeson.object
        [ "requirementKey" Aeson..= failure.failureRequirementKey
        , "payItemName" Aeson..= failure.failurePayItemName
        , "idempotencyKey" Aeson..= failure.failureIdempotencyKey
        , "rateType" Aeson..= failure.failureRateType
        , "ratePerUnit" Aeson..= failure.failureRatePerUnit
        , "error" Aeson..= failure.failureError
        ]

verifiedRequirementRate :: [XeroEarningsRateRef] -> XeroPayItemRequirement -> Maybe (XeroPayItemRequirement, XeroEarningsRateRef)
verifiedRequirementRate fetchedRates requirement =
    fmap (\rate -> (requirement, rate)) (List.find isMatchingActiveRate fetchedRates)
    where
        isMatchingActiveRate rate =
            rate.xeroEarningsRateName == requirement.payItemRequirementName
                && rate.xeroEarningsRateIsActive

xeroPayItemVerificationFailureMessage :: CreatePayItemsVerificationResult -> Text
xeroPayItemVerificationFailureMessage verification =
    Text.intercalate
        " "
        (filter (not . Text.null) [failureSummary, verificationSummary, missingSummary])
    where
        failureSummary =
            if verification.failedCount == 0
                then ""
                else
                    "Xero rejected "
                        <> tshow verification.failedCount
                        <> " pay item creates. First error for "
                        <> maybe "unknown pay item" (.failurePayItemName) (listToMaybe verification.submissionFailures)
                        <> ": "
                        <> maybe "unknown error" (.failureError) (listToMaybe verification.submissionFailures)
        verificationSummary =
            "Submitted "
                <> tshow verification.submittedCount
                <> " Xero pay item creates and verified "
                <> tshow verification.verifiedCount
                <> " after pulling Xero pay items."
        missingSummary =
            if verification.missingCount == 0
                then ""
                else
                    "Still missing: "
                        <> Text.intercalate ", " (take 5 verification.missingNames)
                        <> if verification.missingCount > 5 then " and " <> tshow (verification.missingCount - 5) <> " more." else "."

xeroPayItemIdempotencyBatchKey :: UTCTime -> Text
xeroPayItemIdempotencyBatchKey now =
    cs (formatTime defaultTimeLocale "%Y%m%d%H%M%S%q" now)

xeroPayItemIdempotencyKey :: Text -> Int -> XeroPayItemRequirement -> Text
xeroPayItemIdempotencyKey batchKey itemIndex requirement =
    "bepis-pay-item-"
        <> batchKey
        <> "-"
        <> Text.justifyRight 3 '0' (tshow itemIndex)
        <> "-"
        <> Text.take 76 (xeroPayItemIdempotencySlug requirement.payItemRequirementKey)

xeroPayItemIdempotencySlug :: Text -> Text
xeroPayItemIdempotencySlug =
    Text.map \char ->
        if Char.isAlphaNum char
            then Char.toLower char
            else '-'

upsertFetchedXeroEarningsRates ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    XeroConnection ->
    UTCTime ->
    [XeroEarningsRateRef] ->
    IO ()
upsertFetchedXeroEarningsRates connection now fetchedRates =
    withTransaction do
        mapM_ (upsertXeroEarningsRate connection now) fetchedRates
        markStaleXeroEarningsRateMappings connection fetchedRates

xeroPayItemRequestPayload :: [Aeson.Value] -> Text -> XeroPayItemRequirement -> Aeson.Value
xeroPayItemRequestPayload existingEarningsRates accountCode requirement =
    Aeson.object
        [ "EarningsRates" Aeson..= (existingEarningsRates <> [xeroEarningsRatePayload accountCode requirement])
        ]

xeroEarningsRatePayload :: Text -> XeroPayItemRequirement -> Aeson.Value
xeroEarningsRatePayload accountCode requirement =
    Aeson.object
        [ "Name" Aeson..= requirement.payItemRequirementName
        , "TypeOfUnits" Aeson..= ("Hours" :: Text)
        , "EarningsType" Aeson..= requirement.payItemRequirementEarningsType
        , "RateType" Aeson..= requirement.payItemRequirementRateType
        , "RatePerUnit" Aeson..= requirement.payItemRequirementRatePerUnit
        , "IsExemptFromTax" Aeson..= False
        , "IsExemptFromSuper" Aeson..= False
        , "IsReportableAsW1" Aeson..= True
        , "IsQualifyingEarnings" Aeson..= True
        , "AccountCode" Aeson..= accountCode
        ]

persistCreatedXeroPayItem ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    XeroConnection ->
    UTCTime ->
    XeroPayItemRequirement ->
    XeroEarningsRateRef ->
    IO ()
persistCreatedXeroPayItem connection now requirement createdRate = do
    earningsRate <- upsertXeroEarningsRate connection now createdRate
    withTransaction do
        maybeRequirementRecord <-
            query @XeroPayItemRequirementRecord
                |> filterWhere (#xeroConnectionId, unpackId connection.id)
                |> filterWhere (#requirementKey, requirement.payItemRequirementKey)
                |> fetchOneOrNothing
        forM_ maybeRequirementRecord \record ->
            record
                |> set #requirementStatus ("created" :: Text)
                |> set #xeroEarningsRateId (Just earningsRate.xeroEarningsRateId)
                |> set #xeroEarningsRateName (Just earningsRate.name)
                |> set #xeroEarningsRateRateType earningsRate.rateType
                |> set #lastVerifiedAt (Just now)
                |> set #updatedByUserId (Just (unpackId currentUser.id))
                |> updateRecord
                |> void
        upsertCreatedXeroEarningsRateMapping connection now requirement earningsRate

upsertCreatedXeroEarningsRateMapping ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    XeroConnection ->
    UTCTime ->
    XeroPayItemRequirement ->
    XeroEarningsRate ->
    IO ()
upsertCreatedXeroEarningsRateMapping connection now requirement earningsRate = do
    existingMapping <-
        query @XeroEarningsRateMapping
            |> filterWhere (#xeroConnectionId, unpackId connection.id)
            |> filterWhere (#localBucketKey, requirement.payItemRequirementKey)
            |> fetchOneOrNothing
    let localBucketLabel = fromMaybe requirement.payItemRequirementName (Text.stripPrefix xeroManagedPayItemNamePrefix requirement.payItemRequirementName)
    let prepared record =
            record
                |> set #venueId (unpackId currentVenueId)
                |> set #xeroConnectionId (unpackId connection.id)
                |> set #localBucketKey requirement.payItemRequirementKey
                |> set #localBucketLabel localBucketLabel
                |> set #xeroEarningsRateId (Just earningsRate.xeroEarningsRateId)
                |> set #xeroEarningsRateName (Just earningsRate.name)
                |> set #mappingStatus ("verified" :: Text)
                |> set #lastVerifiedAt (Just now)
                |> set #updatedByUserId (Just (unpackId currentUser.id))
    case existingMapping of
        Just existing -> prepared existing |> updateRecord |> void
        Nothing ->
            prepared (newRecord @XeroEarningsRateMapping)
                |> set #createdByUserId (Just (unpackId currentUser.id))
                |> createRecord
                |> void

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
                            redirectTo XeroAction

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
    redirectTo XeroAction

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
        else redirectTo XeroAction

markStaleXeroStaffMappings ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    XeroConnection ->
    [XeroEmployeeRef] ->
    IO ()
markStaleXeroStaffMappings connection employees = do
    let activeEmployeeIds = map (.xeroEmployeeId) employees
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
    let activeEarningsRateIds = map (.xeroEarningsRateId) earningsRates
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
    let activePayrollCalendarIds = map (.xeroPayrollCalendarId) payrollCalendars
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
        else redirectTo XeroAction

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
