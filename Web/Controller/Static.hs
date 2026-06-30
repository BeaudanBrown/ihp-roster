module Web.Controller.Static where
import Application.Legal.Documents
import Web.Controller.Prelude
import Web.View.Static.Welcome

instance Controller StaticController where
    beforeAction = bepisBeforeAction BepisPublicController annotateTelemetryAction

    action WelcomeAction = bepisPageAction "WelcomeAction" do
        case currentUserOrNothing of
            Just _ -> redirectTo RosterWeeksAction
            Nothing -> do
                setTitle "Bepis"
                render WelcomeView
    action PublicBillingSupportAction = bepisPageAction "PublicBillingSupportAction" do
        legalPublicConfig <- readLegalPublicConfig
        setTitle "Bepis Billing and Support"
        render PublicBillingSupportView { .. }
    action LegalTermsAction = bepisPageAction "LegalTermsAction" $
        renderLegalDocument TermsDocument
    action LegalPrivacyAction = bepisPageAction "LegalPrivacyAction" $
        renderLegalDocument PrivacyDocument
    action LegalRefundsDisputesAction = bepisPageAction "LegalRefundsDisputesAction" $
        renderLegalDocument RefundsDisputesDocument
    action LegalCancellationAction = bepisPageAction "LegalCancellationAction" $
        renderLegalDocument CancellationDocument

renderLegalDocument kind = do
    legalDocument <- readLegalDocument kind
    setTitle ("Bepis " <> legalDocument.legalDocumentTitle)
    render LegalDocumentView { .. }
