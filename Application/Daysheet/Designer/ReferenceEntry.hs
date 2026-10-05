-- | Raw form spelling is interpreted only by the saved field declaration.
-- No client-supplied type, list scope or replacement reference document is used.
module Application.Daysheet.Designer.ReferenceEntry (parseReferenceEntry) where

import Prelude
import Application.Daysheet.Contract
import Application.Daysheet.Entry (parseNumericEntry, parseClockEntry)
import qualified Application.Daysheet.Evaluation as E
import Application.Daysheet.References
import Application.Helper.NominalText (parseNominalText)
import Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.UUID as UUID
import Data.Time (defaultTimeLocale, parseTimeM)

parseReferenceEntry :: FieldType -> Text -> Either Text (Maybe ReferenceValue)
parseReferenceEntry kind raw
    | Text.length raw > maxTextLength limits || Text.any (== '\NUL') raw = Left "The entered value is too long or contains unsupported text."
    | Text.null raw = Right Nothing
    | otherwise = Just <$> case kind of
        TextType -> scalar (TextLiteral raw)
        BooleanType -> case raw of
            "true" -> scalar (BooleanLiteral True)
            "false" -> scalar (BooleanLiteral False)
            _ -> Left "Choose Yes, No or blank."
        ChoiceType _ -> scalar . ChoiceLiteral . ChoiceId =<< identity
        ReferenceType source -> ReferenceLink . ReferenceKey source . E.RowId <$> identity
        DateType | Text.length raw == 10 -> maybe (Left "Enter a date as YYYY-MM-DD.") (scalar . DateLiteral)
            (parseTimeM True defaultTimeLocale "%Y-%m-%d" (Text.unpack raw))
        DateType -> Left "Enter a date as YYYY-MM-DD."
        OperationalTimeType -> ReferenceScalar <$> (parseNominalText raw >>= parseClockEntry)
        _ -> ReferenceScalar <$> (parseNominalText raw >>= parseNumericEntry kind)
  where
    scalar = Right . ReferenceScalar
    identity = maybe (Left "Choose a valid entry from the list.") Right (UUID.fromText raw)
