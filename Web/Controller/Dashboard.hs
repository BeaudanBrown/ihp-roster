module Web.Controller.Dashboard where

import Application.Helper.Controller
import Application.Helper.LiveDemo
import Application.Helper.LiveUpdate
import Web.Controller.Prelude
import Web.View.Dashboard.Index

instance Controller DashboardController where
    beforeAction = ensureIsUser

    action DashboardAction = do
        liveDemoCount <- liftIO readDashboardLiveDemoCount
        render IndexView { .. }

    action ShowDashboardLiveDemoContentAction = do
        liveDemoCount <- liftIO readDashboardLiveDemoCount
        respondHtml (renderLiveDemoCard liveDemoCount)

    action IncrementDashboardLiveDemoAction = do
        liveDemoCount <- liftIO incrementDashboardLiveDemoCount
        let fragment =
                LiveFragmentRef
                    { targetId = "dashboard-live-demo-fragment"
                    , url = pathTo ShowDashboardLiveDemoContentAction
                    , deferUntilBlur = False
                    }
        liftIO $
            broadcastLiveInvalidation
                "dashboard-live-demo"
                [fragment]
                currentLiveUpdateClientId

        if isHtmxRequest
            then respondHtml (renderLiveDemoCard liveDemoCount)
            else redirectTo DashboardAction
