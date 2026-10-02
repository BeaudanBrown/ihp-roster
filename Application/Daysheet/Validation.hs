module Application.Daysheet.Validation
    ( ContractError (..)
    , binaryType
    , unaryType
    , expressionType
    , validateFields
    ) where

import Prelude
import Application.Daysheet.Contract
import qualified Application.Daysheet.Number as Number
import Data.Graph (SCC (..), stronglyConnComp)
import Data.List (nub)
import qualified Data.Text as Text

-- | Errors here reject publication, unlike ordinary unavailable saved inputs.
data ContractError
    = UnsupportedVersion
    | DuplicateField FieldId
    | DuplicateList ListId
    | InvalidFieldType
    | UnknownField FieldId
    | UnknownList ListId
    | InvalidContext
    | InvalidReferencePath
    | IncompatibleTypes
    | CyclicFields [FieldId]
    | ResourceLimit
    | InvalidLiteral
    | InvalidChecklist
    | InvalidReferenceScope
    deriving (Eq, Show)

numeric :: FieldType -> Bool
numeric t = t `elem` [WholeType, DecimalType, MoneyType, PercentageType]

scalar :: FieldType -> Bool
scalar t = t `elem` [WholeType, DecimalType]

ordered :: FieldType -> Bool
ordered t = numeric t || t `elem` [DateType, OperationalTimeType]

binaryType :: Binary -> FieldType -> FieldType -> Either ContractError FieldType
binaryType operation a b = case operation of
    Add | a == b && numeric a -> Right a
    Subtract | a == b && numeric a -> Right a
    Multiply
        | scalar a && scalar b -> Right (if a == WholeType && b == WholeType then WholeType else DecimalType)
        | numeric a && scalar b -> Right a
        | scalar a && numeric b -> Right b
        | a == MoneyType && b == PercentageType -> Right MoneyType
        | a == PercentageType && b == MoneyType -> Right MoneyType
    Divide
        | a == b && numeric a -> Right DecimalType
        | numeric a && scalar b -> Right (if a == WholeType then DecimalType else a)
    Equal | a == b -> Right BooleanType
    NotEqual | a == b -> Right BooleanType
    Less | a == b && ordered a -> Right BooleanType
    LessOrEqual | a == b && ordered a -> Right BooleanType
    Greater | a == b && ordered a -> Right BooleanType
    GreaterOrEqual | a == b && ordered a -> Right BooleanType
    And | a == BooleanType && b == BooleanType -> Right BooleanType
    Or | a == BooleanType && b == BooleanType -> Right BooleanType
    _ -> Left IncompatibleTypes

unaryType :: Unary -> FieldType -> Either ContractError FieldType
unaryType operation input = case operation of
    Negate | numeric input -> Right input
    Absolute | numeric input -> Right input
    Not | input == BooleanType -> Right BooleanType
    RoundCents | input == MoneyType -> Right MoneyType
    PercentageRatio | input == PercentageType -> Right DecimalType
    _ -> Left IncompatibleTypes

findList :: Definition -> ListId -> Either ContractError RecordList
findList definition key = case filter ((== key) . listId) (recordLists definition) of
    [value] -> Right value
    _ -> Left (UnknownList key)

findField :: [Field] -> FieldId -> Either ContractError Field
findField fields key = case filter ((== key) . fieldId) fields of
    [value] -> Right value
    _ -> Left (UnknownField key)

literalType :: Literal -> Either ContractError FieldType
literalType literal = case literal of
    TextLiteral value | Text.length value <= maxTextLength limits -> Right TextType
    BooleanLiteral _ -> Right BooleanType
    -- Choice constants acquire their configured domain from a matching field.
    ChoiceLiteral _ -> Left InvalidLiteral
    WholeLiteral value -> either (const (Left InvalidLiteral)) (const (Right WholeType)) (Number.number value 1)
    DecimalLiteral _ -> Right DecimalType
    MoneyLiteral value -> either (const (Left InvalidLiteral)) (const (Right MoneyType)) (Number.enteredMoney value)
    PercentageLiteral _ -> Right PercentageType
    DateLiteral _ -> Right DateType
    OperationalTimeLiteral _ -> Right OperationalTimeType
    _ -> Left InvalidLiteral

-- | Enclosing row and aggregate item are lexical scopes, not caller-provided
-- record IDs. A fold cannot contain another fold in v1.
expressionType :: Definition -> Maybe ListId -> Expression -> Either ContractError FieldType
expressionType definition current expression = do
    _ <- checkBudget 1 expression
    case current of
        Nothing -> Right ()
        Just key -> do
            owner <- findList definition key
            if listMode owner == VenueReference then referenceOnly expression else Right ()
    infer Nothing expression
  where
    -- Reusable venue records cannot depend on a particular daily form.
    referenceOnly expr = do
        case expr of
            ReadField (FieldPath Root _) -> Left InvalidReferenceScope
            Fold _ key _ _ -> do
                source <- findList definition key
                if listMode source == VenueReference then Right () else Left InvalidReferenceScope
            _ -> Right ()
        mapM_ referenceOnly (children expr)
    checkBudget depth expr
        | depth > maxExpressionDepth limits = Left ResourceLimit
        | otherwise = do
            counts <- traverse (checkBudget (depth + 1)) (children expr)
            let count = 1 + sum counts
            if count > maxExpressionNodes limits then Left ResourceLimit else Right count
    infer item expr = case expr of
        Constant (ChoiceLiteral key) -> case nub [choices | f <- allFields definition, ChoiceType choices <- [fieldType f], key `elem` choices] of
            [choices] -> Right (ChoiceType choices)
            _ -> Left InvalidLiteral
        Constant literal -> literalType literal
        ReadField (FieldPath context path) -> do
            fields <- case context of
                Root -> Right (rootFields definition)
                Current -> maybe (Left InvalidContext) (fmap listFields . findList definition) current
                Item -> maybe (Left InvalidContext) (fmap listFields . findList definition) item
            if length path > maxReferenceDepth limits then Left ResourceLimit else resolve fields path
        Binary operation a b -> do
            aType <- infer item a
            bType <- infer item b
            binaryType operation aType bType
        Unary operation a -> infer item a >>= unaryType operation
        If condition yes no -> do
            conditionType <- infer item condition
            yesType <- infer item yes
            noType <- infer item no
            if conditionType == BooleanType && yesType == noType then Right yesType else Left IncompatibleTypes
        Fold operation key predicate value -> do
            case item of
                Just _ -> Left InvalidContext
                Nothing -> Right ()
            _ <- findList definition key
            case predicate of
                Nothing -> Right ()
                Just condition -> do
                    t <- infer (Just key) condition
                    if t == BooleanType then Right () else Left IncompatibleTypes
            t <- infer (Just key) value
            case operation of
                Sum | numeric t -> Right t
                Count -> Right WholeType
                _ -> Left IncompatibleTypes
    resolve _ [] = Left InvalidReferencePath
    resolve fields (key : rest) = do
        field <- findField fields key
        case rest of
            [] -> Right (fieldType field)
            _ -> case fieldType field of
                ReferenceType target -> findList definition target >>= \list -> resolve (listFields list) rest
                _ -> Left InvalidReferencePath

children :: Expression -> [Expression]
children expression = case expression of
    Constant _ -> []
    ReadField _ -> []
    Binary _ a b -> [a, b]
    Unary _ a -> [a]
    If a b c -> [a, b, c]
    Fold _ _ predicate value -> maybe [] pure predicate <> [value]

allFields :: Definition -> [Field]
allFields definition = rootFields definition <> concatMap listFields (recordLists definition)

-- | Field-level validation across the whole definition, not just the changed
-- field, so deleting dependencies cannot leave dangling rules. This is NOT a
-- publication/request boundary: layout, wire-byte and total payload validation
-- must also succeed before an untrusted definition may be published.
validateFields :: Definition -> Either ContractError ()
validateFields definition = do
    if contractVersion definition == 1 then Right () else Left UnsupportedVersion
    let fields = allFields definition
    if length fields > maxFields limits || length (recordLists definition) > maxLists limits then Left ResourceLimit else Right ()
    unique DuplicateField (map fieldId fields)
    unique DuplicateList (map listId (recordLists definition))
    mapM_ (validateField Nothing) (rootFields definition)
    mapM_ validateList (recordLists definition)
    mapM_ rejectCycle (stronglyConnComp [(field, fieldId field, dependencies field) | field <- fields])
  where
    unique failure keys = case [key | key <- nub keys, length (filter (== key) keys) > 1] of
        key : _ -> Left (failure key)
        [] -> Right ()
    validateList list = do
        case listMode list of
            ReferenceChecklist target -> do
                reference <- findList definition target
                if listMode reference == VenueReference then Right () else Left InvalidChecklist
            _ -> Right ()
        mapM_ (validateField (Just (listId list))) (listFields list)
    validateField scope field = do
        case fieldType field of
            ChoiceType choices | null choices || length choices > 256 || length choices /= length (nub choices) -> Left InvalidFieldType
            ReferenceType target -> do
                referenced <- findList definition target
                case scope of
                    Nothing -> Right ()
                    Just owner -> do
                        source <- findList definition owner
                        if listMode source == VenueReference && listMode referenced /= VenueReference then Left InvalidReferenceScope else Right ()
            _ -> Right ()
        case fieldSource field of
            Entered -> Right ()
            Calculated expression -> do
                actual <- expressionType definition scope expression
                if actual == fieldType field then Right () else Left IncompatibleTypes
    dependencies field = case fieldSource field of
        Entered -> []
        Calculated expression -> reads expression
    reads expression = case expression of
        ReadField (FieldPath _ keys) -> keys
        _ -> concatMap reads (children expression)
    rejectCycle (AcyclicSCC _) = Right ()
    rejectCycle (CyclicSCC fields) = Left (CyclicFields (map fieldId fields))
