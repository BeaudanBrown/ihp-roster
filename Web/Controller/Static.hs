module Web.Controller.Static where
import Application.Legal.Documents
import Web.Controller.Prelude
import Web.View.Static.Welcome

instance Controller StaticController where
    beforeAction = annotateTelemetryAction

    action WelcomeAction = do
        case currentUserOrNothing of
            Just _ -> redirectTo RosterWeeksAction
            Nothing -> do
                setTitle "Bepis"
                render WelcomeView
    action PublicBillingSupportAction = do
        legalPublicConfig <- readLegalPublicConfig
        setTitle "Bepis Billing and Support"
        render PublicBillingSupportView { .. }
    action LegalTermsAction =
        renderLegalDocument TermsDocument
    action LegalPrivacyAction =
        renderLegalDocument PrivacyDocument
    action LegalRefundsDisputesAction =
        renderLegalDocument RefundsDisputesDocument
    action LegalCancellationAction =
        renderLegalDocument CancellationDocument

renderLegalDocument kind = do
    legalDocument <- readLegalDocument kind
    setTitle ("Bepis " <> legalDocument.legalDocumentTitle)
    render LegalDocumentView { .. }
