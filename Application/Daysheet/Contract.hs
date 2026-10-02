-- | Version-one definition vocabulary. IDs have meaning only inside the pinned
-- definition; no expression contains a venue, day, query, script or function name.
module Application.Daysheet.Contract where

import Prelude
import Application.Daysheet.Number (Number)
import Data.Text (Text)
import Data.Time (Day, TimeOfDay)
import Data.UUID (UUID)
import IHP.ModelSupport (InputValue (..))

newtype FieldId = FieldId UUID deriving (Eq, Ord, Show)
newtype ListId = ListId UUID deriving (Eq, Ord, Show)
newtype ChoiceId = ChoiceId UUID deriving (Eq, Ord, Show)
newtype SectionId = SectionId UUID deriving (Eq, Ord, Show)
newtype ReportId = ReportId UUID deriving (Eq, Ord, Show)

-- | A definition key is not a database record identity.
data FieldType
    = TextType | BooleanType | ChoiceType [ChoiceId] | WholeType | DecimalType
    | MoneyType | PercentageType | DateType | OperationalTimeType
    | ReferenceType ListId
    deriving (Eq, Show)

data Literal
    = TextLiteral Text | BooleanLiteral Bool | ChoiceLiteral ChoiceId
    | WholeLiteral Integer | DecimalLiteral Number | MoneyLiteral Number
    | PercentageLiteral Number | DateLiteral Day | OperationalTimeLiteral TimeOfDay
    deriving (Eq, Show)

-- | Root fields and row fields have disjoint evaluation contexts. During a
-- fold, Current remains the enclosing row; Item denotes the selected list row.
data Context = Root | Current | Item deriving (Eq, Show, Enum, Bounded)
data FieldPath = FieldPath Context [FieldId] deriving (Eq, Show)

data Binary
    = Add | Subtract | Multiply | Divide
    | Equal | NotEqual | Less | LessOrEqual | Greater | GreaterOrEqual
    | And | Or
    deriving (Eq, Show, Enum, Bounded)
data Unary = Negate | Absolute | Not | RoundCents | PercentageRatio deriving (Eq, Show, Enum, Bounded)
data Aggregate = Sum | Count deriving (Eq, Show, Enum, Bounded)

instance InputValue Context where
    inputValue Root = "root"
    inputValue Current = "current"
    inputValue Item = "item"

instance InputValue Binary where
    inputValue Add = "add"
    inputValue Subtract = "subtract"
    inputValue Multiply = "multiply"
    inputValue Divide = "divide"
    inputValue Equal = "equal"
    inputValue NotEqual = "not-equal"
    inputValue Less = "less"
    inputValue LessOrEqual = "less-or-equal"
    inputValue Greater = "greater"
    inputValue GreaterOrEqual = "greater-or-equal"
    inputValue And = "and"
    inputValue Or = "or"

instance InputValue Unary where
    inputValue Negate = "negate"
    inputValue Absolute = "absolute"
    inputValue Not = "not"
    inputValue RoundCents = "round-cents"
    inputValue PercentageRatio = "percentage-ratio"

instance InputValue Aggregate where
    inputValue Sum = "sum"
    inputValue Count = "count"

data Expression
    = Constant Literal
    | ReadField FieldPath
    | Binary Binary Expression Expression
    | Unary Unary Expression
    | If Expression Expression Expression
    | Fold Aggregate ListId (Maybe Expression) Expression
    deriving (Eq, Show)

-- | Percentages are ratios (1.6% is 0.016), never an implicit /100 cast.
-- Decimal literals allow sums such as (1 + rate) through explicit conversion.
data FieldSource = Entered | Calculated Expression deriving (Eq, Show)
data Field = Field
    { fieldId :: FieldId
    , fieldLabel :: Text
    , fieldType :: FieldType
    , fieldSource :: FieldSource
    } deriving (Eq, Show)
data ListMode = VenueReference | OpenDaily | ReferenceChecklist ListId deriving (Eq, Show)
data RecordList = RecordList
    { listId :: ListId
    , listLabel :: Text
    , listMode :: ListMode
    , listFields :: [Field]
    } deriving (Eq, Show)

data Advisory = Advisory
    { advisoryCondition :: Expression
    , passedMessage :: Text
    , concernMessage :: Text
    } deriving (Eq, Show)

data SortDirection = Ascending | Descending deriving (Eq, Show)
data Block
    = Instructions Text
    | FieldBlock FieldId
    | AdvisoryBlock Advisory
    | TableBlock ListId [FieldId] (Maybe FieldId) [(FieldId, SortDirection)]
    deriving (Eq, Show)
data Section = Section SectionId Text [Block] deriving (Eq, Show)
data Output = FormattedReport | ExcelDownload deriving (Eq, Show)
data Report = Report ReportId Text [Section] [Output] deriving (Eq, Show)
data Definition = Definition
    { contractVersion :: Int
    , rootFields :: [Field]
    , recordLists :: [RecordList]
    , entryLayout :: [Section]
    , reports :: [Report]
    } deriving (Eq, Show)

-- | Missing runtime data is not an invalid definition. Evaluation must preserve
-- reasons; no coercion to zero/false or advisory success is allowed.
data UnavailableReason
    = MissingInput FieldId
    | MissingReference FieldId
    | ZeroDenominator
    | NumericLimit
    | EvaluationLimit
    | UnavailableCondition
    deriving (Eq, Show)
data Result a = Known a | Unavailable UnavailableReason deriving (Eq, Show)
data AdvisoryResult = Passed Text | Concern Text | NotEvaluated UnavailableReason deriving (Eq, Show)

advisoryResult :: Advisory -> Result Bool -> AdvisoryResult
advisoryResult advisory (Known True) = Passed (passedMessage advisory)
advisoryResult advisory (Known False) = Concern (concernMessage advisory)
advisoryResult _ (Unavailable reason) = NotEvaluated reason

-- | Fixed v1 resource ceilings, checked before recursive validation/evaluation.
-- Wire decoders also need an input-byte/depth limit before allocating this AST.
data Limits = Limits
    { maxFields :: Int
    , maxLists :: Int
    , maxExpressionNodes :: Int
    , maxExpressionDepth :: Int
    , maxReferenceDepth :: Int
    , maxRowsPerList :: Int
    , maxEvaluationSteps :: Int
    , maxTextLength :: Int
    , maxDefinitionBytes :: Int
    } deriving (Eq, Show)

limits :: Limits
limits = Limits 512 64 4096 32 8 10000 1000000 10000 1048576
