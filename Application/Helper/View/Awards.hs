module Application.Helper.View.Awards
    ( awardLevelDisplayLabel
    , awardLevelOptionLabel
    , awardLevelRateLabels
    , employmentBasisShortLabel
    , formatHourlyRate
    ) where

import qualified Data.Scientific as Scientific
import Generated.Types
import IHP.ViewPrelude
import qualified Data.Text as Text

awardLevelDisplayLabel :: AwardLevel -> Text
awardLevelDisplayLabel awardLevel =
    maybe "" (<> " - ") awardLevel.classificationLevel <> awardLevel.classification

awardLevelOptionLabel :: [AwardLevelBaseRate] -> AwardLevel -> Text
awardLevelOptionLabel awardLevelBaseRates awardLevel =
    case awardLevelRateLabels awardLevelBaseRates awardLevel of
        []         -> awardLevelDisplayLabel awardLevel
        rateLabels -> awardLevelDisplayLabel awardLevel <> " (" <> Text.intercalate ", " rateLabels <> ")"

awardLevelRateLabels :: [AwardLevelBaseRate] -> AwardLevel -> [Text]
awardLevelRateLabels awardLevelBaseRates awardLevel =
    mapMaybe rateLabel [Permanent, Casual]
    where
        rateLabel employmentBasis =
            fmap
                (\rate -> employmentBasisShortLabel employmentBasis <> " " <> formatHourlyRate rate.hourlyRate)
                (find (matchingRate employmentBasis) awardLevelBaseRates)

        matchingRate employmentBasis rate =
            rate.awardLevelId == unpackId awardLevel.id
                && rate.employmentBasis == employmentBasis

employmentBasisShortLabel :: StaffEmploymentBasisEnum -> Text
employmentBasisShortLabel Permanent = "perm"
employmentBasisShortLabel Casual    = "casual"

formatHourlyRate :: Scientific.Scientific -> Text
formatHourlyRate rate =
    "$" <> trimWholeDollars rendered <> "/hr"
    where
        rendered = Text.pack (Scientific.formatScientific Scientific.Fixed (Just 2) rate)
        trimWholeDollars value =
            fromMaybe value (Text.stripSuffix ".00" value)
