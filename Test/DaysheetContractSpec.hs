module Test.DaysheetContractSpec where

import Prelude
import Application.Daysheet.Contract
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
    it "represents per-register surcharge conversion followed by rounding" do
        let expression = do
                rate <- Number.number 16 1000
                inclusive <- Number.number 32 100
                one <- Number.number 1 1
                pure (Unary RoundCents (Binary Divide (Constant (MoneyLiteral inclusive)) (Binary Add (Constant (DecimalLiteral one)) (Unary PercentageRatio (Constant (PercentageLiteral rate))))))
        fmap (expressionType base Nothing) expression `shouldBe` Right (Right MoneyType)
