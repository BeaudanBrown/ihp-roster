{-# LANGUAGE TypeApplications #-}

module Web.RosterWeeks.Paths
    ( rosterAssignmentFiltersUrl
    , rosterCopyWeekUrl
    , rosterLayoutPreferenceUrl
    , rosterMoveShiftUrl
    , rosterTimelineMoveShiftUrl
    , rosterTemplateApplicationUrl
    , rosterTemplateReferenceUrl
    , rosterDuplicateShiftUrl
    , rosterDropStaffUrl
    , rosterWarningPreferenceUrl
    , rosterWageEstimatePreferenceUrl
    , rosterOwnLiveShiftHighlightPreferenceUrl
    , rosterOverviewFragmentUrl
    , rosterTimelineWindowUrl
    , rosterDayTimelineContentFragmentUrl
    , rosterWeekContentFragmentUrl
    , rosterWeekGridFrameFragmentUrl
    , rosterWeekGridToolbarFragmentUrl
    , rosterWeekDayColumnsFragmentUrl
    , rosterWeekDayRailFragmentUrl
    , rosterWeekWageRailFragmentUrl
    , rosterWeekSlotsGridFragmentUrl
    , rosterWeekDaySectionFragmentUrl
    , rosterWeekRowFragmentUrl
    , rosterWeekStaffPanelFragmentUrl
    , rosterWindowBaseUrl
    , rosterWindowUrl
    , rosterWeekWithDateUrl
    , supportVenueSwitchReturnPath
    ) where

import qualified Application.Helper.FrontendContract.Surface.Roster.Action as RosterAction
import Application.Helper.FrontendContract.Surface.Values (surfaceFieldsText)
import Application.Helper.Url (appendQueryParams, replaceQueryParams)
import Data.Coerce (coerce)
import qualified Data.Text as Text
import qualified Data.Text.Encoding as TextEncoding
import Data.Time.Calendar (Day)
import Data.Time.Format (defaultTimeLocale, formatTime)
import Generated.Types
import IHP.ModelSupport.Types (Id' (..))
import IHP.Prelude
import IHP.Router.UrlGenerator (pathTo)
import qualified Network.HTTP.Types.URI as URI
import Web.Routes ()
import Web.Types

supportVenueSwitchReturnPath :: Text -> Text
supportVenueSwitchReturnPath candidate
    | returnPathWithoutQuery candidate == returnPathWithoutQuery (pathTo ShowRosterWeekAction { weekOffset = 0 })
        && returnPathHasQueryParameter "rosterGroupId" candidate = pathTo RosterWeeksAction
    | otherwise = candidate

returnPathWithoutQuery :: Text -> Text
returnPathWithoutQuery = Text.takeWhile (/= '?')

returnPathHasQueryParameter :: Text -> Text -> Bool
returnPathHasQueryParameter parameterName candidate =
    any ((== TextEncoding.encodeUtf8 parameterName) . fst) parsedQuery
    where
        queryWithPrefix = snd (Text.breakOn "?" candidate)
        queryWithoutFragment = Text.takeWhile (/= '#') (Text.drop 1 queryWithPrefix)
        parsedQuery = URI.parseQuery (TextEncoding.encodeUtf8 queryWithoutFragment)

rosterWindowBaseUrl :: Day -> Text
rosterWindowBaseUrl anchorDate =
    replaceQueryParams
        (pathTo ShowRosterWindowAction { anchorDate })
        [("anchorDate", formatDayParam anchorDate)]

rosterWindowUrl :: Day -> Id RosterGroup -> Text
rosterWindowUrl anchorDate rosterGroupId =
    replaceQueryParams
        (pathTo ShowRosterWindowAction { anchorDate })
        (surfaceFieldsText (RosterAction.navigateRosterWeekActionFields anchorDate (coerce rosterGroupId)))

rosterWeekWithDateUrl :: Id RosterGroup -> Day -> Text
rosterWeekWithDateUrl rosterGroupId date =
    rosterWindowUrl date rosterGroupId

rosterViewQueryParams :: Id RosterGroup -> Maybe Day -> [(Text, Text)]
rosterViewQueryParams rosterGroupId maybeTimelineDate =
    ("rosterGroupId", tshow rosterGroupId) : case maybeTimelineDate of
        Nothing -> []
        Just dayDate -> [("rosterView", "timeline"), ("dayDate", formatDayParam dayDate)]

rosterTimelineWindowUrl :: Day -> Id RosterGroup -> Text
rosterTimelineWindowUrl operationalDate rosterGroupId =
    appendQueryParams
        (rosterWindowUrl operationalDate rosterGroupId)
        [("rosterView", "timeline"), ("dayDate", formatDayParam operationalDate)]

rosterDayTimelineContentFragmentUrl :: Day -> Id RosterGroup -> Id RosterDay -> Text
rosterDayTimelineContentFragmentUrl anchorDate rosterGroupId rosterDayId =
    replaceQueryParams
        (pathTo ShowRosterDayTimelineContentFragmentAction { anchorDate, rosterDayId })
        [ ("anchorDate", formatDayParam anchorDate)
        , ("rosterDayId", tshow rosterDayId)
        , ("rosterGroupId", tshow rosterGroupId)
        ]

rosterOverviewFragmentUrl :: Day -> Id RosterGroup -> Text
rosterOverviewFragmentUrl anchorDate rosterGroupId =
    replaceQueryParams (pathTo ShowRosterWeekOverviewFragmentAction { anchorDate }) (rosterWindowActionQuery anchorDate rosterGroupId)

rosterWeekContentFragmentUrl :: Day -> Id RosterGroup -> Text
rosterWeekContentFragmentUrl anchorDate rosterGroupId =
    replaceQueryParams (pathTo ShowRosterWeekContentFragmentAction { anchorDate }) (rosterWindowActionQuery anchorDate rosterGroupId)

rosterWeekGridToolbarFragmentUrl :: Day -> Id RosterGroup -> Maybe Day -> Text
rosterWeekGridToolbarFragmentUrl anchorDate rosterGroupId maybeTimelineDate =
    replaceQueryParams (pathTo ShowRosterWeekGridToolbarFragmentAction { anchorDate }) (("anchorDate", formatDayParam anchorDate) : rosterViewQueryParams rosterGroupId maybeTimelineDate)

rosterWeekGridFrameFragmentUrl :: Day -> Id RosterGroup -> Maybe Day -> Text
rosterWeekGridFrameFragmentUrl anchorDate rosterGroupId maybeTimelineDate =
    replaceQueryParams (pathTo ShowRosterWeekGridFrameFragmentAction { anchorDate }) (("anchorDate", formatDayParam anchorDate) : rosterViewQueryParams rosterGroupId maybeTimelineDate)

rosterWeekDayColumnsFragmentUrl :: Day -> Id RosterGroup -> Text
rosterWeekDayColumnsFragmentUrl anchorDate rosterGroupId =
    replaceQueryParams (pathTo ShowRosterWeekDayColumnsFragmentAction { anchorDate }) (rosterWindowActionQuery anchorDate rosterGroupId)

rosterWeekDayRailFragmentUrl :: Day -> Id RosterGroup -> Text
rosterWeekDayRailFragmentUrl anchorDate rosterGroupId =
    replaceQueryParams (pathTo ShowRosterWeekDayRailFragmentAction { anchorDate }) (rosterWindowActionQuery anchorDate rosterGroupId)

rosterWeekWageRailFragmentUrl :: Day -> Id RosterGroup -> Text
rosterWeekWageRailFragmentUrl anchorDate rosterGroupId =
    replaceQueryParams (pathTo ShowRosterWeekWageRailFragmentAction { anchorDate }) (rosterWindowActionQuery anchorDate rosterGroupId)

rosterWeekSlotsGridFragmentUrl :: Day -> Id RosterGroup -> Text
rosterWeekSlotsGridFragmentUrl anchorDate rosterGroupId =
    replaceQueryParams (pathTo ShowRosterWeekSlotsGridFragmentAction { anchorDate }) (rosterWindowActionQuery anchorDate rosterGroupId)

rosterWeekStaffPanelFragmentUrl :: Day -> Id RosterGroup -> Text
rosterWeekStaffPanelFragmentUrl anchorDate rosterGroupId =
    replaceQueryParams (pathTo ShowRosterWeekStaffPanelFragmentAction { anchorDate }) (rosterWindowActionQuery anchorDate rosterGroupId)

rosterWeekDaySectionFragmentUrl :: Day -> Id RosterGroup -> Id RosterDay -> Text
rosterWeekDaySectionFragmentUrl anchorDate rosterGroupId rosterDayId =
    replaceQueryParams
        (pathTo ShowRosterWeekDaySectionFragmentAction { anchorDate, rosterDayId })
        [ ("anchorDate", formatDayParam anchorDate)
        , ("rosterDayId", tshow rosterDayId)
        , ("rosterGroupId", tshow rosterGroupId)
        ]

rosterWeekRowFragmentUrl :: Day -> Id RosterGroup -> Id RosterDay -> Int -> Text
rosterWeekRowFragmentUrl anchorDate rosterGroupId rosterDayId rowIndex =
    replaceQueryParams
        (pathTo ShowRosterWeekRowFragmentAction { anchorDate, rosterDayId, rowIndex })
        [ ("anchorDate", formatDayParam anchorDate)
        , ("rosterDayId", tshow rosterDayId)
        , ("rowIndex", tshow rowIndex)
        , ("rosterGroupId", tshow rosterGroupId)
        ]

rosterAssignmentFiltersUrl :: Day -> Id RosterGroup -> Text
rosterAssignmentFiltersUrl anchorDate rosterGroupId =
    appendQueryParams (pathTo UpdateRosterAssignmentFiltersAction) (rosterWindowActionQuery anchorDate rosterGroupId)

rosterLayoutPreferenceUrl :: Day -> Id RosterGroup -> Text
rosterLayoutPreferenceUrl anchorDate rosterGroupId =
    appendQueryParams (pathTo UpdateRosterLayoutPreferenceAction) (rosterWindowActionQuery anchorDate rosterGroupId)

rosterMoveShiftUrl :: Day -> Id RosterGroup -> Text
rosterMoveShiftUrl anchorDate rosterGroupId =
    appendQueryParams (pathTo MoveRosterShiftToSlotAction) (rosterWindowActionQuery anchorDate rosterGroupId)

rosterTimelineMoveShiftUrl :: Day -> Id RosterGroup -> Day -> Text
rosterTimelineMoveShiftUrl anchorDate rosterGroupId operationalDate =
    appendQueryParams
        (pathTo MoveRosterTimelineShiftAction)
        (rosterWindowActionQuery anchorDate rosterGroupId <> [("rosterView", "timeline"), ("dayDate", formatDayParam operationalDate)])

rosterDuplicateShiftUrl :: Day -> Id RosterGroup -> Text
rosterDuplicateShiftUrl anchorDate rosterGroupId =
    appendQueryParams (pathTo DuplicateRosterShiftToDayAction) (rosterWindowActionQuery anchorDate rosterGroupId)

rosterDropStaffUrl :: Day -> Id RosterGroup -> Text
rosterDropStaffUrl anchorDate rosterGroupId =
    appendQueryParams (pathTo DropRosterStaffAction) (rosterWindowActionQuery anchorDate rosterGroupId)

rosterWarningPreferenceUrl :: Day -> Id RosterGroup -> Text
rosterWarningPreferenceUrl anchorDate rosterGroupId =
    appendQueryParams (pathTo UpdateRosterWarningPreferenceAction) (rosterWindowActionQuery anchorDate rosterGroupId)

rosterWageEstimatePreferenceUrl :: Day -> Id RosterGroup -> Text
rosterWageEstimatePreferenceUrl anchorDate rosterGroupId =
    appendQueryParams (pathTo UpdateRosterWageEstimatePreferenceAction) (rosterWindowActionQuery anchorDate rosterGroupId)

rosterOwnLiveShiftHighlightPreferenceUrl :: Day -> Id RosterGroup -> Text
rosterOwnLiveShiftHighlightPreferenceUrl anchorDate rosterGroupId =
    appendQueryParams (pathTo UpdateRosterOwnLiveShiftHighlightPreferenceAction) (rosterWindowActionQuery anchorDate rosterGroupId)

rosterTemplateApplicationUrl :: Day -> Id RosterTemplate -> Id RosterGroup -> Text
rosterTemplateApplicationUrl anchorDate rosterTemplateId rosterGroupId =
    appendQueryParams
        (pathTo (ApplyRosterTemplateAction rosterTemplateId rosterGroupId))
        [("anchorDate", formatDayParam anchorDate)]

rosterTemplateReferenceUrl :: Day -> Id RosterGroup -> Text -> Text -> Text
rosterTemplateReferenceUrl anchorDate rosterGroupId templateName templateScale =
    appendQueryParams
        (pathTo ShowRosterTemplateReferenceAction { rosterGroupId })
        [ ("anchorDate", formatDayParam anchorDate)
        , ("name", templateName)
        , ("scale", templateScale)
        ]

rosterCopyWeekUrl :: Day -> Day -> Id RosterGroup -> Text
rosterCopyWeekUrl sourceAnchorDate targetAnchorDate rosterGroupId =
    appendQueryParams
        (pathTo CopyRosterWeekAction)
        [ ("sourceAnchorDate", formatDayParam sourceAnchorDate)
        , ("targetAnchorDate", formatDayParam targetAnchorDate)
        , ("rosterGroupId", tshow rosterGroupId)
        ]

rosterWindowActionQuery :: Day -> Id RosterGroup -> [(Text, Text)]
rosterWindowActionQuery anchorDate rosterGroupId =
    [("anchorDate", formatDayParam anchorDate), ("rosterGroupId", tshow rosterGroupId)]

formatDayParam :: Day -> Text
formatDayParam date = cs (formatTime defaultTimeLocale "%Y-%m-%d" date)
