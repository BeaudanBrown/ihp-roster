module Test.DaysheetEvaluationSpec where

import Prelude
import Application.Daysheet.Contract
import qualified Application.Daysheet.Evaluation as E
import qualified Application.Daysheet.Number as N
import Application.Daysheet.Validation (ContractError (..))
import Control.Monad (forM_)
import qualified Data.Map.Strict as Map
import Data.Time (TimeOfDay (..))
import qualified Data.UUID as UUID
import Data.Word (Word32)
import Test.Hspec

key :: Word32 -> FieldId
key n = FieldId (UUID.fromWords 0 0 0 n)

number :: Integer -> Integer -> N.Number
number n d = either (error . show) id (N.number n d)

money :: Integer -> Integer -> Expression
money n d = Constant (MoneyLiteral (number n d))

whole :: Integer -> Expression
whole = Constant . WholeLiteral

emptySnapshot :: E.Snapshot
emptySnapshot = E.Snapshot (E.SnapshotKey UUID.nil UUID.nil) Map.empty Map.empty

base :: Definition
base = Definition 1 [] [] [] []

runExpression :: FieldType -> Expression -> Either E.EvaluationError [Result E.Value]
runExpression t expression = do
    evaluation <- E.prepareEvaluation (base { rootFields = [Field (key 1) "Result" t (Calculated expression)] }) emptySnapshot
    E.evaluate evaluation [E.RootTarget (key 1)]

knownMoney :: Integer -> Integer -> Either E.EvaluationError [Result E.Value]
knownMoney n d = Right [Known (E.Scalar (MoneyLiteral (number n d)))]

tests :: Spec
tests = describe "Daysheet server evaluation" do
    it "reads preserved checklist records in row and aggregate contexts without editable links" do
        let source = ListId (UUID.fromWords 0 0 0 10)
        let checklist = ListId (UUID.fromWords 0 0 0 11)
        let row = E.RowId (UUID.fromWords 0 0 0 12)
        let definition = base
                { contractVersion = 2
                , rootFields = [Field (key 5) "Selected terminal" (ReferenceType source) Entered,
                    Field (key 4) "Matching receipts" WholeType (Calculated (Fold Count checklist (Just (Binary Equal (ChecklistReference Item) (ReadField (FieldPath Root [key 5])))) (whole 1)))]
                , recordLists = [RecordList source "Terminals" VenueReference [Field (key 1) "Label" TextType Entered],
                    RecordList checklist "Receipts" (ReferenceChecklist source)
                        [Field (key 2) "Terminal" (ReferenceType source) (Calculated (ChecklistReference Current)),
                         Field (key 3) "Terminal label" TextType (Calculated (ReadField (FieldPath Current [key 2, key 1])))]] }
        let reference = E.Reference (E.RecordReference (E.snapshotKey emptySnapshot) source row)
        let snapshot = emptySnapshot
                { E.savedRoot = Map.singleton (key 5) reference
                , E.savedRows = Map.fromList [(source, Map.singleton row (Map.singleton (key 1) (E.Scalar (TextLiteral "Preserved terminal")))), (checklist, Map.singleton row Map.empty)] }
        let evaluate saved = E.prepareEvaluation definition saved >>= \ready -> E.evaluate ready [E.RowTarget checklist row (key 2), E.RowTarget checklist row (key 3), E.RootTarget (key 4)]
        evaluate snapshot `shouldBe` Right [Known reference, Known (E.Scalar (TextLiteral "Preserved terminal")), Known (E.Scalar (WholeLiteral 1))]
        evaluate (snapshot { E.savedRows = Map.delete source (E.savedRows snapshot) }) `shouldBe`
            Right [Unavailable MissingChecklistReference, Unavailable MissingChecklistReference, Unavailable MissingChecklistReference]
        let override = snapshot { E.savedRows = Map.insert checklist (Map.singleton row (Map.singleton (key 2) reference)) (E.savedRows snapshot) }
        either Just (const Nothing) (E.prepareEvaluation definition override) `shouldBe` Just (E.CalculatedInput (key 2))
    it "preserves money precision and applies explicit half-away rounding" do
        runExpression MoneyType (Unary RoundCents (Binary Multiply (Binary Divide (money 1 1) (whole 3)) (whole 3))) `shouldBe` knownMoney 1 1
        runExpression MoneyType (Unary RoundCents (Binary Divide (money 201 100) (whole 2))) `shouldBe` knownMoney 101 100
        runExpression MoneyType (Unary RoundCents (Binary Divide (money (-201) 100) (whole 2))) `shouldBe` knownMoney (-101) 100
    it "removes surcharge before rounding each register and summing" do
        let factor = Binary Add (Constant (DecimalLiteral (number 1 1))) (Unary PercentageRatio (Constant (PercentageLiteral (number 16 1000))))
        let register = Unary RoundCents (Binary Divide (money 32 100) factor)
        runExpression MoneyType (Binary Add register register) `shouldBe` knownMoney 62 100
        runExpression MoneyType (Unary RoundCents (Binary Divide (money 20320 100) factor)) `shouldBe` knownMoney 200 1
    it "evaluates denomination counts, movements, terminal actuals and sales breakdown independently" do
        runExpression MoneyType (Binary Add (Binary Multiply (whole 3) (money 20 1)) (money 750 100)) `shouldBe` knownMoney 6750 100
        runExpression MoneyType (Binary Subtract (money 500 1) (money 50 1)) `shouldBe` knownMoney 450 1
        runExpression MoneyType (Binary Add (money 500 1) (money 20 1)) `shouldBe` knownMoney 520 1
        runExpression MoneyType (Binary Subtract (Binary Subtract (money 25320 100) (money 320 100)) (money 50 1)) `shouldBe` knownMoney 200 1
        runExpression MoneyType (Binary Subtract (Binary Subtract (money 1000 1) (money 300 1)) (money 100 1)) `shouldBe` knownMoney 600 1
    it "keeps missing surcharge distinct from explicit zero" do
        let expression = Binary Subtract (Binary Subtract (money 25320 100) (ReadField (FieldPath Root [key 2]))) (money 50 1)
        let definition = base { rootFields = [Field (key 1) "Sales" MoneyType (Calculated expression), Field (key 2) "Surcharge" MoneyType Entered] }
        let run snapshot = E.prepareEvaluation definition snapshot >>= \evaluation -> E.evaluate evaluation [E.RootTarget (key 1)]
        run emptySnapshot `shouldBe` Right [Unavailable (MissingInput (key 2))]
        run (emptySnapshot { E.savedRoot = Map.singleton (key 2) (E.Scalar (MoneyLiteral (number 0 1))) }) `shouldBe` knownMoney 20320 100
    it "does not evaluate unselected branches but propagates Boolean unavailability" do
        let failure = Binary Divide (money 1 1) (whole 0)
        runExpression MoneyType (If (Constant (BooleanLiteral True)) (money 1 1) failure) `shouldBe` knownMoney 1 1
        runExpression MoneyType failure `shouldBe` Right [Unavailable ZeroDenominator]
        let condition = Binary Equal failure (money 1 1)
        runExpression BooleanType (Binary Or (Constant (BooleanLiteral True)) condition) `shouldBe` Right [Unavailable ZeroDenominator]
    it "orders overnight times in the Operational day" do
        runExpression BooleanType (Binary Greater (Constant (OperationalTimeLiteral (TimeOfDay 1 0 0))) (Constant (OperationalTimeLiteral (TimeOfDay 23 0 0))))
            `shouldBe` Right [Known (E.Scalar (BooleanLiteral True))]
    it "rejects calculated overrides, malformed expressions and foreign references" do
        let calculated = base { rootFields = [Field (key 1) "Calculated" MoneyType (Calculated (money 1 1))] }
        let override = emptySnapshot { E.savedRoot = Map.singleton (key 1) (E.Scalar (MoneyLiteral (number 2 1))) }
        fmap (const ()) (E.prepareEvaluation calculated override) `shouldBe` Left (E.CalculatedInput (key 1))
        runExpression MoneyType (Binary Add (money 1 1) (Constant (TextLiteral "script"))) `shouldBe` Left (E.InvalidDefinition IncompatibleTypes)
        let list = ListId UUID.nil
        let definition = base { rootFields = [Field (key 1) "Area" (ReferenceType list) Entered], recordLists = [RecordList list "Areas" VenueReference []] }
        let foreignKey = E.SnapshotKey UUID.nil (UUID.fromWords 0 0 0 1)
        let reference = E.Reference (E.RecordReference foreignKey list (E.RowId UUID.nil))
        fmap (const ()) (E.prepareEvaluation definition (emptySnapshot { E.savedRoot = Map.singleton (key 1) reference })) `shouldBe` Left (E.ForeignReference (key 1))
    it "evaluates filtered sums/counts with empty and unavailable rows" do
        let list = ListId UUID.nil
        let rows = RecordList list "Cash out" OpenDaily [Field (key 2) "Amount" MoneyType Entered, Field (key 3) "Included" BooleanType Entered]
        let definition = base { rootFields = [Field (key 1) "Total" MoneyType (Calculated (Fold Sum list (Just (ReadField (FieldPath Item [key 3]))) (ReadField (FieldPath Item [key 2]))))], recordLists = [rows] }
        let run snapshot = E.prepareEvaluation definition snapshot >>= \evaluation -> E.evaluate evaluation [E.RootTarget (key 1)]
        run emptySnapshot `shouldBe` knownMoney 0 1
        let row = Map.fromList [(key 2, E.Scalar (MoneyLiteral (number 50 1))), (key 3, E.Scalar (BooleanLiteral True))]
        let saved values = emptySnapshot { E.savedRows = Map.singleton list (Map.singleton (E.RowId UUID.nil) values) }
        run (saved row) `shouldBe` knownMoney 50 1
        run (saved (Map.delete (key 3) row)) `shouldBe` Right [Unavailable (MissingInput (key 3))]
        run (saved (Map.singleton (key 3) (E.Scalar (BooleanLiteral False)))) `shouldBe` knownMoney 0 1
        let count = Fold Count list Nothing (ReadField (FieldPath Item [key 2]))
        let averageDefinition = definition { rootFields = [Field (key 1) "Average" MoneyType (Calculated (Binary Divide (Fold Sum list Nothing (ReadField (FieldPath Item [key 2]))) count))] }
        (E.prepareEvaluation averageDefinition emptySnapshot >>= \evaluation -> E.evaluate evaluation [E.RootTarget (key 1)]) `shouldBe` Right [Unavailable ZeroDenominator]
    it "groups daily money through preserved reference identities" do
        let areas = ListId UUID.nil
        let cashouts = ListId (UUID.fromWords 0 0 0 1)
        let areaA = E.RowId UUID.nil
        let areaB = E.RowId (UUID.fromWords 0 0 0 1)
        let reference row = E.Reference (E.RecordReference (E.snapshotKey emptySnapshot) areas row)
        let predicate = Binary Equal (ReadField (FieldPath Item [key 3])) (ReadField (FieldPath Root [key 2]))
        let total = Fold Sum cashouts (Just predicate) (ReadField (FieldPath Item [key 4]))
        let definition = base
                { rootFields = [Field (key 1) "Area total" MoneyType (Calculated total), Field (key 2) "Selected area" (ReferenceType areas) Entered]
                , recordLists = [RecordList areas "Areas" VenueReference [], RecordList cashouts "Cash out" OpenDaily [Field (key 3) "Area" (ReferenceType areas) Entered, Field (key 4) "Amount" MoneyType Entered]]
                }
        let snapshot = emptySnapshot
                { E.savedRoot = Map.singleton (key 2) (reference areaA)
                , E.savedRows = Map.fromList
                    [(areas, Map.fromList [(areaA, Map.empty), (areaB, Map.empty)])
                    ,(cashouts, Map.fromList [(areaA, Map.fromList [(key 3, reference areaA), (key 4, E.Scalar (MoneyLiteral (number 50 1)))]), (areaB, Map.fromList [(key 3, reference areaB), (key 4, E.Scalar (MoneyLiteral (number 20 1)))])])]
                }
        (E.prepareEvaluation definition snapshot >>= \evaluation -> E.evaluate evaluation [E.RootTarget (key 1)]) `shouldBe` knownMoney 50 1
        let missing = snapshot { E.savedRows = Map.adjust (Map.delete areaA) areas (E.savedRows snapshot) }
        (E.prepareEvaluation definition missing >>= \evaluation -> E.evaluate evaluation [E.RootTarget (key 1)]) `shouldBe` Right [Unavailable (MissingReference (key 3))]
    it "rejects foreign venues, excessive row counts and invalid operational times" do
        let list = ListId UUID.nil
        let definition = base { rootFields = [Field (key 1) "Area" (ReferenceType list) Entered], recordLists = [RecordList list "Areas" VenueReference []] }
        let reference = E.Reference (E.RecordReference (E.SnapshotKey (UUID.fromWords 0 0 0 1) UUID.nil) list (E.RowId UUID.nil))
        fmap (const ()) (E.prepareEvaluation definition (emptySnapshot { E.savedRoot = Map.singleton (key 1) reference })) `shouldBe` Left (E.ForeignReference (key 1))
        let rows = Map.fromList [(E.RowId (UUID.fromWords 0 0 0 (fromIntegral n)), Map.empty) | n <- [0..maxRowsPerList limits]]
        fmap (const ()) (E.prepareEvaluation definition (emptySnapshot { E.savedRows = Map.singleton list rows })) `shouldBe` Left E.SnapshotLimit
        runExpression OperationalTimeType (Constant (OperationalTimeLiteral (TimeOfDay 25 0 0))) `shouldBe` Left (E.InvalidDefinition InvalidLiteral)
    it "produces three advisory outcomes from saved source values" do
        let definition = base { rootFields = [Field (key 1) "Variance" MoneyType Entered] }
        let advisory = Advisory (Binary LessOrEqual (Unary Absolute (ReadField (FieldPath Root [key 1]))) (money 10 1)) "Within tolerance" "Outside tolerance"
        let check snapshot = E.prepareEvaluation definition snapshot >>= \evaluation -> E.evaluateAdvisory evaluation Nothing advisory
        check emptySnapshot `shouldBe` Right (NotEvaluated (MissingInput (key 1)))
        check (emptySnapshot { E.savedRoot = Map.singleton (key 1) (E.Scalar (MoneyLiteral (number 3 1))) }) `shouldBe` Right (Passed "Within tolerance")
        check (emptySnapshot { E.savedRoot = Map.singleton (key 1) (E.Scalar (MoneyLiteral (number (-25) 1))) }) `shouldBe` Right (Concern "Outside tolerance")
    it "bounds exponential dependency work independently from expression depth" do
        let field n = Field (key n) "Double" MoneyType (Calculated (if n == 1 then money 1 1 else Binary Add (ReadField (FieldPath Root [key (n - 1)])) (ReadField (FieldPath Root [key (n - 1)]))))
        let definition = base { rootFields = map field [1..21] }
        (E.prepareEvaluation definition emptySnapshot >>= \evaluation -> E.evaluate evaluation [E.RootTarget (key 21)]) `shouldBe` Right [Unavailable EvaluationLimit]
    it "preserves divide/multiply identity over representative signed whole-cent inputs" do
        forM_ [-20..20] \n -> forM_ [1..7] \d ->
            runExpression MoneyType (Unary RoundCents (Binary Multiply (Binary Divide (money n 100) (whole d)) (whole d))) `shouldBe` knownMoney n 100
