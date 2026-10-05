-- | Bounded server-authored calculation menus. Options carry validated internal
-- edits, never a browser expression document. A submitted menu position must be
-- resolved against the same definition revision and validated again on write.
module Application.Daysheet.Designer.Calculation
    ( CalculationOption, calculationOptionLabel, calculationOptionEdit
    , CalculationLink (..), CalculationMenu (..), calculationMenu
    , calculationTypeLabel, unaryLabel, binaryLabel
    ) where

import Prelude
import Application.Daysheet.Contract
import Application.Daysheet.Designer
import Application.Daysheet.Designer.Controls
import qualified Application.Daysheet.Number as Number
import qualified Application.Daysheet.Validation as Validation
import Data.Bifunctor (first)
import Data.List (find, nubBy)
import Data.Maybe (maybeToList)
import Data.Text (Text)
import Data.Time (TimeOfDay (..), fromGregorian)

-- Construction stays private: a menu option is valid for its supplied snapshot,
-- not authorization or permission to ignore persistence revision checks.
data CalculationOption = CalculationOption
    { calculationOptionLabel :: Text
    , calculationOptionEdit :: Edit
    } deriving (Eq, Show)
data CalculationLink = CalculationLink
    { calculationLinkLabel :: Text
    , calculationLinkPath :: FieldPath
    } deriving (Eq, Show)
data CalculationMenu = CalculationMenu
    { calculationMenuOptions :: [CalculationOption]
    , calculationMenuLinks :: [CalculationLink]
    } deriving (Eq, Show)

calculationMenu :: CalculationGroup -> FieldId -> [ExpressionSlot] -> Maybe FieldPath -> Definition -> Either EditError CalculationMenu
calculationMenu group key location browse definition = do
    focus <- calculationFocus key location definition
    paths <- case browse of
        Nothing -> Right (directPaths definition focus)
        Just path@(FieldPath context prefix) | group == FieldParts -> do
            kind <- first RejectedDefinition (Validation.expressionTypeInScope definition (calculationCurrent focus) (calculationItem focus) (ReadField path))
            case kind of
                ReferenceType source | length prefix < maxReferenceDepth limits -> do
                    declared <- maybe (Left (MissingList source)) Right (find ((== source) . listId) (recordLists definition))
                    pure [(listLabel declared <> " — " <> fieldLabel field, FieldPath context (prefix <> [fieldId field])) | field <- listFields declared]
                _ -> Left (RejectedDefinition Validation.InvalidReferencePath)
        _ -> Left InvalidExpressionLocation
    let infer = Validation.expressionTypeInScope definition (calculationCurrent focus) (calculationItem focus)
        references = [(kind, expression) | (_, path) <- directPaths definition focus, let expression = ReadField path, Right kind@(ReferenceType _) <- [infer expression]]
        pairings = [(label, ChecklistReference context) | (context, label) <- [(Current, "Paired reference — this checklist row"), (Item, "Paired reference — included checklist row")], Right _ <- [infer (ChecklistReference context)]]
        existing = [(kind, expression) | expression <- maybeToList (calculationExpression focus), Right kind <- [infer expression]]
        seeds = nubBy (\a b -> fst a == fst b) (existing <> scalarSeeds <> choiceSeeds definition <> references <> [(kind, expression) | (_, expression) <- pairings, Right kind <- [infer expression]])
        candidates = case group of
            FieldParts -> [(label, ReadField path) | (label, path) <- paths] <> (if browse == Nothing then pairings else [])
            ValueParts -> literalOptions definition (case calculationExpression focus of Nothing -> Just (fieldType (calculationField focus)); Just expression -> either (const Nothing) Just (infer expression))
            OperationParts -> operationOptions definition seeds
            ListParts -> listOptions definition (calculationExpression focus)
        accepted = [CalculationOption label edit | (label, expression) <- candidates, Right edit <- [validatedEdit expression]]
        links = if group /= FieldParts then [] else
            [CalculationLink ("Follow " <> label) path | (label, path@(FieldPath _ fields)) <- paths
                , length fields < maxReferenceDepth limits, Right (ReferenceType _) <- [infer (ReadField path)]]
    pure (CalculationMenu accepted links)
  where
    validatedEdit expression = do
        next <- replaceCalculationPart key location expression definition
        focus <- calculationFocus key [] next
        let field = calculationField focus
        pure (ChangeField key (fieldLabel field) (fieldType field) (fieldSource field))

directPaths :: Definition -> CalculationFocus -> [(Text, FieldPath)]
directPaths definition focus =
    [("Whole Daysheet — " <> fieldLabel field, FieldPath Root [fieldId field]) | field <- rootFields definition]
    <> rows Current "This row — " (calculationCurrent focus)
    <> rows Item "Included row — " (calculationItem focus)
  where
    rows context label scope = [(label <> listLabel source <> " — " <> fieldLabel field, FieldPath context [fieldId field])
        | key <- maybeToList scope, source <- recordLists definition, listId source == key, field <- listFields source]

scalarSeeds :: [(FieldType, Expression)]
scalarSeeds =
    [(TextType, Constant (TextLiteral "")), (BooleanType, Constant (BooleanLiteral False)), (WholeType, Constant (WholeLiteral 0))
    , (DateType, Constant (DateLiteral (fromGregorian 2000 1 1))), (OperationalTimeType, Constant (OperationalTimeLiteral (TimeOfDay 6 0 0)))]
    <> [(kind, Constant (literal zero)) | Right zero <- [Number.number 0 1]
        , (kind, literal) <- [(DecimalType, DecimalLiteral), (MoneyType, MoneyLiteral), (PercentageType, PercentageLiteral)]]

choiceSeeds :: Definition -> [(FieldType, Expression)]
choiceSeeds definition = [(kind, Constant (ChoiceLiteral (choiceId first)))
    | field <- rootFields definition <> concatMap listFields (recordLists definition), let kind = fieldType field, ChoiceType (first : _) <- [kind]]

-- Choice literals stay within the focused nominal domain, bounding this menu
-- to one field's options. Comparison-domain changes use operation templates.
literalOptions :: Definition -> Maybe FieldType -> [(Text, Expression)]
literalOptions definition selectedType =
    [("Text — empty", Constant (TextLiteral "")), ("Yes", Constant (BooleanLiteral True)), ("No", Constant (BooleanLiteral False))
    , ("Whole number — 0", Constant (WholeLiteral 0)), ("Date — 2000-01-01", Constant (DateLiteral (fromGregorian 2000 1 1)))
    , ("Operational time — 06:00", Constant (OperationalTimeLiteral (TimeOfDay 6 0 0)))]
    <> [(label, Constant (literal zero)) | Right zero <- [Number.number 0 1]
        , (label, literal) <- [("Decimal number — 0", DecimalLiteral), ("Money (AUD) — 0.00", MoneyLiteral), ("Percentage — 0%", PercentageLiteral)]]
    <> [("Choice: " <> fieldLabel field <> " — " <> choiceLabel choice, Constant (ChoiceLiteral (choiceId choice)))
        | field <- rootFields definition <> concatMap listFields (recordLists definition), Just (fieldType field) == selectedType, ChoiceType choices <- [fieldType field], choice <- choices]

operationOptions :: Definition -> [(FieldType, Expression)] -> [(Text, Expression)]
operationOptions definition seeds =
    [(unaryLabel operation <> " — " <> calculationTypeLabel definition kind, Unary operation expression)
        | operation <- [minBound .. maxBound], (kind, expression) <- seeds, Right _ <- [Validation.unaryType operation kind]]
    <> [(binaryLabel operation <> " — " <> calculationTypeLabel definition leftType <> " / " <> calculationTypeLabel definition rightType, Binary operation left right)
        | operation <- [minBound .. maxBound], (leftType, left) <- seeds, (rightType, seed) <- seeds
        , Right _ <- [Validation.binaryType operation leftType rightType]
        , let right = if operation == Divide then nonzeroSeed rightType seed else seed]
    <> [("If / otherwise — " <> calculationTypeLabel definition kind, If (Constant (BooleanLiteral False)) expression expression) | (kind, expression) <- seeds]

-- New division controls use a visible nonzero example, never an unavailable
-- denominator disguised as zero. Every value remains editable before publish.
nonzeroSeed :: FieldType -> Expression -> Expression
nonzeroSeed WholeType _ = Constant (WholeLiteral 1)
nonzeroSeed kind fallback = case Number.number 1 1 of
    Right one -> case kind of
        DecimalType -> Constant (DecimalLiteral one)
        MoneyType -> Constant (MoneyLiteral one)
        PercentageType -> Constant (PercentageLiteral one)
        _ -> fallback
    Left _ -> fallback

listOptions :: Definition -> Maybe Expression -> [(Text, Expression)]
listOptions definition current = filters <>
    [("Sum — " <> listLabel source <> " — " <> calculationTypeLabel definition kind, Fold Sum (listId source) Nothing expression)
        | source <- recordLists definition, (kind, expression) <- scalarSeeds, kind `elem` [WholeType, DecimalType, MoneyType, PercentageType]]
    <> [("Count rows — " <> listLabel source, Fold Count (listId source) Nothing (Constant (WholeLiteral 1))) | source <- recordLists definition]
  where
    filters = case current of
        Just (Fold operation source Nothing value) -> [("Add row filter — starts with Yes", Fold operation source (Just (Constant (BooleanLiteral True))) value)]
        Just (Fold operation source (Just _) value) -> [("Remove row filter — include all rows", Fold operation source Nothing value)]
        _ -> []

calculationTypeLabel :: Definition -> FieldType -> Text
calculationTypeLabel definition kind = case kind of
    ReferenceType source -> "Reference: " <> maybe "Unavailable list" listLabel (find ((== source) . listId) (recordLists definition))
    ChoiceType _ -> "Choice: " <> maybe "Unavailable field" fieldLabel (find ((== kind) . fieldType) (rootFields definition <> concatMap listFields (recordLists definition)))
    _ -> fieldKindLabel (fieldKind kind)

unaryLabel :: Unary -> Text
unaryLabel Negate = "Negate"
unaryLabel Absolute = "Absolute value"
unaryLabel Not = "Not"
unaryLabel RoundCents = "Round AUD to cents"
unaryLabel PercentageRatio = "Percentage as decimal ratio"

binaryLabel :: Binary -> Text
binaryLabel Add = "Add"
binaryLabel Subtract = "Subtract"
binaryLabel Multiply = "Multiply"
binaryLabel Divide = "Divide"
binaryLabel Equal = "Equal"
binaryLabel NotEqual = "Not equal"
binaryLabel Less = "Less than"
binaryLabel LessOrEqual = "Less than or equal"
binaryLabel Greater = "Greater than"
binaryLabel GreaterOrEqual = "Greater than or equal"
binaryLabel And = "Both conditions"
binaryLabel Or = "Either condition"
