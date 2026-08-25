module Application.FwcMapd.Client where

import Application.FwcMapd.Config
import Application.FwcMapd.Error
import Application.FwcMapd.Validation (expectedCoreClassificationFixedIds)
import qualified Control.Exception as Exception
import Control.Monad (foldM)
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Types as Aeson
import qualified Data.Bifunctor as Bifunctor
import qualified Data.ByteString.Char8 as ByteString
import qualified Data.Map.Strict as Map
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
fetchClassificationValues config awardFixedId = do
    pagedValues <- fetchPagedEndpoint config classificationPath []
    canonicalValues <- concat <$> forM expectedCoreClassificationFixedIds \classificationFixedId ->
        fetchPagedEndpoint config classificationPath [("classification_fixed_id", Just (cs (tshow classificationFixedId)))]
    case assembleCanonicalClassificationValues expectedCoreClassificationFixedIds pagedValues canonicalValues of
        Left _       -> Exception.throwIO MapdResponseMalformed
        Right values -> pure values
    where
        classificationPath = awardPath awardFixedId <> "/classifications"

assembleCanonicalClassificationValues :: [Int] -> [Aeson.Value] -> [Aeson.Value] -> Either Text [Aeson.Value]
assembleCanonicalClassificationValues expectedIds pagedValues canonicalValues = do
    valuesByIdentity <- foldM addValue Map.empty (pagedValues <> canonicalValues)
    let assembled = Map.elems valuesByIdentity
        assembledIds = mapMaybe classificationFixedId assembled
    forM_ expectedIds \expectedId ->
        unless (expectedId `elem` assembledIds)
            (Left ("FWC MAPD classification retrieval incomplete: missing classification_fixed_id " <> tshow expectedId))
    pure assembled
    where
        addValue accumulated value = do
            identity@(fixedId, _, _) <- classificationIdentity value
            if fixedId `notElem` expectedIds
                then Right accumulated
                else case Map.lookup identity accumulated of
                    Nothing -> Right (Map.insert identity value accumulated)
                    Just existing
                        | existing == value -> Right accumulated
                        | otherwise -> Left ("FWC MAPD classification retrieval conflicting duplicate classification_fixed_id " <> tshow fixedId)
        classificationIdentity :: Aeson.Value -> Either Text (Int, Maybe Day, Maybe Day)
        classificationIdentity =
            Bifunctor.first cs
                . Aeson.parseEither
                    ( Aeson.withObject "classification" \object ->
                        (,,)
                            <$> object Aeson..: "classification_fixed_id"
                            <*> object Aeson..:? "operative_from"
                            <*> object Aeson..:? "operative_to"
                    )
        classificationFixedId =
            Aeson.parseMaybe (Aeson.withObject "classification" (Aeson..: "classification_fixed_id"))

fetchPayRateValues :: MapdConfig -> Int -> IO [Aeson.Value]
fetchPayRateValues config awardFixedId =
    fetchPagedEndpoint config (awardPath awardFixedId <> "/pay-rates") []

fetchWageAllowanceValues :: MapdConfig -> Int -> IO [Aeson.Value]
fetchWageAllowanceValues config awardFixedId =
    fetchPagedEndpoint config (awardPath awardFixedId <> "/wage-allowances") []


fetchPenaltyRateValuesForBasePayRateId :: MapdConfig -> Int -> Text -> IO [Aeson.Value]
fetchPenaltyRateValuesForBasePayRateId config awardFixedId basePayRateId =
    fetchPagedEndpoint
        config
        (awardPath awardFixedId <> "/penalties")
        [("base_pay_rate_id", Just (cs basePayRateId))]

fetchPagedEndpoint :: MapdConfig -> Text -> [(ByteString.ByteString, Maybe ByteString.ByteString)] -> IO [Aeson.Value]
fetchPagedEndpoint config path extraQueryParams = do
    firstPage <- fetchPage config path 1 extraQueryParams
    remainingPages <- forM [2 .. firstPage.meta.pageCount] \pageNumber ->
        fetchPage config path pageNumber extraQueryParams
    case assemblePagedResults (firstPage : remainingPages) of
        Left _       -> Exception.throwIO MapdResponseMalformed
        Right values -> pure values

assemblePagedResults :: [MapdResultsPage] -> Either Text [Aeson.Value]
assemblePagedResults [] = Left "FWC MAPD paging incomplete: no pages returned"
assemblePagedResults pages@(firstPage : _) = do
    let expectedPageCount = firstPage.meta.pageCount
    when (expectedPageCount < 1)
        (Left ("FWC MAPD paging inconsistent: invalid page_count " <> tshow expectedPageCount))
    unless (length pages == expectedPageCount)
        (Left ("FWC MAPD paging incomplete: expected " <> tshow expectedPageCount <> " pages but received " <> tshow (length pages)))
    forM_ (zip [1 ..] pages) \(requestedPage, page) -> do
        unless (page.meta.currentPage == requestedPage)
            (Left ("FWC MAPD paging inconsistent: requested page " <> tshow requestedPage <> " reported current_page " <> tshow page.meta.currentPage))
        unless (page.meta.pageCount == expectedPageCount)
            (Left ("FWC MAPD paging inconsistent: page " <> tshow requestedPage <> " changed page_count from " <> tshow expectedPageCount <> " to " <> tshow page.meta.pageCount))
    pure (concatMap (.results) pages)

fetchPage :: MapdConfig -> Text -> Int -> [(ByteString.ByteString, Maybe ByteString.ByteString)] -> IO MapdResultsPage
fetchPage config path pageNumber extraQueryParams = do
    request <- buildRequest config path pageNumber extraQueryParams
    response <- httpLBS request
    let statusCode = getResponseStatusCode response
    when (statusCode < 200 || statusCode >= 300) do
        Exception.throwIO MapdProviderUnavailable
    case Aeson.eitherDecode (getResponseBody response) of
        Left _     -> Exception.throwIO MapdResponseMalformed
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
