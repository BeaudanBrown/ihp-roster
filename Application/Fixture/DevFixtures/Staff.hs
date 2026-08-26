module Application.Fixture.DevFixtures.Staff
    ( SeededAccounts (..)
    , SeededStaff (..)
    , applySeededPayAssignments
    , seedAccounts
    , seedStaff
    ) where

import Application.Fixture
import Application.Fixture.DevFixtures.Deterministic
import Application.Fixture.Seed.Scenario (SeedScenario (..))
import Application.Helper.VenueBootstrap (provisionVenueUser)
import Control.Monad (void)
import qualified Data.Map.Strict as Map
import qualified Data.Text as Text
import qualified Data.UUID as UUID
import Generated.Types
import IHP.ControllerPrelude
import IHP.Prelude

data SeededAccounts = SeededAccounts
    { admin                  :: !User
    , supportAdmin           :: !User
    , managerUsers           :: ![User]
    , managerUser            :: !User
    , workerUser             :: !User
    , provisionedWorkerStaff :: !Staff
    , aliasStaff             :: ![Staff]
    , invitation             :: !VenueInvitation
    , defaultPasswordHash    :: !Text
    }

data SeededStaff = SeededStaff
    { managerStaffs       :: ![Staff]
    , workerStaff         :: !Staff
    , generatedStaff      :: ![Staff]
    , frontOnlyStaff      :: ![Staff]
    , backOnlyStaff       :: ![Staff]
    , crossGroupStaff     :: ![Staff]
    , trialStaffs         :: ![Staff]
    , awardStaff          :: !Staff
    , xeroStaff           :: !Staff
    , rosterOnlyStaff     :: !Staff
    , allOperationalStaff :: ![Staff]
    }

seedAccounts :: (?modelContext :: ModelContext) => Venue -> SeedScenario -> IO SeededAccounts
seedAccounts venue scenario = do
    passwordHashes <- hashDistinctSeedPasswords [testPassword, "venue2", "admin", "staff", "manager", "venue", "owner"]
    let passwordHash password =
            fromMaybe (error ("Missing dev seed password hash for " <> cs password)) (Map.lookup password passwordHashes)
        defaultPasswordHash = passwordHash testPassword
    admin <- createSeededUserRecordWithPasswordHash "venue2@bepis.lol" (passwordHash "venue2") "admin" Nothing True
    _ <- provisionVenueUser venue admin VenueAdmin "venue2" "bepis"
    supportAdmin <- createSeededUserRecordWithPasswordHash "admin@bepis.lol" (passwordHash "admin") "admin" (Just SuperAdmin) True
    managerUsers <- createManagerUsers venue defaultPasswordHash scenario.managerCount
    let managerUser = fromMaybe (error "Expected at least one seeded manager user") (listToMaybe managerUsers)
    workerUser <- createSeededUserRecordWithPasswordHash "dev-worker@example.com" defaultPasswordHash "staff" Nothing True
    (_, provisionedWorkerStaff) <- provisionVenueUser venue workerUser Worker "Willa" "Worker"
    aliasStaff <- seedSandboxRoleAliasAccounts venue passwordHashes
    invitation <- createVenueInvitationRecord venue (Just admin) "pending-invite@example.com" Worker
    pure SeededAccounts { .. }

seedStaff :: (?modelContext :: ModelContext) => Venue -> SeedScenario -> SeededAccounts -> IO SeededStaff
seedStaff venue scenario accounts = do
    managerStaffs <- mapM (createManagerStaff venue) (zip [0 ..] accounts.managerUsers)
    workerStaff <- accounts.provisionedWorkerStaff |> set #idealShiftsPerWeek 3 |> updateRecord
    generatedStaff <- createGeneratedStaff venue accounts.defaultPasswordHash scenario.scenarioSeed scenario.staffCount
    let frontOnlyStaff = takeByAssignment FrontOnly generatedStaff
    let backOnlyStaff = takeByAssignment BackOnly generatedStaff
    let crossGroupStaff = takeByAssignment CrossGroup generatedStaff
    trialStaffs <- createTrialStaff venue scenario.trialStaffCount
    let awardStaff = fromMaybe (error "Dev seed requires at least one manager staff profile") (listToMaybe managerStaffs)
    let xeroStaff = workerStaff
    let rosterOnlyStaff = fromMaybe (error "Dev seed requires at least one generated staff profile") (listToMaybe generatedStaff)
    let allOperationalStaff = managerStaffs <> [workerStaff] <> generatedStaff <> trialStaffs
    pure SeededStaff { .. }

applySeededPayAssignments ::
    (?modelContext :: ModelContext) =>
    Id AwardLevel ->
    Id XeroImportedPayItem ->
    [Staff] ->
    SeededStaff ->
    IO SeededStaff
applySeededPayAssignments awardLevelId importedPayItemId aliasStaff fixture = do
    linkedStaff <-
        query @Staff
            |> filterWhere (#venueId, fixture.workerStaff.venueId)
            |> filterWhereNot (#userId, Nothing)
            |> fetch
    linkedStaff
        |> mapM_ (updateRecord . set #payAssignmentMode AwardRate . set #defaultAwardLevelId (Just awardLevelId) . set #importedXeroPayItemId Nothing)
    awardStaff <- fixture.awardStaff |> set #payAssignmentMode AwardRate |> set #defaultAwardLevelId (Just awardLevelId) |> set #importedXeroPayItemId Nothing |> updateRecord
    xeroStaff <- fixture.xeroStaff |> set #payAssignmentMode XeroRate |> set #defaultAwardLevelId Nothing |> set #importedXeroPayItemId (Just importedPayItemId) |> updateRecord
    rosterOnlyStaff <- fixture.rosterOnlyStaff |> set #payAssignmentMode RosterOnly |> set #defaultAwardLevelId Nothing |> set #importedXeroPayItemId Nothing |> updateRecord
    remediationStaff <- maybe (fail "Dev seed requires a linked remediation profile") pure (listToMaybe aliasStaff)
    remediationStaff |> set #payAssignmentMode LegacyUnresolved |> set #defaultAwardLevelId Nothing |> set #importedXeroPayItemId Nothing |> updateRecord |> void
    refreshedStaff <-
        query @Staff
            |> filterWhere (#venueId, fixture.workerStaff.venueId)
            |> fetch
    let refreshedById = Map.fromList [(staff.id, staff) | staff <- refreshedStaff]
        refreshOne staff = fromMaybe (error ("Missing refreshed dev staff " <> show staff.id)) (Map.lookup staff.id refreshedById)
        refreshSet = map refreshOne
        managerStaffs = refreshSet fixture.managerStaffs
        generatedStaff = refreshSet fixture.generatedStaff
        frontOnlyStaff = refreshSet fixture.frontOnlyStaff
        backOnlyStaff = refreshSet fixture.backOnlyStaff
        crossGroupStaff = refreshSet fixture.crossGroupStaff
        trialStaffs = refreshSet fixture.trialStaffs
        refreshedAwardStaff = refreshOne awardStaff
        refreshedXeroStaff = refreshOne xeroStaff
        refreshedRosterOnlyStaff = refreshOne rosterOnlyStaff
        allOperationalStaff = managerStaffs <> [refreshedXeroStaff] <> generatedStaff <> trialStaffs
    pure fixture
        { managerStaffs = managerStaffs
        , workerStaff = refreshedXeroStaff
        , generatedStaff = generatedStaff
        , frontOnlyStaff = frontOnlyStaff
        , backOnlyStaff = backOnlyStaff
        , crossGroupStaff = crossGroupStaff
        , trialStaffs = trialStaffs
        , awardStaff = refreshedAwardStaff
        , xeroStaff = refreshedXeroStaff
        , rosterOnlyStaff = refreshedRosterOnlyStaff
        , allOperationalStaff = allOperationalStaff
        }

seedSandboxRoleAliasAccounts :: (?modelContext :: ModelContext) => Venue -> Map.Map Text Text -> IO [Staff]
seedSandboxRoleAliasAccounts venue passwordHashes = do
    staffUser <- seededAliasUser "staff@bepis.lol" "staff" "staff"
    (_, staffProfile) <- provisionVenueUser venue staffUser Worker "staff" "bepis"
    managerUser <- seededAliasUser "manager@bepis.lol" "manager" "manager"
    (_, managerProfile) <- provisionVenueUser venue managerUser Manager "manager" "bepis"
    venueAdminUser <- seededAliasUser "venue@bepis.lol" "venue" "admin"
    (_, venueAdminProfile) <- provisionVenueUser venue venueAdminUser VenueAdmin "venue" "bepis"
    venueOwnerUser <- seededAliasUser "owner@bepis.lol" "owner" "admin"
    (_, venueOwnerProfile) <- provisionVenueUser venue venueOwnerUser VenueOwner "owner" "bepis"
    pure [staffProfile, managerProfile, venueAdminProfile, venueOwnerProfile]
  where
    seededAliasUser emailAddress password globalRole =
        createSeededUserRecordWithPasswordHash
            emailAddress
            (fromMaybe (error ("Missing dev seed alias password hash for " <> cs password)) (Map.lookup password passwordHashes))
            globalRole
            Nothing
            True

hashDistinctSeedPasswords :: [Text] -> IO (Map.Map Text Text)
hashDistinctSeedPasswords passwords =
    Map.fromList <$> mapM hashOne (nub passwords)
  where
    hashOne password = do
        passwordHash <- hashPassword password
        pure (password, passwordHash)

createSeededUserRecordWithPasswordHash :: (?modelContext :: ModelContext) => Text -> Text -> Text -> Maybe PlatformRoleEnum -> Bool -> IO User
createSeededUserRecordWithPasswordHash emailAddress passwordHash globalRole platformRole isProfileCompleted =
    createUserRecordWithPasswordInputAndPlatformRoleAndId
        emailAddress
        (UseRuntimeFixturePasswordHash passwordHash)
        globalRole
        platformRole
        isProfileCompleted
        (seededUserIdForPasskeyEmail emailAddress)

seededUserIdForPasskeyEmail :: Text -> Maybe (Id User)
seededUserIdForPasskeyEmail emailAddress =
    Id <$> (Map.lookup emailAddress seededUserIdsForPasskeys >>= UUID.fromText)

seededUserIdsForPasskeys :: Map.Map Text Text
seededUserIdsForPasskeys =
    Map.fromList
        [ ("admin@bepis.lol", "a1642410-7297-46fd-916f-9d1ce464c388")
        , ("manager@bepis.lol", "71ced305-dc24-414c-9471-e891468e0120")
        , ("owner@bepis.lol", "7fe0607d-32aa-4a63-8a02-147b44987b43")
        , ("staff@bepis.lol", "0342d268-4d58-4c11-b925-124db23b4758")
        , ("venue@bepis.lol", "c3b1be9d-12de-49d1-9f21-e507af4c14ab")
        , ("venue2@bepis.lol", "4c83e177-4d6e-4ef2-abf3-92e9781cfc90")
        ]

createManagerUsers :: (?modelContext :: ModelContext) => Venue -> Text -> Int -> IO [User]
createManagerUsers venue defaultPasswordHash count =
    forM [0 .. max 0 (count - 1)] \index -> do
        let emailAddress = if index == 0 then "dev-manager@example.com" else "dev-manager-" <> tshow (index + 1) <> "@example.com"
        user <- createSeededUserRecordWithPasswordHash emailAddress defaultPasswordHash "manager" Nothing True
        _ <- createVenueMembershipRecord venue user Manager
        pure user

createManagerStaff :: (?modelContext :: ModelContext) => Venue -> (Int, User) -> IO Staff
createManagerStaff venue (index, user) =
    createPlaceholderStaffRecord venue (Just user) firstName lastName
        >>= updateRecord . set #idealShiftsPerWeek (4 + (index `mod` 2))
    where
        (firstName, lastName) = fromMaybe ("Morgan", "Manager") (safeIndex managerNames index)

createGeneratedStaff :: (?modelContext :: ModelContext) => Venue -> Text -> Int -> Int -> IO [Staff]
createGeneratedStaff venue defaultPasswordHash seedValue requestedCount =
    forM (take (max 0 requestedCount) generatedStaffCatalog) \(index, firstName, lastName, preferredName) -> do
        user <- createSeededUserRecordWithPasswordHash ("dev-" <> Text.toLower firstName <> "-" <> tshow (index + 1) <> "@example.com") defaultPasswordHash "staff" Nothing True
        _ <- createVenueMembershipRecord venue user Worker
        createPlaceholderStaffRecord venue (Just user) firstName lastName
            >>= updateRecord . set #preferredName (preferredNameFor seedValue index firstName preferredName)
            >>= updateRecord . set #idealShiftsPerWeek (1 + ((index + 2) `mod` 5))

createTrialStaff :: (?modelContext :: ModelContext) => Venue -> Int -> IO [Staff]
createTrialStaff venue requestedCount =
    forM [0 .. max 0 (requestedCount - 1)] \index ->
        createPlaceholderStaffRecord venue Nothing "Taylor" ("Trial " <> tshow (index + 1))
            >>= updateRecord . set #idealShiftsPerWeek 1

data StaffAssignmentBucket = FrontOnly | BackOnly | CrossGroup deriving (Eq)

takeByAssignment :: StaffAssignmentBucket -> [Staff] -> [Staff]
takeByAssignment bucket staff =
    map snd (filter (\(index, _) -> assignmentBucket index == bucket) (zip [0 :: Int ..] staff))

assignmentBucket :: Int -> StaffAssignmentBucket
assignmentBucket index =
    case index `mod` 6 of
        1 -> CrossGroup
        2 -> BackOnly
        5 -> BackOnly
        _ -> FrontOnly

preferredNameFor :: Int -> Int -> Text -> Maybe Text -> Maybe Text
preferredNameFor _ _ _ (Just preferredName) = Just preferredName
preferredNameFor seedValue index firstName Nothing
    | deterministicPercent seedValue [index, 601] < 32 = generatedNickname firstName
    | otherwise = Nothing

generatedNickname :: Text -> Maybe Text
generatedNickname firstName =
    case Text.toLower firstName of
        "alice" -> Just "Ali"
        "cara"  -> Just "C"
        "dylan" -> Just "Dyl"
        "frank" -> Just "Frankie"
        "jules" -> Just "J"
        "talia" -> Just "T"
        _       -> Nothing

managerNames :: [(Text, Text)]
managerNames =
    [ ("Morgan", "Manager")
    , ("Harper", "Lead")
    , ("Casey", "Shiftlead")
    , ("Jordan", "Supervisor")
    ]

generatedStaffCatalog :: [(Int, Text, Text, Maybe Text)]
generatedStaffCatalog =
    zipWith (\index (firstName, lastName, preferredName) -> (index, firstName, lastName, preferredName)) [0 ..]
        [ ("Alice", "Front", Nothing)
        , ("Bob", "Both", Nothing)
        , ("James", "Lebron", Just "JL")
        , ("Oliver", "Grey", Nothing)
        , ("Odette", "Garrison", Nothing)
        , ("Sally", "Martin", Nothing)
        , ("Sonia", "Michaels", Nothing)
        , ("Tracy", "Green", Nothing)
        , ("Alice", "Host", Just "Ali")
        , ("Jules", "Cook", Nothing)
        , ("Kira", "Cafe", Nothing)
        , ("Luca", "Pass", Nothing)
        , ("Mia", "Morning", Nothing)
        , ("Noah", "Dish", Nothing)
        , ("Omar", "Floor", Nothing)
        , ("Piper", "Expo", Nothing)
        , ("Quinn", "Late", Nothing)
        , ("Rosa", "Morning", Just "Rosie")
        , ("Seth", "Grill", Nothing)
        , ("Talia", "Barista", Just "T")
        ]
