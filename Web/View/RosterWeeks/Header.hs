{-# LANGUAGE TypeApplications #-}

module Web.View.RosterWeeks.Header
    ( renderRosterGridHeader
    ) where

import qualified Application.Helper.FrontendContract.Surface.Interaction as SurfaceInteraction
import qualified Application.Helper.FrontendContract.Surface.Roster as Surface
import qualified Application.Helper.FrontendContract.Surface.Roster.Action as RosterAction
import Application.Helper.FrontendContract.Surface.Roster.SidePanel (rosterSidePanelRenderAttrs)
import Application.Helper.FrontendContract.Surface.Runtime (FrontendSurfaceActionRoute (..),
                                                            renderFrontendSurfaceActionForm,
                                                            renderFrontendSurfaceActionLink)
import Application.Helper.FrontendContract.Surface.Values
import Application.Helper.RosterWagePrediction (RosterWagePrediction (..),
                                                formatMoneyAmount)
import Application.Helper.Url (appendQueryParams)
import qualified Data.Text as Text
import Data.Time.Calendar (Day)
import qualified Data.Time.Calendar as Calendar
import Web.RosterWeeks.Dom (rosterWeekShellId)
import Web.RosterWeeks.FrontendSurface (rosterDeleteShiftDropzoneRef)
import Web.RosterWeeks.Paths (rosterTimelineWindowUrl, rosterWindowUrl)
import Web.RosterWeeks.Types (RosterGridViewMode (..),
                              RosterViewCapabilities (..))
import Web.View.Prelude
import Web.View.RosterWeeks.Overview (renderRosterWeekLabel)

rosterActionRoute :: Text -> FrontendSurfaceActionRoute
rosterActionRoute actionUrl =
    FrontendSurfaceActionRoute
        { actionRouteUrl = actionUrl
        , actionRouteCustomHtmx = []
        , actionRouteStandardUrl = Nothing
        , actionRouteExtraAttrs = []
        }

renderRosterGridHeader :: (?context :: ControllerContext) => Maybe RosterWeek -> Int -> Int -> RosterGroup -> Day -> RosterViewCapabilities -> Maybe RosterWagePrediction -> Bool -> RosterGridViewMode -> Maybe Text -> Html
renderRosterGridHeader maybeRosterWeek weekOffset rosterCalendarRevision currentRosterGroup weekStartDate viewCapabilities rosterWagePrediction canToggleSidePanel gridViewMode timelineTodayUrl =
    let toolbarHtml = renderWeekToolbar WeekToolbarConfig
            { weekToolbarVariant = WeekToolbarRoster
            , weekToolbarAriaLabel = "Roster week controls"
            , weekToolbarExtraClass = "roster-grid-header app-side-panel-header"
            , weekToolbarPrimary = renderLiveToggle maybeRosterWeek weekStartDate rosterCalendarRevision currentRosterGroup viewCapabilities
            , weekToolbarReset = renderThisWeekButton gridViewMode currentRosterGroup timelineTodayUrl
            , weekToolbarNavigation = renderRosterWeekControls weekOffset currentRosterGroup weekStartDate gridViewMode
            , weekToolbarSettings = when canToggleSidePanel renderRosterSidePanelToggle
            , weekToolbarAuxiliary = renderRosterWeekWageSummary rosterWagePrediction
            }
        deleteDropzoneKey = "delete" :: Text
     in if currentUserIsManager && maybe False (not . (.isLive)) maybeRosterWeek
            then SurfaceInteraction.withFrontendSurfaceDropzoneRef rosterDeleteShiftDropzoneRef deleteDropzoneKey toolbarHtml
            else toolbarHtml

renderRosterSidePanelToggle :: Html
renderRosterSidePanelToggle = renderSidePanelToggle rosterSidePanelRenderAttrs

renderRosterWeekWageSummary :: (?context :: ControllerContext) => Maybe RosterWagePrediction -> Html
renderRosterWeekWageSummary Nothing = mempty
renderRosterWeekWageSummary (Just prediction)
    | not currentUserIsAdmin = mempty
    | otherwise = [hsx|
        <div class="roster-wage-summary" aria-label="Week wages estimate">
            <span class="roster-wage-summary-label">Wages:</span>
            <span class="roster-wage-summary-total">{formatMoneyAmount prediction.predictionWeekTotal}</span>
            {renderRosterWageFailures prediction}
            {renderRosterWageSourceWarnings prediction}
        </div>
    |]

renderRosterWageFailures :: RosterWagePrediction -> Html
renderRosterWageFailures prediction
    | null prediction.predictionCalculationFailures = mempty
    | otherwise = [hsx|
        <span class="text-danger" role="alert" title={Text.intercalate "; " (map snd prediction.predictionCalculationFailures)}>
            {tshow failureCount} wage estimate {if failureCount == 1 then ("error" :: Text) else "errors"}
        </span>
    |]
  where
    failureCount = length prediction.predictionCalculationFailures

renderRosterWageSourceWarnings :: RosterWagePrediction -> Html
renderRosterWageSourceWarnings prediction
    | null prediction.predictionSourceWarnings = mempty
    | otherwise = [hsx|
        <span class="text-warning" role="status" title="Draft estimate uses wage sources requiring attention">
            Wage source warning
        </span>
    |]

renderRosterWeekControls :: (?context :: ControllerContext) => Int -> RosterGroup -> Day -> RosterGridViewMode -> Html
renderRosterWeekControls weekOffset currentRosterGroup weekStartDate RosterWeekGridView =
    renderWeekNavigationGroup WeekNavigationConfig
        { weekNavigationAriaLabel = "Roster week navigation"
        , weekNavigationExtraClass = "roster-week-nav-group"
        , weekNavigationPrevious = renderWeekNavigationLink "bi-chevron-left" "Previous week" (rosterWindowUrl previousDate currentRosterGroup.id) previousDate currentRosterGroup.id
        , weekNavigationCurrentLabel = [hsx|{renderRosterWeekLabel weekStartDate}|]
        , weekNavigationLabelClass = "roster-week-nav-button roster-week-nav-label"
        , weekNavigationNext = renderWeekNavigationLink "bi-chevron-right" "Next week" (rosterWindowUrl nextDate currentRosterGroup.id) nextDate currentRosterGroup.id
        }
    where
        previousDate = Calendar.addDays (-7) weekStartDate
        nextDate = Calendar.addDays 7 weekStartDate
renderRosterWeekControls weekOffset currentRosterGroup weekStartDate (RosterDayTimelineGridView dayOffset) =
    renderWeekNavigationGroup WeekNavigationConfig
        { weekNavigationAriaLabel = "Roster timeline day navigation"
        , weekNavigationExtraClass = "roster-week-nav-group roster-timeline-day-nav"
        , weekNavigationPrevious = renderWeekNavigationLink "bi-chevron-left" "Previous day" previousUrl previousDate currentRosterGroup.id
        , weekNavigationCurrentLabel = [hsx|{Text.pack (formatTime defaultTimeLocale "%a %d/%m" selectedDate)}|]
        , weekNavigationLabelClass = "roster-week-nav-button roster-week-nav-label"
        , weekNavigationNext = renderWeekNavigationLink "bi-chevron-right" "Next day" nextUrl nextDate currentRosterGroup.id
        }
    where
        clampedDayOffset = max 0 (min 6 dayOffset)
        selectedDate = Calendar.addDays (toInteger clampedDayOffset) weekStartDate
        previousDate = Calendar.addDays (-1) selectedDate
        nextDate = Calendar.addDays 1 selectedDate
        previousUrl = rosterTimelineWindowUrl previousDate currentRosterGroup.id
        nextUrl = rosterTimelineWindowUrl nextDate currentRosterGroup.id

renderWeekNavigationLink :: Text -> Text -> Text -> Day -> Id RosterGroup -> Html
renderWeekNavigationLink iconClass ariaLabel url anchorDate rosterGroupId =
    renderFrontendSurfaceActionLink
        ( RosterAction.navigateRosterWeekAction
            ( RosterAction.navigateRosterWeekActionFields
                anchorDate
                (unpackId rosterGroupId)
            )
        )
        (rosterActionRoute url)
            { actionRouteStandardUrl = Just url
            , actionRouteExtraAttrs =
                [ ("class", weekNavigationButtonClass "roster-week-nav-button roster-week-nav-arrow")
                , ("aria-label", ariaLabel)
                , ("title", ariaLabel)
                , ("data-turbolinks", "false")
                , ("hx-select", "#" <> rosterWeekShellId)
                ]
            }
        [hsx|<i class={"bi " <> iconClass} aria-hidden="true"></i>|]

renderLiveToggle :: (?context :: ControllerContext) => Maybe RosterWeek -> Day -> Int -> RosterGroup -> RosterViewCapabilities -> Html
renderLiveToggle (Just rosterWeek) anchorDate rosterCalendarRevision rosterGroup viewCapabilities
    | viewCapabilities.canToggleRosterLive = renderLiveToggleForm rosterWeek anchorDate rosterCalendarRevision rosterGroup
renderLiveToggle _ _ _ _ _ = mempty

renderThisWeekButton :: (?context :: ControllerContext) => RosterGridViewMode -> RosterGroup -> Maybe Text -> Html
renderThisWeekButton gridViewMode currentRosterGroup timelineTodayUrl =
    renderPartialNavigationLink
        PartialNavigationLink
            { partialNavigationLabel = resetLabel
            , partialNavigationUrl = thisWeekUrl
            , partialNavigationTargetId = rosterWeekShellId
            , partialNavigationSelectId = Just rosterWeekShellId
            , partialNavigationClass = weekNavigationButtonClass ""
            , partialNavigationSwap = "outerHTML"
            , partialNavigationSync = Just ("#" <> rosterWeekShellId <> ":replace")
            , partialNavigationPushUrl = True
            }
    where
        resetLabel = case gridViewMode of
            RosterDayTimelineGridView _ -> "Today"
            RosterWeekGridView          -> "This week"
        thisWeekUrl = case gridViewMode of
            RosterDayTimelineGridView _ -> fromMaybe (appendQueryParams (pathTo RosterWeeksAction) [("rosterGroupId", tshow currentRosterGroup.id), ("rosterView", "timeline")]) timelineTodayUrl
            RosterWeekGridView -> pathTo RosterWeeksAction

renderLiveToggleForm :: RosterWeek -> Day -> Int -> RosterGroup -> Html
renderLiveToggleForm rosterWeek anchorDate rosterCalendarRevision rosterGroup =
    renderFrontendSurfaceActionForm
        (RosterAction.toggleRosterWeekLiveStatusAction fields)
        (rosterActionRoute actionUrl)
            { actionRouteStandardUrl = Just actionUrl
            , actionRouteExtraAttrs = [("class", "mb-0")]
            }
        [hsx|
            <input type="hidden" name={surfaceFieldNameFrom @Surface.RosterCalendarRevision fields} value={tshow rosterCalendarRevision} />
            {renderLiveToggleButton fields rosterWeek}
        |]
  where
    actionUrl = appendQueryParams
        (pathTo (ToggleRosterWeekLiveStatusAction rosterWeek.id))
        [("anchorDate", tshow anchorDate), ("rosterGroupId", tshow rosterGroup.id)]
    fields = RosterAction.toggleRosterWeekLiveStatusActionFields rosterWeek.isLive rosterCalendarRevision

renderLiveToggleButton :: ActionFields RosterAction.ToggleRosterWeekLiveStatusActionOperation -> RosterWeek -> Html
renderLiveToggleButton fields rosterWeek =
    renderAppToggleButton $
        ( defaultAppToggleButtonConfig
            (liveToggleInputId rosterWeek.id)
            (surfaceToggleScalarField @Surface.IsLive fields True False)
            rosterWeek.isLive
            [hsx|<span class="fw-semibold">Published</span>|]
        )
            { appToggleButtonClass = "app-week-live-toggle"
            , appToggleRoleSwitch = True
            , appToggleSubmitPolicy = ToggleSubmitImmediate
            }

liveToggleInputId :: Id RosterWeek -> Text
liveToggleInputId rosterWeekId = "roster-live-toggle-" <> tshow rosterWeekId
