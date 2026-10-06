module Web.Daysheets.CalculationEditing
    ( CalculationEditor (..), prepareCalculationEditor
    , parseCalculationLocation, renderCalculationLocation, parseReferencePath, renderReferencePath
    , constantType, constantEdit, calculationProblem
    ) where

import Prelude
import qualified Application.Daysheet.Contract as D
import Application.Daysheet.Designer
import Application.Daysheet.Designer.Calculation
import Application.Daysheet.Designer.Controls
import Application.Daysheet.Designer.ReferenceEntry (parseReferenceEntry)
import Application.Daysheet.References (ReferenceValue (..))
import qualified Application.Daysheet.Validation as Validation
import Data.Bifunctor (first)
import Data.List (find)
import Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.UUID as UUID
import IHP.ModelSupport (InputValue (..))

data CalculationEditor = CalculationEditor
    { editorField :: D.FieldId
    , editorLocation :: [ExpressionSlot]
    , editorGroup :: CalculationGroup
    , editorReferencePath :: Maybe D.FieldPath
    , editorFocus :: CalculationFocus
    , editorType :: D.FieldType
    , editorMenu :: CalculationMenu
    } deriving (Eq, Show)

prepareCalculationEditor :: D.Definition -> D.FieldId -> [ExpressionSlot] -> CalculationGroup -> Maybe Text -> Either Text CalculationEditor
prepareCalculationEditor definition key location group rawPath = do
    path <- parseReferencePath rawPath
    focus <- first (const calculationProblem) (calculationFocus key location definition)
    kind <- case calculationExpression focus of
        Nothing -> Right (D.fieldType (calculationField focus))
        Just expression -> first (const calculationProblem) (Validation.expressionTypeInScope definition (calculationCurrent focus) (calculationItem focus) expression)
    menu <- first (const calculationProblem) (calculationMenu group key location path definition)
    pure (CalculationEditor key location group path focus kind menu)

-- Only closed structural locations and bounded UUID reference paths appear in
-- navigation URLs. These codecs cannot encode expressions or evaluation rows.
parseCalculationLocation :: Maybe Text -> Either Text [ExpressionSlot]
parseCalculationLocation Nothing = Right []
parseCalculationLocation (Just "") = Right []
parseCalculationLocation (Just raw)
    | Text.length raw > 512 || length pieces > D.maxExpressionDepth D.limits = Left calculationProblem
    | otherwise = traverse (\part -> maybe (Left calculationProblem) Right (readClosed part)) pieces
  where pieces = Text.splitOn "/" raw

renderCalculationLocation :: [ExpressionSlot] -> Maybe Text
renderCalculationLocation [] = Nothing
renderCalculationLocation values = Just (Text.intercalate "/" (map inputValue values))

parseReferencePath :: Maybe Text -> Either Text (Maybe D.FieldPath)
parseReferencePath Nothing = Right Nothing
parseReferencePath (Just "") = Right Nothing
parseReferencePath (Just raw)
    | Text.length raw > 512 = Left calculationProblem
    | otherwise = case Text.splitOn "/" raw of
        context : pieces | not (null pieces) && length pieces <= D.maxReferenceDepth D.limits -> do
            scope <- maybe (Left calculationProblem) Right (readClosed context)
            keys <- traverse (maybe (Left calculationProblem) (Right . D.FieldId) . UUID.fromText) pieces
            pure (Just (D.FieldPath scope keys))
        _ -> Left calculationProblem

renderReferencePath :: D.FieldPath -> Text
renderReferencePath (D.FieldPath context keys) = Text.intercalate "/" (inputValue context : [UUID.toText key | D.FieldId key <- keys])

readClosed :: (Bounded value, Enum value, InputValue value) => Text -> Maybe value
readClosed raw = find ((== raw) . inputValue) [minBound .. maxBound]

constantType :: D.Definition -> D.FieldId -> [ExpressionSlot] -> Either Text D.FieldType
constantType definition key location = do
    focus <- first (const calculationProblem) (calculationFocus key location definition)
    kind <- case calculationExpression focus of
        Nothing -> Right (D.fieldType (calculationField focus))
        Just expression@(D.Constant _) -> first (const calculationProblem) (Validation.expressionTypeInScope definition (calculationCurrent focus) (calculationItem focus) expression)
        _ -> Left "Choose a constant value before editing its value."
    case kind of
        D.ReferenceType _ -> Left "References must be read from fields or the paired checklist record."
        _ -> Right kind

constantEdit :: D.Definition -> D.FieldId -> [ExpressionSlot] -> Text -> Either Text Edit
constantEdit definition key location raw = do
    kind <- constantType definition key location
    literal <- case kind of
        D.TextType -> Right (D.TextLiteral raw)
        _ -> do
            parsed <- parseReferenceEntry kind raw
            case parsed of
                Just (ReferenceScalar value) -> Right value
                _ -> Left "Enter a constant value."
    first (const calculationProblem) (calculationPartEdit key location (D.Constant literal) definition)

calculationProblem :: Text
calculationProblem = "This calculation part is not available in the saved definition. Reload and review it."
