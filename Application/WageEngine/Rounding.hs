module Application.WageEngine.Rounding
    ( finalEarningsBucketKey
    , deriveFinalEarnings
    )
where

import Application.WageEngine.Types
import qualified Data.Map.Strict as Map
import IHP.Prelude

finalEarningsBucketKey :: EarningsComponent -> FinalEarningsBucketKey
finalEarningsBucketKey component =
    FinalEarningsBucketKey
        { finalEarningsBucketUnitType = component.unitType
        , finalEarningsBucketSourceCondition = component.sourceCondition
        , finalEarningsBucketCalculationSource = component.calculationSource
        , finalEarningsBucketRatePerUnit = component.ratePerUnit
        , finalEarningsBucketSourceRateIdentity = component.sourceRateIdentity
        }

deriveFinalEarnings :: [EarningsComponent] -> FinalEarningsSummary
deriveFinalEarnings components =
    FinalEarningsSummary
        { finalEarningsLines = lines
        , finalEarningsTotalAmount = sum (map (.finalEarningsLineRoundedAmount) lines)
        }
  where
    groupedComponents =
        Map.fromListWith addExactValues
            [ (finalEarningsBucketKey component, (component.quantity, component.amount))
            | component <- components
            ]
    lines = map finalLineFor (Map.toAscList groupedComponents)

    addExactValues (leftQuantity, leftAmount) (rightQuantity, rightAmount) =
        (leftQuantity + rightQuantity, leftAmount + rightAmount)

    finalLineFor (bucketKey, (lineQuantity, exactAmount)) =
        FinalEarningsLine
            { finalEarningsLineBucketKey = bucketKey
            , finalEarningsLineQuantity = lineQuantity
            , finalEarningsLineExactAmount = exactAmount
            , finalEarningsLineRoundedAmount = roundToCents exactAmount
            }

roundToCents :: Rational -> Rational
roundToCents value =
    fromInteger (round (value * 100) :: Integer) / 100
