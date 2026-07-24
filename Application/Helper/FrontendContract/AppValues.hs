{-# LANGUAGE TypeApplications #-}

module Application.Helper.FrontendContract.AppValues
    ( AppEvents (..)
    , canonicalAppEvents
    , interactionIntentSubmitHtmxTrigger
    ) where

import Application.Helper.FrontendContract.App
import Application.Helper.FrontendContract.Values
import GHC.Generics (Generic)
import IHP.Prelude

data AppEvents = AppEvents
    { appPageReadyEventName                       :: !Text
    , appLiveFragmentsRefreshEventName            :: !Text
    , appInteractionIntentEventName               :: !Text
    , appInteractionIntentSubmitEventName         :: !Text
    , appInteractionSessionStartEventName         :: !Text
    , appInteractionSessionEndEventName           :: !Text
    , appInteractionSessionCancelRequestEventName :: !Text
    }
    deriving (Eq, Show, Generic)

canonicalAppEvents :: AppEvents
canonicalAppEvents =
    AppEvents
        { appPageReadyEventName = eventNameValue @PageReady
        , appLiveFragmentsRefreshEventName = eventNameValue @LiveFragmentsRefresh
        , appInteractionIntentEventName = eventNameValue @InteractionIntent
        , appInteractionIntentSubmitEventName = eventNameValue @IntentSubmit
        , appInteractionSessionStartEventName = eventNameValue @InteractionSessionStart
        , appInteractionSessionEndEventName = eventNameValue @InteractionSessionEnd
        , appInteractionSessionCancelRequestEventName = eventNameValue @InteractionSessionCancelRequest
        }

interactionIntentSubmitHtmxTrigger :: Text
interactionIntentSubmitHtmxTrigger = canonicalAppEvents.appInteractionIntentSubmitEventName
