module Web.View.Static.Welcome where
import Application.Legal.Documents
import qualified Data.Text as Text
import Web.View.Prelude

data WelcomeView = WelcomeView

data PublicBillingSupportView = PublicBillingSupportView { legalPublicConfig :: LegalPublicConfig }

data LegalDocumentView = LegalDocumentView { legalDocument :: LegalDocument }

instance View WelcomeView where
    html WelcomeView = [hsx|
        <div class="app-page-auth">
            <div class="app-auth-card app-auth-card-wide">
                <div class="app-auth-body text-center">
                    <h1 class="display-5 fw-bold mb-2">Bepis</h1>
                    <p class="app-muted mb-4">
                        Venue rostering, timesheets, unavailability, leave, payroll-ready exports, and support for hospitality operators.
                    </p>
                    <div class="d-grid">
                        <a href={NewSessionAction} class="btn btn-primary btn-lg w-100">Sign In</a>
                    </div>
                    <div class="mt-4">
                        <a href={PublicBillingSupportAction} class="link-secondary">Billing and support information</a>
                    </div>
                </div>
            </div>
        </div>
    |]

instance View PublicBillingSupportView where
    html PublicBillingSupportView { .. } = [hsx|
        <div class="app-public-page">
            <section class="app-public-hero">
                <div>
                    <p class="app-public-kicker">Bepis</p>
                    <h1>Venue operations software for hospitality teams</h1>
                    <p class="app-public-lead">
                        Bepis helps hospitality venues prepare rosters, track timesheets, manage leave and unavailability, and produce payroll-ready exports with founder-managed support.
                    </p>
                    <p class="app-public-operator">
                        Operated by {legalPublicConfig.legalBusinessName}.
                    </p>
                </div>
                <div class="app-public-hero-actions">
                    <a href={NewSessionAction} class="btn btn-primary">Sign In</a>
                    <a href={supportMailto legalPublicConfig.legalSupportEmail} class="btn btn-outline-secondary">{legalPublicConfig.legalSupportEmail}</a>
                </div>
            </section>

            <section class="app-public-section">
                <h2>Service</h2>
                <div class="app-public-grid">
                    <div>
                        <h3>Rostering</h3>
                        <p>Build weekly venue rosters, review coverage, and publish staff schedules.</p>
                    </div>
                    <div>
                        <h3>Timesheets</h3>
                        <p>Record worked shifts, approvals, and payroll-adjacent summaries.</p>
                    </div>
                    <div>
                        <h3>Leave and unavailability</h3>
                        <p>Collect availability changes and leave requests for venue managers to review.</p>
                    </div>
                    <div>
                        <h3>Exports</h3>
                        <p>Generate payroll-ready exports for the customer and their accountant or payroll process.</p>
                    </div>
                </div>
            </section>

            <section class="app-public-section">
                <h2>Subscription Billing</h2>
                <p>
                    Bepis subscriptions are billed per venue. The launch plan is AUD 100 per venue per month, processed through Stripe-hosted Checkout and Stripe-hosted Customer Portal pages. Bepis does not collect or store card details, bank details, ABNs, tax IDs, or billing addresses in the app.
                </p>
                <p>
                    The operator is not GST registered at launch. Prices are not presented as GST-inclusive and Stripe invoices should not be treated as tax invoices unless Bepis later confirms a changed tax position in writing.
                </p>
            </section>

            <section class="app-public-section">
                <h2>Terms, Privacy, Refunds, and Cancellation</h2>
                <div class="app-public-policy-list">
                    <div>
                        <h3><a href={LegalTermsAction}>Customer Terms</a></h3>
                        <p>Venue setup, permitted use, payment responsibility, hosted Stripe payment processing, and service support scope.</p>
                    </div>
                    <div>
                        <h3><a href={LegalPrivacyAction}>Privacy Policy</a></h3>
                        <p>How {legalPublicConfig.legalBusinessName} handles account, venue, workforce, export, support, and minimal Stripe billing metadata.</p>
                    </div>
                    <div>
                        <h3><a href={LegalRefundsDisputesAction}>Refunds and Disputes</a></h3>
                        <p>How refund requests, billing disputes, and non-applicable physical returns are handled.</p>
                    </div>
                    <div>
                        <h3><a href={LegalCancellationAction}>Cancellation</a></h3>
                        <p>How venue subscriptions can be cancelled through the Stripe Customer Portal or support.</p>
                    </div>
                </div>
            </section>

            <section class="app-public-section">
                <h2>Support Contact</h2>
                <p>
                    For billing, cancellation, refund, dispute, privacy, or service support questions, contact <a href={supportMailto legalPublicConfig.legalSupportEmail}>{legalPublicConfig.legalSupportEmail}</a>.
                </p>
            </section>
        </div>
    |]

supportMailto :: Text -> Text
supportMailto email =
    "mailto:" <> email

instance View LegalDocumentView where
    html LegalDocumentView { .. } = [hsx|
        <div class="app-public-page">
            <section class="app-public-section app-legal-document">
                <div class="app-public-policy-nav">
                    <a href={PublicBillingSupportAction}>Billing and support</a>
                    {forEach allLegalDocumentKinds renderPolicyLink}
                </div>
                <h1>{legalDocument.legalDocumentTitle}</h1>
                <div class="app-legal-document-body">
                    {forEach (legalDocumentParagraphs legalDocument.legalDocumentBody) renderLegalParagraph}
                </div>
            </section>
        </div>
    |]

renderPolicyLink :: LegalDocumentKind -> Html
renderPolicyLink kind = [hsx|
    <a href={legalDocumentAction kind}>{legalDocumentActionLabel kind}</a>
|]

legalDocumentAction :: LegalDocumentKind -> StaticController
legalDocumentAction = \case
    TermsDocument           -> LegalTermsAction
    PrivacyDocument         -> LegalPrivacyAction
    RefundsDisputesDocument -> LegalRefundsDisputesAction
    CancellationDocument    -> LegalCancellationAction

legalDocumentParagraphs :: Text -> [Text]
legalDocumentParagraphs body =
    body
        |> Text.splitOn "\n\n"
        |> map Text.strip
        |> filter (/= "")

renderLegalParagraph :: Text -> Html
renderLegalParagraph paragraph = [hsx|<p>{paragraph}</p>|]
