module Test.StripeMock
    ( ExpectedStripeRequest (..)
    , StrictStripeMock
    , assertStripeMockConsumed
    , newStrictStripeMock
    , strictStripeTransport
    )
where

import Application.Billing.Stripe
import qualified Data.ByteString as ByteString
import qualified Data.ByteString.Lazy as LByteString
import qualified Data.IORef as IORef
import qualified Data.List as List
import qualified Data.Text as Text
import qualified Data.Text.Encoding as TextEncoding
import IHP.Prelude
import Network.HTTP.Types.URI (parseQuery)
import Test.Hspec

data ExpectedStripeRequest = ExpectedStripeRequest
    { expectedMethod         :: !ByteString
    , expectedPath           :: !Text
    , expectedQuery          :: ![(ByteString, Maybe ByteString)]
    , expectedFormBody       :: ![(ByteString, ByteString)]
    , expectedIdempotencyKey :: !(Maybe ByteString)
    , responseBody           :: !LByteString.ByteString
    }
    deriving (Eq, Show)

newtype StrictStripeMock = StrictStripeMock (IORef.IORef [ExpectedStripeRequest])

newStrictStripeMock :: [ExpectedStripeRequest] -> IO StrictStripeMock
newStrictStripeMock expectations =
    StrictStripeMock <$> IORef.newIORef expectations

strictStripeTransport :: StrictStripeMock -> StripeHttpRequest -> IO (Either StripeClientError LByteString.ByteString)
strictStripeTransport (StrictStripeMock ref) request = do
    expectations <- IORef.readIORef ref
    case expectations of
        [] ->
            pure (Left (StripeHttpError ("Unexpected Stripe request to " <> request.stripeRequestUrl)))
        expected : rest -> do
            IORef.writeIORef ref rest
            pure case validateRequest expected request of
                Left err -> Left (StripeHttpError err)
                Right () -> Right expected.responseBody

assertStripeMockConsumed :: StrictStripeMock -> Expectation
assertStripeMockConsumed (StrictStripeMock ref) = do
    remaining <- IORef.readIORef ref
    remaining `shouldBe` []

validateRequest :: ExpectedStripeRequest -> StripeHttpRequest -> Either Text ()
validateRequest expected request = do
    unless (request.stripeRequestMethod == expected.expectedMethod) do
        Left ("Expected Stripe method " <> cs expected.expectedMethod <> ", got " <> cs request.stripeRequestMethod)
    unless (requestPath request == expected.expectedPath) do
        Left ("Expected Stripe path " <> expected.expectedPath <> ", got " <> requestPath request)
    unless (normalizeQuery (requestQuery request) == normalizeQuery expected.expectedQuery) do
        Left ("Unexpected Stripe query for " <> expected.expectedPath)
    unless (normalizeForm (requestFormBody request) == normalizeForm expected.expectedFormBody) do
        Left ("Unexpected Stripe form body for " <> expected.expectedPath)
    unless (lookup "Authorization" request.stripeRequestHeaders == Just "Bearer sk_test_123") do
        Left "Stripe Authorization header was missing or incorrect"
    unless (lookup "Stripe-Version" request.stripeRequestHeaders == Just (TextEncoding.encodeUtf8 pinnedStripeApiVersion)) do
        Left "Stripe-Version header was missing or incorrect"
    unless (lookup "Idempotency-Key" request.stripeRequestHeaders == expected.expectedIdempotencyKey) do
        Left "Stripe Idempotency-Key header did not match"

requestPath :: StripeHttpRequest -> Text
requestPath request =
    request.stripeRequestUrl
        |> Text.drop (Text.length "https://api.stripe.com")
        |> Text.takeWhile (/= '?')

requestQuery :: StripeHttpRequest -> [(ByteString, Maybe ByteString)]
requestQuery request =
    case Text.breakOn "?" request.stripeRequestUrl of
        (_, "") -> []
        (_, queryWithQuestion) ->
            parseQuery (TextEncoding.encodeUtf8 queryWithQuestion)

requestFormBody :: StripeHttpRequest -> [(ByteString, ByteString)]
requestFormBody request =
    case request.stripeRequestBody of
        Just (StripeFormBody body) -> body
        Nothing                    -> []

normalizeQuery :: [(ByteString, Maybe ByteString)] -> [(ByteString, Maybe ByteString)]
normalizeQuery = List.sort

normalizeForm :: [(ByteString, ByteString)] -> [(ByteString, ByteString)]
normalizeForm = List.sort
