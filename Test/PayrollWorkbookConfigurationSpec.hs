module Test.PayrollWorkbookConfigurationSpec where

import Control.Exception (SomeException, try)
import qualified Data.Aeson as Aeson
import Data.Either (isLeft, isRight)
import qualified Data.Text as Text
import qualified Data.Text.IO as TextIO
import Data.Time.Clock (addUTCTime, getCurrentTime)
import Generated.Types
import qualified Hasql.Session as HasqlSession
import IHP.Controller.Context (ControllerContext)
import IHP.ControllerPrelude
import IHP.ModelSupport.Types (ModelContext (transactionRunner),
                               TransactionRunner (runInTransaction))
import IHP.Test.Mocking (MockContext, withContext, withUser)
import qualified Network.Wai as Wai
import Test.Hspec

import Application.Helper.ControllerContext (currentVenueSessionKey)
import Application.Helper.Export
import Test.Support
import Web.FrontController ()
import Web.Types (WebApplication)

newConfiguration :: Text -> Int -> [Text] -> NewPayrollWorkbookConfiguration
newConfiguration name version familyKeys =
    NewPayrollWorkbookConfiguration
        { newPayrollWorkbookConfigurationName = name
        , newPayrollWorkbookConfigurationDefinitionVersion = version
        , newPayrollWorkbookConfigurationFamilyKeys = familyKeys
        }

tests :: Spec
tests = aroundAll withDatabaseTestContext do
    describe "Payroll Workbook saved configurations" do
        it "normalizes names and round-trips ordered presentation families without persisting the built-in default" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Saved Workbook Venue"
                admin <- createUserRecord "saved-workbook-admin@example.com" "admin" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin

                initialCount <- query @PayrollWorkbookConfiguration |> fetchCount
                initialCount `shouldBe` 0
                defaultPayrollWorkbookDefinition.payrollWorkbookDefinitionKey `shouldBe` "builtin-default"

                created <- asCurrentVenueUser admin venue.id do
                    createSavedPayrollWorkbookConfiguration
                        (newConfiguration
                            "  Weekly   Payroll  "
                            1
                            [ "shift-type-wages"
                            , "summary"
                            , "employee-pay-bucket-hours"
                            ]
                        )
                saved <- expectRight created
                saved.savedPayrollWorkbookConfigurationRecord.name `shouldBe` "Weekly Payroll"
                saved.savedPayrollWorkbookConfigurationDefinition.payrollWorkbookDefinitionSheetFamilies
                    `shouldBe`
                        [ PayrollWorkbookShiftTypeWages
                        , PayrollWorkbookSummary
                        , PayrollWorkbookEmployeePayBucketHours
                        ]

                listed <- asCurrentVenueUser admin venue.id listSavedPayrollWorkbookConfigurations
                listed `shouldBe` Right [saved]
                fetched <- asCurrentVenueUser admin venue.id do
                    fetchSavedPayrollWorkbookConfiguration saved.savedPayrollWorkbookConfigurationRecord.id
                fetched `shouldBe` Right saved

                positions <- query @PayrollWorkbookConfigurationFamily |> orderByAsc #position |> fetch
                map (.position) positions `shouldBe` [0, 1, 2]
                map (.familyKey) positions
                    `shouldBe` ["shift-type-wages", "summary", "employee-pay-bucket-hours"]

        it "rejects invalid names, versions, families, duplicates, and venue-local name conflicts" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Saved Workbook Validation Venue"
                admin <- createUserRecord "saved-workbook-validation@example.com" "admin" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin
                let create input =
                        asCurrentVenueUser admin venue.id (createSavedPayrollWorkbookConfiguration input)

                create (newConfiguration " \n\t " 1 ["summary"])
                    `shouldReturn` Left (PayrollWorkbookConfigurationInvalidName "Configuration names cannot be empty.")
                create (newConfiguration (Text.replicate 101 "x") 1 ["summary"])
                    `shouldReturn` Left (PayrollWorkbookConfigurationInvalidName "Configuration names cannot exceed 100 characters.")
                create (newConfiguration "Future" 2 ["summary"])
                    `shouldReturn` Left (PayrollWorkbookConfigurationInvalidDefinition "Unsupported Payroll Workbook definition version: 2.")
                create (newConfiguration "Empty" 1 [])
                    `shouldReturn` Left (PayrollWorkbookConfigurationInvalidDefinition "Payroll Workbook definitions require at least one presentation sheet family.")
                create (newConfiguration "Duplicate" 1 ["summary", "summary"])
                    `shouldReturn` Left (PayrollWorkbookConfigurationInvalidDefinition "Payroll Workbook definitions cannot contain duplicate sheet families: summary.")
                create (newConfiguration "Unknown" 1 ["uploaded-template"])
                    `shouldReturn` Left (PayrollWorkbookConfigurationInvalidDefinition "Unsupported Payroll Workbook sheet family: uploaded-template.")

                first <- create (newConfiguration "Weekly Payroll" 1 ["summary"])
                first `shouldSatisfy` isRight
                create (newConfiguration "  weekly payroll " 1 ["summary"])
                    `shouldReturn` Left (PayrollWorkbookConfigurationNameConflict "weekly payroll")

                otherVenue <- createVenueWithConfig "Saved Workbook Other Venue"
                _ <- createVenueMembershipRecord otherVenue admin VenueAdmin
                otherVenueCreated <- asCurrentVenueUser admin otherVenue.id
                    (createSavedPayrollWorkbookConfiguration (newConfiguration "Weekly Payroll" 1 ["summary"]))
                otherVenueCreated `shouldSatisfy` isRight

        it "allows owners and founder support but denies managers and support without a current venue" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Saved Workbook Authority Venue"
                owner <- createUserRecord "saved-workbook-owner@example.com" "admin" True
                manager <- createUserRecord "saved-workbook-manager@example.com" "manager" True
                founder <- createUserRecordWithPlatformRole "saved-workbook-founder@example.com" "staff" (Just SuperAdmin) True
                _ <- createVenueMembershipRecord venue owner VenueOwner
                _ <- createVenueMembershipRecord venue manager Manager
                let input = newConfiguration "Owner Definition" 1 ["summary"]

                withUser founder do
                    withSessionValues [(currentVenueSessionKey, "")] do
                        withCurrentControllerContext listSavedPayrollWorkbookConfigurations
                        `shouldReturn` Left PayrollWorkbookConfigurationAccessDenied

                ownerCreated <- asCurrentVenueUser owner venue.id (createSavedPayrollWorkbookConfiguration input)
                ownerSaved <- expectRight ownerCreated
                asCurrentVenueUser owner venue.id listSavedPayrollWorkbookConfigurations
                    `shouldReturn` Right [ownerSaved]

                asCurrentVenueUser manager venue.id (createSavedPayrollWorkbookConfiguration (newConfiguration "Denied" 1 ["summary"]))
                    `shouldReturn` Left PayrollWorkbookConfigurationAccessDenied
                asCurrentVenueUser manager venue.id listSavedPayrollWorkbookConfigurations
                    `shouldReturn` Left PayrollWorkbookConfigurationAccessDenied
                asCurrentVenueUser manager venue.id (fetchSavedPayrollWorkbookConfiguration ownerSaved.savedPayrollWorkbookConfigurationRecord.id)
                    `shouldReturn` Left PayrollWorkbookConfigurationAccessDenied
                asCurrentVenueUser manager venue.id (deleteSavedPayrollWorkbookConfiguration ownerSaved.savedPayrollWorkbookConfigurationRecord.id)
                    `shouldReturn` Left PayrollWorkbookConfigurationAccessDenied

                founderCreated <- asCurrentVenueUser founder venue.id do
                    createSavedPayrollWorkbookConfiguration (newConfiguration "Support Definition" 1 ["shift-type-hours"])
                founderCreated `shouldSatisfy` isRight

        it "keeps reads and deletion venue-safe and leaves generated-job definition snapshots interpretable" $ withContext do
            withCleanDb do
                venueA <- createVenueWithConfig "Saved Workbook Venue A"
                venueB <- createVenueWithConfig "Saved Workbook Venue B"
                adminA <- createUserRecord "saved-workbook-a@example.com" "admin" True
                adminB <- createUserRecord "saved-workbook-b@example.com" "admin" True
                _ <- createVenueMembershipRecord venueA adminA VenueAdmin
                _ <- createVenueMembershipRecord venueB adminB VenueAdmin

                created <- asCurrentVenueUser adminB venueB.id do
                    createSavedPayrollWorkbookConfiguration
                        (newConfiguration "Venue B Payroll" 1 ["employee-pay-bucket-wages", "summary"])
                saved <- expectRight created
                let configurationId = saved.savedPayrollWorkbookConfigurationRecord.id

                asCurrentVenueUser adminA venueA.id (fetchSavedPayrollWorkbookConfiguration configurationId)
                    `shouldReturn` Left PayrollWorkbookConfigurationNotFound
                asCurrentVenueUser adminA venueA.id (deleteSavedPayrollWorkbookConfiguration configurationId)
                    `shouldReturn` Left PayrollWorkbookConfigurationNotFound

                now <- getCurrentTime
                let definition = saved.savedPayrollWorkbookConfigurationDefinition
                exportJob <-
                    newRecord @ExportJob
                        |> set #venueId (unpackId venueB.id)
                        |> set #requestedByUserId (unpackId adminB.id)
                        |> set #exportType (exportJobTypeToText PayrollWorkbookXlsx)
                        |> set #scope
                            (Aeson.object
                                [ "definitionKey" Aeson..= definition.payrollWorkbookDefinitionKey
                                , "definitionVersion" Aeson..= definition.payrollWorkbookDefinitionVersion
                                , "sheetFamilies" Aeson..= map payrollWorkbookSheetFamilyKey definition.payrollWorkbookDefinitionSheetFamilies
                                ]
                            )
                        |> set #expiresAt (addUTCTime 3600 now)
                        |> createRecord

                asCurrentVenueUser adminB venueB.id (deleteSavedPayrollWorkbookConfiguration configurationId)
                    `shouldReturn` Right ()
                query @PayrollWorkbookConfiguration |> fetchCount `shouldReturn` 0
                query @PayrollWorkbookConfigurationFamily |> fetchCount `shouldReturn` 0
                retainedExportJob <- fetch exportJob.id
                retainedExportJob.scope `shouldBe`
                    Aeson.object
                        [ "definitionKey" Aeson..= definition.payrollWorkbookDefinitionKey
                        , "definitionVersion" Aeson..= (1 :: Int)
                        , "sheetFamilies" Aeson..= (["employee-pay-bucket-wages", "summary"] :: [Text])
                        ]

        it "applies additively to a representative pre-configuration schema without changing customer rows" $ withContext do
            withCleanDb do
                migrationSql <- TextIO.readFile "Application/Migration/1788200100-add-payroll-workbook-configurations.sql"
                withTransaction do
                    case transactionRunner ?modelContext of
                        Nothing -> error "Payroll Workbook configuration migration acceptance requires a transaction runner"
                        Just runner -> do
                            runInTransaction runner $ HasqlSession.script "CREATE SCHEMA payroll_workbook_config_migration_acceptance; CREATE TABLE payroll_workbook_config_migration_acceptance.venues (id UUID PRIMARY KEY, marker TEXT NOT NULL); CREATE TABLE payroll_workbook_config_migration_acceptance.users (id UUID PRIMARY KEY, marker TEXT NOT NULL); INSERT INTO payroll_workbook_config_migration_acceptance.venues VALUES ('10000000-0000-0000-0000-000000000001', 'venue-retained'); INSERT INTO payroll_workbook_config_migration_acceptance.users VALUES ('20000000-0000-0000-0000-000000000001', 'user-retained'); SET LOCAL search_path TO payroll_workbook_config_migration_acceptance, public;"
                            runInTransaction runner (HasqlSession.script migrationSql)
                    retainedMarkers :: [Only Text] <- sqlQuery
                        "SELECT marker FROM payroll_workbook_config_migration_acceptance.venues UNION ALL SELECT marker FROM payroll_workbook_config_migration_acceptance.users ORDER BY marker"
                        ()
                    createdTables :: [Only (Maybe Text)] <- sqlQuery
                        "SELECT to_regclass('payroll_workbook_config_migration_acceptance.' || table_name)::text FROM unnest(ARRAY['payroll_workbook_configurations', 'payroll_workbook_configuration_families']) table_name"
                        ()
                    map fromOnly retainedMarkers `shouldBe` ["user-retained", "venue-retained"]
                    createdTables `shouldSatisfy` all (isJust . fromOnly)
                    sqlExecDiscardResult "DROP SCHEMA payroll_workbook_config_migration_acceptance CASCADE" ()

        it "enforces normalized names, supported versions and families, and deterministic unique positions in PostgreSQL" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Saved Workbook Constraint Venue"
                admin <- createUserRecord "saved-workbook-constraint@example.com" "admin" True
                invalidName <- try
                    (sqlExecDiscardResult
                        "INSERT INTO payroll_workbook_configurations (venue_id, name, definition_version, created_by_user_id) VALUES (?, ' padded ', 1, ?)"
                        (unpackId venue.id, unpackId admin.id))
                    :: IO (Either SomeException ())
                invalidWhitespace <- try
                    (sqlExecDiscardResult
                        "INSERT INTO payroll_workbook_configurations (venue_id, name, definition_version, created_by_user_id) VALUES (?, 'Weekly  Payroll', 1, ?)"
                        (unpackId venue.id, unpackId admin.id))
                    :: IO (Either SomeException ())
                invalidVersion <- try
                    (sqlExecDiscardResult
                        "INSERT INTO payroll_workbook_configurations (venue_id, name, definition_version, created_by_user_id) VALUES (?, 'Future', 2, ?)"
                        (unpackId venue.id, unpackId admin.id))
                    :: IO (Either SomeException ())
                configurationId :: UUID <- sqlQueryScalar
                    "INSERT INTO payroll_workbook_configurations (venue_id, name, definition_version, created_by_user_id) VALUES (?, 'Valid', 1, ?) RETURNING id"
                    (unpackId venue.id, unpackId admin.id)
                duplicateName <- try
                    (sqlExecDiscardResult
                        "INSERT INTO payroll_workbook_configurations (venue_id, name, definition_version, created_by_user_id) VALUES (?, 'valid', 1, ?)"
                        (unpackId venue.id, unpackId admin.id))
                    :: IO (Either SomeException ())
                invalidFamily <- try
                    (sqlExecDiscardResult
                        "INSERT INTO payroll_workbook_configuration_families (configuration_id, family_key, position) VALUES (?, 'uploaded-template', 0)"
                        (Only configurationId))
                    :: IO (Either SomeException ())
                invalidPosition <- try
                    (sqlExecDiscardResult
                        "INSERT INTO payroll_workbook_configuration_families (configuration_id, family_key, position) VALUES (?, 'summary', 5)"
                        (Only configurationId))
                    :: IO (Either SomeException ())
                sqlExecDiscardResult
                    "INSERT INTO payroll_workbook_configuration_families (configuration_id, family_key, position) VALUES (?, 'summary', 0)"
                    (Only configurationId)
                duplicatePosition <- try
                    (sqlExecDiscardResult
                        "INSERT INTO payroll_workbook_configuration_families (configuration_id, family_key, position) VALUES (?, 'shift-type-hours', 0)"
                        (Only configurationId))
                    :: IO (Either SomeException ())
                duplicateFamily <- try
                    (sqlExecDiscardResult
                        "INSERT INTO payroll_workbook_configuration_families (configuration_id, family_key, position) VALUES (?, 'summary', 1)"
                        (Only configurationId))
                    :: IO (Either SomeException ())
                map isLeft [invalidName, invalidWhitespace, invalidVersion, duplicateName, invalidFamily, invalidPosition, duplicatePosition, duplicateFamily]
                    `shouldBe` replicate 8 True

asCurrentVenueUser ::
    (?mocking :: MockContext WebApplication, ?request :: Wai.Request, ?modelContext :: ModelContext) =>
    User ->
    Id Venue ->
    ((?context :: ControllerContext) => IO result) ->
    IO result
asCurrentVenueUser user venueId action =
    withUserAndCurrentVenue user venueId do
        withCurrentControllerContext action

expectRight :: (Show error) => Either error value -> IO value
expectRight = \case
    Left err -> expectationFailure (cs (show err)) >> fail "expected Right"
    Right value -> pure value
