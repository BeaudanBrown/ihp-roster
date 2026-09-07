module Application.Helper.Export.ReadModel where

import Application.Helper.Controller
import Application.Helper.Export.PayrollWorkbookModel
import Application.Helper.Pay (payVersionManifestForEntry)
import Application.Helper.VenueScopedQueries (fetchActiveVenueShiftTypes)
import Application.WageEngine (AwardClassification (..),
                               awardClassificationFromFixedId)
import Control.Monad (guard)
import Data.Coerce (coerce)
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import qualified Data.Text as Text
import Data.Time.Calendar (Day, addDays)
import Generated.Types
import IHP.ControllerPrelude

fetchCurrentVenueActiveShiftTypes :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO [ShiftType]
fetchCurrentVenueActiveShiftTypes =
    fetchActiveVenueShiftTypes currentVenueId

fetchReportShiftTypes :: (?modelContext :: ModelContext) => [TimesheetEntry] -> IO [ShiftType]
fetchReportShiftTypes entries =
    if null shiftTypeIds
        then pure []
        else
            query @ShiftType
                |> filterWhereIn (#id, map Id shiftTypeIds)
                |> fetch
  where
    shiftTypeIds = List.nub (map (.shiftTypeId) entries)

fetchReportStaffMap :: (?modelContext :: ModelContext) => [TimesheetEntry] -> IO (Map.Map UUID Staff)
fetchReportStaffMap entries =
    if null staffIds
        then pure Map.empty
        else do
            staffMembers <- query @Staff
                |> filterWhereIn (#id, map Id staffIds)
                |> filterWhere (#isActive, True)
                |> fetch
            pure (Map.fromList (map (\staff -> (coerce (get #id staff), staff)) staffMembers))
    where
        staffIds = List.nub (map (.staffId) entries)

fetchApprovedTimesheetEntries ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    Day ->
    Day ->
    IO [TimesheetEntry]
fetchApprovedTimesheetEntries rangeStart rangeEnd =
    query @TimesheetEntry
        |> filterWhere (#venueId, unpackId currentVenueId)
        |> filterWhere (#isApproved, True)
        |> filterWhere (#deletedAt, Nothing)
        |> filterWhereGreaterThanOrEqualTo (#operationalDate, rangeStart)
        |> filterWhereLessThan (#operationalDate, addDays 1 rangeEnd)
        |> orderByAsc #operationalDate
        |> orderByAsc #startsAt
        |> fetch

fetchStaffMap :: (?modelContext :: ModelContext) => [TimesheetEntry] -> IO (Map.Map UUID Staff)
fetchStaffMap entries =
    if null staffIds
        then pure Map.empty
        else do
            staff <- query @Staff |> filterWhereIn (#id, map Id staffIds) |> fetch
            pure (Map.fromList (map (\staffMember -> (coerce (get #id staffMember), staffMember)) staff))
    where
        staffIds = List.nub (map (.staffId) entries)

fetchApproverMap :: (?modelContext :: ModelContext) => [TimesheetEntry] -> IO (Map.Map UUID User)
fetchApproverMap entries =
    if null approverIds
        then pure Map.empty
        else do
            users <- query @User |> filterWhereIn (#id, map Id approverIds) |> fetch
            pure (Map.fromList (map (\user -> (coerce (get #id user), user)) users))
    where
        approverIds = List.nub (mapMaybe (.approvedByUserId) entries)

fetchApprovedEntryRosterWindowStarts :: (?modelContext :: ModelContext) => [TimesheetEntry] -> IO (Map.Map UUID Day)
fetchApprovedEntryRosterWindowStarts entries = do
    let calculationIds = List.nub (mapMaybe (.activePayCalculationId) entries)
    if null calculationIds
        then pure Map.empty
        else do
            calculations <- query @TimesheetPayCalculation
                |> filterWhereIn (#id, calculationIds)
                |> fetch
            pure (Map.fromList [(calculation.timesheetEntryId, calculation.rosterWindowStart) | calculation <- calculations])

fetchVersionManifestsForEntries :: (?modelContext :: ModelContext) => [TimesheetEntry] -> IO (Map.Map UUID Text)
fetchVersionManifestsForEntries entries =
    pure (Map.fromList (mapMaybe entryManifest entries))
    where
        entryManifest entry =
            fmap (\manifest -> (coerce (get #id entry), manifest)) (payVersionManifestForEntry entry)

-- | Staff Hours groups by the effective approval-pinned pay selection, never by
-- shift type. Imported assignments take precedence over Award assignments, and
-- shift overrides take precedence over staff defaults, matching the wage engine.
fetchApprovedEntryStaffHoursLabels :: (?modelContext :: ModelContext) => [TimesheetEntry] -> IO (Map.Map UUID (Maybe Text))
fetchApprovedEntryStaffHoursLabels entries =
    fmap (fmap (fmap (.payrollPayBucketLabel))) (fetchApprovedEntryPayrollPayBucketSelections entries)

fetchApprovedEntryPayrollPayBuckets :: (?modelContext :: ModelContext) => [TimesheetEntry] -> IO (Map.Map UUID PayrollWorkbookPayBucket)
fetchApprovedEntryPayrollPayBuckets entries =
    fmap (Map.mapMaybe IHP.ControllerPrelude.id) (fetchApprovedEntryPayrollPayBucketSelections entries)

fetchApprovedEntryPayrollPayBucketSelections :: (?modelContext :: ModelContext) => [TimesheetEntry] -> IO (Map.Map UUID (Maybe PayrollWorkbookPayBucket))
fetchApprovedEntryPayrollPayBucketSelections entries = do
    let staffVersionIds = List.nub (mapMaybe (.staffPayVersionId) entries)
        shiftVersionIds = List.nub (mapMaybe (.shiftTypePayVersionId) entries)
    staffVersions <- if null staffVersionIds then pure [] else query @StaffPayVersion |> filterWhereIn (#id, map Id staffVersionIds) |> fetch
    shiftVersions <- if null shiftVersionIds then pure [] else query @ShiftTypePayVersion |> filterWhereIn (#id, map Id shiftVersionIds) |> fetch
    let staffVersionsById = Map.fromList [(unpackId version.id, version) | version <- staffVersions]
        shiftVersionsById = Map.fromList [(unpackId version.id, version) | version <- shiftVersions]
        selections = map (entryPaySelection staffVersionsById shiftVersionsById) entries
        awardLevelIds = List.nub (mapMaybe (fst . snd) selections)
        importedPayItemIds = List.nub (mapMaybe (snd . snd) selections)
    awardLevels <- if null awardLevelIds then pure [] else query @AwardLevel |> filterWhereIn (#id, map Id awardLevelIds) |> fetch
    importedPayItems <- if null importedPayItemIds then pure [] else query @XeroImportedPayItem |> filterWhereIn (#id, map Id importedPayItemIds) |> fetch
    let awardsById = Map.fromList [(unpackId level.id, level) | level <- awardLevels]
        importedById = Map.fromList [(unpackId item.id, item) | item <- importedPayItems]
    pure $ Map.fromList
        [ (entryId, resolveSelection awardsById importedById selection)
        | (entryId, selection) <- selections
        ]
  where
    entryPaySelection :: Map.Map UUID StaffPayVersion -> Map.Map UUID ShiftTypePayVersion -> TimesheetEntry -> (UUID, (Maybe UUID, Maybe UUID))
    entryPaySelection staffVersionsById shiftVersionsById entry =
        let staffVersion = entry.staffPayVersionId >>= (`Map.lookup` staffVersionsById)
            shiftVersion = entry.shiftTypePayVersionId >>= (`Map.lookup` shiftVersionsById)
            importedPayItemId =
                (shiftVersion >>= shiftImportedPayItemId)
                    <|> (staffVersion >>= staffImportedPayItemId)
            awardLevelId =
                (shiftVersion >>= shiftAwardLevelId)
                    <|> (staffVersion >>= staffAwardLevelId)
         in (unpackId entry.id, (awardLevelId, importedPayItemId))

    shiftImportedPayItemId :: ShiftTypePayVersion -> Maybe UUID
    shiftImportedPayItemId version = fmap unpackId version.importedXeroPayItemId

    staffImportedPayItemId :: StaffPayVersion -> Maybe UUID
    staffImportedPayItemId version = fmap unpackId version.importedXeroPayItemId

    shiftAwardLevelId :: ShiftTypePayVersion -> Maybe UUID
    shiftAwardLevelId version = version.overrideAwardLevelId

    staffAwardLevelId :: StaffPayVersion -> Maybe UUID
    staffAwardLevelId version = version.defaultAwardLevelId

    resolveSelection :: Map.Map UUID AwardLevel -> Map.Map UUID XeroImportedPayItem -> (Maybe UUID, Maybe UUID) -> Maybe PayrollWorkbookPayBucket
    resolveSelection awardsById importedById (awardLevelId, importedPayItemId) =
        (do
            itemId <- importedPayItemId
            item <- Map.lookup itemId importedById
            pure PayrollWorkbookPayBucket
                { payrollPayBucketKey = PayrollWorkbookImportedPayItem itemId
                , payrollPayBucketLabel = item.name
                }
        )
            <|> (do
                levelId <- awardLevelId
                level <- Map.lookup levelId awardsById
                pure PayrollWorkbookPayBucket
                    { payrollPayBucketKey = PayrollWorkbookAwardLevel levelId
                    , payrollPayBucketLabel = staffHoursAwardLabel level
                    }
            )

staffHoursAwardLabel :: AwardLevel -> Text
staffHoursAwardLabel awardLevel =
    maybe awardLevel.classification staffHoursAwardClassificationLabel (awardClassificationFromFixedId awardLevel.classificationFixedId)

staffHoursAwardClassificationLabel :: AwardClassification -> Text
staffHoursAwardClassificationLabel = \case
    HospitalityIntroductory -> "LVL 0"
    HospitalityLevel1       -> "LVL 1"
    HospitalityLevel2       -> "LVL 2"
    HospitalityLevel3       -> "LVL 3"
    HospitalityLevel4       -> "LVL 4"
    HospitalityLevel5       -> "LVL 5"
    HospitalityLevel6       -> "LVL 6"

-- | Detailed payroll output retains the approval-pinned shift payroll label as
-- tracking context alongside its detailed calculation fields.
fetchApprovedEntryPayLabels :: (?modelContext :: ModelContext) => [TimesheetEntry] -> IO (Map.Map UUID (Maybe Text))
fetchApprovedEntryPayLabels entries = do
    let versionIds = List.nub (mapMaybe (.shiftTypePayVersionId) entries)
    versions <- if null versionIds then pure [] else query @ShiftTypePayVersion |> filterWhereIn (#id, map Id versionIds) |> fetch
    let labels = Map.fromList [(unpackId version.id, nonEmptyLabel version.payrollLabel) | version <- versions]
    pure $ Map.fromList
        [ (unpackId entry.id, join (entry.shiftTypePayVersionId >>= (`Map.lookup` labels)))
        | entry <- entries
        ]
  where
    nonEmptyLabel value =
        let label = Text.strip value
         in if Text.null label then Nothing else Just label

fetchApprovedEntryShiftLabels :: (?modelContext :: ModelContext) => [TimesheetEntry] -> IO (Map.Map UUID Text)
fetchApprovedEntryShiftLabels entries = do
    versions <- if null versionIds then pure [] else query @ShiftTypePayVersion |> filterWhereIn (#id, map Id versionIds) |> fetch
    let labels = Map.fromList [(unpackId version.id, version.payrollLabel) | version <- versions]
    pure (Map.fromList (mapMaybe (entryLabel labels) entries))
  where
    versionIds = List.nub (mapMaybe (.shiftTypePayVersionId) entries)
    entryLabel labels entry = do
        versionId <- entry.shiftTypePayVersionId
        label <- Text.strip <$> Map.lookup versionId labels
        guard (not (Text.null label))
        pure (unpackId entry.id, label)
