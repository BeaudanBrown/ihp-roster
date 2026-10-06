-- | Selected-content boundary for all report renderers. No source definition,
-- input document, expression, hidden field or record identity leaves this model.
module Application.Daysheet.Report
    ( ReportContent (..), ReportSection (..), ReportBlock (..), ReportGroup (..)
    , ReportCell (..), ReportCheck (..), ProjectionError (..), projectReport
    ) where

import Prelude
import qualified Application.Daysheet.Contract as D
import qualified Application.Daysheet.Evaluation as E
import qualified Application.Daysheet.Saved as Saved
import Data.List (find, groupBy)
import Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set

-- Text is plain data. HTML renderers must escape it and spreadsheet renderers
-- must write text cells, never treat strings beginning with '=' as formulas.
-- Choice/reference identities are resolved to their preserved display labels.
data ReportCell = ReportValue D.Literal Text | ReportUnavailable Text deriving (Eq, Show)
data ReportCheck = ReportPassed Text | ReportConcern Text | ReportNotEvaluated Text deriving (Eq, Show)
data ReportGroup = ReportGroup (Maybe ReportCell) [[ReportCell]] deriving (Eq, Show)
data ReportBlock
    = ReportInstructions Text
    | ReportField Text ReportCell
    | ReportAdvisory ReportCheck
    | ReportRowAdvisories Text [(Text, ReportCheck)]
    | ReportTable Text [Text] (Maybe Text) [ReportGroup]
    deriving (Eq, Show)
data ReportSection = ReportSection Text [ReportBlock] deriving (Eq, Show)
data ReportContent = ReportContent Text [ReportSection] deriving (Eq, Show)
data ProjectionError = UnknownReport | InvalidReportSelection | ReportEvaluationError E.EvaluationError deriving (Eq, Show)

projectReport :: Saved.Saved -> D.ReportId -> Either ProjectionError ReportContent
projectReport saved key = do
    D.Report _ label sections _ <- maybe (Left UnknownReport) Right (find matches (D.reports definition))
    let positioned = [(sectionIndex, blockIndex, block) | (sectionIndex, D.Section _ _ blocks) <- zip [0 :: Int ..] sections,
            (blockIndex, block) <- zip [0 :: Int ..] blocks]
    let requests = [(location, request) | (sectionIndex, blockIndex, block) <- positioned,
            let location = (sectionIndex, blockIndex), request <- case block of
                D.AdvisoryBlock advisory -> [E.RootAdvisory advisory]
                D.RowAdvisoryBlock list advisory -> [E.ListAdvisory list (rowIds list) advisory]
                _ -> []]
    evaluated <- either (Left . ReportEvaluationError) Right (E.evaluateAdvisories (Saved.evaluation saved) (map snd requests))
    let checks = Map.fromList (zip (map fst requests) evaluated)
    let selected = Set.fromList (concatMap (selectedFields . (\(_, _, block) -> block)) positioned)
    ReportContent label <$> mapM (section selected checks) (zip [0 ..] sections)
  where
    definition = Saved.definition saved
    matches (D.Report report _ _ _) = report == key
    rowIds list = Map.findWithDefault [] list (Saved.rows saved)
    requireField fields key = maybe (Left InvalidReportSelection) Right (find ((== key) . D.fieldId) fields)
    requireList key = maybe (Left InvalidReportSelection) Right (find ((== key) . D.listId) (D.recordLists definition))
    selectedFields = \case
        D.FieldBlock key -> [key]
        D.TableBlock _ columns grouping _ -> columns <> maybe [] pure grouping
        _ -> []
    reason selected unavailable = case unavailable of
        D.MissingInput field | not (Set.member field selected) -> "Required input has not been entered."
        D.MissingReference field | not (Set.member field selected) -> "A required linked record is unavailable."
        _ -> E.explainUnavailable (Saved.evaluation saved) unavailable
    cell selected field = \case
        D.Unavailable unavailable -> ReportUnavailable (reason selected unavailable)
        D.Known value ->
            let text = Saved.valueText saved field value
                literal = case value of
                    E.Scalar (D.ChoiceLiteral _) -> D.TextLiteral text
                    E.Scalar literal -> literal
                    E.Reference _ -> D.TextLiteral text
            in ReportValue literal text
    check selected = \case
        D.Passed message -> ReportPassed message
        D.Concern message -> ReportConcern message
        D.NotEvaluated unavailable -> ReportNotEvaluated (reason selected unavailable)
    section selected checks (index, D.Section _ label blocks) =
        ReportSection label <$> mapM (block selected checks index) (zip [0 ..] blocks)
    block selected checks sectionIndex (blockIndex, configured) = case configured of
        D.Instructions text -> Right (ReportInstructions text)
        D.FieldBlock key -> do
            field <- requireField (D.rootFields definition) key
            pure (ReportField (D.fieldLabel field) (cell selected field (Saved.resultFor saved (E.RootTarget key))))
        D.AdvisoryBlock _ -> case Map.lookup (sectionIndex, blockIndex) checks of
            Just [result] -> Right (ReportAdvisory (check selected result))
            _ -> Left InvalidReportSelection
        D.RowAdvisoryBlock key _ -> do
            source <- requireList key
            results <- maybe (Left InvalidReportSelection) Right (Map.lookup (sectionIndex, blockIndex) checks)
            if length results /= length (rowIds key) then Left InvalidReportSelection else pure ()
            -- Do not discover a hidden text field to label an advisory row.
            pure (ReportRowAdvisories (D.listLabel source)
                [(D.listLabel source <> " record " <> Text.pack (show index), check selected result)
                    | (index, result) <- zip [1 :: Int ..] results])
        D.TableBlock key columns grouping ordering -> do
            source <- requireList key
            fields <- mapM (requireField (D.listFields source)) columns
            groupField <- traverse (requireField (D.listFields source)) grouping
            let ordered = Saved.tableRows saved source grouping ordering
            let result row field = Saved.resultFor saved (E.RowTarget key row (D.fieldId field))
            let sameGroup field a b = case (result a field, result b field) of
                    (D.Unavailable _, D.Unavailable _) -> True
                    (left, right) -> left == right
            let groups = maybe [ordered] (\field -> groupBy (sameGroup field) ordered) groupField
            let heading [] = Nothing
                heading members@(row:_) = fmap (\field -> case result row field of
                    D.Known value -> cell selected field (D.Known value)
                    D.Unavailable _ -> ReportUnavailable (Text.intercalate " " (Set.toList (Set.fromList
                        [reason selected unavailable | member <- members, D.Unavailable unavailable <- [result member field]])))) groupField
            pure (ReportTable (D.listLabel source) (map D.fieldLabel fields) (D.fieldLabel <$> groupField)
                [ReportGroup (heading members) [[cell selected field (result row field) | field <- fields] | row <- members] | members <- groups])
