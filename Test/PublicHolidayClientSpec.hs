module Test.PublicHolidayClientSpec where

import IHP.Prelude
import Application.PublicHolidays.Client
import Application.PublicHolidays.Override (verifiedVic2026Holidays)
import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Lazy as LBS
import qualified Data.ByteString.Char8 as BS
import Data.IORef
import Data.Either (isLeft)
import qualified Network.HTTP.Client as HTTP
import Test.Hspec

fixture :: Integer -> IO LBS.ByteString
fixture year = LBS.readFile ("Test/Fixtures/wage-sources/datavic-v2/" <> cs (tshow year) <> ".json")

response :: Int -> Int -> Int -> [Aeson.Value] -> LBS.ByteString
response total page limit rows = Aeson.encode (Aeson.object
    [ "_meta" Aeson..= Aeson.object ["total_records" Aeson..= total, "page" Aeson..= page, "limit" Aeson..= limit]
    , "dates" Aeson..= rows
    ])

row :: Text -> Text -> Text -> Text -> Aeson.Value
row date name kind uuid = Aeson.object
    [ "date" Aeson..= date, "name" Aeson..= name, "type" Aeson..= kind, "uuid" Aeson..= uuid
    , "description" Aeson..= (" " :: Text)
    ]

tests :: Spec
tests = describe "DataVic v2 read-only candidate client" do
    it "matches every reviewed 2026 date/name pair from the live dated fixture" do
        body <- fixture 2026
        case decodeDataVicYear 2026 body of
            Left err -> expectationFailure (cs (tshow err))
            Right dates -> do
                sort (map (\entry -> (entry.date, entry.name)) dates) `shouldBe` sort verifiedVic2026Holidays
                map (.sourceId) dates `shouldBe` replicate 14 Nothing
                map (.sourceUrl) dates `shouldSatisfy` all (== "https://wovg-community.gateway.prod.api.vic.gov.au/vicgov/v2.0/dates?type=PUBLIC_HOLIDAY&from_date=2026-01-01&to_date=2026-12-31&limit=100&page=1&sort=date:asc")

    it "rejects the actual wrong Easter Monday 2027 instead of silently fixing it" do
        body <- fixture 2027
        decodeDataVicYear 2027 body `shouldBe` Left DataVicInvalidCalendar

    it "rejects malformed, empty, partial, oversized and repeated-page responses" do
        let r = row "2026-01-01" "New Year's Day" "PUBLIC_HOLIDAY" ""
        decodeDataVicYear 2026 "not-json" `shouldBe` Left DataVicMalformedResponse
        forM_ [response 0 1 100 [], response 2 1 100 [r], response 1 2 100 [r], response 1 1 50 [r], response 101 1 100 (replicate 101 r)] \body ->
            decodeDataVicYear 2026 body `shouldBe` Left DataVicIncompleteResponse
        decodeDataVicYear 2026 (LBS.replicate (1024 * 1024 + 1) 32) `shouldBe` Left DataVicResponseTooLarge

    it "rejects out-of-year, slash, ambiguous timestamp, invalid date, blank name and wrong type" do
        let invalidRows =
                [ row "2027-01-01" "New Year's Day" "PUBLIC_HOLIDAY" ""
                , row "1/01/2026" "New Year's Day" "PUBLIC_HOLIDAY" ""
                , row "2026-09-03T00:00:00" "Labour Day" "PUBLIC_HOLIDAY" ""
                , row "2026-02-30" "Bad date" "PUBLIC_HOLIDAY" ""
                , row "2026-1-01" "New Year's Day" "PUBLIC_HOLIDAY" ""
                , row "2026-01-01" " " "PUBLIC_HOLIDAY" ""
                , row "2026-01-01" "Other" "SCHOOL_TERM" ""
                ]
        forM_ invalidRows \r -> decodeDataVicYear 2026 (response 1 1 100 [r]) `shouldBe` Left DataVicInvalidCalendar

    it "rejects duplicate holiday identities or nonempty IDs but permits blank IDs" do
        let r = row "2026-01-01" "New Year's Day" "PUBLIC_HOLIDAY" "one"
            other = row "2026-01-26" "Australia Day" "PUBLIC_HOLIDAY" "one"
        decodeDataVicYear 2026 (response 2 1 100 [r,r]) `shouldBe` Left DataVicInvalidCalendar
        decodeDataVicYear 2026 (response 2 1 100 [r,other]) `shouldBe` Left DataVicInvalidCalendar

    it "accepts a corrected Monday without pinning the wrong provider value" do
        let monday = row "2027-03-29" "Easter Monday" "PUBLIC_HOLIDAY" ""
        decodeDataVicYear 2027 (response 1 1 100 [monday]) `shouldSatisfy` not . isLeft

    it "sends the verified annual query with key-only auth and no redirects" do
        body <- fixture 2026
        requests <- newIORef []
        let send request = modifyIORef' requests (<> [request]) >> pure (Right (200, body))
        result <- fetchDataVicYearsWith send "test-key-not-secret" [2026,2026]
        result `shouldSatisfy` not . isLeft
        sent <- readIORef requests
        length sent `shouldBe` 1
        forM_ sent \request -> do
            HTTP.method request `shouldBe` "GET"
            HTTP.secure request `shouldBe` True
            HTTP.host request `shouldBe` "wovg-community.gateway.prod.api.vic.gov.au"
            HTTP.path request `shouldBe` "/vicgov/v2.0/dates"
            HTTP.queryString request `shouldBe` "?type=PUBLIC_HOLIDAY&from_date=2026-01-01&to_date=2026-12-31&limit=100&page=1&sort=date%3Aasc"
            lookup "apikey" (HTTP.requestHeaders request) `shouldBe` Just "test-key-not-secret"
            lookup "Authorization" (HTTP.requestHeaders request) `shouldBe` Nothing
            HTTP.redirectCount request `shouldBe` 0
            HTTP.responseTimeout request `shouldBe` HTTP.responseTimeoutMicro (30 * 1000000)

    it "does not request with missing credentials or invalid/unbounded year selections" do
        let never _ = expectationFailure "unexpected HTTP call" >> pure (Left DataVicTransportUnavailable)
        forM_ ["", " ", "key\nheader"] \key -> fetchDataVicYearsWith never key [2026] `shouldReturn` Left DataVicMissingKey
        forM_ [[], [0], [10000], [2020..2025]] \years -> fetchDataVicYearsWith never "key" years `shouldReturn` Left DataVicInvalidYear

    it "returns only sanitized errors for provider status failures" do
        forM_ [301,401,403,429,500] \status -> do
            let send _ = pure (Right (status, "credential-reflecting upstream error body"))
            fetchDataVicYearsWith send "key" [2026] `shouldReturn` Left (DataVicHttpStatus status)

    it "returns no partial candidate when the next year is invalid; stops before later years" do
        good <- fixture 2026
        bad <- fixture 2027
        calls <- newIORef (0 :: Int)
        let send request = do
                modifyIORef' calls (+1)
                pure (Right (200, if BS.isInfixOf "from_date=2026" (HTTP.queryString request) then good else bad))
        fetchDataVicYearsWith send "key" [2028,2027,2026] `shouldReturn` Left DataVicInvalidCalendar
        readIORef calls `shouldReturn` 2

    it "preserves typed transport failure without attempting subsequent requests" do
        fetchDataVicYearsWith (\_ -> pure (Left DataVicTransportUnavailable)) "key" [2026,2027]
            `shouldReturn` Left DataVicTransportUnavailable
