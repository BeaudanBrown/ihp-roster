module Application.FwcMapd.Client where

import Application.FwcMapd.Config
import qualified Control.Exception as Exception
import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Char8 as ByteString
import qualified Data.Text as Text
import IHP.Prelude
import Network.HTTP.Simple

data MapdPageMeta = MapdPageMeta
    { pageCount   :: !Int
    , currentPage :: !Int
    }
    deriving (Eq, Show)

data MapdResultsPage = MapdResultsPage
    { results :: ![Aeson.Value]
    , meta    :: !MapdPageMeta
    }
    deriving (Eq, Show)

instance Aeson.FromJSON MapdPageMeta where
    parseJSON = Aeson.withObject "MapdPageMeta" \object ->
        MapdPageMeta
            <$> object Aeson..: "page_count"
            <*> object Aeson..: "current_page"

instance Aeson.FromJSON MapdResultsPage where
    parseJSON = Aeson.withObject "MapdResultsPage" \object ->
        MapdResultsPage
            <$> object Aeson..: "results"
            <*> object Aeson..: "_meta"

fetchAwardValues :: MapdConfig -> Int -> IO [Aeson.Value]
fetchAwardValues config awardFixedId =
    fetchPagedEndpoint config (awardPath awardFixedId) []

fetchClassificationValues :: MapdConfig -> Int -> IO [Aeson.Value]
fetchClassificationValues config awardFixedId =
    fetchPagedEndpoint config (awardPath awardFixedId <> "/classifications") []

fetchPayRateValues :: MapdConfig -> Int -> IO [Aeson.Value]
fetchPayRateValues config awardFixedId =
    fetchPagedEndpoint config (awardPath awardFixedId <> "/pay-rates") []

fetchPagedEndpoint :: MapdConfig -> Text -> [(ByteString.ByteString, Maybe ByteString.ByteString)] -> IO [Aeson.Value]
fetchPagedEndpoint config path extraQueryParams = do
    firstPage <- fetchPage config path 1 extraQueryParams
    remainingPages <- forM [2 .. firstPage.meta.pageCount] \pageNumber ->
        fetchPage config path pageNumber extraQueryParams
    pure (firstPage.results <> concatMap (.results) remainingPages)

fetchPage :: MapdConfig -> Text -> Int -> [(ByteString.ByteString, Maybe ByteString.ByteString)] -> IO MapdResultsPage
fetchPage config path pageNumber extraQueryParams = do
    request <- buildRequest config path pageNumber extraQueryParams
    response <- httpLBS request
    let statusCode = getResponseStatusCode response
    when (statusCode < 200 || statusCode >= 300) do
        Exception.throwIO
            (userError (cs ("FWC MAPD request failed with status " <> tshow statusCode <> " for " <> path)))
    case Aeson.eitherDecode (getResponseBody response) of
        Left errorMessage ->
            Exception.throwIO
                (userError ("FWC MAPD response decode failed for " <> cs path <> ": " <> errorMessage))
        Right page -> pure page

buildRequest :: MapdConfig -> Text -> Int -> [(ByteString.ByteString, Maybe ByteString.ByteString)] -> IO Request
buildRequest config path pageNumber extraQueryParams = do
    request <- parseRequest (cs (normalizeBaseUrl config.baseUrl <> path))
    pure
        ( request
            |> setRequestMethod "GET"
            |> setRequestHeader "Ocp-Apim-Subscription-Key" [cs config.apiKey]
            |> setRequestQueryString
                ( extraQueryParams
                    <> [ ("page", Just (cs (tshow pageNumber)))
                       , ("limit", Just "100")
                       ]
                )
        )

awardPath :: Int -> Text
awardPath awardFixedId = "/awards/" <> tshow awardFixedId

normalizeBaseUrl :: Text -> Text
normalizeBaseUrl = Text.dropWhileEnd (== '/')
