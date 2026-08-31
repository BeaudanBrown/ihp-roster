module Application.Xero.StaffMappings
    ( ClearedXeroStaffMapping (..)
    , applyXeroStaffMappingSelection
    , clearXeroStaffMappingsForInactiveStaff
    ) where

import Application.Xero.EmployeeId (XeroEmployeeSelection (..),
                                    xeroEmployeeIdText)
import Application.Xero.WorkflowState (xeroStaffMappingIsVerified)
import Control.Monad (void)
import Generated.Types
import IHP.ControllerPrelude

data ClearedXeroStaffMapping = ClearedXeroStaffMapping
    { clearedMappingId             :: !(Id XeroStaffMapping)
    , clearedConnectionId          :: !(Id XeroConnection)
    , clearedXeroEmployeeId        :: !(Maybe Text)
    , clearedXeroEmployeeName      :: !(Maybe Text)
    , clearedPreviousMappingStatus :: !XeroStaffMappingStatusEnum
    }
    deriving (Eq, Show)

applyXeroStaffMappingSelection ::
    (?modelContext :: ModelContext) =>
    Id Venue ->
    Id User ->
    XeroConnection ->
    Id Staff ->
    XeroEmployeeSelection ->
    IO (Either Text XeroStaffMapping)
applyXeroStaffMappingSelection venueId actorUserId connection staffId selection
    | connection.venueId /= unpackId venueId || connection.connectionStatus /= "active" =
        pure (Left "Connect Xero before managing staff mappings.")
    | otherwise = do
        maybeStaff <-
            query @Staff
                |> filterWhere (#id, staffId)
                |> filterWhere (#venueId, unpackId venueId)
                |> filterWhere (#isActive, True)
                |> filterWhere (#archivedAt, Nothing)
                |> filterWhereSql (#userId, "IS NOT NULL")
                |> fetchOneOrNothing
        case maybeStaff of
            Nothing -> pure (Left "Choose a linked active staff member from the current venue.")
            Just staff -> applySelection staff
  where
    applySelection staff = case selection of
        XeroEmployeeUnmapped ->
            Right <$> persistMapping staff XeroStaffMappingStatusEnumUnmapped Nothing
        XeroEmployeeNotApplicable ->
            Right <$> persistMapping staff NotApplicable Nothing
        XeroEmployeeSelected employeeId -> do
            let employeeIdText = xeroEmployeeIdText employeeId
            maybeEmployee <-
                query @XeroEmployee
                    |> filterWhere (#venueId, unpackId venueId)
                    |> filterWhere (#xeroConnectionId, unpackId connection.id)
                    |> filterWhere (#xeroEmployeeId, employeeIdText)
                    |> filterWhere (#providerAvailable, True)
                    |> fetchOneOrNothing
            case maybeEmployee of
                Nothing -> pure (Left "Choose a synced Xero employee from this venue.")
                Just employee -> do
                    duplicateMapping <-
                        query @XeroStaffMapping
                            |> filterWhere (#venueId, unpackId venueId)
                            |> filterWhere (#xeroConnectionId, unpackId connection.id)
                            |> filterWhere (#xeroEmployeeId, Just employeeIdText)
                            |> filterWhere (#mappingStatus, XeroStaffMappingStatusEnumVerified)
                            |> filterWhereNot (#staffId, unpackId staff.id)
                            |> fetchOneOrNothing
                    case duplicateMapping of
                        Just _ -> pure (Left "That Xero employee is already mapped to another staff member.")
                        Nothing -> Right <$> persistMapping staff XeroStaffMappingStatusEnumVerified (Just employee)

    persistMapping staff mappingStatus maybeEmployee = do
        now <- getCurrentTime
        existingMapping <-
            query @XeroStaffMapping
                |> filterWhere (#staffId, unpackId staff.id)
                |> filterWhere (#xeroConnectionId, unpackId connection.id)
                |> fetchOneOrNothing
        let prepared record =
                record
                    |> set #venueId (unpackId venueId)
                    |> set #staffId (unpackId staff.id)
                    |> set #xeroConnectionId (unpackId connection.id)
                    |> set #xeroEmployeeId ((.xeroEmployeeId) <$> maybeEmployee)
                    |> set #xeroEmployeeName ((.displayName) <$> maybeEmployee)
                    |> set #xeroEmployeeEmail (maybeEmployee >>= (.email))
                    |> set #mappingStatus mappingStatus
                    |> set #lastVerifiedAt (if xeroStaffMappingIsVerified mappingStatus then Just now else Nothing)
                    |> set #updatedByUserId (Just (unpackId actorUserId))
        case existingMapping of
            Just existing -> prepared existing |> updateRecord
            Nothing ->
                prepared (newRecord @XeroStaffMapping)
                    |> set #createdByUserId (Just (unpackId actorUserId))
                    |> createRecord

clearXeroStaffMappingsForInactiveStaff ::
    (?modelContext :: ModelContext) =>
    Id User ->
    Staff ->
    IO [ClearedXeroStaffMapping]
clearXeroStaffMappingsForInactiveStaff actorUserId staff
    | staff.isActive && isNothing staff.archivedAt =
        pure []
    | otherwise = do
        mappings <-
            query @XeroStaffMapping
                |> filterWhere (#venueId, staff.venueId)
                |> filterWhere (#staffId, unpackId staff.id)
                |> fetch
        mapM clearMapping mappings
  where
    clearMapping mapping = do
        let cleared =
                ClearedXeroStaffMapping
                    { clearedMappingId = mapping.id
                    , clearedConnectionId = Id mapping.xeroConnectionId
                    , clearedXeroEmployeeId = mapping.xeroEmployeeId
                    , clearedXeroEmployeeName = mapping.xeroEmployeeName
                    , clearedPreviousMappingStatus = mapping.mappingStatus
                    }
        mapping
            |> set #xeroEmployeeId Nothing
            |> set #xeroEmployeeName Nothing
            |> set #xeroEmployeeEmail Nothing
            |> set #mappingStatus XeroStaffMappingStatusEnumUnmapped
            |> set #lastVerifiedAt Nothing
            |> set #referenceRefreshedAt Nothing
            |> set #updatedByUserId (Just (unpackId actorUserId))
            |> updateRecord
            |> void
        pure cleared
