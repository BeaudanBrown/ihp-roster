module Test.XeroMock where

import Application.Helper.Xero
import qualified Control.Exception as Exception
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as Key
import qualified Data.Aeson.KeyMap as KeyMap
import qualified Data.ByteString.Char8 as ByteStringChar8
import qualified Data.ByteString.Lazy as LByteString
import qualified Data.IORef as IORef
import qualified Data.List as List
import qualified Data.Text as Text
import qualified Data.Text.Encoding as TextEncoding
import qualified Data.Text.IO as TextIO
import Data.Time.Calendar (fromGregorian)
import Data.Time.Clock (UTCTime (..), secondsToDiffTime)
import qualified Data.Vector as Vector
import IHP.Prelude
import Network.HTTP.Simple (Request, parseRequest, setRequestBodyJSON,
                            setRequestHeader, setRequestMethod)
import Network.HTTP.Types.Header (HeaderName)
import Network.HTTP.Types.Method (methodDelete, methodGet, methodPost)
import Network.HTTP.Types.Status (Status, status200, status204, status400,
                                  status404)
import qualified Network.HTTP.Types.URI as URI
import qualified Network.Wai as Wai
import qualified Network.Wai.Handler.Warp as Warp
import Test.Hspec

data OpenApiSpec = OpenApiSpec
    { specPath :: !FilePath
    , specText :: !Text
    }

data PathMatch
    = CaseSensitivePath
    | CaseInsensitivePath
    deriving (Eq, Show)

data BodyContract
    = NoRequestBody
    | FormRequestFields [ByteString]
    | JsonObjectWithArrayField Text
    | JsonArrayBody
    deriving (Eq, Show)

data XeroEndpointContract = XeroEndpointContract
    { contractName             :: !Text
    , contractSpecServer       :: !(Maybe Text)
    , contractRequestServer    :: !Text
    , contractSpecPath         :: !Text
    , contractMethod           :: !ByteString
    , contractRequestPath      :: !Text
    , contractPathMatch        :: !PathMatch
    , contractRequiredHeaders  :: ![HeaderName]
    , contractDocumentedParams :: ![Text]
    , contractAllowedQueries   :: ![ByteString]
    , contractBody             :: !BodyContract
    }
    deriving (Eq, Show)

testConfig :: XeroConfig
testConfig =
    XeroConfig
        { clientId = "client-id"
        , clientSecret = "client-secret"
        , redirectUri = "http://localhost:8000/XeroOAuthCallback"
        , tokenEncryptionKey = "unused"
        }

xeroPayrollServer :: Text
xeroPayrollServer = "https://api.xero.com/payroll.xro/1.0"

loadOpenApiSpec :: FilePath -> IO OpenApiSpec
loadOpenApiSpec path = OpenApiSpec path <$> TextIO.readFile path

loadXeroOpenApiSpecs :: IO (OpenApiSpec, OpenApiSpec)
loadXeroOpenApiSpecs = do
    identitySpec <- loadOpenApiSpec "vendor/xero-openapi/xero-identity.yaml"
    payrollSpec <- loadOpenApiSpec "vendor/xero-openapi/xero-payroll-au.yaml"
    pure (identitySpec, payrollSpec)

xeroRequestContractCases :: OpenApiSpec -> OpenApiSpec -> [(OpenApiSpec, XeroEndpointContract, XeroHttpRequest)]
xeroRequestContractCases identitySpec payrollSpec =
    [ (identitySpec, tokenContract "token exchange" (FormRequestFields ["grant_type", "code", "redirect_uri"]), buildExchangeCodeForTokenRequest testConfig "auth-code")
    , (identitySpec, tokenContract "token refresh" (FormRequestFields ["grant_type", "refresh_token"]), buildRefreshXeroTokenRequest testConfig "refresh-token")
    , (identitySpec, identityContract "connections list" "GET" "/Connections" "/connections" NoRequestBody, buildFetchConnectedTenantsRequest "access-token")
    , (identitySpec, identityContract "connection delete" "DELETE" "/Connections/{id}" "/connections/connection-id" NoRequestBody, buildDeleteXeroConnectionRequest "access-token" "connection-id")
    , (payrollSpec, payrollReadContract "employees list" "/Employees" "/Employees" [], buildFetchPayrollEmployeesRequest "access-token" "tenant-id")
    , (payrollSpec, payrollReadContract "pay items list" "/PayItems" "/PayItems" [], buildFetchEarningsRatesRequest "access-token" "tenant-id")
    , (payrollSpec, payrollReadContract "payroll calendars list" "/PayrollCalendars" "/PayrollCalendars" [], buildFetchPayrollCalendarsRequest "access-token" "tenant-id")
    , ( payrollSpec
      , (payrollReadContract "pay runs list" "/PayRuns" "/PayRuns" ["where", "order", "page", "If-Modified-Since"]) { contractAllowedQueries = ["where", "order", "page"] }
      , buildFetchPayRunsRequest "access-token" "tenant-id" samplePayRunQuery
      )
    , ( payrollSpec
      , (payrollReadContract "timesheets list" "/Timesheets" "/Timesheets" ["where", "order", "page", "If-Modified-Since"]) { contractAllowedQueries = ["where", "order", "page"] }
      , buildFetchTimesheetsRequest "access-token" "tenant-id" sampleTimesheetQuery
      )
    , (payrollSpec, payrollReadContract "timesheet show" "/Timesheets/{TimesheetID}" "/Timesheets/timesheet-id" [], buildFetchTimesheetRequest "access-token" "tenant-id" "timesheet-id")
    , (payrollSpec, payrollWriteContract "pay item create" "/PayItems" "/PayItems" (JsonObjectWithArrayField "EarningsRates"), buildCreatePayItemRequest "access-token" "tenant-id" "idem-pay-items" samplePayItemsBody)
    , (payrollSpec, payrollWriteContract "timesheet create" "/Timesheets" "/Timesheets" JsonArrayBody, buildCreateTimesheetRequest "access-token" "tenant-id" "idem-create" sampleTimesheetArrayBody)
    , (payrollSpec, payrollWriteContract "timesheet update" "/Timesheets/{TimesheetID}" "/Timesheets/timesheet-id" JsonArrayBody, buildUpdateTimesheetRequest "access-token" "tenant-id" "idem-update" "timesheet-id" sampleTimesheetArrayBody)
    ]

tokenContract :: Text -> BodyContract -> XeroEndpointContract
tokenContract name body =
    XeroEndpointContract
        { contractName = name
        , contractSpecServer = Nothing
        , contractRequestServer = "https://identity.xero.com"
        , contractSpecPath = "/connect/token"
        , contractMethod = "POST"
        , contractRequestPath = "/connect/token"
        , contractPathMatch = CaseSensitivePath
        , contractRequiredHeaders = ["Authorization", "Accept", "Content-Type"]
        , contractDocumentedParams = []
        , contractAllowedQueries = []
        , contractBody = body
        }

identityContract :: Text -> ByteString -> Text -> Text -> BodyContract -> XeroEndpointContract
identityContract name method specPath requestPath body =
    XeroEndpointContract
        { contractName = name
        , contractSpecServer = Just "https://api.xero.com"
        , contractRequestServer = "https://api.xero.com"
        , contractSpecPath = specPath
        , contractMethod = method
        , contractRequestPath = requestPath
        , contractPathMatch = CaseInsensitivePath
        , contractRequiredHeaders = ["Authorization", "Accept"]
        , contractDocumentedParams = []
        , contractAllowedQueries = []
        , contractBody = body
        }

payrollReadContract :: Text -> Text -> Text -> [Text] -> XeroEndpointContract
payrollReadContract name specPath requestPath documentedParams =
    XeroEndpointContract
        { contractName = name
        , contractSpecServer = Just xeroPayrollServer
        , contractRequestServer = xeroPayrollServer
        , contractSpecPath = specPath
        , contractMethod = "GET"
        , contractRequestPath = requestPath
        , contractPathMatch = CaseSensitivePath
        , contractRequiredHeaders = ["Authorization", "Accept", "Xero-Tenant-Id"]
        , contractDocumentedParams = documentedParams
        , contractAllowedQueries = []
        , contractBody = NoRequestBody
        }

payrollWriteContract :: Text -> Text -> Text -> BodyContract -> XeroEndpointContract
payrollWriteContract name specPath requestPath body =
    XeroEndpointContract
        { contractName = name
        , contractSpecServer = Just xeroPayrollServer
        , contractRequestServer = xeroPayrollServer
        , contractSpecPath = specPath
        , contractMethod = "POST"
        , contractRequestPath = requestPath
        , contractPathMatch = CaseSensitivePath
        , contractRequiredHeaders = ["Authorization", "Accept", "Xero-Tenant-Id", "Idempotency-Key", "Content-Type"]
        , contractDocumentedParams = ["Idempotency-Key"]
        , contractAllowedQueries = []
        , contractBody = body
        }

samplePayItemsBody :: Aeson.Value
samplePayItemsBody =
    Aeson.object
        [ "EarningsRates" Aeson..= [Aeson.object ["Name" Aeson..= ("Bepis - Ordinary" :: Text)]]
        ]

sampleTimesheetArrayBody :: Aeson.Value
sampleTimesheetArrayBody =
    Aeson.Array (Vector.fromList [sampleTimesheetObject])

sampleTimesheetObject :: Aeson.Value
sampleTimesheetObject =
    Aeson.object
        [ "EmployeeID" Aeson..= ("employee-id" :: Text)
        , "StartDate" Aeson..= ("2026-05-04" :: Text)
        , "EndDate" Aeson..= ("2026-05-10" :: Text)
        , "Status" Aeson..= ("DRAFT" :: Text)
        , "TimesheetLines" Aeson..= [Aeson.object ["EarningsRateID" Aeson..= ("earnings-id" :: Text), "NumberOfUnits" Aeson..= ([2 :: Int, 0, 0, 0, 0, 0, 0] :: [Int])]]
        ]

sampleTimesheetQuery :: XeroTimesheetQuery
sampleTimesheetQuery =
    XeroTimesheetQuery
        { xeroTimesheetIfModifiedSince = Just (UTCTime (fromGregorian 2026 4 30) (secondsToDiffTime 3723))
        , xeroTimesheetWhere = Just "EmployeeID==Guid(\"employee-1\")"
        , xeroTimesheetOrder = Just "StartDate DESC"
        , xeroTimesheetPage = Just 2
        }

samplePayRunQuery :: XeroPayRunQuery
samplePayRunQuery =
    XeroPayRunQuery
        { xeroPayRunIfModifiedSince = Just (UTCTime (fromGregorian 2026 4 30) (secondsToDiffTime 3723))
        , xeroPayRunWhere = Just "PayrollCalendarID==Guid(\"calendar-id\")"
        , xeroPayRunOrder = Just "PayRunPeriodStartDate DESC"
        , xeroPayRunPage = Just 2
        }

validateXeroRequest :: OpenApiSpec -> XeroEndpointContract -> XeroHttpRequest -> Expectation
validateXeroRequest spec contract request = do
    assertContractSpecOperation spec contract
    request.xeroRequestMethod `shouldBe` contract.contractMethod
    assertRequestPath contract request
    assertRequiredHeaders contract request
    assertAllowedQueryParams contract request
    assertBodyContract contract request

assertContractSpecOperation :: OpenApiSpec -> XeroEndpointContract -> Expectation
assertContractSpecOperation spec contract
    | contract.contractSpecPath == "/connect/token" =
        assertSpecContains spec "tokenUrl: https://identity.xero.com/connect/token"
    | otherwise = do
        forM_ contract.contractSpecServer (assertSpecServer spec)
        assertSpecOperation spec contract.contractSpecPath (Text.toLower (TextEncoding.decodeUtf8 contract.contractMethod))
        forM_ contract.contractDocumentedParams \paramName ->
            assertOperationOrSpecContains spec contract ("name: " <> paramName)

assertRequestPath :: XeroEndpointContract -> XeroHttpRequest -> Expectation
assertRequestPath contract request = do
    let expectedUrl = contract.contractRequestServer <> contract.contractRequestPath
    case contract.contractPathMatch of
        CaseSensitivePath ->
            requestUrlWithoutQuery request `shouldBe` expectedUrl
        CaseInsensitivePath ->
            Text.toLower (requestUrlWithoutQuery request) `shouldBe` Text.toLower expectedUrl

assertRequiredHeaders :: XeroEndpointContract -> XeroHttpRequest -> Expectation
assertRequiredHeaders contract request =
    forM_ contract.contractRequiredHeaders \name ->
        shouldSatisfyWithMessage
            (headerValue name request)
            isJust
            (contract.contractName <> " missing required header " <> cs (show name))

assertAllowedQueryParams :: XeroEndpointContract -> XeroHttpRequest -> Expectation
assertAllowedQueryParams contract request = do
    let actualQueryKeys = List.sort (List.nub (map fst (requestQueryParams request)))
    let expectedQueryKeys = List.sort contract.contractAllowedQueries
    actualQueryKeys `shouldBe` expectedQueryKeys

assertBodyContract :: XeroEndpointContract -> XeroHttpRequest -> Expectation
assertBodyContract contract request =
    case contract.contractBody of
        NoRequestBody ->
            request.xeroRequestBody `shouldBe` Nothing
        FormRequestFields expectedFields ->
            case request.xeroRequestBody of
                Just (XeroFormBody fields) ->
                    List.sort (map fst fields) `shouldBe` List.sort expectedFields
                _ ->
                    expectationFailure (cs (contract.contractName <> " should use a form body"))
        JsonObjectWithArrayField field ->
            case request.xeroRequestBody of
                Just (XeroJsonBody value) ->
                    shouldSatisfyWithMessage
                        value
                        (hasArrayField field)
                        (contract.contractName <> " should use JSON object envelope with " <> field <> " array")
                _ ->
                    expectationFailure (cs (contract.contractName <> " should use a JSON body"))
        JsonArrayBody ->
            case request.xeroRequestBody of
                Just (XeroJsonBody value) ->
                    shouldSatisfyWithMessage
                        value
                        isJsonArray
                        (contract.contractName <> " should use OpenAPI array body envelope")
                _ ->
                    expectationFailure (cs (contract.contractName <> " should use a JSON body"))

assertOperationOrSpecContains :: OpenApiSpec -> XeroEndpointContract -> Text -> Expectation
assertOperationOrSpecContains spec contract expected =
    case operationBlock spec contract.contractSpecPath (Text.toLower (TextEncoding.decodeUtf8 contract.contractMethod)) of
        Just block | expected `Text.isInfixOf` block -> pure ()
        _ | expected `Text.isInfixOf` spec.specText -> pure ()
        _ -> expectationFailure ("Missing documented contract fragment for " <> cs contract.contractName <> ": " <> cs expected)

requestQueryParams :: XeroHttpRequest -> [(ByteString, Maybe ByteString)]
requestQueryParams request =
    case Text.breakOn "?" request.xeroRequestUrl of
        (_url, query)
            | Text.null query -> []
            | otherwise -> URI.parseQuery (TextEncoding.encodeUtf8 query)

shouldSatisfyWithMessage :: Show value => value -> (value -> Bool) -> Text -> Expectation
shouldSatisfyWithMessage value predicate message =
    unless (predicate value) (expectationFailure (cs (message <> ": " <> tshow value)))

withStrictXeroMock :: OpenApiSpec -> OpenApiSpec -> (XeroRequestBaseUrls -> IO a) -> IO a
withStrictXeroMock identitySpec payrollSpec action =
    withStrictXeroMockBaseUrl identitySpec payrollSpec (action . xeroRequestBaseUrlsFor)

withStrictXeroMockTimesheetCreateResponses :: OpenApiSpec -> OpenApiSpec -> [Wai.Response] -> (XeroRequestBaseUrls -> IO a) -> IO a
withStrictXeroMockTimesheetCreateResponses identitySpec payrollSpec timesheetCreateResponses action =
    withStrictXeroMockBaseUrlWithTimesheetCreateResponses identitySpec payrollSpec timesheetCreateResponses (action . xeroRequestBaseUrlsFor)

withStrictXeroMockBaseUrl :: OpenApiSpec -> OpenApiSpec -> (Text -> IO a) -> IO a
withStrictXeroMockBaseUrl identitySpec payrollSpec action =
    withStrictXeroMockBaseUrlWithTimesheetCreateResponses identitySpec payrollSpec [] action

withStrictXeroMockBaseUrlWithTimesheetCreateResponses :: OpenApiSpec -> OpenApiSpec -> [Wai.Response] -> (Text -> IO a) -> IO a
withStrictXeroMockBaseUrlWithTimesheetCreateResponses identitySpec payrollSpec timesheetCreateResponses action = do
    timesheetCreateResponseRef <- IORef.newIORef timesheetCreateResponses
    Warp.testWithApplication (pure (xeroStrictMockApp identitySpec payrollSpec timesheetCreateResponseRef)) \port ->
        action ("http://127.0.0.1:" <> tshow port)

xeroRequestBaseUrlsFor :: Text -> XeroRequestBaseUrls
xeroRequestBaseUrlsFor baseUrl =
    XeroRequestBaseUrls
        { xeroIdentityTokenUrl = baseUrl <> "/connect/token"
        , xeroConnectionsUrl = baseUrl <> "/connections"
        , xeroPayrollBaseUrl = baseUrl <> "/payroll.xro/1.0"
        }

malformedMockRequests :: [(Text, Int, Text -> IO Request)]
malformedMockRequests =
    [ ( "missing Xero-Tenant-Id"
      , 400
      , \baseUrl -> do
            request <- parseRequest (cs (baseUrl <> "/payroll.xro/1.0/Employees"))
            pure (request |> setRequestMethod "GET" |> setRequestHeader "Authorization" ["Bearer access-token"] |> setRequestHeader "Accept" ["application/json"])
      )
    , ( "missing Idempotency-Key"
      , 400
      , \baseUrl -> do
            request <- parseRequest (cs (baseUrl <> "/payroll.xro/1.0/PayItems"))
            pure
                ( request
                    |> setRequestMethod "POST"
                    |> setRequestHeader "Authorization" ["Bearer access-token"]
                    |> setRequestHeader "Accept" ["application/json"]
                    |> setRequestHeader "Xero-Tenant-Id" ["tenant-id"]
                    |> setRequestBodyJSON samplePayItemsBody
                )
      )
    , ( "wrong Timesheets body envelope"
      , 400
      , \baseUrl -> do
            request <- parseRequest (cs (baseUrl <> "/payroll.xro/1.0/Timesheets"))
            pure
                ( request
                    |> setRequestMethod "POST"
                    |> setRequestHeader "Authorization" ["Bearer access-token"]
                    |> setRequestHeader "Accept" ["application/json"]
                    |> setRequestHeader "Xero-Tenant-Id" ["tenant-id"]
                    |> setRequestHeader "Idempotency-Key" ["idem-create"]
                    |> setRequestBodyJSON (Aeson.object ["Timesheets" Aeson..= [sampleTimesheetObject]])
                )
      )
    , ( "unknown Timesheets query param"
      , 400
      , \baseUrl -> do
            request <- parseRequest (cs (baseUrl <> "/payroll.xro/1.0/Timesheets?unexpected=1"))
            pure (request |> setRequestMethod "GET" |> setRequestHeader "Authorization" ["Bearer access-token"] |> setRequestHeader "Accept" ["application/json"] |> setRequestHeader "Xero-Tenant-Id" ["tenant-id"])
      )
    , ( "unexpected method"
      , 404
      , \baseUrl -> do
            request <- parseRequest (cs (baseUrl <> "/payroll.xro/1.0/Employees"))
            pure (request |> setRequestMethod "DELETE" |> setRequestHeader "Authorization" ["Bearer access-token"] |> setRequestHeader "Accept" ["application/json"] |> setRequestHeader "Xero-Tenant-Id" ["tenant-id"])
      )
    , ( "unexpected path"
      , 404
      , \baseUrl -> do
            request <- parseRequest (cs (baseUrl <> "/payroll.xro/1.0/SuperFunds"))
            pure (request |> setRequestMethod "GET" |> setRequestHeader "Authorization" ["Bearer access-token"] |> setRequestHeader "Accept" ["application/json"] |> setRequestHeader "Xero-Tenant-Id" ["tenant-id"])
      )
    ]

fixedXeroResponse :: Status -> Aeson.Value -> (XeroRequestBaseUrls -> IO a) -> IO a
fixedXeroResponse status body =
    fixedXeroRawResponse status (Aeson.encode body)

fixedXeroRawResponse :: Status -> LByteString.ByteString -> (XeroRequestBaseUrls -> IO a) -> IO a
fixedXeroRawResponse status body action =
    Warp.testWithApplication (pure app) \port ->
        action (xeroRequestBaseUrlsFor ("http://127.0.0.1:" <> tshow port))
    where
        app _ respond =
            respond (Wai.responseLBS status [("Content-Type", "application/json")] body)

xeroStrictMockApp :: OpenApiSpec -> OpenApiSpec -> IORef.IORef [Wai.Response] -> Wai.Application
xeroStrictMockApp identitySpec payrollSpec timesheetCreateResponseRef request respond = do
    body <- Wai.strictRequestBody request
    let baseUrl = requestBaseUrl request
    let mockRequest = waiToXeroHttpRequest baseUrl request body
    maybeContract <- mockContractForRequest baseUrl request body
    case maybeContract of
        Nothing ->
            respond (jsonResponse status404 (Aeson.object ["error" Aeson..= ("unexpected Xero mock endpoint" :: Text)]))
        Just (spec, contract, response) -> do
            validation <- Exception.try (validateXeroRequest spec contract mockRequest)
            case validation of
                Left (err :: Exception.SomeException) ->
                    respond (jsonResponse status400 (Aeson.object ["error" Aeson..= (show err :: Text)]))
                Right () ->
                    respond response
    where
        mockContractForRequest baseUrl request body =
            case (Wai.requestMethod request, Wai.rawPathInfo request) of
                (method, "/connect/token")
                    | method == methodPost -> pure (Just (identitySpec, mockTokenContract baseUrl body, jsonResponse status200 tokenFixture))
                (method, "/connections")
                    | method == methodGet -> pure (Just (identitySpec, (identityContract "mock connections list" "GET" "/Connections" "/connections" NoRequestBody) { contractRequestServer = baseUrl }, jsonResponse status200 connectionsFixture))
                (method, "/connections/connection-id")
                    | method == methodDelete -> pure (Just (identitySpec, (identityContract "mock connection delete" "DELETE" "/Connections/{id}" "/connections/connection-id" NoRequestBody) { contractRequestServer = baseUrl }, Wai.responseLBS status204 [] ""))
                (method, "/payroll.xro/1.0/Employees")
                    | method == methodGet -> pure (Just (payrollSpec, mockPayrollReadContract baseUrl "mock employees list" "/Employees" "/Employees" [], jsonResponse status200 employeesFixture))
                (method, "/payroll.xro/1.0/PayItems")
                    | method == methodGet -> pure (Just (payrollSpec, mockPayrollReadContract baseUrl "mock pay items list" "/PayItems" "/PayItems" [], jsonResponse status200 payItemsFixture))
                    | method == methodPost -> pure (Just (payrollSpec, mockPayrollWriteContract baseUrl "mock pay item create" "/PayItems" "/PayItems" (JsonObjectWithArrayField "EarningsRates"), jsonResponse status200 payItemsFixture))
                (method, "/payroll.xro/1.0/PayrollCalendars")
                    | method == methodGet -> pure (Just (payrollSpec, mockPayrollReadContract baseUrl "mock payroll calendars list" "/PayrollCalendars" "/PayrollCalendars" [], jsonResponse status200 calendarsFixture))
                (method, "/payroll.xro/1.0/PayRuns")
                    | method == methodGet -> pure (Just (payrollSpec, (mockPayrollReadContract baseUrl "mock pay runs list" "/PayRuns" "/PayRuns" ["where", "order", "page", "If-Modified-Since"]) { contractAllowedQueries = ["where", "order", "page"] }, jsonResponse status200 payRunsFixture))
                (method, "/payroll.xro/1.0/Timesheets")
                    | method == methodGet -> pure (Just (payrollSpec, (mockPayrollReadContract baseUrl "mock timesheets list" "/Timesheets" "/Timesheets" ["where", "order", "page", "If-Modified-Since"]) { contractAllowedQueries = ["where", "order", "page"] }, jsonResponse status200 timesheetsFixture))
                    | method == methodPost -> do
                        response <- nextTimesheetCreateResponse
                        pure (Just (payrollSpec, mockPayrollWriteContract baseUrl "mock timesheet create" "/Timesheets" "/Timesheets" JsonArrayBody, response))
                (method, "/payroll.xro/1.0/Timesheets/timesheet-id")
                    | method == methodGet -> pure (Just (payrollSpec, mockPayrollReadContract baseUrl "mock timesheet show" "/Timesheets/{TimesheetID}" "/Timesheets/timesheet-id" [], jsonResponse status200 timesheetFixture))
                    | method == methodPost -> pure (Just (payrollSpec, mockPayrollWriteContract baseUrl "mock timesheet update" "/Timesheets/{TimesheetID}" "/Timesheets/timesheet-id" JsonArrayBody, jsonResponse status200 timesheetsFixture))
                _ -> pure Nothing

        nextTimesheetCreateResponse = IORef.atomicModifyIORef' timesheetCreateResponseRef \case
            [] -> ([], jsonResponse status200 timesheetsFixture)
            response : rest -> (rest, response)

mockTokenContract :: Text -> LByteString.ByteString -> XeroEndpointContract
mockTokenContract baseUrl body =
    (tokenContract "mock token request" (FormRequestFields expectedFields)) { contractRequestServer = baseUrl }
    where
        formFields = map fst (URI.parseQuery (LByteString.toStrict body))
        expectedFields
            | "refresh_token" `elem` formFields = ["grant_type", "refresh_token"]
            | otherwise = ["grant_type", "code", "redirect_uri"]

mockPayrollReadContract :: Text -> Text -> Text -> Text -> [Text] -> XeroEndpointContract
mockPayrollReadContract baseUrl name specPath requestPath documentedParams =
    (payrollReadContract name specPath requestPath documentedParams) { contractRequestServer = baseUrl <> "/payroll.xro/1.0" }

mockPayrollWriteContract :: Text -> Text -> Text -> Text -> BodyContract -> XeroEndpointContract
mockPayrollWriteContract baseUrl name specPath requestPath body =
    (payrollWriteContract name specPath requestPath body) { contractRequestServer = baseUrl <> "/payroll.xro/1.0" }

waiToXeroHttpRequest :: Text -> Wai.Request -> LByteString.ByteString -> XeroHttpRequest
waiToXeroHttpRequest baseUrl request body =
    XeroHttpRequest
        { xeroRequestMethod = Wai.requestMethod request
        , xeroRequestUrl = baseUrl <> TextEncoding.decodeUtf8 (Wai.rawPathInfo request <> Wai.rawQueryString request)
        , xeroRequestHeaders = Wai.requestHeaders request
        , xeroRequestBody = parseMockRequestBody request body
        }

parseMockRequestBody :: Wai.Request -> LByteString.ByteString -> Maybe XeroRequestBody
parseMockRequestBody request body
    | LByteString.null body = Nothing
    | headerValueFromList "Content-Type" (Wai.requestHeaders request) == Just "application/x-www-form-urlencoded" =
        Just (XeroFormBody (mapMaybe sequencePair (URI.parseQuery (LByteString.toStrict body))))
    | otherwise =
        XeroJsonBody <$> Aeson.decode body
    where
        sequencePair (key, Just value) = Just (key, value)
        sequencePair (_key, Nothing)   = Nothing

requestBaseUrl :: Wai.Request -> Text
requestBaseUrl request =
    "http://127.0.0.1:" <> TextEncoding.decodeUtf8 (maybe "80" portFromHost (lookup "Host" (Wai.requestHeaders request)))
    where
        portFromHost host =
            case ByteStringChar8.dropWhile (/= ':') host of
                colonAndPort | not (ByteStringChar8.null colonAndPort) -> ByteStringChar8.drop 1 colonAndPort
                _ -> host

headerValueFromList :: HeaderName -> [(HeaderName, ByteString)] -> Maybe ByteString
headerValueFromList = lookup

jsonResponse :: Status -> Aeson.Value -> Wai.Response
jsonResponse status body =
    Wai.responseLBS status [("Content-Type", "application/json")] (Aeson.encode body)

tokenFixture :: Aeson.Value
tokenFixture =
    Aeson.object
        [ "access_token" Aeson..= ("access-token" :: Text)
        , "refresh_token" Aeson..= ("refresh-token" :: Text)
        , "expires_in" Aeson..= (1800 :: Int)
        , "scope" Aeson..= requiredXeroScopesText
        ]

connectionsFixture :: Aeson.Value
connectionsFixture =
    Aeson.toJSON
        [ Aeson.object
            [ "id" Aeson..= ("connection-id" :: Text)
            , "tenantId" Aeson..= ("tenant-id" :: Text)
            , "tenantName" Aeson..= ("Demo Company" :: Text)
            ]
        ]

employeesFixture :: Aeson.Value
employeesFixture =
    Aeson.object
        [ "Employees" Aeson..=
            [ Aeson.object
                [ "EmployeeID" Aeson..= ("employee-id" :: Text)
                , "FirstName" Aeson..= ("Ada" :: Text)
                , "LastName" Aeson..= ("Lovelace" :: Text)
                , "Email" Aeson..= ("ada@example.test" :: Text)
                , "Status" Aeson..= ("ACTIVE" :: Text)
                ]
            ]
        ]

payItemsFixture :: Aeson.Value
payItemsFixture =
    Aeson.object
        [ "PayItems" Aeson..=
            Aeson.object
                [ "EarningsRates" Aeson..=
                    [ Aeson.object
                        [ "EarningsRateID" Aeson..= ("earnings-rate-id" :: Text)
                        , "Name" Aeson..= ("Ordinary Hours" :: Text)
                        , "EarningsType" Aeson..= ("ORDINARYTIMEEARNINGS" :: Text)
                        , "RateType" Aeson..= ("RATEPERUNIT" :: Text)
                        , "IsActive" Aeson..= True
                        ]
                    ]
                ]
        ]

calendarsFixture :: Aeson.Value
calendarsFixture =
    Aeson.object
        [ "PayrollCalendars" Aeson..=
            [ Aeson.object
                [ "PayrollCalendarID" Aeson..= ("calendar-id" :: Text)
                , "Name" Aeson..= ("Weekly" :: Text)
                , "CalendarType" Aeson..= ("WEEKLY" :: Text)
                , "StartDate" Aeson..= ("2026-05-04" :: Text)
                , "PaymentDate" Aeson..= ("2026-05-11" :: Text)
                ]
            ]
        ]

payRunsFixture :: Aeson.Value
payRunsFixture =
    Aeson.object
        [ "PayRuns" Aeson..=
            [ Aeson.object
                [ "PayRunID" Aeson..= ("pay-run-id" :: Text)
                , "PayrollCalendarID" Aeson..= ("calendar-id" :: Text)
                , "PayRunPeriodStartDate" Aeson..= ("2026-05-04" :: Text)
                , "PayRunPeriodEndDate" Aeson..= ("2026-05-10" :: Text)
                , "PaymentDate" Aeson..= ("2026-05-11" :: Text)
                , "PayRunStatus" Aeson..= ("DRAFT" :: Text)
                ]
            ]
        ]

timesheetsFixture :: Aeson.Value
timesheetsFixture =
    Aeson.object ["Timesheets" Aeson..= [timesheetObjectFixture]]

timesheetFixture :: Aeson.Value
timesheetFixture =
    Aeson.object ["Timesheet" Aeson..= timesheetObjectFixture]

timesheetObjectFixture :: Aeson.Value
timesheetObjectFixture =
    Aeson.object
        [ "TimesheetID" Aeson..= ("timesheet-id" :: Text)
        , "EmployeeID" Aeson..= ("employee-id" :: Text)
        , "StartDate" Aeson..= ("2026-05-04" :: Text)
        , "EndDate" Aeson..= ("2026-05-10" :: Text)
        , "Status" Aeson..= ("DRAFT" :: Text)
        , "Hours" Aeson..= (2 :: Int)
        , "TimesheetLines" Aeson..=
            [ Aeson.object
                [ "EarningsRateID" Aeson..= ("earnings-rate-id" :: Text)
                , "NumberOfUnits" Aeson..= ([2 :: Int, 0, 0, 0, 0, 0, 0] :: [Int])
                ]
            ]
        ]

headerValue :: HeaderName -> XeroHttpRequest -> Maybe ByteString
headerValue name request = lookup name request.xeroRequestHeaders

requestUrlWithoutQuery :: XeroHttpRequest -> Text
requestUrlWithoutQuery request =
    fst (Text.breakOn "?" request.xeroRequestUrl)

jsonBody :: XeroHttpRequest -> Aeson.Value
jsonBody request =
    case request.xeroRequestBody of
        Just (XeroJsonBody value) -> value
        _                         -> error "Expected JSON request body"

isJsonArray :: Aeson.Value -> Bool
isJsonArray (Aeson.Array _) = True
isJsonArray _               = False

hasArrayField :: Text -> Aeson.Value -> Bool
hasArrayField field (Aeson.Object object) =
    case KeyMap.lookup (Key.fromText field) object of
        Just (Aeson.Array _) -> True
        _                    -> False
hasArrayField _ _ = False

assertSpecServer :: OpenApiSpec -> Text -> Expectation
assertSpecServer spec server =
    assertSpecContains spec ("url: " <> server)

assertSpecOperation :: OpenApiSpec -> Text -> Text -> Expectation
assertSpecOperation spec path method =
    assertOperationContains spec path method (methodLine method)

assertOperationContains :: OpenApiSpec -> Text -> Text -> Text -> Expectation
assertOperationContains spec path method expected =
    case operationBlock spec path method of
        Nothing -> expectationFailure ("Missing " <> cs method <> " operation for " <> cs path <> " in " <> spec.specPath)
        Just block -> block `shouldSatisfy` Text.isInfixOf expected

assertSpecContains :: OpenApiSpec -> Text -> Expectation
assertSpecContains spec expected =
    spec.specText `shouldSatisfy` Text.isInfixOf expected

operationBlock :: OpenApiSpec -> Text -> Text -> Maybe Text
operationBlock spec path method = do
    pathBlock <- pathBlockFor spec path
    let marker = methodLine method
    let (_before, methodAndRest) = break (Text.isPrefixOf marker) (Text.lines pathBlock)
    case methodAndRest of
        [] -> Nothing
        methodLineFound : rest -> Just (Text.unlines (methodLineFound : takeWhile (not . startsPeerOperation) rest))

pathBlockFor :: OpenApiSpec -> Text -> Maybe Text
pathBlockFor spec path = do
    let marker = "  " <> path <> ":"
    (_before, blockStart) <- nonEmptyBreakOn marker spec.specText
    let blockLines = Text.lines blockStart
    pure (Text.unlines (take 1 blockLines <> takeWhile (not . startsPath) (drop 1 blockLines)))

nonEmptyBreakOn :: Text -> Text -> Maybe (Text, Text)
nonEmptyBreakOn needle haystack =
    let parts = Text.breakOn needle haystack
     in if Text.null (snd parts) then Nothing else Just parts

methodLine :: Text -> Text
methodLine method = "    " <> method <> ":"

startsPath :: Text -> Bool
startsPath line = "  /" `Text.isPrefixOf` line

startsPeerOperation :: Text -> Bool
startsPeerOperation line =
    any (`Text.isPrefixOf` line) ["    get:", "    post:", "    put:", "    delete:"]
