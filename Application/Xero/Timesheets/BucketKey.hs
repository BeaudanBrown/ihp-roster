module Application.Xero.Timesheets.BucketKey
    ( XeroComponentBucketContext (..)
    , componentBucketKey
    ) where

import Application.Helper.WeekBoundaries (WeekdayIndex)
import Application.WageEngine
import Application.Xero.PayrollSourceKey (sourceRateSuffix)
import qualified Data.Map.Strict as Map
import Generated.Types
import IHP.ControllerPrelude

data XeroComponentBucketContext = XeroComponentBucketContext
    { bucketStaffPayVersions     :: !(Map.Map UUID StaffPayVersion)
    , bucketShiftTypePayVersions :: !(Map.Map UUID ShiftTypePayVersion)
    , bucketAwardLevels          :: ![AwardLevel]
    }

componentBucketKey :: WeekdayIndex -> XeroComponentBucketContext -> TimesheetEntry -> Staff -> EarningsComponent -> Day -> Either Text Text
componentBucketKey _ context entry _ component _ =
    case component.sourceCondition of
        ImportedFlatRateCondition itemId ->
            pure ("xero:imported-pay-item:" <> itemId)
        condition -> do
            staffVersionId <- maybeToEither "Missing approved staff pay version." entry.staffPayVersionId
            shiftVersionId <- maybeToEither "Missing approved shift pay version." entry.shiftTypePayVersionId
            staffVersion <- maybeToEither "Approved staff pay version was not loaded." (Map.lookup staffVersionId context.bucketStaffPayVersions)
            shiftVersion <- maybeToEither "Approved shift pay version was not loaded." (Map.lookup shiftVersionId context.bucketShiftTypePayVersions)
            payLevelId <- maybeToEither "Missing approved Award classification." (shiftVersion.overrideAwardLevelId <|> staffVersion.defaultAwardLevelId)
            awardLevel <- maybeToEither "Approved Award classification was not loaded." (find (\level -> unpackId level.id == payLevelId) context.bucketAwardLevels)
            let effectiveFrom = component.publishedRateBoundaryDate
                classificationPrefix = "xero:pay-item:classification:" <> tshow awardLevel.classificationFixedId
                effectivePart = ":effective:" <> maybe "undated" tshow effectiveFrom
                sourceSuffix = sourceRateSuffix component.sourceRateIdentity component.ratePerUnit
            pure $ case condition of
                MissedMealBreakAdditionCondition -> classificationPrefix <> effectivePart <> ":penalty:missed_meal_break_addition" <> sourceSuffix
                _ -> classificationPrefix <> ":basis:" <> inputValue staffVersion.employmentBasis <> effectivePart <> ":" <> conditionKey condition <> sourceSuffix

maybeToEither :: Text -> Maybe value -> Either Text value
maybeToEither message = maybe (Left message) Right

conditionKey :: SourceCondition -> Text
conditionKey = \case
    OrdinaryCondition                -> "ordinary"
    SaturdayCondition                -> "penalty:saturday_penalty"
    SundayCondition                  -> "penalty:sunday_penalty"
    PublicHolidayCondition           -> "penalty:public_holiday_penalty"
    EveningAdditionCondition         -> "penalty:evening_after_7pm"
    EarlyMorningAdditionCondition    -> "penalty:late_night_after_midnight"
    MissedMealBreakAdditionCondition -> "penalty:missed_meal_break_addition"
    ImportedFlatRateCondition itemId -> "imported:" <> itemId
