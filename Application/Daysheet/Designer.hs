-- | Server-owned definition edits. Neither this command algebra nor a complete
-- definition document is a browser payload. Controllers decode typed controls,
-- retain draft revision checks, and call this same validated edit interface.
module Application.Daysheet.Designer
    ( Edit (..), LayoutTarget (..), EditError (..), ExpressionSlot (..)
    , CalculationFocus (..), calculationFocus, calculationChildren
    , applyEdit, replaceCalculationPart, permittedCalculationParts
    ) where

import Prelude
import Application.Daysheet.Contract
import Application.Daysheet.Validation (ContractError (IncompatibleTypes), expressionType, validateDefinition)
import IHP.ModelSupport (InputValue (..))
import Data.Bifunctor (first)
import Data.List (find)
import Data.Text (Text)

-- Nothing identifies root fields; Just identifies an existing named list.
data Edit
    = AddField (Maybe ListId) Int Field
    | ChangeField FieldId Text FieldType FieldSource
    | RemoveField FieldId
    | MoveField FieldId Int
    | AddChoice FieldId Int Choice
    | RenameChoice FieldId ChoiceId Text
    | RemoveChoice FieldId ChoiceId
    | MoveChoice FieldId ChoiceId Int
    | AddList Int RecordList
    | ChangeList ListId Text ListMode
    | RemoveList ListId
    | MoveList ListId Int
    | AddReport Int Report
    | ChangeReport ReportId Text [Output]
    | RemoveReport ReportId
    | MoveReport ReportId Int
    | AddSection LayoutTarget Int Section
    | RenameSection LayoutTarget SectionId Text
    | RemoveSection LayoutTarget SectionId
    | MoveSection LayoutTarget SectionId Int
    | AddBlock LayoutTarget SectionId Int Block
    | ChangeBlock LayoutTarget SectionId Int Block
    | RemoveBlock LayoutTarget SectionId Int
    | MoveBlock LayoutTarget SectionId Int Int
    deriving (Eq, Show)

data LayoutTarget = EntryLayout | ReportLayout ReportId deriving (Eq, Show)
data EditError
    = MissingField FieldId | MissingList ListId | MissingReport ReportId
    | MissingSection SectionId | MissingChoice ChoiceId | ExpectedChoiceField FieldId
    | InvalidPosition | InvalidExpressionLocation
    | RejectedDefinition ContractError
    deriving (Eq, Show)

-- A closed structural location, not user code or an expression string. A
-- location is interpreted only against the caller's revision-checked draft.
data ExpressionSlot
    = UnaryInput | BinaryLeft | BinaryRight | Condition | WhenTrue | WhenFalse
    | FoldFilter | FoldValue
    deriving (Eq, Show, Enum, Bounded)

instance InputValue ExpressionSlot where
    inputValue UnaryInput = "unary-input"
    inputValue BinaryLeft = "left"
    inputValue BinaryRight = "right"
    inputValue Condition = "condition"
    inputValue WhenTrue = "when-true"
    inputValue WhenFalse = "when-false"
    inputValue FoldFilter = "filter"
    inputValue FoldValue = "value"

-- Lexical context belongs to the saved expression, never to a submitted row or
-- list identity. During a fold Current stays outside; only Item changes.
data CalculationFocus = CalculationFocus
    { calculationField :: Field
    , calculationCurrent :: Maybe ListId
    , calculationItem :: Maybe ListId
    , calculationExpression :: Maybe Expression
    } deriving (Eq, Show)

calculationChildren :: Expression -> [(ExpressionSlot, Expression)]
calculationChildren expression = case expression of
    Unary _ input -> [(UnaryInput, input)]
    Binary _ left right -> [(BinaryLeft, left), (BinaryRight, right)]
    If condition yes no -> [(Condition, condition), (WhenTrue, yes), (WhenFalse, no)]
    Fold _ _ predicate value -> maybe [] (\condition -> [(FoldFilter, condition)]) predicate <> [(FoldValue, value)]
    _ -> []

calculationFocus :: FieldId -> [ExpressionSlot] -> Definition -> Either EditError CalculationFocus
calculationFocus key location definition = do
    (current, field) <- calculationOwner key definition
    if length location > maxExpressionDepth limits then Left InvalidExpressionLocation else Right ()
    (item, expression) <- case (fieldSource field, location) of
        (Entered, []) -> Right (Nothing, Nothing)
        (Calculated expression, _) -> do
            (scope, selected) <- descend Nothing location expression
            pure (scope, Just selected)
        _ -> Left InvalidExpressionLocation
    pure (CalculationFocus field current item expression)
  where
    descend item [] expression = Right (item, expression)
    descend item (slot : rest) expression = do
        child <- maybe (Left InvalidExpressionLocation) Right (lookup slot (calculationChildren expression))
        let nextItem = case expression of Fold _ source _ _ -> Just source; _ -> item
        descend nextItem rest child

calculationOwner :: FieldId -> Definition -> Either EditError (Maybe ListId, Field)
calculationOwner key definition = do
    scope <- fieldContainer key definition
    fields <- case scope of
        Nothing -> Right (rootFields definition)
        Just source -> maybe (Left (MissingList source)) (Right . listFields) (find ((== source) . listId) (recordLists definition))
    field <- maybe (Left (MissingField key)) Right (find ((== key) . fieldId) fields)
    pure (scope, field)

applyEdit :: Edit -> Definition -> Either EditError Definition
applyEdit edit definition = do
    changed <- case edit of
        AddField scope index field -> fieldsAt scope (insertAt index field) definition
        ChangeField key label kind source -> inFieldContainer key
            (updateBy fieldId key (MissingField key) (\field -> Right field { fieldLabel = label, fieldType = kind, fieldSource = source })) definition
        RemoveField key -> inFieldContainer key (removeBy fieldId key (MissingField key)) definition
        MoveField key index -> inFieldContainer key (moveBy fieldId key (MissingField key) index) definition
        AddChoice key index choice -> choicesAt key (insertAt index choice) definition
        RenameChoice key choice label -> choicesAt key (updateBy choiceId choice (MissingChoice choice) (\value -> Right value { choiceLabel = label })) definition
        RemoveChoice key choice -> choicesAt key (removeBy choiceId choice (MissingChoice choice)) definition
        MoveChoice key choice index -> choicesAt key (moveBy choiceId choice (MissingChoice choice) index) definition
        AddList index source -> lists (insertAt index source)
        ChangeList key label mode -> lists (updateBy listId key (MissingList key) (\source -> Right source { listLabel = label, listMode = mode }))
        RemoveList key -> lists (removeBy listId key (MissingList key))
        MoveList key index -> lists (moveBy listId key (MissingList key) index)
        AddReport index report -> reportList (insertAt index report)
        ChangeReport key label outputs -> reportList (updateBy reportKey key (MissingReport key) (\(Report identity _ sections _) -> Right (Report identity label sections outputs)))
        RemoveReport key -> reportList (removeBy reportKey key (MissingReport key))
        MoveReport key index -> reportList (moveBy reportKey key (MissingReport key) index)
        AddSection target index section -> sectionsAt target (insertAt index section) definition
        RenameSection target key label -> sectionsAt target (updateBy sectionKey key (MissingSection key) (\(Section identity _ blocks) -> Right (Section identity label blocks))) definition
        RemoveSection target key -> sectionsAt target (removeBy sectionKey key (MissingSection key)) definition
        MoveSection target key index -> sectionsAt target (moveBy sectionKey key (MissingSection key) index) definition
        AddBlock target key index block -> blocksAt target key (insertAt index block) definition
        ChangeBlock target key index block -> blocksAt target key (replaceAt index block) definition
        RemoveBlock target key index -> blocksAt target key (removeAt index) definition
        MoveBlock target key from to -> blocksAt target key (\blocks -> do
            block <- at from blocks
            remaining <- removeAt from blocks
            insertAt to block remaining) definition
    first RejectedDefinition (validateDefinition changed)
    pure changed
  where
    lists change = (\values -> definition { recordLists = values }) <$> change (recordLists definition)
    reportList change = (\values -> definition { reports = values }) <$> change (reports definition)

-- Whole-definition validation is also the guidance authority. It rules out
-- wrong types, illegal scope, cycles and broken downstream dependencies, even
-- when the changed node is inside a filter or conditional. No second type or
-- dependency checker belongs in the designer or JavaScript.
replaceCalculationPart :: FieldId -> [ExpressionSlot] -> Expression -> Definition -> Either EditError Definition
replaceCalculationPart key location replacement definition = do
    (scope, field) <- calculationOwner key definition
    expression <- case (fieldSource field, location) of
        (_, []) -> Right replacement
        (Calculated current, _) | length location <= maxExpressionDepth limits -> replaceAtLocation location current
        _ -> Left InvalidExpressionLocation
    -- Cheap canonical type rejection precedes complete dependency/layout
    -- validation when constructing bounded menus of candidate replacements.
    resultType <- first RejectedDefinition (expressionType definition scope expression)
    if resultType == fieldType field then Right () else Left (RejectedDefinition IncompatibleTypes)
    applyEdit (ChangeField key (fieldLabel field) (fieldType field) (Calculated expression)) definition
  where
    replaceAtLocation [] _ = Right replacement
    replaceAtLocation (slot : rest) current = case (slot, current) of
        (UnaryInput, Unary operation input) -> Unary operation <$> replaceAtLocation rest input
        (BinaryLeft, Binary operation a b) -> (\value -> Binary operation value b) <$> replaceAtLocation rest a
        (BinaryRight, Binary operation a b) -> Binary operation a <$> replaceAtLocation rest b
        (Condition, If condition a b) -> (\value -> If value a b) <$> replaceAtLocation rest condition
        (WhenTrue, If condition a b) -> (\value -> If condition value b) <$> replaceAtLocation rest a
        (WhenFalse, If condition a b) -> If condition a <$> replaceAtLocation rest b
        (FoldFilter, Fold operation source (Just predicate) value) -> (\next -> Fold operation source (Just next) value) <$> replaceAtLocation rest predicate
        (FoldValue, Fold operation source predicate value) -> Fold operation source predicate <$> replaceAtLocation rest value
        _ -> Left InvalidExpressionLocation

-- Candidates come from bounded, server-authored controls. Accepted candidates
-- preserve their order; submission always repeats the authoritative check.
permittedCalculationParts :: FieldId -> [ExpressionSlot] -> [Expression] -> Definition -> [Expression]
permittedCalculationParts key location candidates definition =
    [candidate | candidate <- candidates, Right _ <- [replaceCalculationPart key location candidate definition]]

choicesAt :: FieldId -> ([Choice] -> Either EditError [Choice]) -> Definition -> Either EditError Definition
choicesAt key change = inFieldContainer key (updateBy fieldId key (MissingField key) (\field -> case fieldType field of
    ChoiceType choices -> (\next -> field { fieldType = ChoiceType next }) <$> change choices
    _ -> Left (ExpectedChoiceField key)))

fieldContainer :: FieldId -> Definition -> Either EditError (Maybe ListId)
fieldContainer key definition
    | any ((== key) . fieldId) (rootFields definition) = Right Nothing
    | otherwise = maybe (Left (MissingField key)) (Right . Just . listId)
        (find (any ((== key) . fieldId) . listFields) (recordLists definition))

inFieldContainer :: FieldId -> ([Field] -> Either EditError [Field]) -> Definition -> Either EditError Definition
inFieldContainer key change definition = do
    scope <- fieldContainer key definition
    fieldsAt scope change definition

fieldsAt :: Maybe ListId -> ([Field] -> Either EditError [Field]) -> Definition -> Either EditError Definition
fieldsAt Nothing change definition = (\values -> definition { rootFields = values }) <$> change (rootFields definition)
fieldsAt (Just key) change definition = do
    values <- updateBy listId key (MissingList key) (\source -> (\fields -> source { listFields = fields }) <$> change (listFields source)) (recordLists definition)
    pure definition { recordLists = values }

reportKey :: Report -> ReportId
reportKey (Report key _ _ _) = key
sectionKey :: Section -> SectionId
sectionKey (Section key _ _) = key

sectionsAt :: LayoutTarget -> ([Section] -> Either EditError [Section]) -> Definition -> Either EditError Definition
sectionsAt EntryLayout change definition = (\values -> definition { entryLayout = values }) <$> change (entryLayout definition)
sectionsAt (ReportLayout key) change definition = do
    values <- updateBy reportKey key (MissingReport key) (\(Report identity label sections outputs) -> (\next -> Report identity label next outputs) <$> change sections) (reports definition)
    pure definition { reports = values }

blocksAt :: LayoutTarget -> SectionId -> ([Block] -> Either EditError [Block]) -> Definition -> Either EditError Definition
blocksAt target key change = sectionsAt target (updateBy sectionKey key (MissingSection key)
    (\(Section identity label blocks) -> Section identity label <$> change blocks))

updateBy :: Eq key => (a -> key) -> key -> EditError -> (a -> Either EditError a) -> [a] -> Either EditError [a]
updateBy identity key missing change values = case break ((== key) . identity) values of
    (_, []) -> Left missing
    (before, value : after) -> (\next -> before <> [next] <> after) <$> change value

removeBy :: Eq key => (a -> key) -> key -> EditError -> [a] -> Either EditError [a]
removeBy identity key missing values = case break ((== key) . identity) values of
    (_, []) -> Left missing
    (before, _ : after) -> Right (before <> after)

moveBy :: Eq key => (a -> key) -> key -> EditError -> Int -> [a] -> Either EditError [a]
moveBy identity key missing index values = do
    value <- maybe (Left missing) Right (find ((== key) . identity) values)
    remaining <- removeBy identity key missing values
    insertAt index value remaining

insertAt :: Int -> a -> [a] -> Either EditError [a]
insertAt index value values
    | index < 0 || index > length values = Left InvalidPosition
    | otherwise = let (before, after) = splitAt index values in Right (before <> [value] <> after)

at :: Int -> [a] -> Either EditError a
at index values = case drop index values of
    value : _ | index >= 0 -> Right value
    _ -> Left InvalidPosition

removeAt :: Int -> [a] -> Either EditError [a]
removeAt index values = at index values >> Right (take index values <> drop (index + 1) values)

replaceAt :: Int -> a -> [a] -> Either EditError [a]
replaceAt index value values = at index values >> Right (take index values <> [value] <> drop (index + 1) values)
