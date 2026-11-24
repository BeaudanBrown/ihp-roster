-- | Whole-second business time. Payroll quantities and technical timers retain
-- their own representations; convert only when elapsed business time is needed.
module Application.VenueTime.Seconds
    ( Seconds
    , fromSeconds
    , fromMinutes
    , fromStoredHours
    , fromElapsed
    , between
    , toSeconds
    , toHours
    , toElapsed
    , add
    , subtract
    , sum
    , addTo
    ) where

import Data.Time (NominalDiffTime, UTCTime, addUTCTime, diffUTCTime)
import Prelude hiding (subtract, sum)
import qualified Prelude

-- No Num instance: units must be explicit and division must not silently create
-- fractional business durations. Signed offsets and zero are valid; interval
-- validity belongs to the domain consuming them.
newtype Seconds = Seconds Integer
    deriving (Eq, Ord, Show)

fromSeconds :: Integer -> Seconds
fromSeconds = Seconds

fromMinutes :: Integer -> Seconds
fromMinutes = Seconds . (* 60)

fromStoredHours :: Rational -> Seconds
fromStoredHours = rounded . (* 3600)

fromElapsed :: NominalDiffTime -> Seconds
fromElapsed = rounded . toRational

-- | Start then end. Subtract before rounding, never round endpoints separately.
between :: UTCTime -> UTCTime -> Seconds
between start end = fromElapsed (diffUTCTime end start)

rounded :: Rational -> Seconds
rounded value = Seconds (signum valueInteger * magnitude)
  where
    valueInteger = if value < 0 then (-1 :: Integer) else 1
    magnitude = floor (abs value + 1 / 2)

toSeconds :: Seconds -> Integer
toSeconds (Seconds value) = value

toHours :: Seconds -> Rational
toHours value = fromInteger (toSeconds value) / 3600

toElapsed :: Seconds -> NominalDiffTime
toElapsed = fromInteger . toSeconds

add :: Seconds -> Seconds -> Seconds
add (Seconds left) (Seconds right) = Seconds (left + right)

subtract :: Seconds -> Seconds -> Seconds
subtract (Seconds left) (Seconds right) = Seconds (left - right)

sum :: [Seconds] -> Seconds
sum = Seconds . Prelude.sum . map toSeconds

addTo :: Seconds -> UTCTime -> UTCTime
addTo = addUTCTime . toElapsed
