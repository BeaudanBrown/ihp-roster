module Web.Controller.Feedback where

import Application.Feedback.Notification (enqueueFeedbackNotificationJobs,
                                          feedbackSubmittedMailKind)
import Application.Helper.Controller (boundedText, normalizeTextField)
import Application.Helper.FrontendContract.AppShell (ContentField,
                                                     FeedbackDevicePixelRatioField,
                                                     FeedbackDisplayModeField,
                                                     FeedbackTypeField,
                                                     FeedbackViewportHeightField,
                                                     FeedbackViewportWidthField,
                                                     SubmitFeedback)
import Application.Helper.FrontendContract.AppShell.Request (AppShellActionFields,
                                                             parseAppShellActionParams)
import Application.Helper.FrontendContract.Surface.Request (surfaceRequestFieldErrorsMessage)
import Application.Helper.FrontendContract.Surface.Values (surfaceFieldValue)
import Application.Helper.Telemetry (addTelemetryEvent)
import Application.Helper.View (ToastOverlayPosition (..),
                                renderDialogOverlayClearOob, renderToastOob,
                                successToast)
import Control.Monad (guard)
import Data.Char (isControl)
import Data.Coerce (coerce)
import qualified Data.Text as Text
import qualified Data.Text.Encoding as TextEncoding
import qualified Data.Text.Encoding.Error as TextEncodingError
import qualified Network.Wai as Wai
import OpenTelemetry.Attributes (toAttribute)
import Text.Read (readMaybe)
import Web.Controller.Prelude
import Web.View.Feedback.New

instance Controller FeedbackController where
    beforeAction = bepisBeforeAction BepisAuthenticatedVenueController do
        annotateTelemetryAction
        ensureIsUser
        ensureCurrentVenueOrSupportRedirect

    action currentAction@NewFeedbackAction = runBepis currentAction BepisFormAction do
        let feedbackItem = buildNewFeedbackItem
        if isHtmxRequest
            then respondHtml (renderNewFeedbackDialog feedbackItem)
            else render NewView { .. }

    action currentAction@CreateFeedbackAction = runBepis currentAction BepisMutationAction do
        case parseAppShellActionParams @SubmitFeedback of
            Left errors -> do
                let errorSummary = surfaceRequestFieldErrorsMessage errors
                let feedbackItem =
                        if "feedbackType" `Text.isInfixOf` errorSummary
                            then buildNewFeedbackItem |> attachFailure #feedbackType "Choose a feedback type"
                            else buildNewFeedbackItem |> attachFailure #content "Please enter at least 3 characters"
                renderInvalidFeedback feedbackItem
            Right fields -> do
                let feedbackItem = buildSubmittedFeedbackItem fields
                feedbackItem
                    |> ifValid \case
                        Left invalidFeedbackItem -> renderInvalidFeedback invalidFeedbackItem
                        Right validFeedbackItem -> do
                            notificationJobs <- withTransaction do
                                persistedFeedbackItem <- validFeedbackItem |> createRecord
                                enqueueFeedbackNotificationJobs persistedFeedbackItem
                            addTelemetryEvent
                                "bepis.email.enqueue"
                                [ ("mail.kind", toAttribute feedbackSubmittedMailKind)
                                , ("recipient.count", toAttribute (length notificationJobs))
                                ]
                            if isHtmxRequest
                                then respondHtml [hsx|
                                    {renderDialogOverlayClearOob}
                                    {renderToastOob ToastBottomCenter (successToast "Thanks — your feedback was sent.")}
                                |]
                                else do
                                    setSuccessMessage "Thanks — your feedback was sent."
                                    redirectTo RosterWeeksAction
      where
        renderInvalidFeedback feedbackItem =
            if isHtmxRequest
                then respondHtml (renderNewFeedbackDialog feedbackItem)
                else render NewView { .. }

buildNewFeedbackItem :: (?context :: ControllerContext, ?request :: Request) => UserFeedbackItem
buildNewFeedbackItem =
    newRecord @UserFeedbackItem
        |> set #venueId (coerce currentVenueId)
        |> set #submittedByUserId (coerce currentUser.id)
        |> set #feedbackType Bug
        |> set #status "new"
        |> set #priority "normal"
        |> set #content ""

buildSubmittedFeedbackItem :: (?context :: ControllerContext, ?request :: Request) => AppShellActionFields SubmitFeedback -> UserFeedbackItem
buildSubmittedFeedbackItem fields =
    buildNewFeedbackItem
        |> set #feedbackType (surfaceFieldValue @FeedbackTypeField fields)
        |> set #content (surfaceFieldValue @ContentField fields)
        |> normalizeTextField #content
        |> validateField #content nonEmpty
        |> validateField #content feedbackContentMinLength
        |> validateField #content (boundedText 3000)
        |> set #submittedPath submittedOriginPath
        |> set #userAgent currentUserAgent
        |> set #submittedRole currentSubmittedRole
        |> set #viewportWidth viewportWidth
        |> set #viewportHeight viewportHeight
        |> set #devicePixelRatio devicePixelRatio
        |> set #deviceClass (viewportDeviceClass viewportWidth)
        |> set #displayMode displayMode
  where
    viewportWidth = parseBoundedNumber 1 10000 (surfaceFieldValue @FeedbackViewportWidthField fields)
    viewportHeight = parseBoundedNumber 1 10000 (surfaceFieldValue @FeedbackViewportHeightField fields)
    devicePixelRatio = parseBoundedNumber 0 100 (surfaceFieldValue @FeedbackDevicePixelRatioField fields) >>= positiveOnly
    displayMode = validDisplayMode (surfaceFieldValue @FeedbackDisplayModeField fields)
    positiveOnly value
        | value > 0 = Just value
        | otherwise = Nothing

feedbackContentMinLength :: Text -> ValidatorResult
feedbackContentMinLength content
    | Text.length content >= 3 = Success
    | otherwise = Failure "Please enter at least 3 characters"

submittedOriginPath :: (?request :: Request) => Maybe Text
submittedOriginPath = do
    originPath <- currentReferrerPath >>= sanitizeOriginPath
    guard (originPath /= "/CreateFeedback")
    pure originPath

currentReferrerPath :: (?request :: Request) => Maybe Text
currentReferrerPath = do
    rawReferrer <- lookup "Referer" (Wai.requestHeaders ?request)
    rawHost <- lookup "Host" (Wai.requestHeaders ?request)
    let referrer = decodeHeader rawReferrer
    let requestHost = decodeHeader rawHost
    authorityAndPath <- Text.stripPrefix "https://" referrer <|> Text.stripPrefix "http://" referrer
    let (referrerAuthority, referrerPath) = Text.breakOn "/" authorityAndPath
    guard (referrerAuthority == requestHost)
    pure (if Text.null referrerPath then "/" else referrerPath)

sanitizeOriginPath :: Text -> Maybe Text
sanitizeOriginPath rawPath
    | Text.null pathOnly = Nothing
    | not (Text.isPrefixOf "/" pathOnly) = Nothing
    | Text.isPrefixOf "//" pathOnly = Nothing
    | Text.any isControl pathOnly = Nothing
    | otherwise = Just (Text.take 500 pathOnly)
    where
        pathOnly = Text.takeWhile (\character -> character /= '?' && character /= '#') rawPath

parseBoundedNumber :: (Read value, Ord value) => value -> value -> Maybe Text -> Maybe value
parseBoundedNumber minimumValue maximumValue maybeRawValue = do
    rawValue <- maybeRawValue
    value <- readMaybe (cs rawValue)
    guard (value >= minimumValue && value <= maximumValue)
    pure value

viewportDeviceClass :: Maybe Int -> Maybe Text
viewportDeviceClass = fmap \width -> if width < 768 then "mobile" else "desktop"

validDisplayMode :: Maybe Text -> Maybe Text
validDisplayMode maybeDisplayMode = do
    displayMode <- maybeDisplayMode
    guard (displayMode == "browser" || displayMode == "standalone")
    pure displayMode

currentSubmittedRole :: (?context :: ControllerContext) => Maybe Text
currentSubmittedRole
    | currentUserIsUnimpersonatedSuperAdmin = Just "support_super_admin"
    | otherwise = venueRoleToText <$> effectiveVenueRoleOrNothing

currentUserAgent :: (?request :: Request) => Maybe Text
currentUserAgent = do
    rawUserAgent <- lookup "User-Agent" (Wai.requestHeaders ?request)
    let userAgent = Text.take 500 (decodeHeader rawUserAgent)
    guard (not (Text.null userAgent))
    pure userAgent

decodeHeader :: ByteString -> Text
decodeHeader = TextEncoding.decodeUtf8With TextEncodingError.lenientDecode
