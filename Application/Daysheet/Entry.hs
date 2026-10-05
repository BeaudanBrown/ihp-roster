-- | Bounded raw numeric/time form inputs. Nominal transport retains submitted
-- spelling for validation/conflict rendering; the pinned field type owns the
-- second, semantic parse. No floating point or expression parser is involved.
module Application.Daysheet.Entry
    ( DaysheetNumericEntry, DaysheetClockEntry, DaysheetDeletionToken
    , parseNumericEntry, parseClockEntry, deletionToken
    ) where

import Prelude
import Application.Daysheet.Contract
import qualified Application.Daysheet.Daily.Types as Daily
import qualified Application.Daysheet.Evaluation as Evaluation
import qualified "crypton" Crypto.Hash as Hash
import Data.List (sort)
import qualified Data.Text.Encoding as TextEncoding
import qualified Application.Daysheet.Number as Number
import Application.Helper.NominalText
import qualified Data.Text as Text
import Data.Text (Text)
import Data.Time (TimeOfDay (..), defaultTimeLocale, parseTimeM)

newtype DaysheetNumericEntry = DaysheetNumericEntry Text deriving (Eq, Show)
newtype DaysheetClockEntry = DaysheetClockEntry Text deriving (Eq, Show)
newtype DaysheetDeletionToken = DaysheetDeletionToken Text deriving (Eq, Show)

-- A version fingerprint, not authority or a client-owned mutation document.
-- Compare with a freshly loaded plan; the locked mutation must still validate
-- that exact plan. No deleted values or reference contents enter this token.
instance NominalText DaysheetDeletionToken where
    renderNominalText (DaysheetDeletionToken value) = value
    parseNominalText value
        | Text.length value == 64 && Text.all (\c -> (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f')) value = Right (DaysheetDeletionToken value)
        | otherwise = Left "Refresh the deletion confirmation."

deletionToken :: Evaluation.SnapshotKey -> Daily.DeletionPlan -> DaysheetDeletionToken
deletionToken scope plan = DaysheetDeletionToken (Text.pack (show digest))
  where
    payload = Text.pack (show ("daysheet-delete-v1" :: String, scope, Daily.deletionTarget plan, Daily.targetRevision plan, sort (Daily.incomingCells plan)))
    digest = Hash.hash (TextEncoding.encodeUtf8 payload) :: Hash.Digest Hash.SHA256

instance NominalText DaysheetNumericEntry where
    renderNominalText (DaysheetNumericEntry value) = value
    parseNominalText value = DaysheetNumericEntry <$> bounded 80 value
instance NominalText DaysheetClockEntry where
    renderNominalText (DaysheetClockEntry value) = value
    parseNominalText value = DaysheetClockEntry <$> bounded 32 value

bounded :: Int -> Text -> Either Text Text
bounded sizeLimit value
    | Text.length value > sizeLimit || Text.any (== '\NUL') value = Left "The entered value is too long or contains unsupported text."
    | otherwise = Right value

parseNumericEntry :: FieldType -> DaysheetNumericEntry -> Either Text Literal
parseNumericEntry fieldType (DaysheetNumericEntry raw) = do
    (numerator, denominator) <- decimal (Text.strip raw)
    let divisor = denominator * if fieldType == PercentageType then 100 else 1
    let common = gcd numerator divisor
    value <- either (const (Left "The number exceeds the supported range.")) Right
        (Number.number (numerator `div` common) (divisor `div` common))
    case fieldType of
        WholeType -> case Number.fraction value of
            (whole, 1) -> Right (WholeLiteral whole)
            _ -> Left "Enter a whole number."
        DecimalType -> Right (DecimalLiteral value)
        MoneyType -> either (const (Left "Enter an AUD amount with whole-cent precision.")) (Right . MoneyLiteral) (Number.enteredMoney value)
        PercentageType -> Right (PercentageLiteral value)
        _ -> Left "This field does not accept a numeric entry."
  where
    decimal text = do
        let (sign, unsigned) = case Text.uncons text of
                Just ('-', rest) -> (-1, rest)
                Just ('+', rest) -> (1, rest)
                _ -> (1, text)
        (whole, fraction) <- case Text.splitOn "." unsigned of
            [whole] -> Right (whole, "")
            [whole, fraction] -> Right (whole, fraction)
            _ -> Left "Enter a decimal number, without formulas or separators."
        let digits = whole <> fraction
        if Text.null digits || not (Text.all (\character -> character >= '0' && character <= '9') digits)
            then Left "Enter a decimal number, without formulas or separators."
            else Right (sign * Text.foldl' (\total character -> total * 10 + toInteger (fromEnum character - fromEnum '0')) 0 digits,
                10 ^ Text.length fraction)

parseClockEntry :: DaysheetClockEntry -> Either Text Literal
parseClockEntry (DaysheetClockEntry raw) = do
    let value = Text.strip raw
    format <- case Text.length value of
        5 -> Right "%H:%M"
        8 -> Right "%H:%M:%S"
        _ -> Left "Enter a time as HH:MM."
    case parseTimeM True defaultTimeLocale format (Text.unpack value) of
        Just time | todHour time >= 0 && todHour time < 24 && todMin time >= 0 && todMin time < 60 && todSec time >= 0 && todSec time < 60 -> Right (OperationalTimeLiteral time)
        _ -> Left "Enter a valid Operational-day clock time."
