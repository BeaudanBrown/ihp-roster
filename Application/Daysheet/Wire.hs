{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}

-- | Exact declaration-indexed formula decoding. JSON field/case names belong
-- to Schema, not this parser. No browser or persisted formula is trusted merely
-- because it passed structural decoding.
module Application.Daysheet.Wire
    ( decodeFormula, FormulaWireError (..)
    , expressionJson, parseExpressionJson, literalJson, parseLiteralJson
    ) where

import Prelude
import Application.Daysheet.Contract
import Application.Daysheet.Formula
import qualified Application.Daysheet.Number as Number
import qualified Application.Daysheet.Schema as S
import Application.Helper.FrontendContract.Wire.Carrier
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Types as Aeson
import qualified Data.ByteString as ByteString
import Data.Text (Text)
import qualified Data.Text as Text
import Data.Time (TimeOfDay, defaultTimeLocale, parseTimeM)
import Text.Read (readMaybe)

-- Structural errors deliberately expose no parser input or sensitive content.
data FormulaWireError = FormulaPayloadTooLarge | InvalidFormulaPayload | InvalidFormula FormulaError
    deriving (Eq, Show)

decodeFormula :: Definition -> Maybe ListId -> ByteString.ByteString -> Either FormulaWireError Expression
decodeFormula definition scope bytes
    | ByteString.length bytes > maxDefinitionBytes limits = Left FormulaPayloadTooLarge
    | otherwise = do
        value <- either (const (Left InvalidFormulaPayload)) Right (Aeson.eitherDecodeStrict' bytes)
        formula <- either (const (Left InvalidFormulaPayload)) Right (Aeson.parseEither parseFormula value)
        either (Left . InvalidFormula) Right (compileFormula definition scope formula)

expressionJson :: Expression -> Aeson.Value
expressionJson expression =
    let Formula (NodeId root) nodes = flattenExpression expression
     in recordValueIn @S.FormulaContracts @S.DaysheetFormula
            (requiredField @S.RootNode root &: requiredField @S.Nodes nodes &: noFields)

parseExpressionJson :: Aeson.Value -> Aeson.Parser Expression
parseExpressionJson value = do
    formula <- parseFormula value
    either (const (fail "invalid formula graph")) pure (expandFormula formula)

literalJson :: Literal -> Aeson.Value
literalJson = contractReferenceJson @S.DaysheetLiteral

parseLiteralJson :: Aeson.Value -> Aeson.Parser Literal
parseLiteralJson = parseContractReference @S.DaysheetLiteral

parseFormula :: Aeson.Value -> Aeson.Parser Formula
parseFormula = parseRecordIn @S.FormulaContracts @S.DaysheetFormula \(root, (nodes, ())) -> do
    if length (take (maxExpressionNodes limits + 1) nodes) > maxExpressionNodes limits
        then fail "too many formula nodes"
        else pure (Formula (NodeId root) nodes)

instance ContractReference S.DaysheetNode where
    type ContractReferenceValue S.DaysheetNode = (NodeId, Step)
    contractReferenceJson (NodeId key, step) = recordValueIn @S.FormulaContracts @S.DaysheetNode
        (requiredField @S.NodeId key &: requiredField @S.Step step &: noFields)
    parseContractReference = parseRecordIn @S.FormulaContracts @S.DaysheetNode
        (\(key, (step, ())) -> pure (NodeId key, step))

instance ContractReference S.DaysheetStep where
    type ContractReferenceValue S.DaysheetStep = Step
    contractReferenceJson step = case step of
        LiteralStep value -> taggedUnionValueIn @S.FormulaContracts @S.DaysheetStep @S.LiteralStep
            (requiredField @S.LiteralValue value &: noFields)
        FieldStep path -> taggedUnionValueIn @S.FormulaContracts @S.DaysheetStep @S.FieldStep
            (requiredField @S.Path path &: noFields)
        BinaryStep operation (NodeId left) (NodeId right) -> taggedUnionValueIn @S.FormulaContracts @S.DaysheetStep @S.BinaryStep
            (requiredField @S.Operator operation &: requiredField @S.LeftNode left &: requiredField @S.RightNode right &: noFields)
        UnaryStep operation (NodeId child) -> taggedUnionValueIn @S.FormulaContracts @S.DaysheetStep @S.UnaryStep
            (requiredField @S.Operator operation &: requiredField @S.ChildNode child &: noFields)
        ConditionalStep (NodeId condition) (NodeId yes) (NodeId no) -> taggedUnionValueIn @S.FormulaContracts @S.DaysheetStep @S.ConditionalStep
            (requiredField @S.ConditionNode condition &: requiredField @S.YesNode yes &: requiredField @S.NoNode no &: noFields)
        AggregateStep operation (ListId list) predicate (NodeId child) -> taggedUnionValueIn @S.FormulaContracts @S.DaysheetStep @S.AggregateStep
            (requiredField @S.Operator operation &: requiredField @S.ListId list &: optionalField @S.PredicateNode (fmap (\(NodeId key) -> key) predicate) &: requiredField @S.ChildNode child &: noFields)
    parseContractReference = parseTaggedUnionIn @S.FormulaContracts @S.DaysheetStep
        (unionCase @S.LiteralStep (\(value, ()) -> pure (LiteralStep value))
        |: unionCase @S.FieldStep (\(path, ()) -> pure (FieldStep path))
        |: unionCase @S.BinaryStep (\(operation, (left, (right, ()))) -> pure (BinaryStep operation (NodeId left) (NodeId right)))
        |: unionCase @S.UnaryStep (\(operation, (child, ())) -> pure (UnaryStep operation (NodeId child)))
        |: unionCase @S.ConditionalStep (\(condition, (yes, (no, ()))) -> pure (ConditionalStep (NodeId condition) (NodeId yes) (NodeId no)))
        |: unionCase @S.AggregateStep (\(operation, (list, (predicate, (child, ())))) -> pure (AggregateStep operation (ListId list) (fmap NodeId predicate) (NodeId child)))
        |: noUnionCases)

instance ContractReference S.DaysheetPath where
    type ContractReferenceValue S.DaysheetPath = FieldPath
    contractReferenceJson (FieldPath context fields) = recordValueIn @S.FormulaContracts @S.DaysheetPath
        (requiredField @S.ContextValue context &: requiredField @S.Fields (map (\(FieldId key) -> key) fields) &: noFields)
    parseContractReference = parseRecordIn @S.FormulaContracts @S.DaysheetPath \(context, (fields, ())) ->
        if null fields || length (take (maxReferenceDepth limits + 1) fields) > maxReferenceDepth limits
            then fail "invalid field path"
            else pure (FieldPath context (map FieldId fields))

instance ContractReference S.DaysheetLiteral where
    type ContractReferenceValue S.DaysheetLiteral = Literal
    contractReferenceJson literal = case literal of
        TextLiteral value -> taggedUnionValueIn @S.FormulaContracts @S.DaysheetLiteral @S.TextValue (requiredField @S.Value value &: noFields)
        BooleanLiteral value -> taggedUnionValueIn @S.FormulaContracts @S.DaysheetLiteral @S.BooleanValue (requiredField @S.Value value &: noFields)
        ChoiceLiteral (ChoiceId value) -> taggedUnionValueIn @S.FormulaContracts @S.DaysheetLiteral @S.ChoiceValue (requiredField @S.Value value &: noFields)
        WholeLiteral value -> taggedUnionValueIn @S.FormulaContracts @S.DaysheetLiteral @S.WholeValue (requiredField @S.Value (Text.pack (show value)) &: noFields)
        DecimalLiteral value -> let (n, d) = Number.fraction value in taggedUnionValueIn @S.FormulaContracts @S.DaysheetLiteral @S.DecimalValue
            (requiredField @S.Numerator (Text.pack (show n)) &: requiredField @S.Denominator (Text.pack (show d)) &: noFields)
        MoneyLiteral value -> let (n, d) = Number.fraction value in taggedUnionValueIn @S.FormulaContracts @S.DaysheetLiteral @S.MoneyValue
            (requiredField @S.Numerator (Text.pack (show n)) &: requiredField @S.Denominator (Text.pack (show d)) &: noFields)
        PercentageLiteral value -> let (n, d) = Number.fraction value in taggedUnionValueIn @S.FormulaContracts @S.DaysheetLiteral @S.PercentageValue
            (requiredField @S.Numerator (Text.pack (show n)) &: requiredField @S.Denominator (Text.pack (show d)) &: noFields)
        DateLiteral value -> taggedUnionValueIn @S.FormulaContracts @S.DaysheetLiteral @S.DateValue (requiredField @S.Value value &: noFields)
        OperationalTimeLiteral value -> taggedUnionValueIn @S.FormulaContracts @S.DaysheetLiteral @S.OperationalTimeValue (requiredField @S.Value (Text.pack (show value)) &: noFields)
    parseContractReference = parseTaggedUnionIn @S.FormulaContracts @S.DaysheetLiteral
        (unionCase @S.TextValue (\(value, ()) -> if Text.length value > maxTextLength limits then fail "text limit" else pure (TextLiteral value))
        |: unionCase @S.BooleanValue (\(value, ()) -> pure (BooleanLiteral value))
        |: unionCase @S.ChoiceValue (\(value, ()) -> pure (ChoiceLiteral (ChoiceId value)))
        |: unionCase @S.WholeValue (\(value, ()) -> WholeLiteral <$> integer value)
        |: unionCase @S.DecimalValue (\(n, (d, ())) -> DecimalLiteral <$> rational n d)
        |: unionCase @S.MoneyValue (\(n, (d, ())) -> do
            value <- rational n d
            either (const (fail "money requires cents")) (pure . MoneyLiteral) (Number.enteredMoney value))
        |: unionCase @S.PercentageValue (\(n, (d, ())) -> PercentageLiteral <$> rational n d)
        |: unionCase @S.DateValue (\(value, ()) -> pure (DateLiteral value))
        |: unionCase @S.OperationalTimeValue (\(value, ()) -> OperationalTimeLiteral <$> time value)
        |: noUnionCases)

integer :: Text -> Aeson.Parser Integer
integer value
    | Text.length value > 40 = fail "integer limit"
    | otherwise = case readMaybe (Text.unpack value) of
        Just parsed | Text.pack (show parsed) == value ->
            either (const (fail "integer limit")) (const (pure parsed)) (Number.number parsed 1)
        _ -> fail "invalid integer"

rational :: Text -> Text -> Aeson.Parser Number.Number
rational n d = do
    numerator <- integer n
    denominator <- integer d
    if denominator <= 0 then fail "invalid denominator" else
        either (const (fail "number limit")) pure (Number.number numerator denominator)

time :: Text -> Aeson.Parser TimeOfDay
time value
    | Text.length value /= 8 = fail "invalid time"
    | otherwise = maybe (fail "invalid time") pure (parseTimeM True defaultTimeLocale "%H:%M:%S" (Text.unpack value))
