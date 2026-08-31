module Application.Xero.StaffMappings
    ( ClearedXeroStaffMapping (..)
    , clearXeroStaffMappingsForInactiveStaff
    ) where

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
