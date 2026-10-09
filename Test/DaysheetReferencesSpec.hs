module Test.DaysheetReferencesSpec where

import Prelude
import Application.Daysheet.Contract
import Application.Daysheet.DefinitionCodec
import Application.Daysheet.ReferenceCodec
import Application.Daysheet.References
import Application.Daysheet.Designer.ReferenceRetirement
import Application.Helper.NominalText
import qualified Application.Daysheet.Evaluation as E
import qualified Data.Map.Strict as Map
import Data.Either (isLeft)
import qualified Data.UUID as UUID
import Test.Hspec

areaList, terminalList :: ListId
areaList = ListId UUID.nil
terminalList = ListId (UUID.fromWords 0 0 0 1)
areaField :: FieldId
areaField = FieldId UUID.nil
areaA, areaB, terminal :: E.RowId
areaA = E.RowId UUID.nil
areaB = E.RowId (UUID.fromWords 0 0 0 1)
terminal = E.RowId (UUID.fromWords 0 0 0 2)
owner :: E.SnapshotKey
owner = E.SnapshotKey UUID.nil UUID.nil

definition :: Definition
definition = Definition 1 []
    [RecordList areaList "Areas" VenueReference [], RecordList terminalList "Terminals" VenueReference [Field areaField "Area" (ReferenceType areaList) Entered]] [] []

references :: ReferenceData
references = ReferenceData
    [ReferenceList areaList [ReferenceRecord areaA False [], ReferenceRecord areaB False []]
    ,ReferenceList terminalList [ReferenceRecord terminal False [(areaField, ReferenceLink (ReferenceKey areaList areaA))]]]

tests :: Spec
tests = describe "Daysheet reference staging" do
    it "round-trips the canonical definition and reference documents" do
        (encodeDefinition definition >>= decodeDefinition) `shouldBe` Right definition
        (encodeReferenceData references >>= decodeReferenceData) `shouldBe` Right references
    it "persists formulas through the flat DSL rather than another expression codec" do
        let calculated = definition { rootFields = [Field (FieldId (UUID.fromWords 0 0 0 3)) "Count" WholeType (Calculated (Binary Add (Constant (WholeLiteral 1)) (Constant (WholeLiteral 2))))] }
        (encodeDefinition calculated >>= decodeDefinition) `shouldBe` Right calculated
    it "shows direct dependants and refuses silent retirement cascades" do
        let target = ReferenceKey areaList areaA
        retirementDependencies references target `shouldBe` [Dependency (ReferenceKey terminalList terminal) areaField]
        retireReferences definition owner references target [] `shouldBe` Left (DanglingActiveReference (ReferenceKey terminalList terminal) areaField target)
    it "requires explicit reassignment and excludes retired entries from new captures" do
        let target = ReferenceKey areaList areaA
        let plan = [ReassignReference (ReferenceKey terminalList terminal) areaField (ReferenceKey areaList areaB)]
        let captured = retireReferences definition owner references target plan >>= captureReferences definition owner
        fmap (fmap Map.keys . Map.lookup areaList . E.savedRows) captured `shouldBe` Right (Just [areaB])
        fmap (fmap Map.keys . Map.lookup areaList . E.savedRows) (captureReferences definition owner references) `shouldBe` Right (Just [areaA, areaB])
    it "allows explicitly retiring the dependent terminal instead" do
        let target = ReferenceKey areaList areaA
        let captured = retireReferences definition owner references target [RetireReference (ReferenceKey terminalList terminal)] >>= captureReferences definition owner
        fmap (Map.size . Map.findWithDefault Map.empty terminalList . E.savedRows) captured `shouldBe` Right 0
    it "round-trips bounded opaque retirement choices and rejects malformed requests" do
        let choices = [KeepReference, ResolveReference (RetireReference (ReferenceKey terminalList terminal)), ResolveReference (ReassignReference (ReferenceKey terminalList terminal) areaField (ReferenceKey areaList areaB))]
        mapM_ (\choice -> parseNominalText (renderNominalText choice) `shouldBe` Right choice) choices
        mapM_ (\raw -> parseNominalText @ReferenceResolution raw `shouldSatisfy` isLeft)
            ["", "{}", "[\"keep\",\"extra\"]", "[\"retire\",\"invalid\",\"invalid\"]"]
    it "accepts only explicit dependency resolutions and rejects conflicting or unrelated edits" do
        let target = ReferenceKey areaList areaA
            dependent = ReferenceKey terminalList terminal
            retire = ResolveReference (RetireReference dependent)
            reassign = ResolveReference (ReassignReference dependent areaField (ReferenceKey areaList areaB))
        retirementEdit references target [KeepReference] `shouldBe` Right (RetireReferenceRecord target [])
        retirementEdit references target [retire, retire] `shouldBe` Right (RetireReferenceRecord target [RetireReference dependent])
        retirementEdit references target [retire, reassign] `shouldBe` Left InvalidReferenceChange
        retirementEdit references target [ResolveReference (ReassignReference dependent areaField target), reassign] `shouldBe` Left InvalidReferenceChange
        retirementEdit references target [reassign, reassign] `shouldBe` retirementEdit references target [reassign]
        retirementEdit references target [ResolveReference (RetireReference (ReferenceKey areaList areaB))] `shouldBe` Left InvalidReferenceChange
        Right edit <- pure (retirementEdit references target [reassign])
        editReferenceData definition owner references edit `shouldSatisfy` either (const False) (const True)
    it "lists indirect dependants without implicitly cascading their retirement" do
        let extraList = ListId (UUID.fromWords 0 0 0 3)
            extraRow = E.RowId (UUID.fromWords 0 0 0 4)
            extraField = FieldId (UUID.fromWords 0 0 0 5)
            target = ReferenceKey areaList areaA
            dependent = ReferenceKey terminalList terminal
            indirect = ReferenceKey extraList extraRow
            ReferenceData lists = references
            expanded = ReferenceData (lists <> [ReferenceList extraList [ReferenceRecord extraRow False [(extraField, ReferenceLink dependent)]]])
            expandedDefinition = definition { recordLists = recordLists definition <> [RecordList extraList "Indirect" VenueReference [Field extraField "Terminal" (ReferenceType terminalList) Entered]] }
        retirementDependants expanded target `shouldBe` [Dependency dependent areaField, Dependency indirect extraField]
        Right incomplete <- pure (retirementEdit expanded target [ResolveReference (RetireReference dependent)])
        editReferenceData expandedDefinition owner expanded incomplete `shouldSatisfy` isLeft
        Right complete <- pure (retirementEdit expanded target (map (ResolveReference . RetireReference) [dependent, indirect]))
        editReferenceData expandedDefinition owner expanded complete `shouldSatisfy` either (const False) (const True)
        let cycle = ReferenceData [ReferenceList areaList [ReferenceRecord areaA False [(areaField, ReferenceLink dependent)]], ReferenceList terminalList [ReferenceRecord terminal False [(areaField, ReferenceLink target)]]]
        retirementDependants cycle target `shouldBe` [Dependency dependent areaField]
    it "keeps incompatible staged values editable but forbids their publication" do
        let changed = definition { recordLists = [RecordList areaList "Areas" VenueReference [], RecordList terminalList "Terminals" VenueReference [Field areaField "Area text" TextType Entered]] }
        (encodeDefinition changed >>= decodeDefinition) `shouldBe` Right changed
        (encodeReferenceData references >>= decodeReferenceData) `shouldBe` Right references
        validateReferences changed owner references `shouldBe` Left (InvalidReferenceValues (E.InvalidInput areaField))
        validateReferences definition owner references `shouldBe` Right ()
    it "repairs staged values individually without accepting new incompatible values" do
        let other = E.RowId (UUID.fromWords 0 0 0 3)
            key = ReferenceKey terminalList terminal
            second = ReferenceKey terminalList other
            changed = definition { recordLists = [RecordList areaList "Areas" VenueReference [], RecordList terminalList "Terminals" VenueReference [Field areaField "Area text" TextType Entered]] }
        Right withRow <- pure (editReferenceData definition owner references (AddReferenceRecord terminalList other))
        Right withOldValues <- pure (editReferenceData definition owner withRow (SetReferenceValue second areaField (Just (ReferenceLink (ReferenceKey areaList areaA)))))
        Right oneFixed <- pure (editReferenceData changed owner withOldValues (SetReferenceValue key areaField (Just (ReferenceScalar (TextLiteral "Inside")))))
        validateReferences changed owner oneFixed `shouldSatisfy` isLeft
        editReferenceData changed owner oneFixed (SetReferenceValue second areaField (Just (ReferenceScalar (WholeLiteral 1)))) `shouldSatisfy` isLeft
        Right repaired <- pure (editReferenceData changed owner oneFixed (SetReferenceValue second areaField (Just (ReferenceScalar (TextLiteral "Outside")))))
        validateReferences changed owner repaired `shouldBe` Right ()
        validateReferences definition owner withOldValues `shouldBe` Right ()

    it "permits explicitly clearing an obsolete staged field but not forging a new one" do
        let changed = definition { recordLists = [RecordList areaList "Areas" VenueReference [], RecordList terminalList "Terminals" VenueReference []] }
            clear = SetReferenceValue (ReferenceKey terminalList terminal) areaField Nothing
        Right repaired <- pure (editReferenceData changed owner references clear)
        validateReferences changed owner repaired `shouldBe` Right ()
        editReferenceData changed owner repaired clear `shouldBe` Left InvalidReferenceChange
        editReferenceData changed owner repaired (SetReferenceValue (ReferenceKey terminalList terminal) areaField (Just (ReferenceScalar (TextLiteral "Forged")))) `shouldSatisfy` isLeft

    it "requires real active destinations and never resurrects retired rows" do
        let target = ReferenceKey areaList areaA
            missing = ReferenceKey areaList (E.RowId (UUID.fromWords 0 0 0 99))
        editReferenceData definition owner references (SetReferenceValue (ReferenceKey terminalList terminal) areaField (Just (ReferenceLink missing))) `shouldBe` Left (MissingReferenceRecord missing)
        Right retired <- pure (editReferenceData definition owner references (RetireReferenceRecord target [ReassignReference (ReferenceKey terminalList terminal) areaField (ReferenceKey areaList areaB)]))
        editReferenceData definition owner retired (AddReferenceRecord areaList areaA) `shouldBe` Left DuplicateReferenceIdentity
        editReferenceData definition owner retired (SetReferenceValue target areaField Nothing) `shouldBe` Left (MissingReferenceRecord target)
        editReferenceData definition owner retired (SetReferenceValue (ReferenceKey terminalList terminal) areaField (Just (ReferenceLink target))) `shouldBe` Left (MissingReferenceRecord target)

    it "rejects reference row creation in daily lists and enforces retained identity limits" do
        let daily = definition { recordLists = recordLists definition <> [RecordList (ListId (UUID.fromWords 0 0 0 9)) "Daily" OpenDaily []] }
            full = ReferenceData [ReferenceList areaList [ReferenceRecord (E.RowId (UUID.fromWords 0 0 1 (fromIntegral n))) True [] | n <- [1 .. maxRowsPerList limits]]]
        editReferenceData daily owner references (AddReferenceRecord (ListId (UUID.fromWords 0 0 0 9)) areaA) `shouldBe` Left (UnknownReferenceList (ListId (UUID.fromWords 0 0 0 9)))
        editReferenceData definition owner full (AddReferenceRecord areaList areaA) `shouldBe` Left ReferenceLimit

    it "rejects duplicate record identities and links into another document" do
        let duplicate = ReferenceData [ReferenceList areaList [ReferenceRecord areaA False [], ReferenceRecord areaA False []]]
        validateReferences definition owner duplicate `shouldBe` Left DuplicateReferenceIdentity
        let missing = ReferenceKey areaList (E.RowId (UUID.fromWords 0 0 0 99))
        let invalid = ReferenceData [ReferenceList terminalList [ReferenceRecord terminal False [(areaField, ReferenceLink missing)]]]
        validateReferences definition owner invalid `shouldBe` Left (DanglingActiveReference (ReferenceKey terminalList terminal) areaField missing)
