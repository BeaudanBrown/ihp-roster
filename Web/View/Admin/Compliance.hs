module Web.View.Admin.Compliance
    ( renderComplianceSection
    ) where

import Application.StaffDocuments.Rsa
import Web.View.Admin.Common
import Web.View.Prelude
import Web.View.StaffDocuments.Rsa

renderComplianceSection :: [StaffRsaComplianceRow] -> Day -> Html
renderComplianceSection rows today =
    renderConfigSection
        "compliance-section"
        "Compliance"
        "Track RSA documents for active staff."
        (renderComplianceSummary rows today)
        mempty
        (renderComplianceRows rows today)

renderComplianceSummary :: [StaffRsaComplianceRow] -> Day -> Html
renderComplianceSummary rows today = [hsx|
    <div class="d-flex flex-wrap gap-2 mb-3">
        {renderAppStatusBadge AppStatusDanger (tshow missingCount <> " missing")}
        {renderAppStatusBadge AppStatusDanger (tshow expiredCount <> " expired")}
        {renderAppStatusBadge AppStatusWarning (tshow expiringCount <> " expiring")}
        {renderAppStatusBadge AppStatusWarning (tshow pendingCount <> " pending")}
        {renderAppStatusBadge AppStatusSuccess (tshow verifiedCount <> " verified")}
    </div>
|]
    where
        statuses = map (effectiveRsaComplianceStatus today . (.complianceDocument)) rows
        missingCount = length (filter (== StaffRsaMissing) statuses)
        expiredCount = length (filter (== StaffRsaExpired) statuses)
        expiringCount = length [ () | StaffRsaExpiringSoon _ <- statuses ]
        pendingCount = length (filter (== StaffRsaPendingReview) statuses)
        verifiedCount = length (filter (== StaffRsaVerified) statuses)

renderComplianceRows :: [StaffRsaComplianceRow] -> Day -> Html
renderComplianceRows rows today
    | null rows = renderEmptyState "Active staff will appear here once they are added."
    | otherwise = [hsx|
        <div class="rsa-compliance-list">
            {forEach rows (renderComplianceRow today)}
        </div>
    |]

renderComplianceRow :: Day -> StaffRsaComplianceRow -> Html
renderComplianceRow today StaffRsaComplianceRow { complianceStaff, complianceUser, complianceDocument } =
    let rsaPanel =
            renderRsaDocumentPanel
                RsaPanelConfig
                    { rsaPanelStaff = complianceStaff
                    , rsaPanelDocument = complianceDocument
                    , rsaPanelToday = today
                    , rsaPanelReturnContext =
                        RsaReturnContext
                            { rsaReturnTo = "admin"
                            , rsaReturnWeekOffset = Nothing
                            , rsaReturnRosterGroupId = Nothing
                            }
                    , rsaPanelCanReview = True
                    }
     in [hsx|
        <section class="rsa-compliance-row">
            <header class="rsa-compliance-row__header">
                <div>
                    <div class="fw-semibold">{rsaStaffDisplayName complianceStaff}</div>
                    <div class="small app-muted">{maybe "No linked login" (.email) complianceUser}</div>
                </div>
                {renderRsaStatusBadge today complianceDocument}
            </header>
            <div class="rsa-compliance-row__body">
                {rsaPanel}
            </div>
        </section>
    |]
