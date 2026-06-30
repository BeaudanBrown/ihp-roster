module Web.Controller.Static where
import Application.Legal.Documents
import Web.Controller.Prelude
import Web.View.Static.Welcome

instance Controller StaticController where
    beforeAction = bepisBeforeAction BepisPublicController annotateTelemetryAction

    action currentAction@WelcomeAction = bepisPageAction currentAction do
        case currentUserOrNothing of
            Just _ -> redirectTo RosterWeeksAction
            Nothing -> do
                setTitle "Bepis"
                render WelcomeView
    action currentAction@PublicBillingSupportAction = bepisPageAction currentAction do
        legalPublicConfig <- readLegalPublicConfig
        setTitle "Bepis Billing and Support"
        render PublicBillingSupportView { .. }
    action currentAction@LegalTermsAction = bepisPageAction currentAction $
        renderLegalDocument TermsDocument
    action currentAction@LegalPrivacyAction = bepisPageAction currentAction $
        renderLegalDocument PrivacyDocument
    action currentAction@LegalRefundsDisputesAction = bepisPageAction currentAction $
        renderLegalDocument RefundsDisputesDocument
    action currentAction@LegalCancellationAction = bepisPageAction currentAction $
        renderLegalDocument CancellationDocument

renderLegalDocument kind = do
    legalDocument <- readLegalDocument kind
    setTitle ("Bepis " <> legalDocument.legalDocumentTitle)
    render LegalDocumentView { .. }
