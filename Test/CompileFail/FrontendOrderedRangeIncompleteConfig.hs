{-# LANGUAGE DataKinds        #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators    #-}

module Test.CompileFail.FrontendOrderedRangeIncompleteConfig where

import qualified Application.Helper.FrontendContract.OrderedRange as OrderedRange
import Application.Helper.FrontendContract.Wire.Carrier
import IHP.Prelude

incompleteOrderedRangeConfig =
    recordValue @OrderedRange.OrderedRangeConfig
        ( requiredField @OrderedRange.MinimumValue (5 :: Int)
            &: requiredField @OrderedRange.MaximumValue (23 :: Int)
            &: requiredField @OrderedRange.StepValue (1 :: Int)
            &: requiredField @OrderedRange.DefaultStartValue (9 :: Int)
            &: requiredField @OrderedRange.DefaultEndValue (17 :: Int)
            &: requiredField @OrderedRange.ValueLabels (["5 AM"] :: [Text])
            &: noFields
        )
