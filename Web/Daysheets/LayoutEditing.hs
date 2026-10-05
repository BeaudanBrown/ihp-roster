-- | Adapt generated layout controls to validated definition edits. Layouts
-- refer to existing fields; there is no report-specific expression language.
module Web.Daysheets.LayoutEditing
    ( layoutTarget, layoutSections, sectionById, blockAt, blockSource
    , blockFormFields, blockEdit, moveEdit
    ) where

import Prelude
import qualified Application.Daysheet.Contract as D
import qualified Application.Daysheet.Designer as Designer
import Application.Daysheet.Designer.Controls
import Application.Daysheet.Storage (DesignerState (..))
import qualified Application.Helper.FrontendContract.Surface.DaysheetDesigner as Surface
import qualified Application.Helper.FrontendContract.Surface.DaysheetDesigner.Action as Action
import Application.Helper.FrontendContract.Surface.Values
import Data.List (find)
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.UUID (UUID)

layoutTarget :: Maybe UUID -> Designer.LayoutTarget
layoutTarget = maybe Designer.EntryLayout (Designer.ReportLayout . D.ReportId)

layoutSections :: D.Definition -> Maybe UUID -> Either Text [D.Section]
layoutSections definition Nothing = Right (D.entryLayout definition)
layoutSections definition (Just key) = case [sections | D.Report (D.ReportId identity) _ sections _ <- D.reports definition, key == identity] of
    [sections] -> Right sections
    _ -> Left "This report no longer exists."

sectionById :: UUID -> [D.Section] -> Either Text D.Section
sectionById key = maybe (Left "This section no longer exists.") Right . find (\(D.Section (D.SectionId identity) _ _) -> identity == key)

blockAt :: Int -> [D.Block] -> Either Text D.Block
blockAt = itemAt

itemAt :: Int -> [a] -> Either Text a
itemAt index values = case drop index values of
    value : _ | index >= 0 -> Right value
    _ -> Left "This content position no longer exists."

blockSource :: D.Block -> Maybe UUID
blockSource (D.TableBlock (D.ListId source) _ _ _) = Just source
blockSource (D.RowAdvisoryBlock (D.ListId source) _) = Just source
blockSource _ = Nothing

blockFormFields :: DesignerState -> Maybe UUID -> UUID -> Maybe Int -> BlockKind -> Maybe UUID -> Maybe D.Block -> ActionFields Action.SaveDesignerBlockActionOperation
blockFormFields state report section index requestedKind source current =
    Action.saveDesignerBlockActionFields (fromInteger (designerBaseRevision state)) (fromInteger <$> designerDraftRevision state)
        report section index (maybe requestedKind blockKind current) (maybe source blockSource current)
        field text columns grouping sorting descending passed concern
  where
    fieldKey (D.FieldId key) = key
    field = case current of
        Just (D.FieldBlock key) -> Just (fieldKey key)
        _ -> case condition of
            Just (D.ReadField (D.FieldPath _ [key])) -> Just (fieldKey key)
            _ -> Nothing
    text = case current of Just (D.Instructions value) -> Just value; _ -> Nothing
    columns = case current of Just (D.TableBlock _ values _ _) -> Just (map fieldKey values); _ -> Nothing
    grouping = case current of Just (D.TableBlock _ _ value _) -> fieldKey <$> value; _ -> Nothing
    sorting = case current of Just (D.TableBlock _ _ _ values) -> Just (map (fieldKey . fst) values); _ -> Nothing
    descending = case current of Just (D.TableBlock _ _ _ values) -> Just [fieldKey key | (key, D.Descending) <- values]; _ -> Nothing
    advisory = case current of Just (D.AdvisoryBlock value) -> Just value; Just (D.RowAdvisoryBlock _ value) -> Just value; _ -> Nothing
    condition = D.advisoryCondition <$> advisory
    passed = D.passedMessage <$> advisory
    concern = D.concernMessage <$> advisory

moveEdit :: D.Definition -> ActionFields Action.MoveDesignerItemActionOperation -> Either Text Designer.Edit
moveEdit definition fields = case surfaceFieldValue @Surface.MoveKind fields of
    MoveFieldItem -> do
        entries <- case surfaceFieldValue @Surface.DefinitionListId fields of
            Nothing -> Right (D.rootFields definition)
            Just key -> maybe (Left "This list no longer exists.") (Right . D.listFields) (find ((== D.ListId key) . D.listId) (D.recordLists definition))
        field <- itemAt from entries
        pure (Designer.MoveField (D.fieldId field) to)
    MoveListItem -> do
        source <- itemAt from (D.recordLists definition)
        pure (Designer.MoveList (D.listId source) to)
    MoveReportItem -> do
        D.Report key _ _ _ <- itemAt from (D.reports definition)
        pure (Designer.MoveReport key to)
    MoveSectionItem -> do
        sections <- layoutSections definition report
        D.Section key _ _ <- itemAt from sections
        pure (Designer.MoveSection target key to)
    MoveBlockItem -> Designer.MoveBlock target . D.SectionId <$> requiredSection <*> pure from <*> pure to
    MoveColumnItem -> changeTable True
    MoveSortItem -> changeTable False
  where
    from = surfaceFieldValue @Surface.FromPosition fields
    to = surfaceFieldValue @Surface.ToPosition fields
    report = surfaceFieldValue @Surface.DefinitionReportId fields
    target = layoutTarget report
    requiredSection = maybe (Left "Choose a section.") Right (surfaceFieldValue @Surface.DefinitionSectionId fields)
    changeTable columns = do
        section <- requiredSection
        position <- maybe (Left "Choose a table.") Right (surfaceFieldValue @Surface.BlockIndex fields)
        sections <- layoutSections definition report
        D.Section _ _ blocks <- sectionById section sections
        block <- blockAt position blocks
        changed <- case block of
            D.TableBlock source selected grouping sorting -> if columns
                then (\next -> D.TableBlock source next grouping sorting) <$> moveAt selected
                else D.TableBlock source selected grouping <$> moveAt sorting
            _ -> Left "This content is not a record table."
        pure (Designer.ChangeBlock target (D.SectionId section) position changed)
    moveAt :: [a] -> Either Text [a]
    moveAt values = do
        value <- itemAt from values
        _ <- itemAt to values
        let remaining = take from values <> drop (from + 1) values
        pure (take to remaining <> [value] <> drop to remaining)

blockEdit :: D.Definition -> ActionFields Action.SaveDesignerBlockActionOperation -> Either Text Designer.Edit
blockEdit definition fields = do
    sections <- layoutSections definition report
    D.Section _ _ blocks <- sectionById section sections
    previous <- traverse (`blockAt` blocks) index
    block <- case kind of
        InstructionsContent -> Right (D.Instructions (fromMaybe "" (surfaceFieldValue @Surface.TextContent fields)))
        FieldContent -> D.FieldBlock . D.FieldId <$> selectedField
        TableContent -> do
            source <- selectedSource
            let columns = map D.FieldId (fromMaybe [] (surfaceFieldValue @Surface.ColumnIds fields))
                sorting = fromMaybe [] (surfaceFieldValue @Surface.SortingFieldIds fields)
                descending = fromMaybe [] (surfaceFieldValue @Surface.DescendingFieldIds fields)
            if any ((> D.maxFields D.limits) . length) [columns, map D.FieldId sorting, map D.FieldId descending]
                then Left "Too many table fields selected." else Right ()
            if all (`elem` sorting) descending then Right () else Left "Select sorting for a field before choosing descending order."
            pure (D.TableBlock source columns (D.FieldId <$> surfaceFieldValue @Surface.GroupingFieldId fields)
                [(D.FieldId key, if key `elem` descending then D.Descending else D.Ascending) | key <- sorting])
        AdvisoryContent -> D.AdvisoryBlock <$> advisory D.Root previous
        RowAdvisoryContent -> D.RowAdvisoryBlock <$> selectedSource <*> advisory D.Current previous
    pure (case index of
        Nothing -> Designer.AddBlock (layoutTarget report) (D.SectionId section) (length blocks) block
        Just position -> Designer.ChangeBlock (layoutTarget report) (D.SectionId section) position block)
  where
    report = surfaceFieldValue @Surface.DefinitionReportId fields
    section = surfaceFieldValue @Surface.DefinitionSectionId fields
    index = surfaceFieldValue @Surface.BlockIndex fields
    kind = surfaceFieldValue @Surface.ContentKind fields
    selectedField = maybe (Left "Choose a field.") Right (surfaceFieldValue @Surface.DefinitionFieldId fields)
    selectedSource = maybe (Left "Choose a record list.") (Right . D.ListId) (surfaceFieldValue @Surface.DefinitionListId fields)
    advisory context previous = do
        condition <- case surfaceFieldValue @Surface.DefinitionFieldId fields of
            Just key -> Right (D.ReadField (D.FieldPath context [D.FieldId key]))
            Nothing -> case previous of
                Just (D.AdvisoryBlock old) | kind == AdvisoryContent -> Right (D.advisoryCondition old)
                Just (D.RowAdvisoryBlock source old) | kind == RowAdvisoryContent && Right source == selectedSource -> Right (D.advisoryCondition old)
                _ -> Left "Choose a boolean field for the advisory condition."
        pure (D.Advisory condition (fromMaybe "" (surfaceFieldValue @Surface.PassedText fields)) (fromMaybe "" (surfaceFieldValue @Surface.ConcernText fields)))
