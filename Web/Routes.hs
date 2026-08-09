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
instance AutoRoute FeedbackController
instance AutoRoute HelpController
instance AutoRoute SupportController
instance AutoRoute StaffController
instance AutoRoute RosterTemplatesController
instance AutoRoute RosterWeeksController
