module Web.View.StaffDocuments.Rsa
    ( RsaPanelConfig (..)
    , RsaReturnContext (..)
    , renderRsaDocumentPanel
    , renderRsaReturnInputs
    , renderRsaStatusBadge
    , renderRsaStateStatusBadge
    , renderRsaUploadOnlyPanel
    , rsaStaffDisplayName
    , rsaStatusLabel
    ) where

import Application.StaffDocuments.Rsa
import qualified Data.Text as Text
import Web.View.Prelude

data RsaReturnContext = RsaReturnContext
    { rsaReturnTo            :: !Text
    , rsaReturnWeekOffset    :: !(Maybe Int)
    , rsaReturnRosterGroupId :: !(Maybe (Id RosterGroup))
    }

data RsaPanelConfig = RsaPanelConfig
    { rsaPanelStaff         :: !Staff
    , rsaPanelDocument      :: !(Maybe StaffDocument)
    , rsaPanelToday         :: !Day
    , rsaPanelReturnContext :: !RsaReturnContext
    , rsaPanelCanReview     :: !Bool
    , rsaPanelShowHeader    :: !Bool
    }

renderRsaDocumentPanel :: RsaPanelConfig -> Html
renderRsaDocumentPanel config@RsaPanelConfig { rsaPanelStaff, rsaPanelDocument, rsaPanelToday, rsaPanelShowHeader } = [hsx|
    <div class="rsa-document-panel">
        {renderRsaPanelHeader rsaPanelShowHeader rsaPanelToday rsaPanelDocument}
        {renderCurrentRsaSummary config}
        <div class="mt-3">
            {renderRsaUploadForm rsaPanelStaff config.rsaPanelReturnContext}
        </div>
    </div>
|]

renderRsaPanelHeader :: Bool -> Day -> Maybe StaffDocument -> Html
renderRsaPanelHeader False _ _ = mempty
renderRsaPanelHeader True today maybeDocument = [hsx|
    <div class="d-flex flex-wrap align-items-start justify-content-between gap-2 mb-3">
        <div>
            <h5 class="mb-1">RSA</h5>
            <p class="app-muted mb-0">Upload a Responsible Service of Alcohol statement of attainment.</p>
        </div>
        {renderRsaStatusBadge today maybeDocument}
    </div>
|]

renderRsaUploadOnlyPanel :: Staff -> RsaReturnContext -> Html
renderRsaUploadOnlyPanel staff returnContext = [hsx|
    <div class="rsa-document-panel">
        <h5 class="mb-1">RSA</h5>
        <p class="app-muted mb-3">Upload a Responsible Service of Alcohol statement of attainment.</p>
        {renderRsaUploadForm staff returnContext}
    </div>
|]

renderCurrentRsaSummary :: RsaPanelConfig -> Html
renderCurrentRsaSummary RsaPanelConfig { rsaPanelDocument = Nothing } = [hsx|
    <div class="rsa-current-document rsa-current-document--missing">
        <div class="fw-semibold">No RSA document on file</div>
        <div class="small app-muted">Upload the current document and include the expiry date.</div>
    </div>
|]
renderCurrentRsaSummary RsaPanelConfig { rsaPanelDocument = Just staffDocument, rsaPanelReturnContext, rsaPanelCanReview } = [hsx|
    <div class="rsa-current-document">
        <div class="d-flex flex-wrap align-items-start justify-content-between gap-3">
            <div>
                <div class="fw-semibold">{staffDocument.fileName}</div>
                <dl class="row small mb-0 mt-2">
                    <dt class="col-sm-4">Expiry</dt>
                    <dd class="col-sm-8">{tshow staffDocument.expiryDate}</dd>
                    {forEach staffDocument.issueDate renderIssueDate}
                    {forEach staffDocument.issuingAuthority (renderOptionalMeta "Issuer")}
                    {forEach staffDocument.documentNumber (renderOptionalMeta "Document no.")}
                </dl>
                {renderRejectionReason staffDocument}
            </div>
            <div class="d-flex flex-wrap gap-2">
                <a class="btn btn-outline-secondary btn-sm"
                   href={appendRsaReturnParams (pathTo (DownloadStaffDocumentAction staffDocument.id)) rsaPanelReturnContext}>
                    Download
                </a>
            </div>
        </div>
        {when rsaPanelCanReview (renderRsaReviewControls staffDocument rsaPanelReturnContext)}
    </div>
|]

renderIssueDate :: Day -> Html
renderIssueDate issueDate = [hsx|
    <dt class="col-sm-4">Issued</dt>
    <dd class="col-sm-8">{tshow issueDate}</dd>
|]

renderOptionalMeta :: Text -> Text -> Html
renderOptionalMeta label value = [hsx|
    <dt class="col-sm-4">{label}</dt>
    <dd class="col-sm-8">{value}</dd>
|]

renderRejectionReason :: StaffDocument -> Html
renderRejectionReason staffDocument =
    case staffDocument.rejectionReason of
        Just reason | staffDocument.status == Rejected -> [hsx|
            <div class="alert alert-warning py-2 px-3 mt-3 mb-0 small">{reason}</div>
        |]
        _ -> mempty

renderRsaUploadForm :: Staff -> RsaReturnContext -> Html
renderRsaUploadForm staff returnContext = [hsx|
    <form method="POST"
          action={ScanStaffDocumentAction}
          enctype="multipart/form-data"
          class="rsa-upload-form"
          data-disable-javascript-submission="true">
        <input type="hidden" name="staffId" value={tshow staff.id}/>
        {renderRsaReturnInputs returnContext}
        <div class="row g-3">
            <div class="col-12">
                <label class="form-label" for={rsaInputId staff "documentFile"}>RSA PDF</label>
                <input id={rsaInputId staff "documentFile"} class="form-control" type="file" name="documentFile" accept="application/pdf" required="required"/>
                <div class="form-text">Upload a PDF first. We will scan it for candidate dates and details before you confirm.</div>
            </div>
        </div>
        <div class="d-grid d-sm-flex gap-2 mt-3">
            <button type="submit" class="btn btn-primary">Upload and scan PDF</button>
        </div>
    </form>
|]

renderRsaReviewControls :: StaffDocument -> RsaReturnContext -> Html
renderRsaReviewControls staffDocument returnContext = [hsx|
    <div class="rsa-review-controls mt-3 pt-3 border-top">
        <div class="d-flex flex-wrap gap-2">
            <form method="POST" action={ReviewStaffDocumentAction staffDocument.id} data-disable-javascript-submission="true">
                {renderRsaReturnInputs returnContext}
                <input type="hidden" name="status" value="verified"/>
                <button type="submit" class="btn btn-success btn-sm">Verify</button>
            </form>
            <form method="POST" action={ReviewStaffDocumentAction staffDocument.id} class="d-flex flex-wrap gap-2" data-disable-javascript-submission="true">
                {renderRsaReturnInputs returnContext}
                <input type="hidden" name="status" value="rejected"/>
                <input class="form-control form-control-sm rsa-rejection-input" name="rejectionReason" maxlength="500" placeholder="Rejection reason"/>
                <button type="submit" class="btn btn-outline-danger btn-sm">Reject</button>
            </form>
        </div>
    </div>
|]

renderRsaReturnInputs :: RsaReturnContext -> Html
renderRsaReturnInputs RsaReturnContext { .. } = [hsx|
    <input type="hidden" name="returnTo" value={rsaReturnTo}/>
    {forEach rsaReturnWeekOffset renderWeekOffsetInput}
    {forEach rsaReturnRosterGroupId renderRosterGroupInput}
|]

renderWeekOffsetInput :: Int -> Html
renderWeekOffsetInput weekOffset = [hsx|
    <input type="hidden" name="weekOffset" value={tshow weekOffset}/>
|]

renderRosterGroupInput :: Id RosterGroup -> Html
renderRosterGroupInput rosterGroupId = [hsx|
    <input type="hidden" name="rosterGroupId" value={tshow rosterGroupId}/>
|]

appendRsaReturnParams :: Text -> RsaReturnContext -> Text
appendRsaReturnParams basePath RsaReturnContext { .. } =
    appendQueryParams basePath $
        [("returnTo", rsaReturnTo)]
            <> maybe [] (\weekOffset -> [("weekOffset", tshow weekOffset)]) rsaReturnWeekOffset
            <> maybe [] (\rosterGroupId -> [("rosterGroupId", tshow rosterGroupId)]) rsaReturnRosterGroupId

renderRsaStatusBadge :: Day -> Maybe StaffDocument -> Html
renderRsaStatusBadge today maybeDocument =
    uncurry renderAppStatusBadge (rsaStatusBadgeParts (effectiveRsaComplianceStatus today maybeDocument))

renderRsaStateStatusBadge :: StaffRsaEffectiveState -> Html
renderRsaStateStatusBadge state =
    uncurry renderAppStatusBadge (rsaStatusBadgeParts state.rsaEffectiveStatus)

rsaStatusBadgeParts :: StaffRsaComplianceStatus -> (AppStatusTone, Text)
rsaStatusBadgeParts StaffRsaMissing           = (AppStatusDanger, "Missing")
rsaStatusBadgeParts StaffRsaPendingReview     = (AppStatusWarning, "Pending review")
rsaStatusBadgeParts StaffRsaPendingReplacement = (AppStatusWarning, "Pending replacement")
rsaStatusBadgeParts StaffRsaVerified          = (AppStatusSuccess, "Verified")
rsaStatusBadgeParts (StaffRsaExpiringSoon daysRemaining) = (AppStatusWarning, "Expires in " <> tshow daysRemaining <> "d")
rsaStatusBadgeParts StaffRsaExpired           = (AppStatusDanger, "Expired")
rsaStatusBadgeParts StaffRsaRejected          = (AppStatusDanger, "Rejected")

rsaStatusLabel :: Day -> Maybe StaffDocument -> Text
rsaStatusLabel today maybeDocument =
    snd (rsaStatusBadgeParts (effectiveRsaComplianceStatus today maybeDocument))

rsaInputId :: Staff -> Text -> Text
rsaInputId staff suffix =
    "rsa-" <> tshow staff.id <> "-" <> suffix

rsaStaffDisplayName :: Staff -> Text
rsaStaffDisplayName staff =
    let displayName = Text.strip (staff.firstName <> " " <> staff.lastName)
     in if Text.null displayName then "Unnamed staff member" else displayName
