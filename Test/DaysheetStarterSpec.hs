module Test.DaysheetStarterSpec where

import Prelude
import Application.Daysheet.Contract
import Application.Daysheet.DefinitionCodec
import qualified Application.Daysheet.Designer as Designer
import Control.Monad (forM_)
import qualified Application.Daysheet.Daily as Daily
import qualified Application.Daysheet.Evaluation as E
import qualified Application.Daysheet.Number as N
import Application.Daysheet.Starter
import Application.Daysheet.References
import Application.Daysheet.Validation (validateDefinition)
import qualified Data.Map.Strict as Map
import Data.List (find)
import Data.Text (Text)
import qualified Data.UUID as UUID
import Test.Hspec

template :: (Definition, ReferenceData)
template = either (error . show) id starterTemplate

definition :: Definition
definition = fst template

source :: Text -> RecordList
source label = maybe (error "Missing starter list") id (find ((== label) . listLabel) (recordLists definition))

column :: Text -> Text -> FieldId
column label heading = fieldId (maybe (error (show (label, heading))) id (find ((== heading) . fieldLabel) (listFields (source label))))

rootColumn :: Text -> FieldId
rootColumn heading = fieldId (maybe (error (show heading)) id (find ((== heading) . fieldLabel) (rootFields definition)))

number :: Integer -> Integer -> N.Number
number a b = either (error . show) id (N.number a b)

baseline :: E.Snapshot
baseline = either (error . show) fill do
    document <- Daily.emptyDaily definition (snd template) owner
    Daily.dailySnapshot definition (snd template) owner document
  where
    owner = E.SnapshotKey UUID.nil UUID.nil
    fill snapshot = snapshot { E.savedRows = foldr fillList (E.savedRows snapshot) (recordLists definition) }
    fillList entry rows = case listMode entry of
        VenueReference -> rows
        _ -> Map.adjust (Map.map (\values -> foldr fillField values (listFields entry))) (listId entry) rows
    fillField entry values = case (fieldSource entry, fieldType entry) of
        (Entered, MoneyType) -> Map.insert (fieldId entry) (E.Scalar (MoneyLiteral (number 0 1))) values
        (Entered, WholeType) -> Map.insert (fieldId entry) (E.Scalar (WholeLiteral 0)) values
        _ -> values

firstRow :: Text -> E.RowId
firstRow label = case Map.keys (E.savedRows baseline Map.! listId (source label)) of
    key : _ -> key
    [] -> error "Starter checklist unexpectedly empty"

setCell :: Text -> E.RowId -> Text -> Literal -> E.Snapshot -> E.Snapshot
setCell label identity heading value snapshot = snapshot { E.savedRows = Map.adjust
    (Map.adjust (Map.insert (column label heading) (E.Scalar value)) identity) (listId (source label)) (E.savedRows snapshot) }

result :: E.Snapshot -> E.Target -> Either E.EvaluationError [Result E.Value]
result snapshot target = E.prepareEvaluation definition snapshot >>= \ready -> E.evaluate ready [target]

knownMoney :: Integer -> Integer -> Either E.EvaluationError [Result E.Value]
knownMoney a b = Right [Known (E.Scalar (MoneyLiteral (number a b)))]

-- Follow the captured reference relationships instead of relying on example
-- row names, ordering or a one-terminal fixture.
registerRow :: E.RowId
registerRow = firstRow "POS readings"

areaReference :: E.Value
areaReference = E.savedRows baseline Map.! listId (source "POS registers") Map.! registerRow Map.! column "POS registers" "Area"

areaRow :: E.RowId
areaRow = case areaReference of
    E.Reference (E.RecordReference _ _ key) -> key
    _ -> error "Missing area reference"

terminalRow :: E.RowId
terminalRow = case [key | (key, values) <- Map.toList (E.savedRows baseline Map.! listId (source "Terminals")), Map.lookup (column "Terminals" "Area") values == Just areaReference] of
    key : _ -> key
    [] -> error "Missing matching terminal"

withMovement :: Text -> Integer -> E.Snapshot -> E.Snapshot
withMovement kind amount snapshot = snapshot { E.savedRows = Map.insert (listId (source "Cash in / cash out")) (Map.singleton (E.RowId (UUID.fromWords 0 0 0 888)) values) (E.savedRows snapshot) }
  where
    selected = case [choiceId option | declared <- listFields (source "Cash in / cash out"), ChoiceType options <- [fieldType declared], option <- options, choiceLabel option == kind] of
        key : _ -> key
        [] -> error "Missing movement choice"
    entries = [("Movement type", E.Scalar (ChoiceLiteral selected)), ("Amount", E.Scalar (MoneyLiteral (number amount 1)))]
        <> if kind == "Customer cashout" then [("Terminal (customer cashout)", E.Reference (E.RecordReference (E.snapshotKey snapshot) (listId (source "Terminals")) terminalRow))]
            else [("Area (cash-in / expenses)", areaReference)]
    values = Map.fromList [(column "Cash in / cash out" label, value) | (label, value) <- entries]

areaResult :: E.Snapshot -> Text -> Either E.EvaluationError [Result E.Value]
areaResult snapshot label = result snapshot (E.RowTarget (listId (source "Area cash counts and reconciliation")) areaRow (column "Area cash counts and reconciliation" label))

tests :: Spec
tests = describe "Daysheet starter template" do
    it "validates and round-trips entirely through public definition and reference contracts" do
        validateDefinition definition `shouldBe` Right ()
        (encodeDefinition definition >>= decodeDefinition) `shouldBe` Right definition
        validateReferences definition (E.SnapshotKey UUID.nil UUID.nil) (snd template) `shouldBe` Right ()
        Map.size (E.savedRows baseline Map.! listId (source "Terminal Receipts")) `shouldBe` 8
    it "accepts every calculation fragment through the public revision-bound edit algebra" do
        let visit key path expression = do
                (Designer.calculationPartEdit key path expression definition >>= (\edit -> Designer.applyEdit edit definition)) `shouldBe` Right definition
                forM_ (Designer.calculationChildren expression) \(slot, child) -> visit key (path <> [slot]) child
        forM_ (rootFields definition <> concatMap listFields (recordLists definition)) \declared ->
            case fieldSource declared of
                Entered -> pure ()
                Calculated expression -> visit (fieldId declared) [] expression
    it "calculates note amounts and coins after float removal" do
        let key = firstRow "Area cash counts and reconciliation"
        let snapshot = setCell "Area cash counts and reconciliation" key "$20 notes — count" (WholeLiteral 3)
                (setCell "Area cash counts and reconciliation" key "Coins total (after float removal)" (MoneyLiteral (number 750 100)) baseline)
        result snapshot (E.RowTarget (listId (source "Area cash counts and reconciliation")) key (column "Area cash counts and reconciliation" "Counted cash (after float removal)")) `shouldBe` knownMoney 6750 100
    it "rounds each register before summing, independently of terminal receipts" do
        let keys = take 2 (Map.keys (E.savedRows baseline Map.! listId (source "POS readings")))
        let snapshot = foldr (\key -> setCell "POS readings" key "POS card including surcharge" (MoneyLiteral (number 32 100))) baseline keys
        result snapshot (E.RootTarget (rootColumn "Expected card sales")) `shouldBe` knownMoney 62 100
        result snapshot (E.RootTarget (rootColumn "Actual card sales")) `shouldBe` knownMoney 0 1
    it "keeps POS sales and kitchen/ticket/bar breakdown separate from cash shortages" do
        let key = firstRow "POS readings"
        let snapshot = setCell "POS readings" key "POS-recorded sales" (MoneyLiteral (number 1000 1))
                (setCell "POS readings" key "Kitchen sales" (MoneyLiteral (number 300 1))
                (setCell "POS readings" key "Ticket sales" (MoneyLiteral (number 100 1))
                (setCell "POS readings" key "POS cash sales" (MoneyLiteral (number 10 1)) baseline)))
        result snapshot (E.RootTarget (rootColumn "POS-recorded sales")) `shouldBe` knownMoney 1000 1
        result snapshot (E.RootTarget (rootColumn "Bar sales")) `shouldBe` knownMoney 600 1
        result snapshot (E.RootTarget (rootColumn "Cash variance — actual minus expected")) `shouldBe` knownMoney (-10) 1
    it "subtracts linked cashout exactly once from cash and terminal card, independently of POS card" do
        let snapshot = withMovement "Customer cashout" 50
                (setCell "POS readings" registerRow "POS cash sales" (MoneyLiteral (number 500 1))
                (setCell "POS readings" registerRow "POS card including surcharge" (MoneyLiteral (number 20320 100))
                (setCell "Terminal Receipts" terminalRow "Terminal receipt total" (MoneyLiteral (number 25320 100))
                (setCell "Terminal Receipts" terminalRow "Actual reported surcharge" (MoneyLiteral (number 320 100))
                (setCell "Area cash counts and reconciliation" areaRow "Coins total (after float removal)" (MoneyLiteral (number 450 1)) baseline)))))
        areaResult snapshot "Expected counted cash" `shouldBe` knownMoney 450 1
        areaResult snapshot "Cash variance — actual minus expected" `shouldBe` knownMoney 0 1
        result snapshot (E.RootTarget (rootColumn "Expected card sales")) `shouldBe` knownMoney 200 1
        result snapshot (E.RootTarget (rootColumn "Actual card sales")) `shouldBe` knownMoney 200 1
        let cleared = snapshot { E.savedRows = Map.adjust (Map.adjust (Map.delete (column "Terminal Receipts" "Actual reported surcharge")) terminalRow) (listId (source "Terminal Receipts")) (E.savedRows snapshot) }
        result cleared (E.RootTarget (rootColumn "Actual card sales")) `shouldBe` Right [Unavailable (MissingInput (column "Terminal Receipts" "Actual reported surcharge"))]
        result (setCell "Terminal Receipts" terminalRow "Actual reported surcharge" (MoneyLiteral (number 0 1)) snapshot) (E.RootTarget (rootColumn "Actual card sales")) `shouldBe` knownMoney 20320 100
    it "handles cash-in and expenses without requiring a terminal or changing POS sales" do
        let original = setCell "POS readings" registerRow "POS cash sales" (MoneyLiteral (number 500 1))
                (setCell "POS readings" registerRow "POS-recorded sales" (MoneyLiteral (number 500 1)) baseline)
        areaResult (withMovement "Cash-in" 20 original) "Expected counted cash" `shouldBe` knownMoney 520 1
        areaResult (withMovement "Cash-out / expense" 50 original) "Expected counted cash" `shouldBe` knownMoney 450 1
        result (withMovement "Cash-out / expense" 50 original) (E.RootTarget (rootColumn "POS-recorded sales")) `shouldBe` knownMoney 500 1
        areaResult original "Cash-out including customer cashout" `shouldBe` knownMoney 0 1
    it "labels actual-minus-expected cash shortages and surpluses explicitly" do
        let original = setCell "POS readings" registerRow "POS cash sales" (MoneyLiteral (number 500 1)) baseline
        let count amount = setCell "Area cash counts and reconciliation" areaRow "Coins total (after float removal)" (MoneyLiteral (number amount 1)) original
        areaResult (count 490) "Cash result" `shouldBe` Right [Known (E.Scalar (TextLiteral "Shortage"))]
        areaResult (count 510) "Cash result" `shouldBe` Right [Known (E.Scalar (TextLiteral "Surplus"))]
        areaResult (count 490) "Cash variance — actual minus expected" `shouldBe` knownMoney (-10) 1
        areaResult (count 510) "Cash variance — actual minus expected" `shouldBe` knownMoney 10 1
    it "keeps intermediate precision and rounds half-cent ties through editable starter formulas" do
        let key = column "POS readings" "Expected card sales, rounded per register"
        let money amount = Constant (MoneyLiteral amount)
        let evaluateVariant expression = do
                edit <- either (error . show) pure (Designer.calculationPartEdit key [] expression definition)
                changed <- either (error . show) pure (Designer.applyEdit edit definition)
                ready <- either (error . show) pure (E.prepareEvaluation changed baseline)
                pure (E.evaluate ready [E.RowTarget (listId (source "POS readings")) registerRow key])
        evaluateVariant (Unary RoundCents (Binary Multiply (Binary Divide (money (number 1 1)) (Constant (WholeLiteral 3))) (Constant (WholeLiteral 3)))) `shouldReturn` knownMoney 1 1
        evaluateVariant (Unary RoundCents (Binary Divide (money (number 201 100)) (Constant (WholeLiteral 2)))) `shouldReturn` knownMoney 101 100
        evaluateVariant (Unary RoundCents (Binary Divide (money (number (-201) 100)) (Constant (WholeLiteral 2)))) `shouldReturn` knownMoney (-101) 100
    it "reports advisory pass, concern and unavailable over the starter's own condition" do
        let declared = case [advisory | Section _ _ blocks <- entryLayout definition, RowAdvisoryBlock key advisory <- blocks, key == listId (source "Area cash counts and reconciliation")] of
                advisory : _ -> advisory
                [] -> error "Missing starter cash advisory"
        let original = setCell "POS readings" registerRow "POS cash sales" (MoneyLiteral (number 500 1)) baseline
        let count amount = setCell "Area cash counts and reconciliation" areaRow "Coins total (after float removal)" (MoneyLiteral (number amount 1)) original
        let evaluateCheck snapshot = E.prepareEvaluation definition snapshot >>= \ready -> E.evaluateAdvisory ready (Just (listId (source "Area cash counts and reconciliation"), areaRow)) declared
        evaluateCheck (count 503) `shouldBe` Right (Passed (passedMessage declared))
        evaluateCheck (count 475) `shouldBe` Right (Concern (concernMessage declared))
        let missing = original { E.savedRows = Map.adjust (Map.adjust (Map.delete (column "Area cash counts and reconciliation" "Coins total (after float removal)")) areaRow) (listId (source "Area cash counts and reconciliation")) (E.savedRows original) }
        evaluateCheck missing `shouldBe` Right (NotEvaluated (MissingInput (column "Area cash counts and reconciliation" "Coins total (after float removal)")))
    it "leaves missing and zero customer counts unavailable rather than reporting zero averages" do
        let key = firstRow "POS readings"
        result baseline (E.RowTarget (listId (source "POS readings")) key (column "POS readings" "Expected card sales, rounded per register")) `shouldBe` knownMoney 0 1
        result baseline (E.RootTarget (rootColumn "Average spend")) `shouldBe` Right [Unavailable ZeroDenominator]
        let missing = baseline { E.savedRows = Map.adjust (Map.adjust (Map.delete (column "POS readings" "Customer count")) key) (listId (source "POS readings")) (E.savedRows baseline) }
        result missing (E.RootTarget (rootColumn "Average spend")) `shouldBe` Right [Unavailable (MissingInput (column "POS readings" "Customer count"))]
