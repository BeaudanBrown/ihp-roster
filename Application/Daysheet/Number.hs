-- | Exact, bounded arithmetic shared by the Daysheet contract and evaluator.
-- No floating point or implicit monetary rounding crosses this boundary.
module Application.Daysheet.Number
    ( Number
    , NumberError (..)
    , number
    , fraction
    , add
    , subtractNumber
    , multiply
    , divide
    , roundCents
    , enteredMoney
    ) where

import Prelude
import Data.Ratio ((%), denominator, numerator)

newtype Number = Number Rational deriving (Eq, Ord, Show)

data NumberError = InvalidDenominator | NumberLimitExceeded | MoneyRequiresWholeCents
    deriving (Eq, Show)

-- | Bound both components to 128 bits. Binary operations on validated numbers
-- allocate at most 256-bit intermediates before reduction and revalidation.
componentLimit :: Integer
componentLimit = 2 ^ (128 :: Int) - 1

number :: Integer -> Integer -> Either NumberError Number
number n d
    | d == 0 = Left InvalidDenominator
    | abs n > componentLimit || abs d > componentLimit = Left NumberLimitExceeded
    | otherwise = bounded (n % d)

bounded :: Rational -> Either NumberError Number
bounded value
    | abs (numerator value) > componentLimit || denominator value > componentLimit = Left NumberLimitExceeded
    | otherwise = Right (Number value)

fraction :: Number -> (Integer, Integer)
fraction (Number value) = (numerator value, denominator value)

add :: Number -> Number -> Either NumberError Number
add (Number a) (Number b) = bounded (a + b)

subtractNumber :: Number -> Number -> Either NumberError Number
subtractNumber (Number a) (Number b) = bounded (a - b)

multiply :: Number -> Number -> Either NumberError Number
multiply (Number a) (Number b) = bounded (a * b)

divide :: Number -> Number -> Either NumberError Number
divide _ (Number 0) = Left InvalidDenominator
divide (Number a) (Number b) = bounded (a / b)

-- | The approved explicit AUD rounding operation: ties away from zero.
roundCents :: Number -> Either NumberError Number
roundCents (Number value) = bounded (cents % 100)
  where
    scaled = value * 100
    (whole, remainder) = quotRem (abs (numerator scaled)) (denominator scaled)
    rounded = whole + if remainder * 2 >= denominator scaled then 1 else 0
    cents = signum (numerator scaled) * rounded

enteredMoney :: Number -> Either NumberError Number
enteredMoney value@(Number amount)
    | denominator (amount * 100) == 1 = Right value
    | otherwise = Left MoneyRequiresWholeCents
