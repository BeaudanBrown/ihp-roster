module Web.Routes where
import Generated.Types
import IHP.RouterPrelude
import Web.Types

-- Generator Marker
instance AutoRoute StaticController
instance AutoRoute SessionsController
instance AutoRoute AuthController
instance AutoRoute PasswordResetsController
instance AutoRoute PasskeysController
instance AutoRoute UsersController
instance AutoRoute ProfilesController
instance AutoRoute TimesheetsController
instance AutoRoute LeaveRequestsController
instance AutoRoute ExportsController
instance AutoRoute StaffDocumentsController
instance AutoRoute BillingController
instance AutoRoute StripeWebhooksController
instance AutoRoute E2ETestController where
    customRoutes = do
        string "/__e2e/mark-passkey-verified"
        endOfInput
        onlyAllowMethods [POST]
        pure MarkE2EPasskeyVerifiedAction

    customPathTo MarkE2EPasskeyVerifiedAction = Just "/__e2e/mark-passkey-verified"
instance AutoRoute AdminController
instance AutoRoute FeedbackController where
    allowedMethodsForAction actionName = case actionName of
        -- Handle read-method rejection in the controller: IHP's automatic
        -- UnexpectedMethodException renders a 500 instead of a controlled 405.
        "VoteFeedbackAction" -> [GET, HEAD, POST]
        "UnvoteFeedbackAction" -> [GET, HEAD, POST]
        "CreateFeedbackAction" -> [POST]
        "UpdateFeedbackAction" -> [POST]
        "PublishFeedbackAction" -> [POST]
        "ArchiveFeedbackAction" -> [POST]
        "RestoreFeedbackAction" -> [POST]
        _ -> [GET, HEAD]
instance AutoRoute HelpController
instance AutoRoute SupportController
instance AutoRoute StaffController
instance AutoRoute RosterTemplatesController
instance AutoRoute RosterWeeksController
