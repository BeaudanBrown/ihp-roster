module Application.Helper.Url
    ( appendQueryParams
    , replaceQueryParams
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
        renderedParams = renderQueryParams False nonEmptyParams

-- | Make the supplied parameters authoritative while retaining unrelated route
-- context already present in the URL. Repeated supplied keys remain repeated;
-- an empty supplied value removes that key from the result.
replaceQueryParams :: Text -> [(Text, Text)] -> Text
replaceQueryParams url params =
    path <> renderedQuery <> fragment
    where
        (pathAndQuery, fragment) = Text.breakOn "#" url
        (path, queryWithPrefix) = Text.breakOn "?" pathAndQuery
        existingQuery =
            if Text.null queryWithPrefix
                then []
                else URI.parseQuery (TextEncoding.encodeUtf8 (Text.drop 1 queryWithPrefix))
        replacedKeys = fmap (TextEncoding.encodeUtf8 . fst) params
        retainedQuery = filter (\(key, _) -> key `notElem` replacedKeys) existingQuery
        suppliedQuery =
            [ (TextEncoding.encodeUtf8 key, Just (TextEncoding.encodeUtf8 value))
            | (key, value) <- params
            , not (Text.null value)
            ]
        combinedQuery = retainedQuery <> suppliedQuery
        renderedQuery = TextEncoding.decodeUtf8 (URI.renderQuery True combinedQuery)

renderQueryParams :: Bool -> [(Text, Text)] -> Text
renderQueryParams includeQuestionMark params =
    TextEncoding.decodeUtf8
        ( URI.renderQuery
            includeQuestionMark
            [ (TextEncoding.encodeUtf8 key, Just (TextEncoding.encodeUtf8 value))
            | (key, value) <- params
            ]
        )
