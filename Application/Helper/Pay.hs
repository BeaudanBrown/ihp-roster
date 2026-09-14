module Application.Helper.Pay where

import Application.Helper.Controller hiding (venueEffectiveRateDate,
                                      venueEffectiveRateEndDate)
import qualified Application.Helper.WeekBoundaries as WeekBoundaries
import Application.VenueTime.Model (ValidatedTimesheetTiming,
                                    timesheetTimingWorkedOn)
import Control.Monad (void)
import qualified Data.Text as Text
import Generated.Types
import IHP.ControllerPrelude

venueEffectiveRateDate :: WeekdayIndex -> Day -> Day
venueEffectiveRateDate = WeekBoundaries.venueEffectiveRateDate

venueEffectiveRateEndDate :: WeekdayIndex -> Maybe Day -> Maybe Day
venueEffectiveRateEndDate = WeekBoundaries.venueEffectiveRateEndDate

rateEffectiveOn :: (HasField "operativeFrom" record (Maybe Day), HasField "operativeTo" record (Maybe Day)) => WeekdayIndex -> Day -> record -> Bool
rateEffectiveOn weekStartsOn referenceDate record =
    maybe True ((<= referenceDate) . venueEffectiveRateDate weekStartsOn) record.operativeFrom
        && maybe True (>= referenceDate) (venueEffectiveRateEndDate weekStartsOn record.operativeTo)


payVersionManifestForEntry :: TimesheetEntry -> Maybe Text
payVersionManifestForEntry entry = do
    staffVersionId <- entry.staffPayVersionId
    shiftVersionId <- entry.shiftTypePayVersionId
    pure ("staff:" <> tshow staffVersionId <> ";shift:" <> tshow shiftVersionId)


collapsePayVersionManifests :: [Text] -> Maybe Text
collapsePayVersionManifests []        = Nothing
collapsePayVersionManifests manifests = Just (Text.intercalate " | " manifests)

ensureStaffPayVersionForStaff ::
    (?modelContext :: ModelContext) =>
    Id User ->
    Staff ->
    Day ->
    IO StaffPayVersion
ensureStaffPayVersionForStaff actorUserId staff effectiveFrom = do
    currentVersion <- query @StaffPayVersion
        |> filterWhere (#staffId, unpackId staff.id)
        |> filterWhere (#effectiveTo, Nothing :: Maybe Day)
        |> fetchOneOrNothing
    case currentVersion of
        Just version
            | version.payAssignmentMode == staff.payAssignmentMode
                && version.defaultAwardLevelId == fmap unpackId staff.defaultAwardLevelId
                && version.importedXeroPayItemId == staff.importedXeroPayItemId
                && version.employmentBasis == staff.employmentBasis ->
                pure version
        _ -> do
            forM_ currentVersion \version ->
                void
                    ( version
                        |> set #effectiveTo (Just effectiveFrom)
                        |> updateRecord
                    )
            newRecord @StaffPayVersion
                |> set #venueId staff.venueId
                |> set #staffId (unpackId staff.id)
                |> set #payAssignmentMode staff.payAssignmentMode
                |> set #defaultAwardLevelId (fmap unpackId staff.defaultAwardLevelId)
                |> set #importedXeroPayItemId staff.importedXeroPayItemId
                |> set #employmentBasis staff.employmentBasis
                |> set #effectiveFrom effectiveFrom
                |> set #createdByUserId (unpackId actorUserId)
                |> createRecord

ensureShiftTypePayVersionForShiftType ::
    (?modelContext :: ModelContext) =>
    Id User ->
    ShiftType ->
    Day ->
    IO ShiftTypePayVersion
ensureShiftTypePayVersionForShiftType actorUserId shiftType effectiveFrom = do
    currentVersion <- query @ShiftTypePayVersion
        |> filterWhere (#shiftTypeId, unpackId shiftType.id)
        |> filterWhere (#effectiveTo, Nothing :: Maybe Day)
        |> fetchOneOrNothing
    case currentVersion of
        Just version
            | version.payAssignmentMode == shiftType.payAssignmentMode
                && version.overrideAwardLevelId == fmap unpackId shiftType.overrideAwardLevelId
                && version.importedXeroPayItemId == shiftType.importedXeroPayItemId
                && version.payrollLabel == shiftType.name ->
                pure version
        _ -> do
            forM_ currentVersion \version ->
                void
                    ( version
                        |> set #effectiveTo (Just effectiveFrom)
                        |> updateRecord
                    )
            newRecord @ShiftTypePayVersion
                |> set #venueId shiftType.venueId
                |> set #shiftTypeId (unpackId shiftType.id)
                |> set #payAssignmentMode shiftType.payAssignmentMode
                |> set #overrideAwardLevelId (fmap unpackId shiftType.overrideAwardLevelId)
                |> set #importedXeroPayItemId shiftType.importedXeroPayItemId
                |> set #payrollLabel shiftType.name
                |> set #effectiveFrom effectiveFrom
                |> set #createdByUserId (unpackId actorUserId)
                |> createRecord

ensurePayVersionsForTimesheetApproval ::
    (?modelContext :: ModelContext) =>
    Id User ->
    ValidatedTimesheetTiming ->
    TimesheetEntry ->
    IO (StaffPayVersion, ShiftTypePayVersion)
ensurePayVersionsForTimesheetApproval actorUserId timing entry = do
    staff <- fetch (Id entry.staffId :: Id Staff)
    shiftType <- fetch (Id entry.shiftTypeId :: Id ShiftType)
    let workedOn = timesheetTimingWorkedOn timing
    staffVersion <- ensureStaffPayVersionForStaff actorUserId staff workedOn
    shiftTypeVersion <- ensureShiftTypePayVersionForShiftType actorUserId shiftType workedOn
    pure (staffVersion, shiftTypeVersion)

lockPayVersionsForApproval ::
    (?modelContext :: ModelContext) =>
    Id User ->
    UTCTime ->
    StaffPayVersion ->
    ShiftTypePayVersion ->
    IO ()
lockPayVersionsForApproval actorUserId lockedAt staffVersion shiftTypeVersion = do
    when (isNothing staffVersion.lockedAt) do
        void
            ( staffVersion
                |> set #lockedAt (Just lockedAt)
                |> set #lockedByUserId (Just (unpackId actorUserId))
                |> updateRecord
            )
    when (isNothing shiftTypeVersion.lockedAt) do
        void
            ( shiftTypeVersion
                |> set #lockedAt (Just lockedAt)
                |> set #lockedByUserId (Just (unpackId actorUserId))
                |> updateRecord
            )
