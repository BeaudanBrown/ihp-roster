module Test.DaysheetSavedSpec where

import Prelude
import Application.Daysheet.Contract
import qualified Application.Daysheet.Daily as Daily
import qualified Application.Daysheet.Evaluation as E
import qualified Application.Daysheet.Saved as Saved
import qualified Application.Daysheet.Number as Number
import Application.Daysheet.References
import qualified Test.Support.Daysheet as Fixture
import Test.Hspec
import Data.List (find)
import Data.Time (TimeOfDay (..))
import Control.Monad (foldM)

tests :: Spec
tests = describe "Daysheet saved projection" do
    it "recomputes captured calculations and preserves unavailable inputs" do
        Right document <- pure (Daily.emptyDaily Fixture.entryDefinition Fixture.entryReferences Fixture.owner)
        Right saved <- pure (Saved.prepareSaved Fixture.entryDefinition Fixture.entryReferences Fixture.owner document)
        Saved.resultFor saved (E.RootTarget (Fixture.field 16)) `shouldBe` Unavailable (MissingInput (Fixture.field 8))
        Saved.valueText saved (Field (Fixture.field 7) "Terminal" (ReferenceType (Fixture.list 10)) Entered)
            (E.Reference (E.RecordReference Fixture.owner (Fixture.list 10) (Fixture.row 1))) `shouldBe` "Terminal 1"
    it "keeps explicit zero distinct from missing input" do
        Right document <- pure (Fixture.fresh >>= Fixture.save (Daily.RootCell (Fixture.field 2)) 0 (Just (ReferenceScalar (WholeLiteral 0))))
        Right saved <- pure (Saved.prepareSaved Fixture.definition Fixture.references Fixture.owner document)
        Saved.resultFor saved (E.RootTarget (Fixture.field 2)) `shouldBe` Known (E.Scalar (WholeLiteral 0))
        Saved.resultFor saved (E.RootTarget (Fixture.field 1)) `shouldBe` Unavailable (MissingInput (Fixture.field 1))
    it "orders overnight times against the operational day, with blanks last in both directions" do
        let withTime source = source { listFields = map (\f -> if fieldId f == Fixture.field 6 then f { fieldType = OperationalTimeType } else f) (listFields source) }
        let definition = Fixture.definition { recordLists = map withTime (recordLists Fixture.definition) }
        let insert document (n, time) = do
                let key = ReferenceKey (Fixture.list 40) (Fixture.row n)
                added <- Daily.addOpenRow definition Fixture.references Fixture.owner key document
                Daily.saveCell definition Fixture.references Fixture.owner (Daily.RowCell key (Fixture.field 6)) 0
                    (ReferenceScalar . OperationalTimeLiteral <$> time) added
        Right document <- pure (Daily.emptyDaily definition Fixture.references Fixture.owner >>= \initial -> foldM insert initial
            [(60, Just (TimeOfDay 2 0 0)), (61, Just (TimeOfDay 23 0 0)), (62, Just (TimeOfDay 6 0 0)), (63, Nothing)])
        Right saved <- pure (Saved.prepareSaved definition Fixture.references Fixture.owner document)
        Just source <- pure (find ((== Fixture.list 40) . listId) (recordLists definition))
        Saved.tableRows saved source Nothing [(Fixture.field 6, Ascending)] `shouldBe` map Fixture.row [62, 61, 60, 63]
        Saved.tableRows saved source Nothing [(Fixture.field 6, Descending)] `shouldBe` map Fixture.row [60, 61, 62, 63]
    it "keeps exact display without implicit financial rounding" do
        Right third <- pure (Number.number 1 3)
        Right exact <- pure (Number.number 1005 1000)
        Right rate <- pure (Number.number 16 1000)
        Saved.numberText third `shouldBe` "1/3"
        Saved.numberText exact `shouldBe` "1.005"
        Saved.percentageText rate `shouldBe` "1.6"
