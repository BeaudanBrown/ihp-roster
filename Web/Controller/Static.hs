module Web.Controller.Static where
import Application.Legal.Documents
import Web.Controller.Prelude
import Web.View.Static.Welcome

instance Controller StaticController where
    beforeAction = bepisBeforeAction BepisPublicController annotateTelemetryAction

    action currentAction@WelcomeAction = runBepis currentAction BepisPageAction do
        case currentUserOrNothing of
            Just _ -> redirectTo RosterWeeksAction
            Nothing -> do
                setTitle "Bepis"
                render WelcomeView
    action currentAction@PublicBillingSupportAction = runBepis currentAction BepisPageAction do
        legalPublicConfig <- readLegalPublicConfig
        setTitle "Bepis Billing and Support"
        render PublicBillingSupportView { .. }
    action currentAction@LegalTermsAction = runBepis currentAction BepisPageAction $
        renderLegalDocument TermsDocument
    action currentAction@LegalPrivacyAction = runBepis currentAction BepisPageAction $
        renderLegalDocument PrivacyDocument
    action currentAction@LegalRefundsDisputesAction = runBepis currentAction BepisPageAction $
        renderLegalDocument RefundsDisputesDocument
    action currentAction@LegalCancellationAction = runBepis currentAction BepisPageAction $
        renderLegalDocument CancellationDocument

renderLegalDocument kind = do
    legalDocument <- readLegalDocument kind
    setTitle ("Bepis " <> legalDocument.legalDocumentTitle)
    render LegalDocumentView { .. }
