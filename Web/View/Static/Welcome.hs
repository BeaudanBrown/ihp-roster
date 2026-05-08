module Web.View.Static.Welcome where
import Web.View.Prelude

data WelcomeView = WelcomeView

data PublicBillingSupportView = PublicBillingSupportView

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
                        <div class="js-passkey-first-login"
                             data-begin-url={pathTo BeginPasskeyAuthenticationAction}
                             data-finish-url={pathTo FinishPasskeyAuthenticationAction}
                             data-fallback-url={pathTo NewSessionAction}
                             data-success-redirect={RosterWeeksAction}>
                            <a href={NewSessionAction} class="btn btn-primary btn-lg w-100 js-passkey-first-login-button">Sign In</a>
                        </div>
                    </div>
                    <div class="mt-4">
                        <a href={PublicBillingSupportAction} class="link-secondary">Billing and support information</a>
                    </div>
                </div>
            </div>
        </div>
    |]

instance View PublicBillingSupportView where
    html PublicBillingSupportView = [hsx|
        <div class="app-public-page">
            <section class="app-public-hero">
                <div>
                    <p class="app-public-kicker">Bepis</p>
                    <h1>Venue operations software for hospitality teams</h1>
                    <p class="app-public-lead">
                        Bepis helps hospitality venues prepare rosters, track timesheets, manage leave and unavailability, and produce payroll-ready exports with founder-managed support.
                    </p>
                </div>
                <div class="app-public-hero-actions">
                    <a href={NewSessionAction} class="btn btn-primary">Sign In</a>
                    <a href="mailto:support@bepis.lol" class="btn btn-outline-secondary">support@bepis.lol</a>
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
                        <h3>Customer Terms</h3>
                        <p>Customers agree venue setup, permitted use, payment responsibility, hosted Stripe payment processing, and service support scope before live use.</p>
                    </div>
                    <div>
                        <h3>Privacy</h3>
                        <p>Bepis stores account, venue, rostering, timesheet, leave, export, support, and minimal Stripe billing metadata needed to operate the service.</p>
                    </div>
                    <div>
                        <h3>Refunds and Disputes</h3>
                        <p>Refund or billing dispute requests should be sent to support@bepis.lol. Bepis will review the venue subscription record, Stripe payment status, service access, and customer agreement before deciding whether a refund or credit applies.</p>
                    </div>
                    <div>
                        <h3>Cancellation</h3>
                        <p>Venue subscriptions may be cancelled through the Stripe Customer Portal or by contacting support@bepis.lol. Cancellation stops future renewal according to the Stripe subscription state and customer agreement.</p>
                    </div>
                </div>
            </section>

            <section class="app-public-section">
                <h2>Support Contact</h2>
                <p>
                    For billing, cancellation, refund, dispute, privacy, or service support questions, contact <a href="mailto:support@bepis.lol">support@bepis.lol</a>.
                </p>
            </section>
        </div>
    |]
