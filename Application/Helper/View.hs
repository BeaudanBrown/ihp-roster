module Application.Helper.View where

import qualified Data.Text as Text
import Data.Time.Format (defaultTimeLocale, formatTime, parseTimeM)
import Data.Time.LocalTime (TimeOfDay (..))
import Generated.Types
import IHP.ViewPrelude
import Web.Routes ()
import Web.Types

dialogOverlayMountId :: Text
dialogOverlayMountId = "dialog-overlay-mount"

htmxModalMountId :: Text
htmxModalMountId = dialogOverlayMountId

toastOverlayMountId :: Text
toastOverlayMountId = "toast-overlay-mount"

data OverlayFormMode
    = HtmxOverlayForm
    | PageOverlayForm

data OverlayButtonAction
    = OverlayCloseAction
    | OverlaySubmitFormAction !Text
    | OverlayNavigateAction !Text

data OverlayButton = OverlayButton
    { overlayButtonLabel :: !Text
    , overlayButtonClass :: !Text
    , overlayButtonAction :: !OverlayButtonAction
    }

data DialogOverlayConfig = DialogOverlayConfig
    { dialogOverlayTitle :: !Text
    , dialogOverlayBody :: !Html
    , dialogOverlayButtons :: ![OverlayButton]
    , dialogOverlayDialogClass :: !Text
    }

data ToastOverlayConfig = ToastOverlayConfig
    { toastOverlayTitle :: !(Maybe Text)
    , toastOverlayMessage :: !Text
    , toastOverlayClass :: !Text
    , toastOverlayAutoHideMs :: !Int
    }

data ToastOverlayPosition
    = ToastBottomLeft
    | ToastBottomCenter
    | ToastBottomRight
    deriving (Eq)

data PartialNavigationLink = PartialNavigationLink
    { partialNavigationLabel :: !Text
    , partialNavigationUrl :: !Text
    , partialNavigationTargetId :: !Text
    , partialNavigationSelectId :: !(Maybe Text)
    , partialNavigationClass :: !Text
    , partialNavigationSwap :: !Text
    , partialNavigationSync :: !(Maybe Text)
    , partialNavigationPushUrl :: !Bool
    }

defaultOverlayButtons :: Text -> [OverlayButton]
defaultOverlayButtons formId =
    [ OverlayButton
        { overlayButtonLabel = "Cancel"
        , overlayButtonClass = "btn btn-outline-secondary"
        , overlayButtonAction = OverlayCloseAction
        }
    , OverlayButton
        { overlayButtonLabel = "Save"
        , overlayButtonClass = "btn btn-primary"
        , overlayButtonAction = OverlaySubmitFormAction formId
        }
    ]

renderDialogOverlay :: DialogOverlayConfig -> Html
renderDialogOverlay DialogOverlayConfig { dialogOverlayTitle, dialogOverlayBody, dialogOverlayButtons, dialogOverlayDialogClass } = [hsx|
    <div class="modal fade show d-block"
         data-dialog-overlay="true"
         tabindex="-1"
         role="dialog"
         aria-modal="true"
         aria-labelledby="dialog-overlay-title">
        <div class={classes [("modal-dialog", True), ("modal-dialog-centered", True), (dialogOverlayDialogClass, not (Text.null dialogOverlayDialogClass))]}
             role="document">
            <div class="modal-content shadow">
                <div class="modal-header">
                    <h5 class="modal-title" id="dialog-overlay-title">{dialogOverlayTitle}</h5>
                    <button type="button" class="btn-close" aria-label="Close" data-dialog-overlay-close="true"></button>
                </div>
                <div class="modal-body">{dialogOverlayBody}</div>
                {renderDialogOverlayFooter dialogOverlayButtons}
            </div>
        </div>
    </div>
    <div class="modal-backdrop fade show" data-dialog-overlay-backdrop="true"></div>
|]

renderDialogOverlayFooter :: [OverlayButton] -> Html
renderDialogOverlayFooter buttons
    | null buttons = mempty
    | otherwise = [hsx|
        <div class="modal-footer">
            {forEach buttons renderDialogOverlayButton}
        </div>
    |]

renderDialogOverlayButton :: OverlayButton -> Html
renderDialogOverlayButton button =
    case button.overlayButtonAction of
        OverlayCloseAction -> [hsx|
            <button type="button" class={button.overlayButtonClass} data-dialog-overlay-close="true">
                {button.overlayButtonLabel}
            </button>
        |]
        OverlaySubmitFormAction formId -> [hsx|
            <button type="submit" class={button.overlayButtonClass} form={formId}>
                {button.overlayButtonLabel}
            </button>
        |]
        OverlayNavigateAction targetUrl -> [hsx|
            <a href={targetUrl} class={button.overlayButtonClass}>
                {button.overlayButtonLabel}
            </a>
        |]

renderPageDialogModal :: Text -> DialogOverlayConfig -> Html
renderPageDialogModal closeUrl DialogOverlayConfig { dialogOverlayTitle, dialogOverlayBody, dialogOverlayButtons } =
    renderModal Modal
        { modalTitle = dialogOverlayTitle
        , modalCloseUrl = closeUrl
        , modalFooter = Just (renderPageDialogFooter closeUrl dialogOverlayButtons)
        , modalContent = dialogOverlayBody
        }

renderPageDialogFooter :: Text -> [OverlayButton] -> Html
renderPageDialogFooter closeUrl buttons
    | null buttons = mempty
    | otherwise = [hsx|
        <div class="modal-footer">
            {forEach buttons (renderPageDialogButton closeUrl)}
        </div>
    |]

renderPageDialogButton :: Text -> OverlayButton -> Html
renderPageDialogButton closeUrl button =
    case button.overlayButtonAction of
        OverlayCloseAction -> [hsx|
            <a href={closeUrl} class={button.overlayButtonClass}>
                {button.overlayButtonLabel}
            </a>
        |]
        OverlaySubmitFormAction formId -> [hsx|
            <button type="submit" class={button.overlayButtonClass} form={formId}>
                {button.overlayButtonLabel}
            </button>
        |]
        OverlayNavigateAction targetUrl -> [hsx|
            <a href={targetUrl} class={button.overlayButtonClass}>
                {button.overlayButtonLabel}
            </a>
        |]

renderPartialNavigationLink :: PartialNavigationLink -> Html
renderPartialNavigationLink PartialNavigationLink { partialNavigationLabel, partialNavigationUrl, partialNavigationTargetId, partialNavigationSelectId, partialNavigationClass, partialNavigationSwap, partialNavigationSync, partialNavigationPushUrl } = [hsx|
    <a href={partialNavigationUrl}
       class={partialNavigationClass}
       data-turbolinks="false"
       hx-get={partialNavigationUrl}
       hx-target={"#" <> partialNavigationTargetId}
       hx-swap={partialNavigationSwap}
       hx-select={fmap ("#" <>) partialNavigationSelectId}
       hx-push-url={pushUrlValue}
       hx-sync={partialNavigationSync}>
        {partialNavigationLabel}
    </a>
|]
    where
        pushUrlValue :: Text
        pushUrlValue = if partialNavigationPushUrl then "true" else "false"

renderToastOverlayHost :: ToastOverlayPosition -> [ToastOverlayConfig] -> Html
renderToastOverlayHost position toasts = [hsx|
    <div id={toastOverlayMountId} class={toastOverlayHostClass position}>
        {forEach toasts renderToastOverlay}
    </div>
|]

renderToastOverlayHostOob :: ToastOverlayPosition -> [ToastOverlayConfig] -> Html
renderToastOverlayHostOob position toasts = [hsx|
    <div id={toastOverlayMountId} class={toastOverlayHostClass position} hx-swap-oob="innerHTML">
        {forEach toasts renderToastOverlay}
    </div>
|]

toastOverlayHostClass :: ToastOverlayPosition -> Text
toastOverlayHostClass position =
    classes
        [ ("app-toast-host", True)
        , ("app-toast-host-left", position == ToastBottomLeft)
        , ("app-toast-host-center", position == ToastBottomCenter)
        , ("app-toast-host-right", position == ToastBottomRight)
        ]

renderToastOverlay :: ToastOverlayConfig -> Html
renderToastOverlay toast = [hsx|
    <div class={classes [("app-toast", True), (toast.toastOverlayClass, True)]}
         data-overlay-toast="true"
         data-auto-hide-ms={tshow toast.toastOverlayAutoHideMs}>
        <div class="app-toast-body">
            {renderToastCopy toast}
            <button type="button"
                    class="btn-close btn-close-white app-toast-close"
                    aria-label="Dismiss"
                    data-toast-close="true"></button>
        </div>
    </div>
|]

renderToastCopy :: ToastOverlayConfig -> Html
renderToastCopy toast =
    case toast.toastOverlayTitle of
        Nothing -> [hsx|<span>{toast.toastOverlayMessage}</span>|]
        Just title -> [hsx|
            <div>
                <div class="app-toast-title">{title}</div>
                <div>{toast.toastOverlayMessage}</div>
            </div>
        |]

timePickerModalId :: Text
timePickerModalId = "quarter-hour-time-picker-modal"

quarterHourTimeOptions :: [(Text, Text)]
quarterHourTimeOptions = quarterHourTimeOptionsInRange (TimeOfDay 6 0 0) (TimeOfDay 23 45 0)

quarterHourTimeOptionsInRange :: TimeOfDay -> TimeOfDay -> [(Text, Text)]
quarterHourTimeOptionsInRange startTime endTime =
    map toOption minuteMarks
    where
        startMinutes = timeOfDayToMinuteOfDay startTime
        endMinutesRaw = timeOfDayToMinuteOfDay endTime
        endMinutes = if endMinutesRaw < startMinutes then endMinutesRaw + 1440 else endMinutesRaw
        minuteMarks = [startMinutes, startMinutes + 15 .. endMinutes]

        toOption totalMinutes =
            let minuteOfDay = totalMinutes `mod` 1440
                (hours, minutes) = minuteOfDay `divMod` 60
                tod = TimeOfDay hours minutes 0
             in (timeOfDayToStorageValue tod, Text.pack (formatTime defaultTimeLocale "%-I:%M %p" tod))

        timeOfDayToMinuteOfDay tod = todHour tod * 60 + todMin tod

timeOfDayToStorageValue :: TimeOfDay -> Text
timeOfDayToStorageValue tod = Text.pack (formatTime defaultTimeLocale "%H:%M" tod)

optionalTimeOfDayToStorageValue :: Maybe TimeOfDay -> Text
optionalTimeOfDayToStorageValue = maybe "" timeOfDayToStorageValue

storageTimeToDisplayLabel :: Text -> Text
storageTimeToDisplayLabel rawValue =
    case parseTimeM True defaultTimeLocale "%H:%M" (cs rawValue) :: Maybe TimeOfDay of
        Just tod -> Text.pack (formatTime defaultTimeLocale "%-I:%M %p" tod)
        Nothing -> rawValue

renderQuarterHourTimePickerModal :: Html
renderQuarterHourTimePickerModal = [hsx|
    <div class="modal fade"
         id={timePickerModalId}
         tabindex="-1"
         data-default-start-time="06:00"
         data-default-end-time="23:45"
         aria-labelledby="timePickerModalLabel"
         aria-hidden="true">
        <div class="modal-dialog modal-dialog-scrollable">
            <div class="modal-content">
                <div class="modal-header">
                    <h5 class="modal-title" id="timePickerModalLabel">Select Time</h5>
                    <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>
                </div>
                <div class="modal-body">
                    <div class="time-picker-grid js-time-picker-grid">
                        {forEach quarterHourTimeOptions renderTimePickerOption}
                    </div>
                </div>
                <div class="modal-footer">
                    <button type="button" class="btn btn-outline-secondary js-time-picker-clear">Clear time</button>
                    <button type="button" class="btn btn-secondary" data-bs-dismiss="modal">Cancel</button>
                </div>
            </div>
        </div>
    </div>
|]

renderTimePickerOption :: (Text, Text) -> Html
renderTimePickerOption (value, label) = [hsx|
    <button type="button"
            class="btn btn-outline-secondary time-picker-option js-time-picker-option"
            data-time-value={value}>
        {label}
    </button>
|]
