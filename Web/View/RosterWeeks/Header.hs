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
import Web.RosterWeeks.Paths (rosterDayTimelineUrl, rosterWeekUrl)
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

renderRosterGridHeader :: (?context :: ControllerContext) => Maybe RosterWeek -> Int -> RosterGroup -> Day -> RosterViewCapabilities -> Maybe RosterWagePrediction -> Bool -> RosterGridViewMode -> Maybe Text -> Html
renderRosterGridHeader maybeRosterWeek weekOffset currentRosterGroup weekStartDate viewCapabilities rosterWagePrediction canToggleSidePanel gridViewMode timelineTodayUrl =
    let toolbarHtml = renderWeekToolbar WeekToolbarConfig
            { weekToolbarVariant = WeekToolbarRoster
            , weekToolbarAriaLabel = "Roster week controls"
            , weekToolbarExtraClass = "roster-grid-header"
            , weekToolbarPrimary = renderLiveToggle maybeRosterWeek viewCapabilities
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
        , weekNavigationPrevious = renderWeekNavigationLink "bi-chevron-left" "Previous week" (rosterWeekUrl (weekOffset - 1) currentRosterGroup.id) (weekOffset - 1) currentRosterGroup.id
        , weekNavigationCurrentLabel = [hsx|{renderRosterWeekLabel weekStartDate}|]
        , weekNavigationLabelClass = "roster-week-nav-button roster-week-nav-label"
        , weekNavigationNext = renderWeekNavigationLink "bi-chevron-right" "Next week" (rosterWeekUrl (weekOffset + 1) currentRosterGroup.id) (weekOffset + 1) currentRosterGroup.id
        }
renderRosterWeekControls weekOffset currentRosterGroup weekStartDate (RosterDayTimelineGridView dayOffset) =
    renderWeekNavigationGroup WeekNavigationConfig
        { weekNavigationAriaLabel = "Roster timeline day navigation"
        , weekNavigationExtraClass = "roster-week-nav-group roster-timeline-day-nav"
        , weekNavigationPrevious = renderWeekNavigationLink "bi-chevron-left" "Previous day" previousUrl previousWeekOffset currentRosterGroup.id
        , weekNavigationCurrentLabel = [hsx|{Text.pack (formatTime defaultTimeLocale "%a %d/%m" selectedDate)}|]
        , weekNavigationLabelClass = "roster-week-nav-button roster-week-nav-label"
        , weekNavigationNext = renderWeekNavigationLink "bi-chevron-right" "Next day" nextUrl nextWeekOffset currentRosterGroup.id
        }
    where
        clampedDayOffset = max 0 (min 6 dayOffset)
        selectedDate = Calendar.addDays (toInteger clampedDayOffset) weekStartDate
        (previousWeekOffset, previousDayOffset) = if clampedDayOffset <= 0 then (weekOffset - 1, 6) else (weekOffset, clampedDayOffset - 1)
        (nextWeekOffset, nextDayOffset) = if clampedDayOffset >= 6 then (weekOffset + 1, 0) else (weekOffset, clampedDayOffset + 1)
        previousUrl = rosterDayTimelineUrl previousWeekOffset currentRosterGroup.id previousDayOffset
        nextUrl = rosterDayTimelineUrl nextWeekOffset currentRosterGroup.id nextDayOffset

renderWeekNavigationLink :: Text -> Text -> Text -> Int -> Id RosterGroup -> Html
renderWeekNavigationLink iconClass ariaLabel url targetWeekOffset rosterGroupId =
    renderFrontendSurfaceActionLink
        ( RosterAction.navigateRosterWeekAction
            ( RosterAction.navigateRosterWeekActionFields
                targetWeekOffset
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

renderLiveToggle :: (?context :: ControllerContext) => Maybe RosterWeek -> RosterViewCapabilities -> Html
renderLiveToggle (Just rosterWeek) viewCapabilities
    | viewCapabilities.canToggleRosterLive = renderLiveToggleForm rosterWeek
renderLiveToggle _ _ = mempty

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

renderLiveToggleForm :: RosterWeek -> Html
renderLiveToggleForm rosterWeek =
    renderFrontendSurfaceActionForm
        (RosterAction.toggleRosterWeekLiveStatusAction fields)
        (rosterActionRoute actionUrl)
            { actionRouteStandardUrl = Just actionUrl
            , actionRouteExtraAttrs = [("class", "mb-0")]
            }
        (renderLiveToggleButton fields rosterWeek)
  where
    actionUrl = pathTo (ToggleRosterWeekLiveStatusAction rosterWeek.id)
    fields = RosterAction.toggleRosterWeekLiveStatusActionFields rosterWeek.isLive

renderLiveToggleButton :: SurfaceActionFields Surface.RosterSurface Surface.ToggleRosterWeekLiveStatus -> RosterWeek -> Html
renderLiveToggleButton fields rosterWeek =
    renderAppToggleButton $
        ( defaultAppToggleButtonConfig
            (liveToggleInputId rosterWeek.id)
            (surfaceToggleScalarField @Surface.IsLive fields True False)
            rosterWeek.isLive
            [hsx|<span class="fw-semibold">Live</span>|]
        )
            { appToggleButtonClass = "app-week-live-toggle"
            , appToggleRoleSwitch = True
            , appToggleSubmitPolicy = ToggleSubmitImmediate
            }

liveToggleInputId :: Id RosterWeek -> Text
liveToggleInputId rosterWeekId = "roster-live-toggle-" <> tshow rosterWeekId
