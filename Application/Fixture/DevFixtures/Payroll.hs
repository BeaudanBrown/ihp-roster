module Application.Fixture.DevFixtures.Payroll
    ( PayFixture (..)
    , ensurePayReferenceData
    , seedShiftTypes
    , seedTimesheetProjection
    ) where

import Application.Fixture
import Application.Fixture.DevFixtures.Deterministic
import Application.Fixture.Seed.Scenario
import Application.Fixture.WageSourceFixtures (ensureFreshWageSourceFacts)
import Application.Helper.Pay (ensurePayVersionsForTimesheetApproval,
                               ensureShiftTypePayVersionForShiftType,
                               lockPayVersionsForApproval)
import Application.Helper.ShiftTypeColours (blankShiftTypeColourKey)
import Application.Helper.TimesheetPayLedger (persistDevSeedApprovedTimesheetPayCalculation)
import Application.PayAssignment (StaffPayAssignment (..),
                                  staffAssignmentAllowsTimesheets)
import Application.VenueTime (melbourneTimeZoneName)
import Application.VenueTime.Model
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import Data.Time.Calendar (Day, addDays, fromGregorian)
import Data.Time.Clock (UTCTime, getCurrentTime)
import Data.Time.LocalTime (TimeOfDay (..))
import Data.UUID (UUID)
import qualified Data.UUID as UUID
import Generated.Types
import IHP.ControllerPrelude
import IHP.ModelSupport (sqlExecDiscardResult)
import IHP.ModelSupport.Types (CanCreate (createMany))
import IHP.Prelude
import qualified IHP.Prelude as Prelude

data PayFixture = PayFixture
    { floorShift      :: !ShiftType
    , kitchenShift    :: !ShiftType
    , allShiftTypes   :: ![ShiftType]
    , floorAwardLevel :: !(Id AwardLevel)
    , importedPayItem :: !XeroImportedPayItem
    }

ensurePayReferenceData :: (?modelContext :: ModelContext) => IO ()
ensurePayReferenceData = ensureSeedShiftTypeAwardLevels

seedShiftTypes :: (?modelContext :: ModelContext) => Venue -> User -> Day -> IO PayFixture
seedShiftTypes venue admin fixtureWeekStart = do
    importedPayItem <- createSeedImportedXeroPayItem venue admin
    floorShift <- createSeedShiftTypeRecord venue admin fixtureWeekStart "Floor" 10 Palette1 StaffDefault Nothing Nothing
    kitchenShift <- createSeedShiftTypeRecord venue admin fixtureWeekStart "Kitchen" 20 Palette2 AwardRate (Just seededKitchenAwardLevelId) Nothing
    extraShiftTypes <- forM (seedExtraShiftTypeSpecs importedPayItem.id) \(shiftTypeName, sortOrder, colourKey, payMode, awardLevelId, importedPayItemId) ->
        createSeedShiftTypeRecord venue admin fixtureWeekStart shiftTypeName sortOrder colourKey payMode awardLevelId importedPayItemId
    let allShiftTypes = [floorShift, kitchenShift] <> extraShiftTypes
    let floorAwardLevel = seededFloorAwardLevelId
    pure PayFixture { .. }

seedTimesheetProjection ::
    (?modelContext :: ModelContext) =>
    Day -> Venue -> User -> SeedScenario -> PayFixture -> [Staff] -> UTCTime -> IO ()
seedTimesheetProjection fixtureWeekStart venue admin scenario payFixture staff approvedAt =
    seedTimesheets fixtureWeekStart venue admin scenario payFixture.floorShift payFixture.kitchenShift staff approvedAt

applyDevTimesheetBoundaries :: Day -> TimeOfDay -> TimeOfDay -> Bool -> Maybe TimeOfDay -> Maybe TimeOfDay -> TimesheetEntry -> TimesheetEntry
applyDevTimesheetBoundaries workedOn startTime endTime hadBreak maybeBreakStart maybeBreakEnd entry =
    let breakInput =
            if hadBreak
                then Just BreakBoundaryInput
                    { breakBoundaryStartTime = fromMaybe (error "Missing seeded break start") maybeBreakStart
                    , breakBoundaryStartOccurrence = Nothing
                    , breakBoundaryEndTime = fromMaybe (error "Missing seeded break end") maybeBreakEnd
                    , breakBoundaryEndOccurrence = Nothing
                    }
                else Nothing
        boundaries =
            either (error . ("Invalid seeded timesheet boundaries: " <>) . show) Prelude.id $
                resolveShiftBoundaries entry.timezone ShiftBoundaryInput
                    { shiftBoundaryDate = workedOn
                    , shiftBoundaryStartTime = startTime
                    , shiftBoundaryStartOccurrence = Nothing
                    , shiftBoundaryEndTime = endTime
                    , shiftBoundaryEndOccurrence = Nothing
                    , shiftBoundaryBreak = breakInput
                    }
     in applyTimesheetEntryBoundaries boundaries entry


createSeedShiftTypeRecord :: (?modelContext :: ModelContext) => Venue -> User -> Day -> Text -> Int -> ShiftTypeColourKeyEnum -> PayAssignmentModeEnum -> Maybe (Id AwardLevel) -> Maybe (Id XeroImportedPayItem) -> IO ShiftType
createSeedShiftTypeRecord venue actorUser effectiveFrom shiftTypeName sortOrder colourKey payMode awardLevelId importedPayItemId = do
    shiftType <-
        newRecord @ShiftType
            |> set #venueId (unpackId (get #id venue))
            |> set #name shiftTypeName
            |> set #sortOrder sortOrder
            |> set #colourKey colourKey
            |> set #payAssignmentMode payMode
            |> set #overrideAwardLevelId awardLevelId
            |> set #importedXeroPayItemId importedPayItemId
            |> set #isActive True
            |> createRecord
    _ <- ensureShiftTypePayVersionForShiftType actorUser.id shiftType effectiveFrom
    pure shiftType

seedExtraShiftTypeSpecs :: Id XeroImportedPayItem -> [(Text, Int, ShiftTypeColourKeyEnum, PayAssignmentModeEnum, Maybe (Id AwardLevel), Maybe (Id XeroImportedPayItem))]
seedExtraShiftTypeSpecs importedPayItemId =
    [ ("Bar", 30, blankShiftTypeColourKey, XeroRate, Nothing, Just importedPayItemId)
    , ("Gaming", 40, blankShiftTypeColourKey, RosterOnly, Nothing, Nothing)
    , ("Glassy", 50, blankShiftTypeColourKey, AwardRate, Just seededFloorAwardLevelId, Nothing)
    , ("Cellar", 60, blankShiftTypeColourKey, AwardRate, Just seededFloorAwardLevelId, Nothing)
    , ("Functions", 70, blankShiftTypeColourKey, AwardRate, Just seededFloorAwardLevelId, Nothing)
    , ("Runner", 80, blankShiftTypeColourKey, AwardRate, Just seededFloorAwardLevelId, Nothing)
    , ("Door", 90, blankShiftTypeColourKey, AwardRate, Just seededKitchenAwardLevelId, Nothing)
    , ("Supervisor", 100, blankShiftTypeColourKey, AwardRate, Just seededKitchenAwardLevelId, Nothing)
    ]

createSeedImportedXeroPayItem :: (?modelContext :: ModelContext) => Venue -> User -> IO XeroImportedPayItem
createSeedImportedXeroPayItem venue importedBy = do
    connection <-
        newRecord @XeroConnection
            |> set #venueId (unpackId venue.id)
            |> set #tenantId ("dev-seed-pay-tenant" :: Text)
            |> set #tenantName (Just "Development Seed Payroll")
            |> set #connectionStatus ("active" :: Text)
            |> set #scopes ("payroll.employees payroll.payitems" :: Text)
            |> set #encryptedRefreshToken ("dev-seed-encrypted-refresh-token" :: Text)
            |> set #connectedByUserId (Just (unpackId importedBy.id))
            |> createRecord
    newRecord @XeroImportedPayItem
        |> set #venueId (unpackId venue.id)
        |> set #xeroConnectionId (unpackId connection.id)
        |> set #xeroEarningsRateId ("dev-seed-ordinary-hours" :: Text)
        |> set #name ("Development ordinary hours" :: Text)
        |> set #accountCode (Just "477")
        |> set #earningsType ("ORDINARYTIMEEARNINGS" :: Text)
        |> set #rateType ("RATEPERUNIT" :: Text)
        |> set #typeOfUnits ("Hours" :: Text)
        |> set #ratePerUnit 34.5
        |> set #rawPayload (Aeson.object [])
        |> set #importedByUserId (unpackId importedBy.id)
        |> createRecord

seededFloorAwardLevelId :: Id AwardLevel
seededFloorAwardLevelId =
    seededHospitalityAwardLevelId "2cba4998-4691-4eeb-9bd3-e79263c54769"

seededKitchenAwardLevelId :: Id AwardLevel
seededKitchenAwardLevelId =
    seededHospitalityAwardLevelId "8a53b7c8-574c-49f8-abd4-0caf3b46a22f"

seededHospitalityAwardLevelId :: Text -> Id AwardLevel
seededHospitalityAwardLevelId value =
    Id (fromMaybe (error ("Invalid dev award level id: " <> cs value)) (UUID.fromText value))


ensureSeedShiftTypeAwardLevels :: (?modelContext :: ModelContext) => IO ()
ensureSeedShiftTypeAwardLevels = do
    sqlExecDiscardResult
        "INSERT INTO award_levels (id, award_fixed_id, classification_fixed_id, classification, classification_level, parent_classification_name, clause_description, operative_from, operative_to, published_year, is_active, raw_json) VALUES ('2cba4998-4691-4eeb-9bd3-e79263c54769', 9, 243, 'Level 1', '2.0', 'Food and beverage attendant grade 1; Guest service grade 1; Kitchen attendant grade 1', 'Hospitality Employees', '2025-07-01', NULL, 2025, TRUE, '{}'::jsonb), ('8a53b7c8-574c-49f8-abd4-0caf3b46a22f', 9, 268, 'Level 4', '5.0', 'Clerical grade 3; Cook (tradesperson) grade 3; Food and beverage attendant (tradesperson) grade 4; Front office grade 3; Gardener grade 3 (tradesperson); Guest service grade 4; Leisure attendant grade 3; Storeperson grade 3', 'Hospitality Employees', '2025-07-01', NULL, 2025, TRUE, '{}'::jsonb) ON CONFLICT (id) DO NOTHING"
        ()
    sqlExecDiscardResult
        "DO $$ BEGIN INSERT INTO award_levels (award_fixed_id, classification_fixed_id, classification, classification_level, operative_from, published_year, is_active) SELECT 9, fixed_id, label, level, DATE '2025-07-01', 2025, TRUE FROM (VALUES (242, 'Introductory', '1.0'), (246, 'Level 2', '3.0'), (257, 'Level 3', '4.0'), (276, 'Level 5', '6.0'), (282, 'Level 6', '7.0')) AS missing(fixed_id, label, level) ON CONFLICT (award_fixed_id, classification_fixed_id) DO NOTHING; INSERT INTO fwc_mapd_pay_rates (award_fixed_id, classification_fixed_id, classification, calculated_rate, calculated_rate_type, operative_from, published_year) SELECT 9, level.classification_fixed_id, level.classification, 30, 'Hourly', DATE '2025-07-01', 2025 FROM award_levels level WHERE level.award_fixed_id = 9 AND NOT EXISTS (SELECT 1 FROM fwc_mapd_pay_rates source WHERE source.award_fixed_id = 9 AND source.classification_fixed_id = level.classification_fixed_id AND source.operative_from = DATE '2025-07-01'); INSERT INTO fwc_mapd_penalty_rates (award_fixed_id, classification_fixed_id, classification, penalty_description, penalty_calculated_value, operative_from, published_year) SELECT 9, level.classification_fixed_id, level.classification, 'Dev seed penalty source', 60, DATE '2025-07-01', 2025 FROM award_levels level WHERE level.award_fixed_id = 9 AND NOT EXISTS (SELECT 1 FROM fwc_mapd_penalty_rates source WHERE source.award_fixed_id = 9 AND source.classification_fixed_id = level.classification_fixed_id AND source.operative_from = DATE '2025-07-01'); INSERT INTO fwc_mapd_wage_allowances (award_fixed_id, wage_allowance_fixed_id, allowance, allowance_amount, operative_from, published_year) SELECT 9, fixed_id, label, amount, DATE '2025-07-01', 2025 FROM (VALUES (700001, 'Dev evening addition', 2.50::numeric), (700002, 'Dev early morning addition', 3.00::numeric)) AS source(fixed_id, label, amount) WHERE NOT EXISTS (SELECT 1 FROM fwc_mapd_wage_allowances existing WHERE existing.award_fixed_id = 9 AND existing.wage_allowance_fixed_id = source.fixed_id); INSERT INTO award_level_base_rates (award_level_id, employment_basis, fwc_mapd_pay_rate_id, hourly_rate, rate_label, operative_from, published_year) SELECT level.id, basis.value::staff_employment_basis_enum, source.id, CASE basis.value WHEN 'casual' THEN 37.50 ELSE 30 END, 'Dev seed hourly', DATE '2025-07-01', 2025 FROM award_levels level CROSS JOIN (VALUES ('permanent'), ('casual')) AS basis(value) JOIN fwc_mapd_pay_rates source ON source.classification_fixed_id = level.classification_fixed_id AND source.operative_from = DATE '2025-07-01' WHERE level.award_fixed_id = 9 AND NOT EXISTS (SELECT 1 FROM award_level_base_rates existing WHERE existing.award_level_id = level.id AND existing.employment_basis = basis.value::staff_employment_basis_enum AND existing.operative_from IS NOT DISTINCT FROM DATE '2025-07-01' AND existing.operative_to IS NULL); INSERT INTO award_level_penalty_rates (award_level_id, employment_basis, penalty_kind, fwc_mapd_penalty_rate_id, hourly_rate, operative_from, published_year) SELECT level.id, basis.value::staff_employment_basis_enum, penalty.kind::award_penalty_kind_enum, source.id, penalty.rate, DATE '2025-07-01', 2025 FROM award_levels level CROSS JOIN (VALUES ('permanent'), ('casual')) AS basis(value) CROSS JOIN (VALUES ('saturday_penalty', 45.00::numeric), ('sunday_penalty', 52.50::numeric), ('public_holiday_penalty', 67.50::numeric)) AS penalty(kind, rate) JOIN fwc_mapd_penalty_rates source ON source.classification_fixed_id = level.classification_fixed_id AND source.operative_from = DATE '2025-07-01' WHERE level.award_fixed_id = 9 AND NOT EXISTS (SELECT 1 FROM award_level_penalty_rates existing WHERE existing.award_level_id = level.id AND existing.employment_basis = basis.value::staff_employment_basis_enum AND existing.penalty_kind = penalty.kind::award_penalty_kind_enum AND existing.operative_from IS NOT DISTINCT FROM DATE '2025-07-01' AND existing.operative_to IS NULL); INSERT INTO award_time_penalty_allowances (award_fixed_id, penalty_kind, fwc_mapd_wage_allowance_id, hourly_amount, starts_at_time, ends_at_time, operative_from, published_year) SELECT 9, values_row.kind::award_penalty_kind_enum, source.id, values_row.amount, values_row.starts_at, values_row.ends_at, DATE '2025-07-01', 2025 FROM (VALUES ('evening_after_7pm', 2.50::numeric, TIME '19:00', TIME '00:00', 700001), ('late_night_after_midnight', 3.00::numeric, TIME '00:00', TIME '07:00', 700002)) AS values_row(kind, amount, starts_at, ends_at, fixed_id) JOIN fwc_mapd_wage_allowances source ON source.wage_allowance_fixed_id = values_row.fixed_id AND source.operative_from = DATE '2025-07-01' WHERE NOT EXISTS (SELECT 1 FROM award_time_penalty_allowances existing WHERE existing.award_fixed_id = 9 AND existing.penalty_kind = values_row.kind::award_penalty_kind_enum AND existing.operative_from IS NOT DISTINCT FROM DATE '2025-07-01' AND existing.operative_to IS NULL); END $$"
        ()
    pure ()


seedTimesheets ::
    (?modelContext :: ModelContext) =>
    Day ->
    Venue ->
    User ->
    SeedScenario ->
    ShiftType ->
    ShiftType ->
    [Staff] ->
    UTCTime ->
    IO ()
seedTimesheets fixtureWeekStart venue admin scenario floorShift kitchenShift staffPool approvedAt = do
    let timesheetStaffPool = filter staffCanProduceTimesheets staffPool
    when (null timesheetStaffPool) $ fail "Dev seed requires at least one Timesheet-eligible staff profile"
    seededXeroCaseCount <-
        seedXeroPayCalendarTimesheets
            venue
            admin
            floorShift
            kitchenShift
            timesheetStaffPool
            approvedAt
    let remainingApprovedCount = max 0 (scenario.approvedTimesheets - seededXeroCaseCount)
    let approvedStaffPool = concat (replicate 3 (seededXeroMatchedStaffPool timesheetStaffPool)) <> timesheetStaffPool
    forM_ (zip [0 ..] (take remainingApprovedCount (cycle approvedStaffPool))) \(index, staff) -> do
        let globalIndex = index + seededXeroCaseCount
        let shiftType =
                if globalIndex `mod` 4 == 0
                    then kitchenShift
                    else floorShift
        let shiftStartTime = TimeOfDay (6 + ((globalIndex * 2) `mod` 8)) 0 0
        let shiftEndTime = TimeOfDay (12 + ((globalIndex * 2) `mod` 8)) 0 0
        let (hadBreak, breakStartTime, breakEndTime, _breakMinutes) =
                seededBreakFields scenario.scenarioSeed globalIndex shiftStartTime shiftEndTime
        let workedOn = seededTimesheetWorkedOn fixtureWeekStart globalIndex
        entry <-
            createTimesheetEntryRecordForShiftType venue staff shiftType workedOn
                >>= updateRecord
                    . applyDevTimesheetBoundaries workedOn
                        shiftStartTime
                        shiftEndTime
                        hadBreak
                        breakStartTime
                        breakEndTime
        (staffPayVersion, shiftTypePayVersion) <- ensurePayVersionsForTimesheetApproval admin.id entry
        lockPayVersionsForApproval admin.id approvedAt staffPayVersion shiftTypePayVersion
        _ <- approveSeededTimesheetEntryWithVersions admin approvedAt staffPayVersion shiftTypePayVersion entry
        pure ()
    let pendingStaffPool = nonXeroMatchedStaffPool timesheetStaffPool <> timesheetStaffPool
        pendingInputs = zip [0 ..] (take scenario.pendingTimesheets (drop scenario.approvedTimesheets (cycle pendingStaffPool)))
    pendingIds <- map Id <$> freshUUIDs (length pendingInputs)
    pendingCreatedAt <- getCurrentTime
    let pendingEntries =
            [ let globalIndex = scenario.approvedTimesheets + index
                  shiftStartTime = TimeOfDay (9 + (index `mod` 3)) 0 0
                  shiftEndTime = TimeOfDay (15 + (index `mod` 3)) 0 0
                  (hadBreak, breakStartTime, breakEndTime, _breakMinutes) =
                      seededBreakFields scenario.scenarioSeed globalIndex shiftStartTime shiftEndTime
                  workedOn = seededTimesheetWorkedOn fixtureWeekStart (globalIndex + 2)
               in newRecord @TimesheetEntry
                    |> set #id pendingId
                    |> set #venueId (unpackId venue.id)
                    |> set #staffId (unpackId staff.id)
                    |> set #shiftTypeId (unpackId floorShift.id)
                    |> set #operationalDate workedOn
                    |> set #timezone melbourneTimeZoneName
                    |> applyDevTimesheetBoundaries workedOn
                        shiftStartTime
                        shiftEndTime
                        hadBreak
                        breakStartTime
                        breakEndTime
                    |> set #createdAt pendingCreatedAt
                    |> set #updatedAt pendingCreatedAt
            | (pendingId, (index, staff)) <- zip pendingIds pendingInputs
            ]
    unless (null pendingEntries) (void (createMany pendingEntries))
  where
    staffCanProduceTimesheets staff =
        staffAssignmentAllowsTimesheets
            (StaffPayAssignment staff.payAssignmentMode staff.defaultAwardLevelId staff.importedXeroPayItemId)

data SeededXeroTimesheetCase = SeededXeroTimesheetCase
    { caseFirstName :: !Text
    , caseLastName  :: !Text
    , caseWorkedOn  :: !Day
    , caseShiftType :: !SeededTimesheetShiftType
    , caseStartTime :: !TimeOfDay
    , caseEndTime   :: !TimeOfDay
    , caseBreak     :: !SeededTimesheetBreak
    }

data SeededTimesheetShiftType
    = SeededFloorShift
    | SeededKitchenShift

data SeededTimesheetBreak
    = SeededNoBreak
    | SeededBreak !TimeOfDay !TimeOfDay !Int

seedXeroPayCalendarTimesheets ::
    (?modelContext :: ModelContext) =>
    Venue ->
    User ->
    ShiftType ->
    ShiftType ->
    [Staff] ->
    UTCTime ->
    IO Int
seedXeroPayCalendarTimesheets venue admin floorShift kitchenShift staffPool approvedAt = do
    entries <-
        forM seededXeroPayCalendarCases \seedCase ->
            case findStaffByName seedCase.caseFirstName seedCase.caseLastName staffPool of
                Nothing -> pure Nothing
                Just staff -> do
                    Just <$> createApprovedSeededTimesheetCase venue admin floorShift kitchenShift staff approvedAt seedCase
    pure (length (catMaybes entries))

createApprovedSeededTimesheetCase ::
    (?modelContext :: ModelContext) =>
    Venue ->
    User ->
    ShiftType ->
    ShiftType ->
    Staff ->
    UTCTime ->
    SeededXeroTimesheetCase ->
    IO TimesheetEntry
createApprovedSeededTimesheetCase venue admin floorShift kitchenShift staff approvedAt seedCase = do
    let (hadBreak, breakStartTime, breakEndTime) = seededBreakBoundaries seedCase.caseBreak
    let shiftType = seededCaseShiftType seedCase.caseShiftType floorShift kitchenShift
    entry <-
        createTimesheetEntryRecordForShiftType venue staff shiftType seedCase.caseWorkedOn
            >>= updateRecord
                . applyDevTimesheetBoundaries
                    seedCase.caseWorkedOn
                    seedCase.caseStartTime
                    seedCase.caseEndTime
                    hadBreak
                    breakStartTime
                    breakEndTime
    approveSeededTimesheetEntry admin approvedAt entry

approveSeededTimesheetEntry ::
    (?modelContext :: ModelContext) =>
    User ->
    UTCTime ->
    TimesheetEntry ->
    IO TimesheetEntry
approveSeededTimesheetEntry admin approvedAt entry = do
    (staffPayVersion, shiftTypePayVersion) <- ensurePayVersionsForTimesheetApproval admin.id entry
    lockPayVersionsForApproval admin.id approvedAt staffPayVersion shiftTypePayVersion
    approveSeededTimesheetEntryWithVersions admin approvedAt staffPayVersion shiftTypePayVersion entry

approveSeededTimesheetEntryWithVersions ::
    (?modelContext :: ModelContext) =>
    User ->
    UTCTime ->
    StaffPayVersion ->
    ShiftTypePayVersion ->
    TimesheetEntry ->
    IO TimesheetEntry
approveSeededTimesheetEntryWithVersions admin approvedAt staffPayVersion shiftTypePayVersion entry = do
    ensureFreshWageSourceFacts (timesheetEntryWorkedOn entry)
    let approvalEntry =
            entry
                |> set #isApproved True
                |> set #staffPayVersionId (Just (unpackId staffPayVersion.id))
                |> set #shiftTypePayVersionId (Just (unpackId shiftTypePayVersion.id))
                |> set #approvedAt (Just approvedAt)
                |> set #approvedByUserId (Just (unpackId admin.id))
    persisted <- persistDevSeedApprovedTimesheetPayCalculation approvalEntry
    calculation <- either (fail . cs) pure persisted
    approvalEntry
        |> set #activePayCalculationId (Just calculation.id)
        |> updateRecord

seededCaseShiftType :: SeededTimesheetShiftType -> ShiftType -> ShiftType -> ShiftType
seededCaseShiftType SeededFloorShift floorShift _     = floorShift
seededCaseShiftType SeededKitchenShift _ kitchenShift = kitchenShift

seededBreakBoundaries :: SeededTimesheetBreak -> (Bool, Maybe TimeOfDay, Maybe TimeOfDay)
seededBreakBoundaries SeededNoBreak = (False, Nothing, Nothing)
seededBreakBoundaries (SeededBreak startTime endTime _minutes) =
    (True, Just startTime, Just endTime)

findStaffByName :: Text -> Text -> [Staff] -> Maybe Staff
findStaffByName firstName lastName =
    find (\staff -> staff.firstName == firstName && staff.lastName == lastName)

seededXeroPayCalendarCases :: [SeededXeroTimesheetCase]
seededXeroPayCalendarCases =
    -- Fortnightly Calendar current period ending 26 May 2026.
    seededXeroCalendarWindowCases
        (fromGregorian 2026 5 13)
        (fromGregorian 2026 5 26)
        [ ("James", "Lebron")
        , ("Oliver", "Grey")
        , ("Sally", "Martin")
        ]
        <>
    -- Weekly Calendar current period ending 5 May 2026.
    seededXeroCalendarWindowCases
        (fromGregorian 2026 4 29)
        (fromGregorian 2026 5 5)
        [ ("Odette", "Garrison")
        , ("Tracy", "Green")
        ]

seededXeroCalendarWindowCases :: Day -> Day -> [(Text, Text)] -> [SeededXeroTimesheetCase]
seededXeroCalendarWindowCases startDate endDate staffNames =
    concat
        [ map (seededXeroCaseForDay staffIndex firstName lastName) (zip [0 ..] (dateRange startDate endDate))
        | (staffIndex, (firstName, lastName)) <- zip [0 ..] staffNames
        ]

seededXeroCaseForDay :: Int -> Text -> Text -> (Int, Day) -> SeededXeroTimesheetCase
seededXeroCaseForDay staffIndex firstName lastName (dayIndex, workedOn) =
    let template = seededXeroTimesheetTemplates !! ((staffIndex * 3 + dayIndex) `mod` length seededXeroTimesheetTemplates)
     in xeroCase firstName lastName workedOn template.templateShiftType template.templateStartTime template.templateEndTime template.templateBreak

dateRange :: Day -> Day -> [Day]
dateRange startDate endDate =
    takeWhile (<= endDate) (iterate (addDays 1) startDate)

data SeededXeroTimesheetTemplate = SeededXeroTimesheetTemplate
    { templateShiftType :: !SeededTimesheetShiftType
    , templateStartTime :: !TimeOfDay
    , templateEndTime   :: !TimeOfDay
    , templateBreak     :: !SeededTimesheetBreak
    }

seededXeroTimesheetTemplates :: [SeededXeroTimesheetTemplate]
seededXeroTimesheetTemplates =
    [ xeroTemplate SeededFloorShift (TimeOfDay 9 0 0) (TimeOfDay 17 0 0) (SeededBreak (TimeOfDay 15 30 0) (TimeOfDay 16 0 0) 30)
    , xeroTemplate SeededFloorShift (TimeOfDay 18 0 0) (TimeOfDay 1 0 0) (SeededBreak (TimeOfDay 21 30 0) (TimeOfDay 22 0 0) 30)
    , xeroTemplate SeededKitchenShift (TimeOfDay 10 0 0) (TimeOfDay 16 0 0) (SeededBreak (TimeOfDay 12 30 0) (TimeOfDay 13 0 0) 30)
    , xeroTemplate SeededFloorShift (TimeOfDay 22 0 0) (TimeOfDay 2 0 0) (SeededBreak (TimeOfDay 23 30 0) (TimeOfDay 0 0 0) 30)
    , xeroTemplate SeededKitchenShift (TimeOfDay 8 0 0) (TimeOfDay 14 0 0) SeededNoBreak
    , xeroTemplate SeededFloorShift (TimeOfDay 12 0 0) (TimeOfDay 20 0 0) SeededNoBreak
    , xeroTemplate SeededKitchenShift (TimeOfDay 6 0 0) (TimeOfDay 14 0 0) (SeededBreak (TimeOfDay 10 0 0) (TimeOfDay 10 30 0) 30)
    ]

xeroTemplate ::
    SeededTimesheetShiftType ->
    TimeOfDay ->
    TimeOfDay ->
    SeededTimesheetBreak ->
    SeededXeroTimesheetTemplate
xeroTemplate shiftType startTime endTime timesheetBreak =
    SeededXeroTimesheetTemplate
        { templateShiftType = shiftType
        , templateStartTime = startTime
        , templateEndTime = endTime
        , templateBreak = timesheetBreak
        }

xeroCase ::
    Text ->
    Text ->
    Day ->
    SeededTimesheetShiftType ->
    TimeOfDay ->
    TimeOfDay ->
    SeededTimesheetBreak ->
    SeededXeroTimesheetCase
xeroCase firstName lastName workedOn shiftType startTime endTime timesheetBreak =
    SeededXeroTimesheetCase
        { caseFirstName = firstName
        , caseLastName = lastName
        , caseWorkedOn = workedOn
        , caseShiftType = shiftType
        , caseStartTime = startTime
        , caseEndTime = endTime
        , caseBreak = timesheetBreak
        }

seededTimesheetWorkedOn :: Day -> Int -> Day
seededTimesheetWorkedOn fixtureWeekStart index =
    addDays (toInteger weekStartOffset + toInteger (index `mod` 7)) fixtureWeekStart
    where
        weekStartOffset =
            case index `mod` 3 of
                0 -> -7
                1 -> 0
                _ -> 7

seededXeroMatchedStaffPool :: [Staff] -> [Staff]
seededXeroMatchedStaffPool staffPool =
    filter seededStaffHasXeroEmployeeMatch staffPool

nonXeroMatchedStaffPool :: [Staff] -> [Staff]
nonXeroMatchedStaffPool staffPool =
    filter (not . seededStaffHasXeroEmployeeMatch) staffPool

seededStaffHasXeroEmployeeMatch :: Staff -> Bool
seededStaffHasXeroEmployeeMatch staff =
    (staff.firstName, staff.lastName)
        `elem`
            [ ("Alice", "Front")
            , ("Bob", "Both")
            , ("James", "Lebron")
            , ("Oliver", "Grey")
            , ("Odette", "Garrison")
            , ("Sally", "Martin")
            , ("Tracy", "Green")
            ]

seededBreakFields :: Int -> Int -> TimeOfDay -> TimeOfDay -> (Bool, Maybe TimeOfDay, Maybe TimeOfDay, Int)
seededBreakFields seedValue index shiftStartTime shiftEndTime
    | deterministicPercent seedValue [index, 901] < 80 =
        let breakLengthMinutes = if deterministicPercent seedValue [index, 903] < 55 then 30 else 45
            shiftStartMinutes = timeOfDayToMinutes shiftStartTime
            rawShiftEndMinutes = timeOfDayToMinutes shiftEndTime
            shiftEndMinutes = if rawShiftEndMinutes <= shiftStartMinutes then rawShiftEndMinutes + 1440 else rawShiftEndMinutes
            breakStartMinutes = shiftStartMinutes + ((shiftEndMinutes - shiftStartMinutes - breakLengthMinutes) `div` 2)
            breakStartTime = minutesToTimeOfDay breakStartMinutes
            breakEndTime = addBreakMinutes breakStartTime breakLengthMinutes
         in (True, Just breakStartTime, Just breakEndTime, breakLengthMinutes)
    | otherwise = (False, Nothing, Nothing, 0)

addBreakMinutes :: TimeOfDay -> Int -> TimeOfDay
addBreakMinutes startTime minutes =
    let totalMinutes = todHour startTime * 60 + todMin startTime + minutes
     in TimeOfDay (totalMinutes `div` 60) (totalMinutes `mod` 60) 0
