module Web.Controller.Feedback where

import Application.Helper.Controller (boundedText, normalizeTextField,
                                      requireParam)
import Application.Helper.View (ToastOverlayPosition (..), dialogOverlayMountId,
                                renderToastOob, successToast)
import Control.Monad (guard)
import Data.Char (isControl)
import Data.Coerce (coerce)
import qualified Data.Text as Text
import qualified Data.Text.Encoding as TextEncoding
import qualified Data.Text.Encoding.Error as TextEncodingError
import qualified Network.Wai as Wai
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
        let feedbackItem = buildSubmittedFeedbackItem
        feedbackItem
            |> ifValid \case
                Left feedbackItem ->
                    if isHtmxRequest
                        then respondHtml (renderNewFeedbackDialog feedbackItem)
                        else render NewView { .. }
                Right feedbackItem -> do
                    _ <- feedbackItem |> createRecord
                    if isHtmxRequest
                        then respondHtml [hsx|
                            <div id={dialogOverlayMountId} hx-swap-oob="innerHTML"></div>
                            {renderToastOob ToastBottomCenter (successToast "Thanks — your feedback was sent.")}
                        |]
                        else do
                            setSuccessMessage "Thanks — your feedback was sent."
                            redirectTo RosterWeeksAction

buildNewFeedbackItem :: (?context :: ControllerContext, ?request :: Request) => UserFeedbackItem
buildNewFeedbackItem =
    newRecord @UserFeedbackItem
        |> set #venueId (coerce currentVenueId)
        |> set #submittedByUserId (coerce currentUser.id)
        |> set #feedbackType "bug"
        |> set #status "new"
        |> set #priority "normal"
        |> set #content ""

buildSubmittedFeedbackItem :: (?context :: ControllerContext, ?request :: Request) => UserFeedbackItem
buildSubmittedFeedbackItem =
    buildNewFeedbackItem
        |> requireParam #content "content" "Please enter your feedback"
        |> fill @'["feedbackType", "content"]
        |> normalizeTextField #content
        |> validateField #feedbackType validateFeedbackType
        |> validateField #content nonEmpty
        |> validateField #content feedbackContentMinLength
        |> validateField #content (boundedText 3000)
        |> set #submittedPath submittedOriginPath
        |> set #userAgent currentUserAgent
        |> set #submittedRole currentSubmittedRole
        |> set #viewportWidth submittedViewportWidth
        |> set #viewportHeight submittedViewportHeight
        |> set #devicePixelRatio submittedDevicePixelRatio
        |> set #deviceClass (viewportDeviceClass submittedViewportWidth)
        |> set #displayMode submittedDisplayMode

feedbackContentMinLength :: Text -> ValidatorResult
feedbackContentMinLength content
    | Text.length content >= 3 = Success
    | otherwise = Failure "Please enter at least 3 characters"

validateFeedbackType :: Text -> ValidatorResult
validateFeedbackType feedbackType
    | feedbackType `elem` allowedFeedbackTypes = Success
    | otherwise = Failure "Choose a feedback type"

allowedFeedbackTypes :: [Text]
allowedFeedbackTypes = ["bug", "suggestion", "other"]

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

submittedViewportWidth :: (?request :: Request) => Maybe Int
submittedViewportWidth = parseBoundedNumber 1 10000 "feedbackViewportWidth"

submittedViewportHeight :: (?request :: Request) => Maybe Int
submittedViewportHeight = parseBoundedNumber 1 10000 "feedbackViewportHeight"

submittedDevicePixelRatio :: (?request :: Request) => Maybe Double
submittedDevicePixelRatio = parseBoundedNumber 0 100 "feedbackDevicePixelRatio" >>= positiveOnly
    where
        positiveOnly value
            | value > 0 = Just value
            | otherwise = Nothing

parseBoundedNumber :: (?request :: Request, Read value, Ord value) => value -> value -> Text -> Maybe value
parseBoundedNumber minimumValue maximumValue paramName = do
    rawValue <- requestParamText paramName
    value <- readMaybe (cs rawValue)
    guard (value >= minimumValue && value <= maximumValue)
    pure value

viewportDeviceClass :: Maybe Int -> Maybe Text
viewportDeviceClass = fmap \width -> if width < 768 then "mobile" else "desktop"

submittedDisplayMode :: (?request :: Request) => Maybe Text
submittedDisplayMode = do
    displayMode <- requestParamText "feedbackDisplayMode"
    guard (displayMode == "browser" || displayMode == "standalone")
    pure displayMode

currentSubmittedRole :: (?context :: ControllerContext) => Maybe Text
currentSubmittedRole
    | currentUserIsUnimpersonatedSuperAdmin = Just "support_super_admin"
    | otherwise = venueRoleToText <$> effectiveVenueRoleOrNothing

requestParamText :: (?request :: Request) => Text -> Maybe Text
requestParamText paramName =
    listToMaybe
        [ decodeHeader rawValue
        | (rawName, Just rawValue) <- allParams
        , decodeHeader rawName == paramName
        ]

currentUserAgent :: (?request :: Request) => Maybe Text
currentUserAgent = do
    rawUserAgent <- lookup "User-Agent" (Wai.requestHeaders ?request)
    let userAgent = Text.take 500 (decodeHeader rawUserAgent)
    guard (not (Text.null userAgent))
    pure userAgent

decodeHeader :: ByteString -> Text
decodeHeader = TextEncoding.decodeUtf8With TextEncodingError.lenientDecode
