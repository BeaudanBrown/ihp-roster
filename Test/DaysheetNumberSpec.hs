module Test.DaysheetNumberSpec where

import Prelude
import Application.Daysheet.Number
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
    it "normalizes signs and exact zero" do
        fmap fraction (number 2 (-4)) `shouldBe` Right (-1, 2)
        fmap fraction (number 0 (-7)) `shouldBe` Right (0, 1)
