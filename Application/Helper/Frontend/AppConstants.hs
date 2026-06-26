module Application.Helper.Frontend.AppConstants
    ( AppEvents (..)
    , AppOverlayDom (..)
    , canonicalAppEvents
    , canonicalAppOverlayDom
    , interactionIntentSubmitHtmxTrigger
    , sharedDialogOverlayMountId
    , sharedToastOverlayMountId
    ) where

import IHP.Prelude

data AppOverlayDom = AppOverlayDom
    { appDialogOverlayMountId :: !Text
    , appToastOverlayMountId  :: !Text
    }
    deriving (Eq, Show)

data AppEvents = AppEvents
    { appPageReadyEventName                       :: !Text
    , appLiveFragmentsRefreshEventName            :: !Text
    , appInteractionIntentEventName               :: !Text
    , appInteractionIntentSubmitEventName         :: !Text
    , appInteractionSessionStartEventName         :: !Text
    , appInteractionSessionEndEventName           :: !Text
    , appInteractionSessionCancelRequestEventName :: !Text
    }
    deriving (Eq, Show)

canonicalAppOverlayDom :: AppOverlayDom
canonicalAppOverlayDom =
    AppOverlayDom
        { appDialogOverlayMountId = "dialog-overlay-mount"
        , appToastOverlayMountId = "toast-overlay-mount"
        }

canonicalAppEvents :: AppEvents
canonicalAppEvents =
    AppEvents
        { appPageReadyEventName = "app:page-ready"
        , appLiveFragmentsRefreshEventName = "app-live-fragments-refresh"
        , appInteractionIntentEventName = "bepis:interaction-intent"
        , appInteractionIntentSubmitEventName = "bepis:intent-submit"
        , appInteractionSessionStartEventName = "bepis:interaction-session-start"
        , appInteractionSessionEndEventName = "bepis:interaction-session-end"
        , appInteractionSessionCancelRequestEventName = "bepis:interaction-session-cancel-request"
        }

sharedDialogOverlayMountId :: Text
sharedDialogOverlayMountId = canonicalAppOverlayDom.appDialogOverlayMountId

sharedToastOverlayMountId :: Text
sharedToastOverlayMountId = canonicalAppOverlayDom.appToastOverlayMountId

interactionIntentSubmitHtmxTrigger :: Text
interactionIntentSubmitHtmxTrigger = canonicalAppEvents.appInteractionIntentSubmitEventName
