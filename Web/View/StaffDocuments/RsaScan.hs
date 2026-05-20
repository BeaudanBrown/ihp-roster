module Web.View.StaffDocuments.RsaScan
    ( RsaScanConfirmation (..)
    , ScanView (..)
    ) where

import Application.StaffDocuments.RsaExtraction
import qualified Data.Text as Text
import Web.View.Prelude
import Web.View.StaffDocuments.Rsa

data RsaScanConfirmation = RsaScanConfirmation
    { scanStaff            :: !Staff
    , scanIssueDate        :: !(Maybe Day)
    , scanExpiryDate       :: !(Maybe Day)
    , scanIssuingAuthority :: !(Maybe Text)
    , scanDocumentNumber   :: !(Maybe Text)
    , scanFileName         :: !Text
    , scanContentType      :: !Text
    , scanFileContents     :: !Text
    , scanExtractionResult :: !RsaExtractionResult
    , scanReturnContext    :: !RsaReturnContext
    }

data ScanView = ScanView
    { scanConfirmation :: !RsaScanConfirmation
    }

instance View ScanView where
    html ScanView { scanConfirmation } =
        renderAppPage AppPageConfig
            { appPageTitle = "Confirm RSA Upload"
            , appPageDescription = Just "Review the scan results, edit anything uncertain, then save the pending RSA document."
            , appPageActions = mempty
            , appPageWidthClass = ""
            , appPageBody = [hsx|{renderScanConfirmation scanConfirmation}|]
            }

renderScanConfirmation :: RsaScanConfirmation -> Html
renderScanConfirmation confirmation@RsaScanConfirmation { scanStaff, scanExtractionResult } = [hsx|
    <div class="app-panel">
        <div class="app-panel-header">
            <div>
                <h2 class="app-panel-title mb-1">Confirm RSA metadata</h2>
                <p class="app-panel-description mb-0">File: {confirmation.scanFileName}</p>
            </div>
        </div>
        <div class="app-panel-body">
            <div class="alert alert-info py-2 px-3 small">
                Scan confidence: {tshow scanExtractionResult.confidence}%. This does not verify compliance; confirm the values before saving.
            </div>
            {renderNameCheck scanStaff scanExtractionResult.candidate.recipientName}
            {renderScanWarnings scanExtractionResult.warnings}
            <form method="POST" action={CreateStaffDocumentAction} data-disable-javascript-submission="true">
                <input type="hidden" name="staffId" value={tshow scanStaff.id}/>
                {renderRsaReturnInputs confirmation.scanReturnContext}
                <input type="hidden" name="confirmedFileName" value={confirmation.scanFileName}/>
                <input type="hidden" name="confirmedContentType" value={confirmation.scanContentType}/>
                <input type="hidden" name="confirmedFileContentsBase64" value={confirmation.scanFileContents}/>
                <div class="row g-3">
                    <div class="col-12 col-md-6">
                        <label class="form-label" for="rsa-confirm-expiry-date">Expiry Date</label>
                        <input id="rsa-confirm-expiry-date" class="form-control" type="date" name="expiryDate" value={formatMaybeDay confirmation.scanExpiryDate} required="required"/>
                    </div>
                    <div class="col-12 col-md-6">
                        <label class="form-label" for="rsa-confirm-issue-date">Issue Date</label>
                        <input id="rsa-confirm-issue-date" class="form-control" type="date" name="issueDate" value={formatMaybeDay confirmation.scanIssueDate}/>
                    </div>
                    <div class="col-12 col-md-6">
                        <label class="form-label" for="rsa-confirm-issuer">Issuer</label>
                        <input id="rsa-confirm-issuer" class="form-control" type="text" name="issuingAuthority" maxlength="160" value={fromMaybe "" confirmation.scanIssuingAuthority}/>
                    </div>
                    <div class="col-12 col-md-6">
                        <label class="form-label" for="rsa-confirm-document-number">Document Number</label>
                        <input id="rsa-confirm-document-number" class="form-control" type="text" name="documentNumber" maxlength="80" value={fromMaybe "" confirmation.scanDocumentNumber}/>
                    </div>
                </div>
                <div class="d-grid d-sm-flex gap-2 mt-3">
                    <button type="submit" class="btn btn-primary">Confirm and upload RSA</button>
                    <a class="btn btn-outline-secondary" href={rsaReturnPathFor confirmation.scanReturnContext}>Cancel</a>
                </div>
            </form>
        </div>
    </div>
|]

renderNameCheck :: Staff -> Maybe Text -> Html
renderNameCheck _ Nothing = [hsx|
    <div class="alert alert-warning py-2 px-3 small">Recipient name was not detected. Confirm the PDF belongs to the selected staff member.</div>
|]
renderNameCheck staff (Just recipientName)
    | normalizedName recipientName == normalizedName (rsaStaffDisplayName staff) = [hsx|
        <div class="alert alert-success py-2 px-3 small">Detected name: {recipientName}</div>
    |]
    | otherwise = [hsx|
        <div class="alert alert-warning py-2 px-3 small">
            Detected name "{recipientName}" does not exactly match selected staff member "{rsaStaffDisplayName staff}". You can still upload after confirming this is the right person.
        </div>
    |]

renderScanWarnings :: [Text] -> Html
renderScanWarnings [] = mempty
renderScanWarnings warnings = [hsx|
    <div class="alert alert-warning py-2 px-3 small">
        <div class="fw-semibold mb-1">Review before saving</div>
        <ul class="mb-0">
            {forEach warnings renderWarning}
        </ul>
    </div>
|]

renderWarning :: Text -> Html
renderWarning warning = [hsx|<li>{warning}</li>|]

formatMaybeDay :: Maybe Day -> Text
formatMaybeDay = maybe "" tshow

normalizedName :: Text -> Text
normalizedName = Text.toCaseFold . Text.unwords . Text.words

rsaReturnPathFor :: RsaReturnContext -> Text
rsaReturnPathFor RsaReturnContext { .. } =
    appendQueryParams basePath params
  where
    basePath =
        case rsaReturnTo of
            "admin" -> pathTo AdminAction <> "#compliance"
            "staff" -> pathTo ShowRosterWeekAction { weekOffset = fromMaybe 0 rsaReturnWeekOffset }
            _ -> pathTo EditProfileAction
    params =
        case rsaReturnTo of
            "staff" -> maybe [] (\rosterGroupId -> [("rosterGroupId", tshow rosterGroupId)]) rsaReturnRosterGroupId
            "admin" -> []
            _ -> [("section", "rsa")]

