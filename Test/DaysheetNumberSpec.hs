module Test.DaysheetNumberSpec where

import Prelude
import Application.Daysheet.Number
import Application.Daysheet.Contract (Result (..), UnavailableReason (..), FieldId (..))
import qualified Application.Daysheet.Results as Results
import qualified Data.UUID as UUID
import Test.Hspec

-- Construct all fixtures through the same bounded boundary as entered values.
tests :: Spec
tests = describe "Daysheet exact numbers" do
    it "retains intermediate precision until explicit rounding" do
        let result = do
                one <- number 1 1
                three <- number 3 1
                third <- divide one three
                restored <- multiply third three
                roundCents restored
        fmap fraction result `shouldBe` Right (1, 1)
    it "rounds positive and negative half cents away from zero" do
        fmap fraction (number 1005 1000 >>= roundCents) `shouldBe` Right (101, 100)
        fmap fraction (number (-1005) 1000 >>= roundCents) `shouldBe` Right (-101, 100)
    it "rounds each register before summing" do
        let result = do
                inclusive <- number 32 100
                factor <- number 1016 1000
                sales <- divide inclusive factor
                rounded <- roundCents sales
                add rounded rounded
        fmap fraction result `shouldBe` Right (31, 50)
    it "rejects fractional-cent money entry without silently rounding" do
        (number 1005 1000 >>= enteredMoney) `shouldBe` Left MoneyRequiresWholeCents
        fmap fraction (number 20320 100 >>= enteredMoney) `shouldBe` Right (1016, 5)
    it "rejects zero denominators and division by zero" do
        number 1 0 `shouldBe` Left InvalidDenominator
        (do a <- number 1 1; b <- number 0 1; divide a b) `shouldBe` Left InvalidDenominator
    it "bounds inputs and arithmetic results" do
        number (2 ^ (128 :: Int)) 1 `shouldBe` Left NumberLimitExceeded
        number 1 (2 ^ (128 :: Int)) `shouldBe` Left NumberLimitExceeded
        (do a <- number (2 ^ (127 :: Int)) 1; b <- number 2 1; multiply a b)
            `shouldBe` Left NumberLimitExceeded
    it "calculates denomination amounts and coins after float removal" do
        let result = do
                count <- number 3 1
                denomination <- number 20 1
                notes <- multiply count denomination
                coins <- number 750 100
                add notes coins
        fmap fraction result `shouldBe` Right (135, 2)
    it "applies cash expenses and extra cash without changing POS sales" do
        let expectedCash cashIn cashOut = do
                sales <- number 500 1
                incoming <- number cashIn 1
                outgoing <- number cashOut 1
                subtotal <- add sales incoming
                expected <- subtractNumber subtotal outgoing
                pure (fraction sales, fraction expected)
        expectedCash 0 50 `shouldBe` Right ((500, 1), (450, 1))
        expectedCash 20 0 `shouldBe` Right ((500, 1), (520, 1))
    it "uses actual minus expected for shortage and surplus" do
        let variance counted = do
                expected <- number 500 1
                actual <- number counted 1
                subtractNumber actual expected
        fmap fraction (variance 490) `shouldBe` Right (-10, 1)
        fmap fraction (variance 510) `shouldBe` Right (10, 1)
    it "subtracts linked customer cashout once from terminal sales" do
        let actualCard surcharge = do
                receipt <- number 25320 100
                fees <- number surcharge 100
                cashout <- number 50 1
                withoutFees <- subtractNumber receipt fees
                subtractNumber withoutFees cashout
        fmap fraction (actualCard 320) `shouldBe` Right (200, 1)
        fmap fraction (actualCard 0) `shouldBe` Right (1016, 5)
    it "compares independent POS and terminal card figures rather than adding them" do
        let expectedCard = do
                inclusive <- number 20320 100
                factor <- number 1016 1000
                divide inclusive factor >>= roundCents
        fmap fraction expectedCard `shouldBe` Right (200, 1)
    it "keeps sales breakdown separate from the cash shortage" do
        let breakdown = do
                headline <- number 1000 1
                kitchen <- number 300 1
                tickets <- number 100 1
                withoutKitchen <- subtractNumber headline kitchen
                bar <- subtractNumber withoutKitchen tickets
                pure (fraction headline, fraction bar)
        breakdown `shouldBe` Right ((1000, 1), (600, 1))
    it "distinguishes empty sums, missing counts and zero denominators" do
        let missing = MissingInput (FieldId UUID.nil)
        let empty = Results.sumNumbers []
        fmap fraction (case empty of Known value -> Just value; _ -> Nothing) `shouldBe` Just (0, 1)
        Results.divideNumbers empty empty `shouldBe` Unavailable ZeroDenominator
        Results.divideNumbers empty (Unavailable missing) `shouldBe` Unavailable missing
        Results.sumNumbers [Unavailable missing] `shouldBe` Unavailable missing
    it "never turns missing predicates into excluded rows or advisory passes" do
        let reason = MissingInput (FieldId UUID.nil)
        Results.select [(Unavailable reason, Known (1 :: Int))] `shouldBe` Unavailable reason
        Results.select [(Known False, Unavailable reason :: Result Int)] `shouldBe` Known []
        Results.combine (&&) (Known False) (Unavailable reason) `shouldBe` Unavailable reason
        Results.combine (||) (Known True) (Unavailable reason) `shouldBe` Unavailable reason
        Results.choose (Known True) (Known (1 :: Int)) (Unavailable reason) `shouldBe` Known 1
        Results.choose (Unavailable reason) (Known (1 :: Int)) (Known 2) `shouldBe` Unavailable reason
    it "normalizes signs and exact zero" do
        fmap fraction (number 2 (-4)) `shouldBe` Right (-1, 2)
        fmap fraction (number 0 (-7)) `shouldBe` Right (0, 1)
