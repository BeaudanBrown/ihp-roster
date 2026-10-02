-- | Server authority for a single immutable saved Daysheet projection. The
-- caller supplies only the pinned definition and preserved, venue-scoped data.
module Application.Daysheet.Evaluation
    ( SnapshotKey (..), RowId (..), RecordReference (..), Value (..)
    , Snapshot (..), Target (..), EvaluationError (..)
    , Evaluation, prepareEvaluation, evaluate, evaluateAdvisory, explainUnavailable
    ) where

import Prelude
import Application.Daysheet.Contract
import Application.Daysheet.Validation
import qualified Application.Daysheet.Number as Number
import qualified Application.Daysheet.Results as Results
import Control.Monad.State.Strict (State, evalState, get, put)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as Text
import Data.Time (TimeOfDay (..))
import Data.UUID (UUID)

-- IDs are supplied by authorized persistence, never inferred from a field UUID.
data SnapshotKey = SnapshotKey UUID UUID deriving (Eq, Ord, Show)
newtype RowId = RowId UUID deriving (Eq, Ord, Show)
data RecordReference = RecordReference SnapshotKey ListId RowId deriving (Eq, Show)
data Value = Scalar Literal | Reference RecordReference deriving (Eq, Show)
data Snapshot = Snapshot
    { snapshotKey :: SnapshotKey
    , savedRoot :: Map.Map FieldId Value
    , savedRows :: Map.Map ListId (Map.Map RowId (Map.Map FieldId Value))
    } deriving (Eq, Show)
data Target = RootTarget FieldId | RowTarget ListId RowId FieldId deriving (Eq, Ord, Show)
data EvaluationError
    = InvalidDefinition ContractError
    | UnknownInput FieldId
    | UnknownInputList ListId
    | CalculatedInput FieldId
    | InvalidInput FieldId
    | ForeignReference FieldId
    | SnapshotLimit
    | InvalidTarget
    deriving (Eq, Show)

data Evaluation = Evaluation Definition Snapshot

type Scope = Maybe (ListId, RowId)
type Eval = State Int

-- | Safe presentation derives labels from the pinned definition, never raw
-- supplied values or record IDs. Renderers still escape this plain text.
explainUnavailable :: Evaluation -> UnavailableReason -> Text
explainUnavailable (Evaluation definition _) reason = case reason of
    MissingInput key -> "Enter " <> label key <> "."
    MissingReference key -> "Choose an available record for " <> label key <> "."
    ZeroDenominator -> "Cannot divide by zero."
    NumericLimit -> "The calculation exceeds the supported numeric range."
    EvaluationLimit -> "The calculation exceeds the supported work limit."
    UnavailableCondition -> "The condition could not be evaluated."
  where
    label key = maybe "the missing value" fieldLabel (findField (rootFields definition <> concatMap listFields (recordLists definition)) key)

prepareEvaluation :: Definition -> Snapshot -> Either EvaluationError Evaluation
prepareEvaluation definition snapshot = do
    either (Left . InvalidDefinition) Right (validateDefinition definition)
    let lists = Map.toList (savedRows snapshot)
    if any ((> maxRowsPerList limits) . Map.size . snd) lists
        || Map.size (savedRoot snapshot) + sum [sum (map Map.size (Map.elems rows)) | (_, rows) <- lists] > maxEvaluationSteps limits
        then Left SnapshotLimit else Right ()
    checkInputs (rootFields definition) (savedRoot snapshot)
    mapM_ checkList lists
    pure (Evaluation definition snapshot)
  where
    checkList (key, rows) = case findList definition key of
        Nothing -> Left (UnknownInputList key)
        Just list -> mapM_ (checkInputs (listFields list)) (Map.elems rows)
    checkInputs fields values = mapM_ (checkInput fields) (Map.toList values)
    checkInput fields (key, value) = case findField fields key of
        Nothing -> Left (UnknownInput key)
        Just field -> case fieldSource field of
            Calculated _ -> Left (CalculatedInput key)
            Entered -> case value of
                Reference (RecordReference owner _ _) | owner /= snapshotKey snapshot -> Left (ForeignReference key)
                Reference (RecordReference _ list _) | fieldType field /= ReferenceType list -> Left (InvalidInput key)
                _ -> if matches (fieldType field) value then Right () else Left (InvalidInput key)

matches :: FieldType -> Value -> Bool
matches (ReferenceType expected) (Reference (RecordReference _ actual _)) = expected == actual
matches expected (Scalar literal) = case (expected, literal) of
    (TextType, TextLiteral value) -> Text.length value <= maxTextLength limits
    (BooleanType, BooleanLiteral _) -> True
    (ChoiceType choices, ChoiceLiteral key) -> key `elem` map choiceId choices
    (WholeType, WholeLiteral value) -> case Number.number value 1 of Right _ -> True; Left _ -> False
    (DecimalType, DecimalLiteral _) -> True
    (MoneyType, MoneyLiteral value) -> case Number.enteredMoney value of Right _ -> True; Left _ -> False
    (PercentageType, PercentageLiteral _) -> True
    (DateType, DateLiteral _) -> True
    (OperationalTimeType, OperationalTimeLiteral value) -> todHour value >= 0 && todHour value < 24 && todMin value >= 0 && todMin value < 60 && todSec value >= 0 && todSec value < 60
    _ -> False
matches _ _ = False

-- | A batch shares one budget; callers should evaluate one render/report batch
-- rather than resetting the budget independently for every displayed cell.
evaluate :: Evaluation -> [Target] -> Either EvaluationError [Result Value]
evaluate evaluation@(Evaluation definition snapshot) targets = do
    if length (take (maxEvaluationSteps limits + 1) targets) > maxEvaluationSteps limits then Left SnapshotLimit else Right ()
    mapM_ validTarget targets
    pure (evalState (mapM (evalTarget evaluation) targets) (maxEvaluationSteps limits))
  where
    validTarget target = case target of
        RootTarget key -> maybe (Left InvalidTarget) (const (Right ())) (findField (rootFields definition) key)
        RowTarget list row key -> case (findList definition list, Map.lookup list (savedRows snapshot) >>= Map.lookup row) of
            (Just source, Just _) -> maybe (Left InvalidTarget) (const (Right ())) (findField (listFields source) key)
            _ -> Left InvalidTarget

evaluateAdvisory :: Evaluation -> Scope -> Advisory -> Either EvaluationError AdvisoryResult
evaluateAdvisory evaluation@(Evaluation definition snapshot) scope advisory = do
    case scope of
        Nothing -> Right ()
        Just (list, row) -> case Map.lookup list (savedRows snapshot) >>= Map.lookup row of
            Just _ -> Right ()
            Nothing -> Left InvalidTarget
    actual <- either (Left . InvalidDefinition) Right (expressionType definition (fmap fst scope) (advisoryCondition advisory))
    if actual /= BooleanType then Left (InvalidDefinition IncompatibleTypes) else Right ()
    let result = evalState (evalExpression evaluation scope Nothing (advisoryCondition advisory)) (maxEvaluationSteps limits)
    pure (advisoryResult advisory (asBool result))

spend :: Eval (Result a) -> Eval (Result a)
spend action = do
    remaining <- get
    if remaining <= 0 then pure (Unavailable EvaluationLimit) else put (remaining - 1) >> action

findList :: Definition -> ListId -> Maybe RecordList
findList definition key = case filter ((== key) . listId) (recordLists definition) of
    [list] -> Just list
    _ -> Nothing

findField :: [Field] -> FieldId -> Maybe Field
findField fields key = case filter ((== key) . fieldId) fields of
    [field] -> Just field
    _ -> Nothing

evalTarget :: Evaluation -> Target -> Eval (Result Value)
evalTarget evaluation target = case target of
    RootTarget key -> evalField evaluation Nothing key
    RowTarget list row key -> evalField evaluation (Just (list, row)) key

evalField :: Evaluation -> Scope -> FieldId -> Eval (Result Value)
evalField evaluation@(Evaluation definition snapshot) scope key = spend do
    let fields = maybe (rootFields definition) (maybe [] listFields . findList definition . fst) scope
    let inputs = case scope of
            Nothing -> savedRoot snapshot
            Just (list, row) -> maybe Map.empty id (Map.lookup list (savedRows snapshot) >>= Map.lookup row)
    case findField fields key of
        Nothing -> pure (Unavailable (MissingInput key))
        Just field -> case fieldSource field of
            Entered -> pure case Map.lookup key inputs of
                Nothing -> Unavailable (MissingInput key)
                Just value@(Reference (RecordReference _ list row)) ->
                    if maybe False (Map.member row) (Map.lookup list (savedRows snapshot))
                        then Known value else Unavailable (MissingReference key)
                Just value -> Known value
            Calculated expression -> evalExpression evaluation scope Nothing expression

evalExpression :: Evaluation -> Scope -> Scope -> Expression -> Eval (Result Value)
evalExpression evaluation@(Evaluation definition snapshot) current item expression = spend case expression of
    Constant literal -> pure (Known (Scalar literal))
    ReadField (FieldPath context fields) -> follow (case context of Root -> Nothing; Current -> current; Item -> item) fields
    Binary operation left right -> do
        a <- evalExpression evaluation current item left
        b <- evalExpression evaluation current item right
        pure (applyBinary operation a b)
    Unary operation child -> applyUnary operation <$> evalExpression evaluation current item child
    If condition yes no -> do
        result <- asBool <$> evalExpression evaluation current item condition
        case result of
            Known True -> evalExpression evaluation current item yes
            Known False -> evalExpression evaluation current item no
            Unavailable reason -> pure (Unavailable reason)
    Fold operation key predicate value -> do
        let rows = Map.keys (Map.findWithDefault Map.empty key (savedRows snapshot))
        let resultType = expressionType definition (fmap fst current) expression
        case resultType of
            Left _ -> pure (Unavailable NumericLimit)
            Right t -> foldRows operation key predicate value t rows
  where
    follow _ [] = pure (Unavailable UnavailableCondition)
    follow scope (key : rest) = do
        result <- evalField evaluation scope key
        case rest of
            [] -> pure result
            _ -> case result of
                Unavailable reason -> pure (Unavailable reason)
                Known (Reference (RecordReference owner list row)) ->
                    if owner == snapshotKey snapshot && maybe False (Map.member row) (Map.lookup list (savedRows snapshot))
                        then follow (Just (list, row)) rest
                        else pure (Unavailable (MissingReference key))
                _ -> pure (Unavailable (MissingReference key))
    foldRows operation key predicate value resultType = loop (numberValue resultType (Number.number 0 1))
      where
        loop total [] = pure total
        loop total (row : rest) = spend do
            selected <- case predicate of
                Nothing -> pure (Known True)
                Just condition -> asBool <$> evalExpression evaluation current (Just (key, row)) condition
            case selected of
                Unavailable reason -> pure (Unavailable reason)
                Known False -> loop total rest
                Known True -> do
                    contribution <- case operation of
                        Count -> pure (Known (Scalar (WholeLiteral 1)))
                        Sum -> evalExpression evaluation current (Just (key, row)) value
                    case applyBinary Add total contribution of
                        Unavailable reason -> pure (Unavailable reason)
                        next -> loop next rest

asBool :: Result Value -> Result Bool
asBool (Known (Scalar (BooleanLiteral value))) = Known value
asBool (Unavailable reason) = Unavailable reason
asBool _ = Unavailable UnavailableCondition

numericValue :: Value -> Maybe (FieldType, Number.Number)
numericValue (Scalar literal) = case literal of
    WholeLiteral value -> either (const Nothing) (Just . (WholeType,)) (Number.number value 1)
    DecimalLiteral value -> Just (DecimalType, value)
    MoneyLiteral value -> Just (MoneyType, value)
    PercentageLiteral value -> Just (PercentageType, value)
    _ -> Nothing
numericValue _ = Nothing

numberValue :: FieldType -> Either Number.NumberError Number.Number -> Result Value
numberValue _ (Left Number.InvalidDenominator) = Unavailable ZeroDenominator
numberValue _ (Left _) = Unavailable NumericLimit
numberValue t (Right value) = case t of
    WholeType -> let (n, d) = Number.fraction value in
        if d == 1 then Known (Scalar (WholeLiteral n)) else Unavailable NumericLimit
    DecimalType -> Known (Scalar (DecimalLiteral value))
    MoneyType -> Known (Scalar (MoneyLiteral value))
    PercentageType -> Known (Scalar (PercentageLiteral value))
    _ -> Unavailable NumericLimit

applyUnary :: Unary -> Result Value -> Result Value
applyUnary _ (Unavailable reason) = Unavailable reason
applyUnary Not value = case asBool value of
    Known boolean -> Known (Scalar (BooleanLiteral (not boolean)))
    Unavailable reason -> Unavailable reason
applyUnary operation (Known value) = case numericValue value of
    Nothing -> Unavailable NumericLimit
    Just (t, number) -> case unaryType operation t of
        Left _ -> Unavailable NumericLimit
        Right resultType -> numberValue resultType case operation of
            Negate -> do zero <- Number.number 0 1; Number.subtractNumber zero number
            Absolute -> if fst (Number.fraction number) < 0 then do zero <- Number.number 0 1; Number.subtractNumber zero number else Right number
            RoundCents -> Number.roundCents number
            PercentageRatio -> Right number

applyBinary :: Binary -> Result Value -> Result Value -> Result Value
applyBinary _ (Unavailable reason) _ = Unavailable reason
applyBinary _ _ (Unavailable reason) = Unavailable reason
applyBinary operation (Known a) (Known b) = case operation of
    Equal -> boolean (a == b)
    NotEqual -> boolean (a /= b)
    And -> boolPair (&&)
    Or -> boolPair (||)
    Less -> comparison (== LT)
    LessOrEqual -> comparison (/= GT)
    Greater -> comparison (== GT)
    GreaterOrEqual -> comparison (/= LT)
    _ -> case (numericValue a, numericValue b) of
        (Just (ta, na), Just (tb, nb)) -> case binaryType operation ta tb of
            Left _ -> Unavailable NumericLimit
            Right resultType -> numberValue resultType case operation of
                Add -> Number.add na nb
                Subtract -> Number.subtractNumber na nb
                Multiply -> Number.multiply na nb
                Divide -> Number.divide na nb
        _ -> Unavailable NumericLimit
  where
    boolean = Known . Scalar . BooleanLiteral
    boolPair op = case Results.combine op (asBool (Known a)) (asBool (Known b)) of
        Known result -> boolean result
        Unavailable reason -> Unavailable reason
    comparison predicate = case (a, b) of
        (Scalar (DateLiteral left), Scalar (DateLiteral right)) -> boolean (predicate (compare left right))
        (Scalar (OperationalTimeLiteral left), Scalar (OperationalTimeLiteral right)) -> boolean (predicate (compare (operationalSeconds left) (operationalSeconds right)))
        _ -> case (numericValue a, numericValue b) of
            (Just (_, left), Just (_, right)) -> boolean (predicate (compare left right))
            _ -> Unavailable NumericLimit

-- Only ordering within this Operational day; instant/DST resolution remains
-- the venue-time boundary's responsibility.
operationalSeconds :: TimeOfDay -> Rational
operationalSeconds time = fromIntegral ((todHour time + if todHour time < 6 then 24 else 0) * 3600 + todMin time * 60) + toRational (todSec time)
