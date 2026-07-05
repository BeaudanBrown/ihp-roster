{-# LANGUAGE TypeApplications #-}

module Application.Helper.FrontendContract.AppValues
    ( AppEvents (..)
    , AppOverlayDom (..)
    , canonicalAppEvents
    , canonicalAppOverlayDom
    , interactionIntentSubmitHtmxTrigger
    , sharedDialogOverlayMountId
    , sharedToastOverlayMountId
    ) where

import Application.Helper.FrontendContract.App
import Application.Helper.FrontendContract.Values
import GHC.Generics (Generic)
import IHP.Prelude

data AppOverlayDom = AppOverlayDom
    { appDialogOverlayMountId :: !Text
    , appToastOverlayMountId  :: !Text
    }
    deriving (Eq, Show, Generic)

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

canonicalAppOverlayDom :: AppOverlayDom
canonicalAppOverlayDom =
    AppOverlayDom
        { appDialogOverlayMountId = domIdValue @DialogOverlayMount
        , appToastOverlayMountId = domIdValue @ToastOverlayMount
        }

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

sharedDialogOverlayMountId :: Text
sharedDialogOverlayMountId = canonicalAppOverlayDom.appDialogOverlayMountId

sharedToastOverlayMountId :: Text
sharedToastOverlayMountId = canonicalAppOverlayDom.appToastOverlayMountId

interactionIntentSubmitHtmxTrigger :: Text
interactionIntentSubmitHtmxTrigger = canonicalAppEvents.appInteractionIntentSubmitEventName
