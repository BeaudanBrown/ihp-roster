module Application.Xero.PayrollSourceKey
    ( sourceRateSuffix
    ) where

import Application.WageEngine.RateBook (RateSourceIdentity (..))
import Data.Scientific (Scientific)
import IHP.Prelude

-- Xero managed keys append the exact sealed source and rate identity.
sourceRateSuffix :: Maybe RateSourceIdentity -> Scientific -> Text
sourceRateSuffix maybeSourceIdentity rate =
    ":source:"
        <> maybe "missing" (\(RateSourceIdentity identity) -> identity) maybeSourceIdentity
        <> ":rate:"
        <> tshow rate
