module Application.Helper.Controller.Input
    ( boundedText
    , normalizeMaybeTextField
    , normalizeText
    , normalizeTextField
    , paramTexts
    , parseUUIDText
    , requireParam
    , requiredBoundedTextField
    ) where

import qualified Data.ByteString as ByteString
import qualified Data.Text as Text
import qualified Data.Text.Encoding as Text
import qualified Data.UUID as UUID
import IHP.ControllerPrelude
import IHP.ValidationSupport.Types (attachFailure)
import Network.Wai (Request)

normalizeText :: Text -> Text
normalizeText = Text.strip

paramTexts :: (?request :: Request) => ByteString -> [Text]
paramTexts paramName =
    [ Text.decodeUtf8 rawValue
    | (name, Just rawValue) <- allParams
    , name == paramName
    ]

parseUUIDText :: Text -> Maybe UUID.UUID
parseUUIDText =
    UUID.fromText

boundedText :: Int -> Text -> ValidatorResult
boundedText maxLength value
    | Text.length value <= maxLength = Success
    | otherwise = Failure ("is longer than " <> tshow maxLength <> " characters")

requireParam ::
    forall field model.
    ( ?request :: Request
    , KnownSymbol field
    , HasField "meta" model MetaBag
    , SetField "meta" model MetaBag
    ) =>
    Proxy field ->
    ByteString ->
    Text ->
    model ->
    model
requireParam field paramName message model =
    case queryOrBodyParam paramName of
        Nothing -> attachFailure field message model
        Just rawValue
            | ByteString.null rawValue -> attachFailure field message model
            | otherwise -> model

normalizeTextField ::
    forall field model.
    ( KnownSymbol field
    , HasField field model Text
    , SetField field model Text
    ) =>
    Proxy field ->
    model ->
    model
normalizeTextField field =
    modify field normalizeText

normalizeMaybeTextField ::
    forall field model.
    ( KnownSymbol field
    , HasField field model (Maybe Text)
    , SetField field model (Maybe Text)
    ) =>
    Proxy field ->
    model ->
    model
normalizeMaybeTextField field =
    modify field (fmap normalizeText >=> blankToNothing)
    where
        blankToNothing value
            | Text.null value = Nothing
            | otherwise = Just value

requiredBoundedTextField ::
    forall field model.
    ( KnownSymbol field
    , HasField field model Text
    , SetField field model Text
    , HasField "meta" model MetaBag
    , SetField "meta" model MetaBag
    ) =>
    Proxy field ->
    Int ->
    model ->
    model
requiredBoundedTextField field maxLength model =
    model
        |> normalizeTextField field
        |> validateField field nonEmpty
        |> validateField field (boundedText maxLength)
