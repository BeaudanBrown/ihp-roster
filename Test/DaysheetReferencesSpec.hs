module Test.DaysheetReferencesSpec where

import Prelude
import Application.Daysheet.Contract
import Application.Daysheet.DefinitionCodec
import Application.Daysheet.ReferenceCodec
import Application.Daysheet.References
import qualified Application.Daysheet.Evaluation as E
import qualified Data.Map.Strict as Map
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
    it "keeps incompatible staged values editable but forbids their publication" do
        let changed = definition { recordLists = [RecordList areaList "Areas" VenueReference [], RecordList terminalList "Terminals" VenueReference [Field areaField "Area text" TextType Entered]] }
        (encodeDefinition changed >>= decodeDefinition) `shouldBe` Right changed
        (encodeReferenceData references >>= decodeReferenceData) `shouldBe` Right references
        validateReferences changed owner references `shouldBe` Left (InvalidReferenceValues (E.InvalidInput areaField))
        validateReferences definition owner references `shouldBe` Right ()
    it "rejects duplicate record identities and links into another document" do
        let duplicate = ReferenceData [ReferenceList areaList [ReferenceRecord areaA False [], ReferenceRecord areaA False []]]
        validateReferences definition owner duplicate `shouldBe` Left DuplicateReferenceIdentity
        let missing = ReferenceKey areaList (E.RowId (UUID.fromWords 0 0 0 99))
        let invalid = ReferenceData [ReferenceList terminalList [ReferenceRecord terminal False [(areaField, ReferenceLink missing)]]]
        validateReferences definition owner invalid `shouldBe` Left (DanglingActiveReference (ReferenceKey terminalList terminal) areaField missing)
