module Test.XeroContractSpec where

import Application.Helper.Xero
import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Base64 as Base64
import qualified Data.ByteString.Lazy as LByteString
import Data.Either (isRight)
import qualified Data.List as List
import qualified Data.Text as Text
import qualified Data.Text.Encoding as TextEncoding
import qualified Data.Text.IO as TextIO
import IHP.Prelude
import Network.HTTP.Simple (getResponseStatusCode, httpLBS)
import Network.HTTP.Types.Status (status200, status400, status401, status403,
                                  status429)
import Test.Hspec
import qualified Test.XeroMock as XeroMock

tests :: Spec
tests =
    describe "Xero contract" do
        (identitySpec, payrollSpec) <- runIO XeroMock.loadXeroOpenApiSpecs

        it "constructs Identity token exchange and refresh requests from the vendored token URL" do
            XeroMock.assertSpecContains identitySpec "tokenUrl: https://identity.xero.com/connect/token"
            assertTokenRequest
                (buildExchangeCodeForTokenRequest XeroMock.testConfig "auth-code")
                [("grant_type", "authorization_code"), ("code", "auth-code"), ("redirect_uri", "http://localhost:8000/XeroOAuthCallback")]
            assertTokenRequest
                (buildRefreshXeroTokenRequest XeroMock.testConfig "refresh-token")
                [("grant_type", "refresh_token"), ("refresh_token", "refresh-token")]

        it "constructs Identity connections requests from the vendored paths" do
            XeroMock.assertSpecServer identitySpec "https://api.xero.com"
            XeroMock.assertSpecOperation identitySpec "/Connections" "get"
            XeroMock.assertSpecOperation identitySpec "/Connections/{id}" "delete"

            let listRequest = buildFetchConnectedTenantsRequest "access-token"
            assertRequest listRequest "GET" "https://api.xero.com" "/connections"
            Text.toLower (XeroMock.requestUrlWithoutQuery listRequest) `shouldBe` "https://api.xero.com" <> Text.toLower "/Connections"
            XeroMock.headerValue "Authorization" listRequest `shouldBe` Just "Bearer access-token"
            XeroMock.headerValue "Accept" listRequest `shouldBe` Just "application/json"

            let deleteRequest = buildDeleteXeroConnectionRequest "access-token" "connection-id"
            assertRequest deleteRequest "DELETE" "https://api.xero.com" "/connections/connection-id"
            Text.toLower (XeroMock.requestUrlWithoutQuery deleteRequest) `shouldBe` "https://api.xero.com" <> Text.toLower "/Connections/connection-id"
            XeroMock.headerValue "Authorization" deleteRequest `shouldBe` Just "Bearer access-token"

        it "constructs Payroll AU read requests with documented server, paths, methods, and tenant header" do
            XeroMock.assertSpecServer payrollSpec XeroMock.xeroPayrollServer
            forM_
                [ ("/Employees", buildFetchPayrollEmployeesRequest "access-token" "tenant-id")
                , ("/PayItems", buildFetchEarningsRatesRequest "access-token" "tenant-id")
                , ("/PayrollCalendars", buildFetchPayrollCalendarsRequest "access-token" "tenant-id")
                , ("/Settings", buildFetchPayrollSettingsAccountsRequest "access-token" "tenant-id")
                , ("/PayRuns", buildFetchPayRunsRequest "access-token" "tenant-id" XeroMock.samplePayRunQuery)
                , ("/Timesheets/{TimesheetID}", buildFetchTimesheetRequest "access-token" "tenant-id" "timesheet-id")
                ]
                \(specPath, request) -> do
                    XeroMock.assertSpecOperation payrollSpec specPath "get"
                    request.xeroRequestMethod `shouldBe` "GET"
                    XeroMock.headerValue "Authorization" request `shouldBe` Just "Bearer access-token"
                    XeroMock.headerValue "Xero-Tenant-Id" request `shouldBe` Just "tenant-id"
                    XeroMock.headerValue "Accept" request `shouldBe` Just "application/json"
                    request.xeroRequestBody `shouldBe` Nothing

            assertRequest (buildFetchPayrollEmployeesRequest "access-token" "tenant-id") "GET" XeroMock.xeroPayrollServer "/Employees"
            assertRequest (buildFetchEarningsRatesRequest "access-token" "tenant-id") "GET" XeroMock.xeroPayrollServer "/PayItems"
            assertRequest (buildFetchPayrollCalendarsRequest "access-token" "tenant-id") "GET" XeroMock.xeroPayrollServer "/PayrollCalendars"
            assertRequest (buildFetchPayrollSettingsAccountsRequest "access-token" "tenant-id") "GET" XeroMock.xeroPayrollServer "/Settings"
            assertRequest (buildFetchPayRunsRequest "access-token" "tenant-id" XeroMock.samplePayRunQuery) "GET" XeroMock.xeroPayrollServer "/PayRuns"

        it "constructs Accounting accounts read requests with tenant header" do
            let request = buildFetchAccountsRequest "access-token" "tenant-id"
            request.xeroRequestMethod `shouldBe` "GET"
            assertRequest request "GET" "https://api.xero.com/api.xro/2.0" "/Accounts"
            XeroMock.headerValue "Authorization" request `shouldBe` Just "Bearer access-token"
            XeroMock.headerValue "Xero-Tenant-Id" request `shouldBe` Just "tenant-id"
            XeroMock.headerValue "Accept" request `shouldBe` Just "application/json"
            request.xeroRequestBody `shouldBe` Nothing
            assertRequest (buildFetchTimesheetRequest "access-token" "tenant-id" "timesheet-id") "GET" XeroMock.xeroPayrollServer "/Timesheets/timesheet-id"

        it "constructs PayRuns list query parameters and If-Modified-Since header in documented locations" do
            XeroMock.assertSpecOperation payrollSpec "/PayRuns" "get"
            let request = buildFetchPayRunsRequest "access-token" "tenant-id" XeroMock.samplePayRunQuery
            request.xeroRequestMethod `shouldBe` "GET"
            request.xeroRequestUrl
                `shouldBe` "https://api.xero.com/payroll.xro/1.0/PayRuns?where=PayrollCalendarID%3D%3DGuid%28%22calendar-id%22%29&order=PayRunPeriodStartDate%20DESC&page=2"
            XeroMock.headerValue "If-Modified-Since" request `shouldBe` Just "Thu, 30 Apr 2026 01:02:03 GMT"
            XeroMock.headerValue "Xero-Tenant-Id" request `shouldBe` Just "tenant-id"

        it "constructs Timesheets list query parameters and If-Modified-Since header in documented locations" do
            XeroMock.assertSpecOperation payrollSpec "/Timesheets" "get"
            let request = buildFetchTimesheetsRequest "access-token" "tenant-id" XeroMock.sampleTimesheetQuery
            request.xeroRequestMethod `shouldBe` "GET"
            request.xeroRequestUrl
                `shouldBe` "https://api.xero.com/payroll.xro/1.0/Timesheets?where=EmployeeID%3D%3DGuid%28%22employee-1%22%29&order=StartDate%20DESC&page=2"
            XeroMock.headerValue "If-Modified-Since" request `shouldBe` Just "Thu, 30 Apr 2026 01:02:03 GMT"
            XeroMock.headerValue "Xero-Tenant-Id" request `shouldBe` Just "tenant-id"

        it "constructs Payroll AU write requests with idempotency headers and documented body envelopes" do
            XeroMock.assertSpecOperation payrollSpec "/PayItems" "post"
            XeroMock.assertSpecOperation payrollSpec "/Timesheets" "post"
            XeroMock.assertSpecOperation payrollSpec "/Timesheets/{TimesheetID}" "post"
            XeroMock.assertSpecContains payrollSpec "name: Idempotency-Key"
            XeroMock.assertOperationContains payrollSpec "/Timesheets" "post" "type: array"
            XeroMock.assertOperationContains payrollSpec "/Timesheets/{TimesheetID}" "post" "type: array"

            let payItemsRequest = buildCreatePayItemRequest "access-token" "tenant-id" "idem-pay-items" XeroMock.samplePayItemsBody
            assertWriteRequest payItemsRequest "/PayItems" "idem-pay-items"
            XeroMock.jsonBody payItemsRequest `shouldSatisfy` XeroMock.hasArrayField "EarningsRates"

            let createRequest = buildCreateTimesheetRequest "access-token" "tenant-id" "idem-create" XeroMock.sampleTimesheetArrayBody
            assertWriteRequest createRequest "/Timesheets" "idem-create"
            XeroMock.jsonBody createRequest `shouldSatisfy` XeroMock.isJsonArray

            let updateRequest = buildUpdateTimesheetRequest "access-token" "tenant-id" "idem-update" "timesheet-id" XeroMock.sampleTimesheetArrayBody
            assertWriteRequest updateRequest "/Timesheets/timesheet-id" "idem-update"
            XeroMock.jsonBody updateRequest `shouldSatisfy` XeroMock.isJsonArray

        it "validates every app Xero endpoint request builder against the vendored OpenAPI operations" do
            forM_ (XeroMock.xeroRequestContractCases identitySpec payrollSpec) \(spec, contract, request) ->
                XeroMock.validateXeroRequest spec contract request

        it "keeps the OpenAPI contract table in step with exported Xero request builders" do
            helperSource <- TextIO.readFile "Application/Helper/Xero.hs"
            exportedBuildRequestNames helperSource `shouldBe` expectedBuildRequestExports
            List.sort (map (XeroMock.contractName . middleOfThree) (XeroMock.xeroRequestContractCases identitySpec payrollSpec))
                `shouldBe` List.sort expectedContractCaseNames
            coveredXeroClientOperationNames `shouldBe` expectedContractCaseNames

        it "fetches all paginated Payroll AU pay item pages" do
            XeroMock.withPaginatedPayItemsMock \urls -> do
                result <- withXeroRequestBaseUrlsForTest urls do
                    client <- currentXeroClient
                    client.fetchEarningsRates "access-token" "tenant-id"
                fmap (map (.xeroEarningsRateId)) result `shouldBe` Right (map (\index -> "earnings-rate-" <> tshow index) [1 .. 101 :: Int])

        it "exercises the concrete XeroClient HTTP transport against a strict localhost OpenAPI mock" do
            XeroMock.withStrictXeroMock identitySpec payrollSpec \urls -> do
                withXeroRequestBaseUrlsForTest urls do
                    client <- currentXeroClient
                    exchangeResult <- client.exchangeCodeForToken XeroMock.testConfig "auth-code"
                    exchangeResult `shouldSatisfy` isRight

                    refreshResult <- client.refreshXeroToken XeroMock.testConfig "refresh-token"
                    refreshResult `shouldSatisfy` isRight

                    tenantsResult <- client.fetchConnectedTenants "access-token"
                    fmap (map (.tenantId)) tenantsResult `shouldBe` Right ["tenant-id"]

                    deleteResult <- client.deleteXeroConnection "access-token" "connection-id"
                    deleteResult `shouldBe` Right ()

                    employeesResult <- client.fetchPayrollEmployees "access-token" "tenant-id"
                    fmap (map (.xeroEmployeeId)) employeesResult `shouldBe` Right ["employee-id"]

                    earningsResult <- client.fetchEarningsRates "access-token" "tenant-id"
                    fmap (map (.xeroEarningsRateId)) earningsResult `shouldBe` Right ["earnings-rate-id"]

                    calendarsResult <- client.fetchPayrollCalendars "access-token" "tenant-id"
                    fmap (map (.xeroPayrollCalendarId)) calendarsResult `shouldBe` Right ["calendar-id"]

                    accountsResult <- client.fetchAccounts "access-token" "tenant-id"
                    fmap (map (.xeroAccountCode)) accountsResult `shouldBe` Right [Just "477"]

                    settingsAccountsResult <- client.fetchPayrollSettingsAccounts "access-token" "tenant-id"
                    fmap (map (.xeroAccountType)) settingsAccountsResult `shouldBe` Right [Just "WAGESEXPENSE"]

                    payRunsResult <- client.fetchPayRuns "access-token" "tenant-id" XeroMock.samplePayRunQuery
                    fmap (map (.xeroPayRunId)) payRunsResult `shouldBe` Right ["pay-run-id"]

                    payItemResult <- client.createPayItem "access-token" "tenant-id" "idem-pay-items" XeroMock.samplePayItemsBody
                    fmap (map (.xeroEarningsRateId)) payItemResult `shouldBe` Right ["earnings-rate-id"]

                    timesheetsResult <- client.fetchTimesheets "access-token" "tenant-id" XeroMock.sampleTimesheetQuery
                    fmap (map (.xeroTimesheetEmployeeId)) timesheetsResult `shouldBe` Right ["employee-id"]

                    timesheetResult <- client.fetchTimesheet "access-token" "tenant-id" "timesheet-id"
                    fmap (.xeroTimesheetEmployeeId) timesheetResult `shouldBe` Right "employee-id"

                    createTimesheetResult <- client.createTimesheet "access-token" "tenant-id" "idem-create" XeroMock.sampleTimesheetArrayBody
                    fmap (map (.xeroTimesheetEmployeeId)) createTimesheetResult `shouldBe` Right ["employee-id"]

                    updateTimesheetResult <- client.updateTimesheet "access-token" "tenant-id" "idem-update" "timesheet-id" XeroMock.sampleTimesheetArrayBody
                    fmap (map (.xeroTimesheetEmployeeId)) updateTimesheetResult `shouldBe` Right ["employee-id"]

        it "rejects malformed localhost mock requests before returning fixtures" do
            XeroMock.withStrictXeroMockBaseUrl identitySpec payrollSpec \baseUrl -> do
                forM_ XeroMock.malformedMockRequests \(_label, expectedStatus, buildRequest) -> do
                    response <- httpLBS =<< buildRequest baseUrl
                    getResponseStatusCode response `shouldBe` expectedStatus

        it "surfaces Xero HTTP and decode errors through the concrete transport" do
            XeroMock.fixedXeroResponse status400 (Aeson.object ["Type" Aeson..= ("ValidationException" :: Text), "Message" Aeson..= ("Bad payroll data" :: Text)]) \urls -> do
                result <- withXeroRequestBaseUrlsForTest urls do
                    client <- currentXeroClient
                    client.fetchPayrollEmployees "access-token" "tenant-id"
                result `shouldSatisfyLeftText` \message ->
                    "ValidationException" `Text.isInfixOf` message && "Bad payroll data" `Text.isInfixOf` message

            forM_ [(status401, "401"), (status403, "403"), (status429, "429")] \(status, marker) ->
                XeroMock.fixedXeroResponse status (Aeson.object ["message" Aeson..= ("Xero rejected the request" :: Text)]) \urls -> do
                    result <- withXeroRequestBaseUrlsForTest urls do
                        client <- currentXeroClient
                        client.fetchPayrollEmployees "access-token" "tenant-id"
                    result `shouldSatisfyLeftText` Text.isInfixOf ("status " <> marker)

            XeroMock.fixedXeroRawResponse status200 "not-json" \urls -> do
                result <- withXeroRequestBaseUrlsForTest urls do
                    client <- currentXeroClient
                    client.fetchPayrollEmployees "access-token" "tenant-id"
                result `shouldSatisfy` \case
                    Left (XeroDecodeError _) -> True
                    _                        -> False

expectedBuildRequestExports :: [Text]
expectedBuildRequestExports =
    [ "buildCreatePayItemRequest"
    , "buildCreateTimesheetRequest"
    , "buildDeleteXeroConnectionRequest"
    , "buildExchangeCodeForTokenRequest"
    , "buildFetchAccountsRequest"
    , "buildFetchConnectedTenantsRequest"
    , "buildFetchEarningsRatesRequest"
    , "buildFetchPayRunsRequest"
    , "buildFetchPayrollCalendarsRequest"
    , "buildFetchPayrollEmployeesRequest"
    , "buildFetchPayrollSettingsAccountsRequest"
    , "buildFetchTimesheetRequest"
    , "buildFetchTimesheetsRequest"
    , "buildRefreshXeroTokenRequest"
    , "buildUpdateTimesheetRequest"
    ]

expectedContractCaseNames :: [Text]
expectedContractCaseNames =
    [ "token exchange"
    , "token refresh"
    , "connections list"
    , "connection delete"
    , "employees list"
    , "pay items list"
    , "payroll calendars list"
    , "payroll settings accounts"
    , "pay runs list"
    , "timesheets list"
    , "timesheet show"
    , "pay item create"
    , "timesheet create"
    , "timesheet update"
    ]

coveredXeroClientOperationNames :: [Text]
coveredXeroClientOperationNames = expectedContractCaseNames

exportedBuildRequestNames :: Text -> [Text]
exportedBuildRequestNames source =
    source
        |> Text.lines
        |> map Text.strip
        |> filter (\line -> ", build" `Text.isPrefixOf` line && "Request" `Text.isInfixOf` line)
        |> map (Text.dropWhile (== ','))
        |> map Text.strip
        |> filter (not . Text.isInfixOf "With")
        |> List.sort

middleOfThree :: (a, b, c) -> b
middleOfThree (_, value, _) = value

assertTokenRequest :: XeroHttpRequest -> [(ByteString, ByteString)] -> Expectation
assertTokenRequest request expectedBody = do
    request.xeroRequestMethod `shouldBe` "POST"
    request.xeroRequestUrl `shouldBe` "https://identity.xero.com/connect/token"
    XeroMock.headerValue "Accept" request `shouldBe` Just "application/json"
    XeroMock.headerValue "Content-Type" request `shouldBe` Just "application/x-www-form-urlencoded"
    XeroMock.headerValue "Authorization" request `shouldBe` Just expectedBasicAuth
    request.xeroRequestBody `shouldBe` Just (XeroFormBody expectedBody)

expectedBasicAuth :: ByteString
expectedBasicAuth =
    "Basic " <> Base64.encode (TextEncoding.encodeUtf8 ("client-id:client-secret" :: Text))

assertRequest :: XeroHttpRequest -> ByteString -> Text -> Text -> Expectation
assertRequest request method server path = do
    request.xeroRequestMethod `shouldBe` method
    XeroMock.requestUrlWithoutQuery request `shouldBe` server <> path

assertWriteRequest :: XeroHttpRequest -> Text -> ByteString -> Expectation
assertWriteRequest request path idempotencyKey = do
    assertRequest request "POST" XeroMock.xeroPayrollServer path
    XeroMock.headerValue "Authorization" request `shouldBe` Just "Bearer access-token"
    XeroMock.headerValue "Xero-Tenant-Id" request `shouldBe` Just "tenant-id"
    XeroMock.headerValue "Accept" request `shouldBe` Just "application/json"
    XeroMock.headerValue "Content-Type" request `shouldBe` Just "application/json"
    XeroMock.headerValue "Idempotency-Key" request `shouldBe` Just idempotencyKey

shouldSatisfyLeftText :: Show value => Either XeroClientError value -> (Text -> Bool) -> Expectation
shouldSatisfyLeftText result predicate =
    case result of
        Left err | predicate (xeroClientErrorMessage err) -> pure ()
        _ -> expectationFailure (cs ("Expected XeroClientError matching predicate, got: " <> tshow result))

xeroClientErrorMessage :: XeroClientError -> Text
xeroClientErrorMessage = \case
    XeroHttpError message -> message
    XeroDecodeError message -> message
    XeroNoTenantsError -> "No tenants"
