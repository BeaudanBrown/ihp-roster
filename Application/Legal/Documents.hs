module Application.Legal.Documents
    ( LegalDocument (..)
    , LegalDocumentKind (..)
    , LegalPublicConfig (..)
    , allLegalDocumentKinds
    , legalDocumentActionLabel
    , readLegalPublicConfig
    , readLegalDocument
    ) where

import qualified Data.Text as Text
import qualified Data.Text.IO as TextIO
import IHP.Prelude
import System.Environment (lookupEnv)

data LegalDocumentKind
    = TermsDocument
    | PrivacyDocument
    | RefundsDisputesDocument
    | CancellationDocument
    deriving (Eq, Show)

data LegalDocument = LegalDocument
    { legalDocumentKind  :: !LegalDocumentKind
    , legalDocumentTitle :: !Text
    , legalDocumentBody  :: !Text
    }

data LegalPublicConfig = LegalPublicConfig
    { legalBusinessName :: !Text
    , legalSupportEmail :: !Text
    }

allLegalDocumentKinds :: [LegalDocumentKind]
allLegalDocumentKinds =
    [ TermsDocument
    , PrivacyDocument
    , RefundsDisputesDocument
    , CancellationDocument
    ]

legalDocumentActionLabel :: LegalDocumentKind -> Text
legalDocumentActionLabel = \case
    TermsDocument           -> "Customer Terms"
    PrivacyDocument         -> "Privacy Policy"
    RefundsDisputesDocument -> "Refund and Dispute Policy"
    CancellationDocument    -> "Cancellation Policy"

readLegalDocument :: LegalDocumentKind -> IO LegalDocument
readLegalDocument kind = do
    LegalPublicConfig { legalBusinessName = businessName, legalSupportEmail = supportEmail } <- readLegalPublicConfig
    maybeFile <- cleanMaybe <$> lookupEnvText (legalDocumentFileEnv kind)
    body <- case maybeFile of
        Just filePath -> TextIO.readFile (cs filePath)
        Nothing       -> pure (defaultLegalDocumentBody businessName supportEmail kind)
    pure
        LegalDocument
            { legalDocumentKind = kind
            , legalDocumentTitle = legalDocumentActionLabel kind
            , legalDocumentBody = Text.strip body
            }

readLegalPublicConfig :: IO LegalPublicConfig
readLegalPublicConfig = do
    legalBusinessName <- envOrDefault "BEPIS_LEGAL_BUSINESS_NAME" "Bepis PTY LTD"
    legalSupportEmail <- envOrDefault "BEPIS_LEGAL_SUPPORT_EMAIL" "support@bepis.lol"
    pure LegalPublicConfig { .. }

legalDocumentFileEnv :: LegalDocumentKind -> String
legalDocumentFileEnv = \case
    TermsDocument           -> "BEPIS_LEGAL_TERMS_FILE"
    PrivacyDocument         -> "BEPIS_LEGAL_PRIVACY_FILE"
    RefundsDisputesDocument -> "BEPIS_LEGAL_REFUNDS_DISPUTES_FILE"
    CancellationDocument    -> "BEPIS_LEGAL_CANCELLATION_FILE"

envOrDefault :: String -> Text -> IO Text
envOrDefault name fallback =
    fromMaybe fallback . cleanMaybe <$> lookupEnvText name

lookupEnvText :: String -> IO (Maybe Text)
lookupEnvText name = fmap cs <$> lookupEnv name

cleanMaybe :: Maybe Text -> Maybe Text
cleanMaybe value =
    case Text.strip <$> value of
        Just "" -> Nothing
        cleaned -> cleaned

defaultLegalDocumentBody :: Text -> Text -> LegalDocumentKind -> Text
defaultLegalDocumentBody businessName supportEmail = \case
    TermsDocument ->
        Text.unlines
            [ businessName <> " customer terms"
            , ""
            , businessName <> " provides venue operations software and related support services for hospitality operators, including rostering, timesheets, leave and unavailability workflows, and payroll-ready exports."
            , ""
            , "Subscriptions are billed per venue. Launch subscription pricing is AUD 100 per venue per month unless a written order states otherwise."
            , ""
            , "Payments are processed through Stripe-hosted Checkout and Stripe-hosted Customer Portal pages. " <> businessName <> " does not collect or store card details, bank account details, ABNs, tax IDs, or billing addresses in the app."
            , ""
            , businessName <> " is not GST registered at launch. Amounts are not GST inclusive, and Stripe invoices should not be treated as tax invoices unless " <> businessName <> " later confirms GST registration and updated invoicing terms in writing."
            , ""
            , "Customers are responsible for authorised users, the lawfulness and accuracy of information entered into the service, and reviewing rosters, timesheets, approvals, and exports before relying on them for payroll, compliance, or accounting purposes."
            , ""
            , "Support is available at " <> supportEmail <> "."
            , ""
            , "No promotions are currently offered unless stated in a written order or public offer."
            ]
    PrivacyDocument ->
        Text.unlines
            [ businessName <> " privacy policy"
            , ""
            , businessName <> " collects and handles personal information to provide rostering, timesheet, leave, unavailability, export, onboarding, billing, security, and support services."
            , ""
            , "The kinds of information handled by the service may include account details, venue records, worker profile information, roster information, leave and availability records, timesheet information, support records, export and audit records, technical logs, and minimal Stripe billing metadata."
            , ""
            , "Payment method details are handled by Stripe-hosted billing pages. " <> businessName <> " does not collect or store card or bank account details in the app."
            , ""
            , businessName <> " may disclose information to the relevant customer business and its authorised users, service providers that help operate the platform, Stripe for hosted payment and subscription billing services, professional advisers, and where required or authorised by law."
            , ""
            , "Privacy questions, access requests, correction requests, and complaints can be sent to " <> supportEmail <> "."
            ]
    RefundsDisputesDocument ->
        Text.unlines
            [ businessName <> " refund and dispute policy"
            , ""
            , "Refund or billing dispute requests should be sent to " <> supportEmail <> "."
            , ""
            , businessName <> " will review the venue subscription record, Stripe payment status, service access, customer agreement, and any relevant support history before deciding whether a refund or credit applies."
            , ""
            , "Subscription fees are generally charged for access to the service for the relevant billing period. Refunds are not automatic merely because a customer stops using the service during a paid period."
            , ""
            , businessName <> " sells software subscriptions and related support services, not physical goods, so physical return processes do not apply."
            , ""
            , "If a payment is disputed through a bank, card network, or Stripe process, " <> businessName <> " may provide relevant subscription, payment, and service-access records through that process."
            ]
    CancellationDocument ->
        Text.unlines
            [ businessName <> " cancellation policy"
            , ""
            , "Venue subscriptions may be cancelled through the Stripe Customer Portal where available, or by contacting " <> supportEmail <> "."
            , ""
            , "Cancellation stops future renewal according to the Stripe subscription state and the customer agreement. Access may continue until the end of the paid subscription period unless the customer agreement or operational circumstances require otherwise."
            , ""
            , "Customers should export any records they need before access ends. Some records may be retained after cancellation where required or permitted for legal, audit, backup, dispute, security, or operational reasons."
            , ""
            , "Ordinary Australian use of the service has no product-specific export restriction. Customers must not use the service in a way that breaches applicable law."
            ]
