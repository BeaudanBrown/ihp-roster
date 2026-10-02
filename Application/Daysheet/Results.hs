-- | Small executable result laws for the evaluator. These do not perform
-- record lookup, expression evaluation, or authorization.
module Application.Daysheet.Results
    ( choose
    , combine
    , select
    , sumNumbers
    , divideNumbers
    ) where

import Prelude
import Application.Daysheet.Contract
import qualified Application.Daysheet.Number as Number

choose :: Result Bool -> Result a -> Result a -> Result a
choose (Known True) yes _ = yes
choose (Known False) _ no = no
choose (Unavailable reason) _ _ = Unavailable reason

combine :: (a -> b -> c) -> Result a -> Result b -> Result c
combine operation (Known a) (Known b) = Known (operation a b)
combine _ (Unavailable reason) _ = Unavailable reason
combine _ _ (Unavailable reason) = Unavailable reason

-- | Excluded rows do not demand their values; unknown predicates cannot
-- silently remove rows from a financial aggregate.
select :: [(Result Bool, Result a)] -> Result [a]
select [] = Known []
select ((predicate, value) : rest) = case predicate of
    Unavailable reason -> Unavailable reason
    Known False -> select rest
    Known True -> combine (:) value (select rest)

sumNumbers :: [Result Number.Number] -> Result Number.Number
sumNumbers values = case Number.number 0 1 of
    Left _ -> Unavailable NumericLimit
    Right zero -> go zero values
  where
    go total [] = Known total
    go _ (Unavailable reason : _) = Unavailable reason
    go total (Known value : rest) = case Number.add total value of
        Left _ -> Unavailable NumericLimit
        Right next -> go next rest

divideNumbers :: Result Number.Number -> Result Number.Number -> Result Number.Number
divideNumbers (Unavailable reason) _ = Unavailable reason
divideNumbers _ (Unavailable reason) = Unavailable reason
divideNumbers (Known numerator) (Known denominator) = case Number.divide numerator denominator of
    Right value -> Known value
    Left Number.InvalidDenominator -> Unavailable ZeroDenominator
    Left _ -> Unavailable NumericLimit
