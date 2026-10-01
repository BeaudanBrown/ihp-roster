module Web.Timesheets.WageEstimates
    ( TimesheetPayAudience (..)
    , TimesheetWageEstimateSummary (..)
    , TimesheetWageEstimates (..)
    , canConfigureTimesheetWageEstimates
    , evaluateTimesheetWageEstimates
    , fetchAuthorizedTimesheetWageEntries
    , lookupTimesheetDayWageEstimates
    , timesheetPayAudienceFor
    , timesheetWageEstimateLabel
    ) where

import Application.VenueTime.Model (timesheetEntryOperationalDate)
import Application.WageEngine (FinalEarningsSummary (..), WageCalculation (..),
                               deriveFinalEarnings)
import Application.WageSourceEnforcement (WageEntryOutcome (..),
                                          evaluateDraftWageEntriesAt)
import Application.WageSourcePolicy (PolicyClock (..))
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Scientific (Scientific)
import qualified Data.Scientific as Scientific
import Web.Controller.Prelude

data TimesheetPayAudience = PersonalPayAudience | ManagementPayAudience
    deriving (Eq, Show)

data TimesheetWageEstimateSummary = TimesheetWageEstimateSummary
    { wageEstimateAmount             :: !Scientific
    , wageEstimateUnavailableCount   :: !Int
    , wageEstimateSourceWarningCount :: !Int
    }
    deriving (Eq, Show)

data TimesheetWageEstimates = TimesheetWageEstimates
    { timesheetWageDisplayMode       :: !WageDisplayModeEnum
    , timesheetPayAudience           :: !TimesheetPayAudience
    , timesheetWeekVisibleEstimate   :: !TimesheetWageEstimateSummary
    , timesheetWeekAllEstimate       :: !TimesheetWageEstimateSummary
    , timesheetDayVisibleEstimates   :: !(Map.Map Day TimesheetWageEstimateSummary)
    , timesheetDayAllEstimates       :: !(Map.Map Day TimesheetWageEstimateSummary)
    }
    deriving (Eq, Show)

data WageEstimateItem = WageEstimateItem
    { wageEstimateItemEntryId      :: !(Id TimesheetEntry)
    , wageEstimateItemDay          :: !Day
    , wageEstimateItemAmount       :: !(Maybe Scientific)
    , wageEstimateItemSourceWarning :: !Bool
    }

canConfigureTimesheetWageEstimates :: (?context :: ControllerContext) => Bool
canConfigureTimesheetWageEstimates =
    isJust (timesheetPayAudienceFor currentUserIsUnimpersonatedSuperAdmin effectiveVenueRoleOrNothing hasManagementMode (isJust effectiveStaffOrNothing))

timesheetPayAudienceFor :: Bool -> Maybe VenueRoleEnum -> Bool -> Bool -> Maybe TimesheetPayAudience
timesheetPayAudienceFor unimpersonatedSupport effectiveRole managementMode hasLinkedStaff
    | unimpersonatedSupport = Just ManagementPayAudience
    | managementMode && effectiveRole `elem` map Just [VenueAdmin, VenueOwner] = Just ManagementPayAudience
    | hasLinkedStaff = Just PersonalPayAudience
    | otherwise = Nothing

timesheetPayAudienceForCurrentUser :: (?context :: ControllerContext) => Maybe (TimesheetPayAudience, Maybe (Id Staff))
timesheetPayAudienceForCurrentUser = do
    audience <- timesheetPayAudienceFor currentUserIsUnimpersonatedSuperAdmin effectiveVenueRoleOrNothing hasManagementMode (isJust effectiveStaffOrNothing)
    let staffId = case audience of
            ManagementPayAudience -> Nothing
            PersonalPayAudience -> (.id) <$> effectiveStaffOrNothing
    pure (audience, staffId)

fetchAuthorizedTimesheetWageEntries ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    Day ->
    Day ->
    IO (Maybe (TimesheetPayAudience, [TimesheetEntry]))
fetchAuthorizedTimesheetWageEntries windowStart windowEndExclusive =
    case timesheetPayAudienceForCurrentUser of
        Nothing -> pure Nothing
        Just (audience, maybeStaffId) -> do
            let baseQuery =
                    query @TimesheetEntry
                        |> filterWhere (#venueId, unpackId currentVenueId)
                        |> filterWhereGreaterThanOrEqualTo (#operationalDate, windowStart)
                        |> filterWhereLessThan (#operationalDate, windowEndExclusive)
                        |> filterWhere (#deletedAt, Nothing)
                scopedQuery = maybe baseQuery (\staffId -> baseQuery |> filterWhere (#staffId, unpackId staffId)) maybeStaffId
            entries <- scopedQuery |> orderByAsc #startsAt |> fetch
            pure (Just (audience, entries))

evaluateTimesheetWageEstimates ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    WageDisplayModeEnum ->
    TimesheetPayAudience ->
    [TimesheetEntry] ->
    [TimesheetEntry] ->
    IO TimesheetWageEstimates
evaluateTimesheetWageEstimates displayMode audience visibleEntries allEntries = do
    now <- getCurrentTime
    outcomes <- evaluateDraftWageEntriesAt (PolicyClock now) allEntries
    let items = zipWith entryItem allEntries outcomes
        visibleIds = Set.fromList (map (.id) visibleEntries)
        visibleItems = filter (\item -> item.wageEstimateItemEntryId `Set.member` visibleIds) items
    pure TimesheetWageEstimates
        { timesheetWageDisplayMode = displayMode
        , timesheetPayAudience = audience
        , timesheetWeekVisibleEstimate = summarize visibleItems
        , timesheetWeekAllEstimate = summarize items
        , timesheetDayVisibleEstimates = summariesByDay visibleItems
        , timesheetDayAllEstimates = summariesByDay items
        }
  where
    entryItem entry outcome =
        WageEstimateItem
            { wageEstimateItemEntryId = entry.id
            , wageEstimateItemDay = timesheetEntryOperationalDate entry
            , wageEstimateItemAmount = calculationAmountFromCalculation <$> eitherToMaybe outcome.outcomeCalculation
            , wageEstimateItemSourceWarning = not entry.isApproved && not (null outcome.outcomeSourceDiagnostics)
            }
    eitherToMaybe = either (const Nothing) Just

summariesByDay :: [WageEstimateItem] -> Map.Map Day TimesheetWageEstimateSummary
summariesByDay items =
    Map.map summarize (Map.fromListWith (<>) [(item.wageEstimateItemDay, [item]) | item <- items])

calculationAmountFromCalculation :: WageCalculation -> Scientific
calculationAmountFromCalculation = scientificAmount . (.finalEarningsTotalAmount) . deriveFinalEarnings . (.earningsComponents)

scientificAmount :: Rational -> Scientific
scientificAmount = fst . Scientific.fromRationalRepetendUnlimited

summarize :: [WageEstimateItem] -> TimesheetWageEstimateSummary
summarize items =
    TimesheetWageEstimateSummary
        { wageEstimateAmount = sum (mapMaybe (.wageEstimateItemAmount) items)
        , wageEstimateUnavailableCount = length (filter (isNothing . (.wageEstimateItemAmount)) items)
        , wageEstimateSourceWarningCount = length (filter (.wageEstimateItemSourceWarning) items)
        }

lookupTimesheetDayWageEstimates :: TimesheetWageEstimates -> Day -> (TimesheetWageEstimateSummary, TimesheetWageEstimateSummary)
lookupTimesheetDayWageEstimates estimates day =
    ( Map.findWithDefault (summarize []) day estimates.timesheetDayVisibleEstimates
    , Map.findWithDefault (summarize []) day estimates.timesheetDayAllEstimates
    )

timesheetWageEstimateLabel :: TimesheetPayAudience -> Text
timesheetWageEstimateLabel PersonalPayAudience   = "Your estimated pay"
timesheetWageEstimateLabel ManagementPayAudience = "Estimated gross wages"
