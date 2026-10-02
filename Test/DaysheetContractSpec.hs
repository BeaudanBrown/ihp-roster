module Test.DaysheetContractSpec where

import Prelude
import Application.Daysheet.Contract
import Application.Daysheet.Formula
import Application.Daysheet.Wire
import Application.Daysheet.Validation
import qualified Application.Daysheet.Number as Number
import qualified Data.UUID as UUID
import Test.Hspec

fieldKey :: FieldId
fieldKey = FieldId UUID.nil

base :: Definition
base = Definition 1 [] [] [] []

tests :: Spec
tests = describe "Daysheet definition contract" do
    it "keeps money distinct from text and ordinary decimals" do
        binaryType Add MoneyType TextType `shouldBe` Left IncompatibleTypes
        binaryType Add MoneyType DecimalType `shouldBe` Left IncompatibleTypes
        binaryType Multiply MoneyType WholeType `shouldBe` Right MoneyType
        binaryType Divide MoneyType WholeType `shouldBe` Right MoneyType
        unaryType PercentageRatio PercentageType `shouldBe` Right DecimalType
    it "rejects unknown contract versions" do
        validateFields (base { contractVersion = 2 }) `shouldBe` Left UnsupportedVersion
    it "rejects deleted field references and cycles" do
        let formula = ReadField (FieldPath Root [fieldKey])
        expressionType base Nothing formula `shouldBe` Left (UnknownField fieldKey)
        let definition = base { rootFields = [Field fieldKey "Self" MoneyType (Calculated formula)] }
        validateFields definition `shouldBe` Left (CyclicFields [fieldKey])
    it "rejects duplicate identities before inference" do
        let field = Field fieldKey "Value" TextType Entered
        validateFields (base { rootFields = [field, field] }) `shouldBe` Left (DuplicateField fieldKey)
    it "checks both conditional branches rather than trusting unused code" do
        let expression = If (Constant (BooleanLiteral True)) (Constant (WholeLiteral 1)) (Constant (TextLiteral "unsafe"))
        expressionType base Nothing expression `shouldBe` Left IncompatibleTypes
    it "bounds expression nesting" do
        let expression = iterate (Unary Negate) (Constant (WholeLiteral 1)) !! maxExpressionDepth limits
        expressionType base Nothing expression `shouldBe` Left ResourceLimit
    it "does not expose another day's record identity in a reference expression" do
        expressionType base Nothing (ReadField (FieldPath Current [fieldKey])) `shouldBe` Left InvalidContext
    it "has three advisory outcomes and retains unavailable reasons" do
        let check = Advisory (Constant (BooleanLiteral True)) "Within tolerance" "Outside tolerance"
        advisoryResult check (Known True) `shouldBe` Passed "Within tolerance"
        advisoryResult check (Known False) `shouldBe` Concern "Outside tolerance"
        advisoryResult check (Unavailable (MissingInput fieldKey)) `shouldBe` NotEvaluated (MissingInput fieldKey)
    it "decodes only the DSL's exact flat formula envelope" do
        decodeFormula base Nothing "{\"rootNode\":0,\"nodes\":[{\"nodeId\":0,\"step\":{\"tag\":\"literal-step\",\"literalValue\":{\"tag\":\"whole-value\",\"value\":\"1\"}}}]}"
            `shouldBe` Right (Constant (WholeLiteral 1))
        decodeFormula base Nothing "{\"rootNode\":0,\"nodes\":[],\"script\":\"arbitrary code\"}"
            `shouldBe` Left InvalidFormulaPayload
        decodeFormula base Nothing "{\"rootNode\":0,\"nodes\":[{\"nodeId\":0,\"step\":{\"tag\":\"unary-step\",\"operator\":\"eval\",\"childNode\":0}}]}"
            `shouldBe` Left InvalidFormulaPayload
    it "compiles a linked DSL formula without a second operator vocabulary" do
        let formula = Formula (NodeId 2)
                [(NodeId 0, LiteralStep (WholeLiteral 1)), (NodeId 1, LiteralStep (WholeLiteral 2)), (NodeId 2, BinaryStep Add (NodeId 0) (NodeId 1))]
        compileFormula base Nothing formula `shouldBe` Right (Binary Add (Constant (WholeLiteral 1)) (Constant (WholeLiteral 2)))
    it "rejects missing, duplicate, unreachable and cyclic formula nodes" do
        compileFormula base Nothing (Formula (NodeId 0) []) `shouldBe` Left (MissingNode (NodeId 0))
        let literal = (NodeId 0, LiteralStep (WholeLiteral 1))
        compileFormula base Nothing (Formula (NodeId 0) [literal, literal]) `shouldBe` Left (DuplicateNodeId (NodeId 0))
        compileFormula base Nothing (Formula (NodeId 0) [literal, (NodeId 1, LiteralStep (WholeLiteral 2))]) `shouldBe` Left UnreachableNodes
        compileFormula base Nothing (Formula (NodeId 0) [(NodeId 0, UnaryStep Negate (NodeId 0))]) `shouldBe` Left (FormulaCycle (NodeId 0))
    it "bounds graph expansion, not just the number of stored nodes" do
        let steps = (NodeId 0, LiteralStep (WholeLiteral 1)) : [(NodeId n, BinaryStep Add (NodeId (n - 1)) (NodeId (n - 1))) | n <- [1..12]]
        compileFormula base Nothing (Formula (NodeId 12) steps) `shouldBe` Left ExpandedFormulaTooLarge
    it "rejects forged incompatible linked operations" do
        let formula = Formula (NodeId 1) [(NodeId 0, LiteralStep (TextLiteral "not money")), (NodeId 1, UnaryStep RoundCents (NodeId 0))]
        compileFormula base Nothing formula `shouldBe` Left (FormulaTypeError IncompatibleTypes)
    it "represents per-register surcharge conversion followed by rounding" do
        let expression = do
                rate <- Number.number 16 1000
                inclusive <- Number.number 32 100
                one <- Number.number 1 1
                pure (Unary RoundCents (Binary Divide (Constant (MoneyLiteral inclusive)) (Binary Add (Constant (DecimalLiteral one)) (Unary PercentageRatio (Constant (PercentageLiteral rate))))))
        fmap (expressionType base Nothing) expression `shouldBe` Right (Right MoneyType)
