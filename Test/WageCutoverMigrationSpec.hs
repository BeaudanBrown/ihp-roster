module Test.WageCutoverMigrationSpec where

import Application.Helper.TimesheetPayLedger (loadApprovedTimesheetPayCalculation)
import qualified Data.Text as Text
import Data.Text.Encoding (encodeUtf8)
import qualified Data.Text.IO as TextIO
import Data.Time.Calendar (fromGregorian)
import qualified Database.PostgreSQL.Simple.Types as PGTypes
import Generated.Types
import IHP.ControllerPrelude
import IHP.ModelSupport (sqlExecDiscardResult, sqlQuery)
import IHP.Prelude
import IHP.Test.Mocking
import Test.Hspec
import Test.Support

-- Deployment-level evidence that the forward-only retirement SQL executes only
-- with a usable sealed ledger and leaves final pay readable without SQL math.
tests :: Spec
tests = aroundAll withDatabaseTestContext do
    describe "Haskell wage cutover migration" do
        it "retires both SQL calculators while preserving approved metadata and ledger facts" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Wage cutover migration venue"
                approver <- createUserRecord "wage-cutover@example.com" "staff" True
                staff <- createStaffRecord venue Nothing "Cutover" "Worker"
                entry <- createApprovedTimesheetEntryRecord venue staff approver (fromGregorian 2026 5 4)
                let approvalMetadata = (entry.approvedAt, entry.approvedByUserId, entry.staffPayVersionId, entry.shiftTypePayVersionId)

                sqlExecDiscardResult "CREATE FUNCTION calculate_timesheet_pay(UUID) RETURNS JSONB LANGUAGE SQL AS 'SELECT ''{}''::jsonb'" ()
                sqlExecDiscardResult "CREATE FUNCTION calculate_timesheet_pay_range(UUID, DATE, DATE) RETURNS JSONB LANGUAGE SQL AS 'SELECT ''[]''::jsonb'" ()
                migrationSql <- TextIO.readFile "Application/Deployment/retire-legacy-wage-calculators.sql"
                let (guardSql, retirementSql) = Text.breakOn "DROP FUNCTION" migrationSql
                    dropStatements = filter (Text.isPrefixOf "DROP FUNCTION") (Text.lines retirementSql)
                sqlExecDiscardResult (PGTypes.Query (encodeUtf8 guardSql)) ()
                forM_ dropStatements \statement ->
                    sqlExecDiscardResult (PGTypes.Query (encodeUtf8 statement)) ()

                functionNames :: [(Maybe Text, Maybe Text)] <- sqlQuery
                    "SELECT to_regprocedure('calculate_timesheet_pay(uuid)')::text, to_regprocedure('calculate_timesheet_pay_range(uuid,date,date)')::text"
                    ()
                functionNames `shouldBe` [(Nothing, Nothing)]
                reloadedEntry <- fetch entry.id
                (reloadedEntry.approvedAt, reloadedEntry.approvedByUserId, reloadedEntry.staffPayVersionId, reloadedEntry.shiftTypePayVersionId)
                    `shouldBe` approvalMetadata
                loadApprovedTimesheetPayCalculation reloadedEntry >>= (`shouldSatisfy` either (const False) isJust)
