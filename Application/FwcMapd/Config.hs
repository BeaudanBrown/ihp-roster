module Application.FwcMapd.Config where

import qualified Data.Text as Text
import IHP.Prelude
import qualified System.Environment as Environment
import Text.Read (readMaybe)

data MapdConfig = MapdConfig
    { apiKey        :: !Text
    , baseUrl       :: !Text
    , awardFixedIds :: ![Int]
    }
    deriving (Eq, Show)

defaultBaseUrl :: Text
defaultBaseUrl = "https://api.fwc.gov.au/api/v1"

defaultAwardFixedIds :: [Int]
defaultAwardFixedIds = [9]

loadMapdConfig :: IO (Maybe MapdConfig)
loadMapdConfig = do
    maybeApiKey <- fmap (Text.strip . cs) <$> Environment.lookupEnv "FWC_MAPD_KEY"
    case maybeApiKey of
        Nothing -> pure Nothing
        Just apiKeyValue
            | Text.null apiKeyValue -> pure Nothing
            | otherwise -> do
                maybeBaseUrl <- fmap (Text.strip . cs) <$> Environment.lookupEnv "FWC_MAPD_BASE_URL"
                maybeAwardIds <- fmap (Text.strip . cs) <$> Environment.lookupEnv "FWC_MAPD_AWARD_IDS"
                let configuredBaseUrl =
                        case maybeBaseUrl of
                            Just rawBaseUrl | not (Text.null rawBaseUrl) -> rawBaseUrl
                            _ -> defaultBaseUrl
                pure
                    ( Just
                        MapdConfig
                            { apiKey = apiKeyValue
                            , baseUrl = configuredBaseUrl
                            , awardFixedIds = fromMaybe defaultAwardFixedIds (parseAwardFixedIds =<< maybeAwardIds)
                            }
                    )

parseAwardFixedIds :: Text -> Maybe [Int]
parseAwardFixedIds rawValue =
    if null parsedIds then Nothing else Just parsedIds
    where
        parsedIds =
            rawValue
                |> Text.splitOn ","
                |> map Text.strip
                |> filter (not . Text.null)
                |> mapMaybe (readMaybe . cs)
