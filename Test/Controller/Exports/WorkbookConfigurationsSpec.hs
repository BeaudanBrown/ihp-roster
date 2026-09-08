module Test.Controller.Exports.WorkbookConfigurationsSpec where

import Control.Concurrent (newEmptyMVar, putMVar, takeMVar, threadDelay, tryPutMVar)
import Control.Concurrent.Async (wait, withAsync)
import Control.Exception (bracket_, finally)
import Control.Monad (forM_, void)
import qualified Data.Text as Text
import Generated.Types
import IHP.ControllerPrelude
import IHP.Hspec
import IHP.Test.Mocking
import Network.HTTP.Types.Status (status200, status302)
import qualified Network.Wai as Wai
import System.Timeout (timeout)
import Test.Hspec

import Test.Support
import Web.Controller.Exports ()
import Web.Controller.Support ()
import Web.FrontController ()
import Web.Types

-- Characterize the public request seam before moving its coordination.
tests :: Spec
tests = aroundAll withDatabaseTestContext do
    describe "ExportsController saved Workbook requests" do
        it "closes the HTMX editor, refreshes the actor's exports surface, and publishes each saved change once" $ withContext do
            withCleanDb do
                (venue, admin) <- adminFixture
                withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        created <- callActionWithParams CreatePayrollWorkbookConfigurationAction
                            (configurationParams "  Pay   run  " "[\"shift-type-wages\",\"summary\"]")
                        assertHtmxCompletion venue created
                        configuration <- query @PayrollWorkbookConfiguration |> fetchOne
                        configuration.name `shouldBe` "Pay run"
                        configuration.revision `shouldBe` 0
                        configuration.createdByUserId `shouldBe` unpackId admin.id
                        updated <- callActionWithParams (UpdatePayrollWorkbookConfigurationAction configuration.id)
                            (configurationParams "Updated" "[\"summary\",\"shift-type-hours\"]"
                                <> [("payrollWorkbookConfigurationRevision", "0")])
                        assertHtmxCompletion venue updated
                        reloaded <- fetch configuration.id
                        reloaded.revision `shouldBe` 1
                        query @PayrollWorkbookConfigurationFamily
                            |> filterWhere (#configurationId, unpackId configuration.id)
                            |> orderByAsc #position
                            |> fetch
                            >>= (\families -> map (\family -> (family.position, family.familyKey)) families
                                `shouldBe` [(0, "summary"), (1, "shift-type-hours")])
                        deleted <- callAction (DeletePayrollWorkbookConfigurationAction configuration.id "2025-01-08")
                        assertHtmxCompletion venue deleted
                query @PayrollWorkbookConfiguration |> fetchCount `shouldReturn` 0
                query @PayrollWorkbookConfigurationFamily |> fetchCount `shouldReturn` 0
                events <- query @LiveInvalidationEvent |> orderByAsc #sequenceNumber |> fetch
                map (.source) events `shouldBe`
                    [ "payroll_workbook_configuration.create"
                    , "payroll_workbook_configuration.update"
                    , "payroll_workbook_configuration.delete"
                    ]
                query @AuditEvent |> fetchCount `shouldReturn` 0

        it "keeps transport and unknown-family edit fallbacks distinct, before checking whether the record exists" $ withContext do
            withCleanDb do
                (venue, admin) <- adminFixture
                let configurationId = Id "00000000-0000-0000-0000-000000000000"
                withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        malformed <- callActionWithParams (UpdatePayrollWorkbookConfigurationAction configurationId)
                            (configurationParams "Discard this draft" "[\"summary\"]"
                                <> [("payrollWorkbookConfigurationRevision", "bad-revision")])
                        malformed `responseStatusShouldBe` status200
                        malformed `responseBodyShouldContain` "Check the export fields. payrollWorkbookConfigurationRevision must be an integer"
                        malformed `responseBodyShouldContain` "value=\"[]\""
                        malformed `responseBodyShouldContain` "value=\"0\""
                        malformed `responseBodyShouldNotContain` "Discard this draft"
                        malformed `responseBodyShouldNotContain` "no longer exists"
                        lookup "HX-Trigger" (Wai.responseHeaders malformed) `shouldBe` Nothing

                        unknownFamily <- callActionWithParams (UpdatePayrollWorkbookConfigurationAction configurationId)
                            (configurationParams "Discard this draft" "[\"uploaded-template\"]"
                                <> [("payrollWorkbookConfigurationRevision", "7")])
                        unknownFamily `responseStatusShouldBe` status200
                        unknownFamily `responseBodyShouldContain` "Unsupported Payroll Workbook sheet family: uploaded-template."
                        unknownFamily `responseBodyShouldContain` "value=\"[]\""
                        unknownFamily `responseBodyShouldContain` "value=\"7\""
                        unknownFamily `responseBodyShouldContain` "value=\"2025-01-08\""
                        unknownFamily `responseBodyShouldNotContain` "Discard this draft"
                        lookup "HX-Trigger" (Wai.responseHeaders unknownFamily) `shouldBe` Nothing

                        absent <- callActionWithParams (UpdatePayrollWorkbookConfigurationAction configurationId)
                            (configurationParams "  " "[\"summary\"]"
                                <> [("payrollWorkbookConfigurationRevision", "7")])
                        absent `responseStatusShouldBe` status200
                        absent `responseBodyShouldContain` "That Payroll Workbook configuration no longer exists."
                        absent `responseBodyShouldContain` "value=\"[&quot;summary&quot;]\""
                        absent `responseBodyShouldNotContain` "Configuration names cannot be empty."
                query @PayrollWorkbookConfiguration |> fetchCount `shouldReturn` 0
                query @LiveInvalidationEvent |> fetchCount `shouldReturn` 0

        it "retains submitted drafts for validation, stale and name-conflict errors without partial edits or publication" $ withContext do
            withCleanDb do
                (venue, admin) <- adminFixture
                withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    forM_ ["Taken", "Original"] \name -> do
                        created <- callActionWithParams CreatePayrollWorkbookConfigurationAction
                            (configurationParams name "[\"summary\"]")
                        created `responseStatusShouldBe` status302
                    configuration <- query @PayrollWorkbookConfiguration |> filterWhere (#name, "Original") |> fetchOne
                    withRequestHeaders [("HX-Request", "true")] do
                        forM_
                            [ ("  ", "[\"summary\",\"summary\"]", "-1", "Configuration names cannot be empty.")
                            , ("  My   draft  ", "[\"summary\",\"summary\"]", "-1", "Payroll Workbook definitions cannot contain duplicate sheet families: summary.")
                            , ("  My   draft  ", "[\"shift-type-wages\",\"summary\"]", "7", "This export changed after you opened it. Close the editor and try again.")
                            , ("  tAkEn  ", "[\"shift-type-wages\",\"summary\"]", "0", "A Payroll Workbook configuration named “tAkEn” already exists.")
                            ] \(name, families, revision, message) -> do
                                response <- callActionWithParams (UpdatePayrollWorkbookConfigurationAction configuration.id)
                                    (configurationParams name families <> [("payrollWorkbookConfigurationRevision", revision)])
                                response `responseStatusShouldBe` status200
                                response `responseBodyShouldContain` message
                                response `responseBodyShouldContain` ("value=\"" <> cs name <> "\"")
                                response `responseBodyShouldContain` ("value=\"" <> cs revision <> "\"")
                                response `responseBodyShouldContain` "value=\"2025-01-08\""
                                lookup "HX-Trigger" (Wai.responseHeaders response) `shouldBe` Nothing
                    retained <- fetch configuration.id
                    retained.name `shouldBe` "Original"
                    retained.revision `shouldBe` 0
                    retained.updatedAt `shouldBe` configuration.updatedAt
                    query @PayrollWorkbookConfigurationFamily
                        |> filterWhere (#configurationId, unpackId configuration.id)
                        |> fetch
                        >>= (\families -> map (.familyKey) families `shouldBe` ["summary"])
                query @LiveInvalidationEvent |> fetchCount `shouldReturn` 2
                query @AuditEvent |> fetchCount `shouldReturn` 0

        it "preserves native selected-date redirects and rejects foreign edits and repeated deletes without publication" $ withContext do
            withCleanDb do
                (venue, admin) <- adminFixture
                otherVenue <- createVenueWithConfig "Other workbook venue"
                _ <- createVenueMembershipRecord otherVenue admin VenueAdmin
                created <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams CreatePayrollWorkbookConfigurationAction (configurationParams "Native" "[\"summary\"]")
                assertNativeCompletion created
                configuration <- query @PayrollWorkbookConfiguration |> fetchOne
                withPasskeyVerifiedUserAndCurrentVenue admin otherVenue.id do
                    updated <- callActionWithParams (UpdatePayrollWorkbookConfigurationAction configuration.id)
                        (configurationParams "Foreign overwrite" "[\"summary\"]" <> [("payrollWorkbookConfigurationRevision", "0")])
                    assertNativeCompletion updated
                    deleted <- callAction (DeletePayrollWorkbookConfigurationAction configuration.id "2025-01-08")
                    assertNativeCompletion deleted
                    withRequestHeaders [("HX-Request", "true")] do
                        foreignEdit <- callAction (EditPayrollWorkbookConfigurationAction configuration.id "2025-01-08")
                        foreignEdit `responseStatusShouldBe` status200
                        foreignEdit `responseBodyShouldContain` "That Payroll Workbook configuration no longer exists."
                        lookup "HX-Reswap" (Wai.responseHeaders foreignEdit) `shouldBe` Just "none"
                        lookup "HX-Trigger" (Wai.responseHeaders foreignEdit) `shouldBe` Nothing
                retained <- fetch configuration.id
                retained.name `shouldBe` "Native"
                query @LiveInvalidationEvent |> fetchCount `shouldReturn` 1
                withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    updated <- callActionWithParams (UpdatePayrollWorkbookConfigurationAction configuration.id)
                        (configurationParams "Native updated" "[\"shift-type-wages\"]" <> [("payrollWorkbookConfigurationRevision", "0")])
                    assertNativeCompletion updated
                    deleted <- callAction (DeletePayrollWorkbookConfigurationAction configuration.id "2025-01-08")
                    assertNativeCompletion deleted
                    repeatedDelete <- callAction (DeletePayrollWorkbookConfigurationAction configuration.id "2025-01-08")
                    assertNativeCompletion repeatedDelete
                query @LiveInvalidationEvent |> fetchCount `shouldReturn` 3
                query @PayrollWorkbookConfiguration |> fetchCount `shouldReturn` 0

        it "commits one concurrent creator and returns a friendly unique conflict without partial loser rows or publication" $ withContext do
            withCleanDb do
                (venue, admin) <- adminFixture
                let installBarrier = do
                        sqlExecDiscardResult "CREATE FUNCTION test_wait_for_workbook_create() RETURNS trigger AS 'BEGIN PERFORM pg_advisory_xact_lock(511520); RETURN NEW; END' LANGUAGE plpgsql" ()
                        sqlExecDiscardResult "CREATE TRIGGER test_wait_for_workbook_create BEFORE INSERT ON payroll_workbook_configurations FOR EACH ROW EXECUTE FUNCTION test_wait_for_workbook_create()" ()
                let removeBarrier = do
                        sqlExecDiscardResult "DROP TRIGGER IF EXISTS test_wait_for_workbook_create ON payroll_workbook_configurations" ()
                        sqlExecDiscardResult "DROP FUNCTION IF EXISTS test_wait_for_workbook_create()" ()
                let create name =
                        withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                            withRequestHeaders [("HX-Request", "true")] do
                                callActionWithParams CreatePayrollWorkbookConfigurationAction
                                    (configurationParams name "[\"shift-type-wages\",\"summary\"]")
                responses <- bracket_ installBarrier removeBarrier do
                    ready <- newEmptyMVar
                    release <- newEmptyMVar
                    let releaseBarrier = void (tryPutMVar release ())
                    withAsync (withTransaction do
                        _ :: [Only Int] <- sqlQuery "SELECT 1 FROM pg_advisory_xact_lock(511520)" ()
                        putMVar ready ()
                        takeMVar release) \barrier -> do
                            takeMVar ready
                            withAsync (create "  Race  ") \first ->
                                withAsync (create "race") \second ->
                                    (do
                                        -- Both transactions have passed the name precheck
                                        -- and reached BEFORE INSERT before either can win.
                                        waitForWorkbookCreateContenders
                                        releaseBarrier
                                        wait barrier
                                        firstResponse <- wait first
                                        secondResponse <- wait second
                                        pure [firstResponse, secondResponse]
                                    ) `finally` releaseBarrier
                forM_ responses \response -> response `responseStatusShouldBe` status200
                let hasRefresh = isJust . lookup "HX-Trigger" . Wai.responseHeaders
                case (filter hasRefresh responses, filter (not . hasRefresh) responses) of
                    ([winner], [loser]) -> do
                        assertHtmxCompletion venue winner
                        loser `responseBodyShouldContain` "A Payroll Workbook configuration named “"
                        loser `responseBodyShouldContain` "” already exists."
                    _ -> expectationFailure "Expected exactly one successful actor refresh and one conflict editor"
                configurations <- query @PayrollWorkbookConfiguration |> fetch
                map (Text.toLower . (.name)) configurations `shouldBe` ["race"]
                families <- query @PayrollWorkbookConfigurationFamily |> orderByAsc #position |> fetch
                map (\family -> (family.position, family.familyKey)) families `shouldBe` [(0, "shift-type-wages"), (1, "summary")]
                query @LiveInvalidationEvent |> fetchCount `shouldReturn` 1
                query @LiveInvalidationEventResource |> fetchCount `shouldReturn` 1
                query @LiveResourceVersion |> fetchCount `shouldReturn` 1
                query @AuditEvent |> fetchCount `shouldReturn` 0

        it "uses empty create fallbacks for transport and unknown-family failures, but retains domain-invalid drafts" $ withContext do
            withCleanDb do
                (venue, admin) <- adminFixture
                withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        missing <- callAction CreatePayrollWorkbookConfigurationAction
                        missing `responseStatusShouldBe` status200
                        missing `responseBodyShouldContain` "Check the export fields. exportAnchorDate is required"
                        missing `responseBodyShouldContain` "value=\"[]\""
                        forM_ [("[broken", "must be valid JSON"), ("[\"unknown\"]", "Unsupported Payroll Workbook sheet family: unknown.")] \(families, message) -> do
                            rejected <- callActionWithParams CreatePayrollWorkbookConfigurationAction (configurationParams "Discard this name" families)
                            rejected `responseStatusShouldBe` status200
                            rejected `responseBodyShouldContain` message
                            rejected `responseBodyShouldContain` "value=\"[]\""
                            rejected `responseBodyShouldNotContain` "Discard this name"
                            lookup "HX-Trigger" (Wai.responseHeaders rejected) `shouldBe` Nothing
                        invalid <- callActionWithParams CreatePayrollWorkbookConfigurationAction
                            (configurationParams " <script>draft</script> " "[\"summary\",\"summary\"]")
                        invalid `responseStatusShouldBe` status200
                        invalid `responseBodyShouldContain` "Payroll Workbook definitions cannot contain duplicate sheet families: summary."
                        invalid `responseBodyShouldContain` "value=\" &lt;script&gt;draft&lt;/script&gt; \""
                        invalid `responseBodyShouldContain` "value=\"[&quot;summary&quot;,&quot;summary&quot;]\""
                        invalid `responseBodyShouldNotContain` "<script>draft</script>"
                query @PayrollWorkbookConfiguration |> fetchCount `shouldReturn` 0
                query @LiveInvalidationEvent |> fetchCount `shouldReturn` 0

        it "uses effective venue authority but the actual creator, retaining support and pre-parse writability gates" $ withContext do
            withCleanDb do
                (venue, admin) <- adminFixture
                owner <- createUserRecord "workbook-owner@example.com" "staff" True
                manager <- createUserRecord "workbook-manager@example.com" "staff" True
                founder <- createUserRecordWithPlatformRole "workbook-founder@example.com" "staff" (Just SuperAdmin) True
                _ <- createVenueMembershipRecord venue owner VenueOwner
                _ <- createVenueMembershipRecord venue manager Manager
                withPasskeyVerifiedUserAndCurrentVenue manager venue.id do
                    denied <- callAction CreatePayrollWorkbookConfigurationAction
                    denied `responseStatusShouldBe` status302
                    lookup "Location" (Wai.responseHeaders denied) `shouldBe` Just "http://localhost/RosterWeeks"
                withPasskeyVerifiedUserAndCurrentVenue owner venue.id do
                    created <- callActionWithParams CreatePayrollWorkbookConfigurationAction (configurationParams "Owner" "[\"summary\"]")
                    assertNativeCompletion created
                withPasskeyVerifiedUserAndCurrentVenue founder venue.id do
                    created <- callActionWithParams CreatePayrollWorkbookConfigurationAction (configurationParams "Support" "[\"summary\"]")
                    assertNativeCompletion created
                    entered <- callActionWithParams StartSupportImpersonationAction [("userId", cs (inputValue admin.id))]
                    entered `responseStatusShouldBe` status302
                    impersonated <- callActionWithParams CreatePayrollWorkbookConfigurationAction (configurationParams "Impersonated" "[\"summary\"]")
                    assertNativeCompletion impersonated
                    _ <- callAction ExitSupportImpersonationAction
                    _ <- callActionWithParams StartSupportImpersonationAction [("userId", cs (inputValue manager.id))]
                    denied <- callAction CreatePayrollWorkbookConfigurationAction
                    denied `responseStatusShouldBe` status302
                    lookup "Location" (Wai.responseHeaders denied) `shouldBe` Just "http://localhost/Support"
                configurations <- query @PayrollWorkbookConfiguration |> orderByAsc #name |> fetch
                map (\configuration -> (configuration.name, configuration.createdByUserId)) configurations `shouldBe`
                    [("Impersonated", unpackId founder.id), ("Owner", unpackId owner.id), ("Support", unpackId founder.id)]
                query @VenueMembership |> filterWhere (#userId, unpackId founder.id) |> fetchCount `shouldReturn` 0
                now <- getCurrentTime
                _ <- newRecord @VenueBillingControl
                    |> set #venueId (unpackId venue.id)
                    |> set #manualReadOnly True
                    |> set #manualReadOnlyReason (Just "Test read-only venue")
                    |> set #setByUserId (Just (unpackId founder.id))
                    |> set #setAt (Just now)
                    |> createRecord
                withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        denied <- callAction CreatePayrollWorkbookConfigurationAction
                        denied `responseStatusShouldBe` status302
                        lookup "Location" (Wai.responseHeaders denied) `shouldBe` Just "http://localhost/RosterWeeks"
                query @LiveInvalidationEvent |> fetchCount `shouldReturn` 3

waitForWorkbookCreateContenders :: (?modelContext :: ModelContext) => IO ()
waitForWorkbookCreateContenders = do
    completed <- timeout 10000000 awaitBothInserts
    completed `shouldBe` Just ()
  where
    awaitBothInserts = do
        waiting :: Int <- sqlQueryScalar
            "SELECT COUNT(*)::INT FROM pg_locks WHERE locktype = 'advisory' AND database = (SELECT oid FROM pg_database WHERE datname = current_database()) AND classid = 0 AND objid = 511520 AND NOT granted"
            ()
        if waiting == 2 then pure () else threadDelay 1000 >> awaitBothInserts

adminFixture :: (?modelContext :: ModelContext) => IO (Venue, User)
adminFixture = do
    venue <- createVenueWithConfig "Workbook venue"
    admin <- createUserRecord "workbook-admin@example.com" "staff" True
    _ <- createVenueMembershipRecord venue admin VenueAdmin
    pure (venue, admin)

configurationParams :: ByteString -> ByteString -> [(ByteString, ByteString)]
configurationParams name families =
    [ ("exportAnchorDate", "2025-01-08")
    , ("payrollWorkbookConfigurationName", name)
    , ("payrollWorkbookSheetFamilies", families)
    ]

assertNativeCompletion :: Wai.Response -> Expectation
assertNativeCompletion response = do
    response `responseStatusShouldBe` status302
    lookup "Location" (Wai.responseHeaders response) `shouldBe` Just "http://localhost/Admin?showExports=true&anchorDate=2025-01-08#exports"
    lookup "HX-Trigger" (Wai.responseHeaders response) `shouldBe` Nothing

assertHtmxCompletion :: Venue -> Wai.Response -> Expectation
assertHtmxCompletion venue response = do
    response `responseStatusShouldBe` status200
    lookup "HX-Reswap" (Wai.responseHeaders response) `shouldBe` Just "none"
    response `responseBodyShouldContain` "id=\"dialog-overlay-mount\""
    body <- responseBody response
    (cs body :: String) `shouldNotContain` "hx-swap-oob=\"outerHTML\""
    let trigger = cs <$> lookup "HX-Trigger" (Wai.responseHeaders response)
    trigger `shouldSatisfy` maybe False (Text.isInfixOf "\"kind\":\"admin-exports\"")
    trigger `shouldSatisfy` maybe False (Text.isInfixOf "\"params\":{}")
    trigger `shouldSatisfy` maybe False (not . Text.isInfixOf "anchorDate")
    trigger `shouldSatisfy` maybe False (Text.isInfixOf (inputValue venue.id))
