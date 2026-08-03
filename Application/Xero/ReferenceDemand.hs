module Application.Xero.ReferenceDemand
    ( fetchXeroMissingReferenceDemand
    , fetchXeroPayrollEligibleApprovedStaffIds
    ) where

import Application.PayAssignment
import Application.Xero.ReferenceTrust
import qualified Data.Map.Strict as Map
import Generated.Types
import IHP.ControllerPrelude

data ApprovedAssignment = ApprovedAssignment
    { approvedAssignmentStaffId   :: !UUID
    , approvedEffectiveAssignment :: !EffectivePayAssignment
    , approvedAssignmentChangedAt :: !UTCTime
    }

fetchXeroMissingReferenceDemand ::
    (?modelContext :: ModelContext) =>
    XeroConnection ->
    IO XeroMissingReferenceDemand
fetchXeroMissingReferenceDemand connection = do
    approvedEntries <- fetchApprovedEntries connection
    mappings <- fetchConnectionMappings connection
    assignments <- resolveApprovedAssignments approvedEntries
    let unresolvedAssignments = filter (needsReferenceRefresh connection mappings) assignments
        hasPayrollEligibleMissing = any (payrollEligible . (.approvedEffectiveAssignment)) unresolvedAssignments
        hasRosterOnlyMissing = any ((== EffectiveRosterOnly) . (.approvedEffectiveAssignment)) unresolvedAssignments
    pure
        if hasPayrollEligibleMissing
            then MissingPayrollEligibleStaffReference
            else if hasRosterOnlyMissing
                then MissingRosterOnlyStaffReference
                else NoMissingPayrollReferenceDemand

fetchXeroPayrollEligibleApprovedStaffIds ::
    (?modelContext :: ModelContext) =>
    XeroConnection ->
    IO [UUID]
fetchXeroPayrollEligibleApprovedStaffIds connection = do
    approvedEntries <- fetchApprovedEntries connection
    assignments <- resolveApprovedAssignments approvedEntries
    pure (nub [assignment.approvedAssignmentStaffId | assignment <- assignments, payrollEligible assignment.approvedEffectiveAssignment])

fetchApprovedEntries ::
    (?modelContext :: ModelContext) =>
    XeroConnection ->
    IO [TimesheetEntry]
fetchApprovedEntries connection =
    query @TimesheetEntry
        |> filterWhere (#venueId, connection.venueId)
        |> filterWhere (#isApproved, True)
        |> filterWhere (#deletedAt, Nothing)
        |> fetch

fetchConnectionMappings ::
    (?modelContext :: ModelContext) =>
    XeroConnection ->
    IO [XeroStaffMapping]
fetchConnectionMappings connection =
    query @XeroStaffMapping
        |> filterWhere (#xeroConnectionId, unpackId connection.id)
        |> fetch

resolveApprovedAssignments ::
    (?modelContext :: ModelContext) =>
    [TimesheetEntry] ->
    IO [ApprovedAssignment]
resolveApprovedAssignments entries = do
    staffMembers <-
        query @Staff
            |> filterWhereIn (#id, map (Id . (.staffId)) entries)
            |> fetch
    shiftTypes <-
        query @ShiftType
            |> filterWhereIn (#id, map (Id . (.shiftTypeId)) entries)
            |> fetch
    staffVersions <-
        query @StaffPayVersion
            |> filterWhereIn (#id, map Id (mapMaybe (.staffPayVersionId) entries))
            |> fetch
    shiftVersions <-
        query @ShiftTypePayVersion
            |> filterWhereIn (#id, map Id (mapMaybe (.shiftTypePayVersionId) entries))
            |> fetch
    let staffById = Map.fromList [(unpackId staff.id, staff) | staff <- staffMembers]
        shiftTypeById = Map.fromList [(unpackId shiftType.id, shiftType) | shiftType <- shiftTypes]
        staffVersionById = Map.fromList [(unpackId version.id, version) | version <- staffVersions]
        shiftVersionById = Map.fromList [(unpackId version.id, version) | version <- shiftVersions]
    pure $ mapMaybe (resolvedAssignment staffById shiftTypeById staffVersionById shiftVersionById) entries

resolvedAssignment ::
    Map.Map UUID Staff ->
    Map.Map UUID ShiftType ->
    Map.Map UUID StaffPayVersion ->
    Map.Map UUID ShiftTypePayVersion ->
    TimesheetEntry ->
    Maybe ApprovedAssignment
resolvedAssignment staffById shiftTypeById staffVersionById shiftVersionById entry = do
    staff <- Map.lookup entry.staffId staffById
    shiftType <- Map.lookup entry.shiftTypeId shiftTypeById
    let staffAssignment =
            case entry.staffPayVersionId >>= (`Map.lookup` staffVersionById) of
                Just version -> staffAssignmentFromVersion version
                Nothing      -> staffAssignmentFromStaff staff
        shiftAssignment =
            case entry.shiftTypePayVersionId >>= (`Map.lookup` shiftVersionById) of
                Just version -> shiftAssignmentFromVersion version
                Nothing      -> shiftAssignmentFromShiftType shiftType
        changedAt = fromMaybe entry.updatedAt entry.approvedAt
    pure ApprovedAssignment
        { approvedAssignmentStaffId = entry.staffId
        , approvedEffectiveAssignment = resolvePayAssignment staffAssignment shiftAssignment
        , approvedAssignmentChangedAt = changedAt
        }

staffAssignmentFromVersion :: StaffPayVersion -> StaffPayAssignment
staffAssignmentFromVersion version =
    StaffPayAssignment
        { staffAssignmentMode = version.payAssignmentMode
        , staffAssignmentAwardLevelId = Id <$> version.defaultAwardLevelId
        , staffAssignmentImportedPayItemId = version.importedXeroPayItemId
        }

staffAssignmentFromStaff :: Staff -> StaffPayAssignment
staffAssignmentFromStaff staff =
    StaffPayAssignment
        { staffAssignmentMode = staff.payAssignmentMode
        , staffAssignmentAwardLevelId = staff.defaultAwardLevelId
        , staffAssignmentImportedPayItemId = staff.importedXeroPayItemId
        }

shiftAssignmentFromVersion :: ShiftTypePayVersion -> ShiftPayAssignment
shiftAssignmentFromVersion version =
    ShiftPayAssignment
        { shiftAssignmentMode = version.payAssignmentMode
        , shiftAssignmentAwardLevelId = Id <$> version.overrideAwardLevelId
        , shiftAssignmentImportedPayItemId = version.importedXeroPayItemId
        }

shiftAssignmentFromShiftType :: ShiftType -> ShiftPayAssignment
shiftAssignmentFromShiftType shiftType =
    ShiftPayAssignment
        { shiftAssignmentMode = shiftType.payAssignmentMode
        , shiftAssignmentAwardLevelId = shiftType.overrideAwardLevelId
        , shiftAssignmentImportedPayItemId = shiftType.importedXeroPayItemId
        }

needsReferenceRefresh :: XeroConnection -> [XeroStaffMapping] -> ApprovedAssignment -> Bool
needsReferenceRefresh connection mappings assignment =
    case find ((== assignment.approvedAssignmentStaffId) . (.staffId)) mappings of
        Nothing -> maybe True (< assignment.approvedAssignmentChangedAt) connection.lastSyncAt
        Just mapping
            | mappingResolvesStaff mapping -> False
            | otherwise -> maybe True (< assignment.approvedAssignmentChangedAt) mapping.referenceRefreshedAt

mappingResolvesStaff :: XeroStaffMapping -> Bool
mappingResolvesStaff mapping
    | mapping.mappingStatus == "verified" && isJust mapping.xeroEmployeeId = True
    | mapping.mappingStatus == "not_applicable" && isJust mapping.updatedByUserId = True
    | otherwise = False

payrollEligible :: EffectivePayAssignment -> Bool
payrollEligible = \case
    EffectiveAwardRate _ -> True
    EffectiveXeroRate _ -> True
    EffectiveRosterOnly -> False
    InvalidPayAssignment _ -> False
