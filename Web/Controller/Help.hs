module Web.Controller.Help where

import Application.Helper.View (PageHelpContext (..), PageHelpTopicId (..),
                                filterPageHelpTopic, lookupPageHelpTopic)
import Web.Controller.Prelude
import Web.View.Help.Show

instance Controller HelpController where
    beforeAction = bepisBeforeAction BepisAuthenticatedVenueController do
        annotateTelemetryAction
        ensureIsUser
        ensureCurrentVenueOrSupportRedirect

    action currentAction@ShowPageHelpAction { topic } = runBepis currentAction BepisPageAction do
        let topicId = PageHelpTopicId topic
        case lookupPageHelpTopic topicId of
            Nothing -> do
                setErrorMessage "That help topic is not available."
                redirectTo RosterWeeksAction
            Just helpTopic -> do
                let filteredTopic = filterPageHelpTopic currentPageHelpContext helpTopic
                if isHtmxRequest
                    then respondHtml (renderPageHelpDialog filteredTopic)
                    else render ShowView { .. }

currentPageHelpContext :: (?context :: ControllerContext) => PageHelpContext
currentPageHelpContext =
    PageHelpContext
        { pageHelpCanManage = hasRole Manager
        , pageHelpCanAdmin = hasRole VenueAdmin
        , pageHelpCanOwn = hasRole VenueOwner
        , pageHelpIsSupport = currentUserIsUnimpersonatedSuperAdmin
        , pageHelpIsImpersonating = currentUserIsImpersonating
        , pageHelpIsFounder = currentUserIsSuperAdmin
        }
