module Web.Controller.Admin.Xero.Mappings
    ( saveXeroEarningsRateMappingAction
    , saveXeroPayItemAccountCodeSelectionAction
    , saveXeroPayrollCalendarSelectionAction
    , saveXeroStaffMappingAction
    , suggestXeroStaffMappingAction
    ) where

import Application.Helper.Profiling
import Application.Helper.XeroAdminTypes
import Application.Helper.XeroPayItems
import Application.Xero.Admin.ReadModel
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import qualified Data.List as List
import qualified Data.Text as Text
import Web.Controller.Admin.Xero.Responses
import Web.Controller.Prelude

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
    if isHtmxRequest
        then respondWithXeroStaffMappingControlsAndToast connection maybeUnchangedStaffId (Just (xeroSuccessToast message))
        else do
            profileActionSpan "admin.xero.staff_mapping.persist.broadcast" $
                refreshAdminXero currentVenueId
            setSuccessMessage message
            redirectTo XeroAction

respondWithXeroStaffMappingError ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    XeroConnection ->
    Text ->
    IO ()
respondWithXeroStaffMappingError _ message = do
    if isHtmxRequest
        then respondWithXeroStaffMappingToastOnly (Just (xeroErrorToast message))
        else do
            setErrorMessage message
            redirectTo XeroAction

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
    refreshAdminXero currentVenueId
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
    refreshAdminXero currentVenueId
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
    refreshAdminXero currentVenueId
    respondToXeroMappingMutationSuccess message
