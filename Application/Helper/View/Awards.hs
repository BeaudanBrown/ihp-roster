module Application.Helper.View.Awards
    ( awardLevelDisplayLabel
    , awardLevelOptionLabel
    , awardLevelRateLabels
    , employmentBasisShortLabel
    , formatHourlyRate
    ) where

import qualified Data.List as List
import qualified Data.Scientific as Scientific
import qualified Data.Text as Text
import Generated.Types
import IHP.ViewPrelude

awardLevelDisplayLabel :: AwardLevel -> Text
awardLevelDisplayLabel awardLevel =
    awardLevel.classification

awardLevelOptionLabel :: [AwardLevelBaseRate] -> AwardLevel -> Text
awardLevelOptionLabel awardLevelBaseRates awardLevel =
    case awardLevelRateLabels awardLevelBaseRates awardLevel of
        []         -> awardLevelDisplayLabel awardLevel
        rateLabels -> awardLevelDisplayLabel awardLevel <> " (" <> Text.intercalate ", " rateLabels <> ")"

awardLevelRateLabels :: [AwardLevelBaseRate] -> AwardLevel -> [Text]
awardLevelRateLabels awardLevelBaseRates awardLevel =
    mapMaybe rateLabel [Permanent, Casual]
    where
        sortedRates = List.sortOn (\rate -> (Down rate.operativeFrom, Down rate.createdAt)) awardLevelBaseRates

        rateLabel employmentBasis =
            fmap
                (\rate -> employmentBasisShortLabel employmentBasis <> " " <> formatHourlyRate rate.hourlyRate)
                (find (matchingRate employmentBasis) sortedRates)

        matchingRate employmentBasis rate =
            rate.awardLevelId == unpackId awardLevel.id
                && rate.employmentBasis == employmentBasis

employmentBasisShortLabel :: StaffEmploymentBasisEnum -> Text
employmentBasisShortLabel Permanent = "Part-time"
employmentBasisShortLabel Casual    = "casual"

formatHourlyRate :: Scientific.Scientific -> Text
formatHourlyRate rate =
    "$" <> trimWholeDollars rendered <> "/hr"
    where
        rendered = Text.pack (Scientific.formatScientific Scientific.Fixed (Just 2) rate)
        trimWholeDollars value =
            fromMaybe value (Text.stripSuffix ".00" value)
