-- | Bounded linked-node encoding of the Daysheet expression DSL. Node IDs are
-- local to one formula, not field IDs or arbitrary database references.
module Application.Daysheet.Formula
    ( NodeId (..)
    , Step (..)
    , Formula (..)
    , FormulaError (..)
    , compileFormula
    , expandFormula
    , flattenExpression
    ) where

import Prelude
import Application.Daysheet.Contract
import Application.Daysheet.Validation (ContractError, expressionType)
import Control.Monad.Trans.State.Strict (State, get, put, runState)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set

newtype NodeId = NodeId Int deriving (Eq, Ord, Show)

-- The only operation vocabulary is the same Binary/Unary/Aggregate DSL used
-- by field inference. Transport cannot introduce named functions or scripts.
data Step
    = LiteralStep Literal
    | FieldStep FieldPath
    | ChecklistReferenceStep Context
    | BinaryStep Binary NodeId NodeId
    | UnaryStep Unary NodeId
    | ConditionalStep NodeId NodeId NodeId
    | AggregateStep Aggregate ListId (Maybe NodeId) NodeId
    deriving (Eq, Show)

data Formula = Formula
    { formulaRoot :: NodeId
    , formulaSteps :: [(NodeId, Step)]
    } deriving (Eq, Show)

data FormulaError
    = TooManyNodes
    | InvalidNodeId NodeId
    | DuplicateNodeId NodeId
    | MissingNode NodeId
    | FormulaCycle NodeId
    | FormulaTooDeep
    | ExpandedFormulaTooLarge
    | UnreachableNodes
    | FormulaTypeError ContractError
    deriving (Eq, Show)

-- | Expand with an explicit work budget, not memoization alone: even an acyclic
-- shared-node graph can encode an exponentially large tree. Every occurrence
-- consumes fuel, including repeated references to the same node. Both branches
-- and filters are validated before the formula can reach runtime evaluation.
compileFormula :: Definition -> Maybe ListId -> Formula -> Either FormulaError Expression
compileFormula definition scope formula = do
    expression <- expandFormula formula
    either (Left . FormulaTypeError) (const (Right expression)) (expressionType definition scope expression)

-- | Structural graph decoding precedes whole-definition type validation when
-- fields refer to other fields in the same persisted definition document.
expandFormula :: Formula -> Either FormulaError Expression
expandFormula formula = do
    if length (take (maxExpressionNodes limits + 1) (formulaSteps formula)) > maxExpressionNodes limits
        then Left TooManyNodes else Right ()
    table <- buildTable Map.empty (formulaSteps formula)
    (expression, _, visited) <- expand table Set.empty 1 (maxExpressionNodes limits) (formulaRoot formula)
    if Set.size visited == Map.size table then Right () else Left UnreachableNodes
    pure expression
  where
    buildTable table [] = Right table
    buildTable table ((key@(NodeId value), step) : rest)
        | value < 0 || value >= maxExpressionNodes limits = Left (InvalidNodeId key)
        | Map.member key table = Left (DuplicateNodeId key)
        | otherwise = buildTable (Map.insert key step table) rest
    expand table ancestors depth fuel key
        | Set.member key ancestors = Left (FormulaCycle key)
        | depth > maxExpressionDepth limits = Left FormulaTooDeep
        | fuel <= 0 = Left ExpandedFormulaTooLarge
        | otherwise = do
            step <- maybe (Left (MissingNode key)) Right (Map.lookup key table)
            let visit = expand table (Set.insert key ancestors) (depth + 1)
            let finish expression remaining visited = Right (expression, remaining, Set.insert key visited)
            case step of
                LiteralStep value -> finish (Constant value) (fuel - 1) Set.empty
                FieldStep path -> finish (ReadField path) (fuel - 1) Set.empty
                ChecklistReferenceStep context -> finish (ChecklistReference context) (fuel - 1) Set.empty
                UnaryStep operation child -> do
                    (value, remaining, visited) <- visit (fuel - 1) child
                    finish (Unary operation value) remaining visited
                BinaryStep operation left right -> do
                    (a, next, seenA) <- visit (fuel - 1) left
                    (b, remaining, seenB) <- visit next right
                    finish (Binary operation a b) remaining (Set.union seenA seenB)
                ConditionalStep condition yes no -> do
                    (c, next, seenC) <- visit (fuel - 1) condition
                    (a, afterYes, seenA) <- visit next yes
                    (b, remaining, seenB) <- visit afterYes no
                    finish (If c a b) remaining (Set.unions [seenC, seenA, seenB])
                AggregateStep operation list predicate child -> do
                    (condition, next, seenC) <- case predicate of
                        Nothing -> Right (Nothing, fuel - 1, Set.empty)
                        Just conditionId -> do
                            (c, remaining, seen) <- visit (fuel - 1) conditionId
                            Right (Just c, remaining, seen)
                    (value, remaining, seenV) <- visit next child
                    finish (Fold operation list condition value) remaining (Set.union seenC seenV)

-- | Canonical post-order nodes for a previously validated internal expression.
-- Callers must validate before encoding; decoding always enforces graph limits.
flattenExpression :: Expression -> Formula
flattenExpression expression =
    let (root, (_, nodes)) = runState (flatten expression) (0, [])
     in Formula root (reverse nodes)
  where
    flatten :: Expression -> State (Int, [(NodeId, Step)]) NodeId
    flatten expr = do
        step <- case expr of
            Constant literal -> pure (LiteralStep literal)
            ReadField path -> pure (FieldStep path)
            ChecklistReference context -> pure (ChecklistReferenceStep context)
            Binary operation left right -> BinaryStep operation <$> flatten left <*> flatten right
            Unary operation child -> UnaryStep operation <$> flatten child
            If condition yes no -> ConditionalStep <$> flatten condition <*> flatten yes <*> flatten no
            Fold operation list predicate value -> AggregateStep operation list <$> traverse flatten predicate <*> flatten value
        (next, nodes) <- get
        let key = NodeId next
        put (next + 1, (key, step) : nodes)
        pure key
