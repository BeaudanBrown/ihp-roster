module Web.Controller.Static where
import Application.Legal.Documents
import qualified Data.ByteString as ByteString
import Network.HTTP.Types (methodGet, methodHead)
import Network.HTTP.Types.Header (hAccept)
import qualified Network.Wai as Wai
import Web.Controller.Prelude
import Web.View.Static.InstallApp
import Web.View.Static.Welcome

instance Controller StaticController where
    beforeAction = bepisBeforeAction BepisPublicController annotateTelemetryAction

    action currentAction@WelcomeAction = runBepis currentAction BepisPageAction do
        case currentUserOrNothing of
            Just _ -> redirectTo RosterWeeksAction
            Nothing -> do
                setTitle "Bepis"
                render WelcomeView
    action currentAction@NotFoundRecoveryAction = runBepis currentAction BepisPageAction do
        if isStaleBrowserPageRequest ?request
            then redirectToPath "/"
            else renderNotFound
    action currentAction@InstallAppAction = runBepis currentAction BepisPageAction do
        setTitle "Install Bepis"
        render InstallAppView
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

isStaleBrowserPageRequest :: Wai.Request -> Bool
isStaleBrowserPageRequest request =
    Wai.requestMethod request `elem` [methodGet, methodHead]
        && lookup "HX-Request" headers /= Just "true"
        && ( lookup "Sec-Fetch-Dest" headers == Just "document"
                || maybe False (ByteString.isInfixOf "text/html") (lookup hAccept headers)
           )
  where
    headers = Wai.requestHeaders request

renderLegalDocument kind = do
    legalDocument <- readLegalDocument kind
    setTitle ("Bepis " <> legalDocument.legalDocumentTitle)
    render LegalDocumentView { .. }
