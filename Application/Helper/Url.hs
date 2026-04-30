module Application.Helper.Url
    ( appendQueryParams
    ) where

import qualified Data.Text as Text
import qualified Data.Text.Encoding as TextEncoding
import IHP.Prelude
import qualified Network.HTTP.Types.URI as URI

appendQueryParams :: Text -> [(Text, Text)] -> Text
appendQueryParams basePath params
    | null nonEmptyParams = basePath
    | Text.isInfixOf "?" basePath = basePath <> "&" <> renderedParams
    | otherwise = basePath <> "?" <> renderedParams
    where
        nonEmptyParams = filter (not . Text.null . snd) params
        renderedParams =
            TextEncoding.decodeUtf8
                ( URI.renderQuery
                    False
                    [ (TextEncoding.encodeUtf8 key, Just (TextEncoding.encodeUtf8 value))
                    | (key, value) <- nonEmptyParams
                    ]
                )
