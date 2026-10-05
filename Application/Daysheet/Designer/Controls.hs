-- | Finite designer controls. These Haskell values own their generated browser
-- vocabulary; the browser neither infers field types nor constructs formulas.
module Application.Daysheet.Designer.Controls
    ( FieldKind (..), ListKind (..), fieldKind, fieldKindLabel, fieldKindType
    , listKind, listKindLabel, listKindMode
    ) where

import Prelude
import Application.Daysheet.Contract
import Data.Text (Text)
import IHP.ModelSupport (InputValue (..))

data FieldKind = TextField | BooleanField | ChoiceField | WholeField | DecimalField
    | MoneyField | PercentageField | DateField | ClockField | ReferenceField
    deriving (Eq, Show, Enum, Bounded)
data ListKind = VenueList | DailyList | Checklist deriving (Eq, Show, Enum, Bounded)

instance InputValue FieldKind where
    inputValue TextField = "text"
    inputValue BooleanField = "boolean"
    inputValue ChoiceField = "choice"
    inputValue WholeField = "whole"
    inputValue DecimalField = "decimal"
    inputValue MoneyField = "money"
    inputValue PercentageField = "percentage"
    inputValue DateField = "date"
    inputValue ClockField = "clock"
    inputValue ReferenceField = "reference"

instance InputValue ListKind where
    inputValue VenueList = "venue-reference"
    inputValue DailyList = "open-daily"
    inputValue Checklist = "reference-checklist"

fieldKind :: FieldType -> FieldKind
fieldKind TextType = TextField
fieldKind BooleanType = BooleanField
fieldKind (ChoiceType _) = ChoiceField
fieldKind WholeType = WholeField
fieldKind DecimalType = DecimalField
fieldKind MoneyType = MoneyField
fieldKind PercentageType = PercentageField
fieldKind DateType = DateField
fieldKind OperationalTimeType = ClockField
fieldKind (ReferenceType _) = ReferenceField

fieldKindLabel :: FieldKind -> Text
fieldKindLabel TextField = "Text"
fieldKindLabel BooleanField = "Yes / no"
fieldKindLabel ChoiceField = "Choice"
fieldKindLabel WholeField = "Whole number"
fieldKindLabel DecimalField = "Decimal number"
fieldKindLabel MoneyField = "Money (AUD)"
fieldKindLabel PercentageField = "Percentage"
fieldKindLabel DateField = "Date"
fieldKindLabel ClockField = "Operational time"
fieldKindLabel ReferenceField = "Single reference"

-- Choices retain their identities when an existing choice field is renamed.
-- Validation of choices and reference scope remains with validateDefinition.
fieldKindType :: FieldKind -> [Choice] -> Maybe ListId -> Maybe FieldType
fieldKindType TextField _ _ = Just TextType
fieldKindType BooleanField _ _ = Just BooleanType
fieldKindType ChoiceField choices _ = Just (ChoiceType choices)
fieldKindType WholeField _ _ = Just WholeType
fieldKindType DecimalField _ _ = Just DecimalType
fieldKindType MoneyField _ _ = Just MoneyType
fieldKindType PercentageField _ _ = Just PercentageType
fieldKindType DateField _ _ = Just DateType
fieldKindType ClockField _ _ = Just OperationalTimeType
fieldKindType ReferenceField _ source = ReferenceType <$> source

listKind :: ListMode -> ListKind
listKind VenueReference = VenueList
listKind OpenDaily = DailyList
listKind (ReferenceChecklist _) = Checklist

listKindLabel :: ListKind -> Text
listKindLabel VenueList = "Venue reference list"
listKindLabel DailyList = "Daily list — add rows as needed"
listKindLabel Checklist = "Daily checklist — one row per active reference"

listKindMode :: ListKind -> Maybe ListId -> Maybe ListMode
listKindMode VenueList _ = Just VenueReference
listKindMode DailyList _ = Just OpenDaily
listKindMode Checklist source = ReferenceChecklist <$> source
