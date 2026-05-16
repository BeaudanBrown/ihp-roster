module Web.View.Admin.Compliance
    ( StaffComplianceLiveFragment (..)
    , staffComplianceFragment
    , staffComplianceLiveSurfaceDefinition
    , renderComplianceSection
    , renderComplianceSectionFragment
    ) where

import Application.Helper.Controller (currentVenueOrNothing)
import Application.Helper.LiveSurface
import Application.Helper.LiveUpdate
import Application.StaffDocuments.Rsa
import Web.View.Admin.Common
import Web.View.Prelude
import Web.View.StaffDocuments.Rsa

data StaffComplianceSurface

data StaffComplianceLiveFragment
    = StaffComplianceLiveFragment
    deriving (Eq, Show)

staffComplianceFragment :: StaffComplianceLiveFragment
staffComplianceFragment =
    StaffComplianceLiveFragment

staffComplianceFragmentId :: Text
staffComplianceFragmentId = "staff-compliance-fragment"

staffComplianceLiveSurfaceDefinition :: (?context :: ControllerContext) => TypedLiveSurfaceDefinition StaffComplianceSurface () StaffComplianceLiveFragment
staffComplianceLiveSurfaceDefinition =
    TypedLiveSurfaceDefinition
        { typedSurfaceFeature = "staff-compliance"
        , typedSurfaceScope = const (SurfaceScope StaffComplianceScope { venueId = currentVenueScopeId })
        , typedSurfaceScopeFromWire = \case
            StaffComplianceScope { venueId } | venueId == currentVenueScopeId -> Just ()
            _ -> Nothing
        , typedSurfaceDefaultFragments = const [staffComplianceFragment]
        , typedSurfaceFragmentRef = const staffComplianceLiveFragmentRef
        , typedSurfaceDecorateRequestsWithin = const ["#" <> staffComplianceFragmentId]
        , typedSurfaceAuthorize = liveSurfaceAuthorizationByRequirement (const (RequireCurrentVenueManager currentVenueScopeId))
        }

staffComplianceLiveFragmentRef :: (?context :: ControllerContext) => StaffComplianceLiveFragment -> SurfaceFragmentRef StaffComplianceSurface
staffComplianceLiveFragmentRef StaffComplianceLiveFragment =
    mkSurfaceFragmentRef
        StaffComplianceFragment
        staffComplianceFragmentId
        (pathTo ShowAdminComplianceFragmentAction)

currentVenueScopeId :: (?context :: ControllerContext) => UUID
currentVenueScopeId =
    case currentVenueOrNothing of
        Just venue -> unpackId venue.id
        Nothing -> error "Staff compliance live surface requires a current venue"

renderComplianceSectionFragment :: [StaffRsaComplianceRow] -> Day -> Html
renderComplianceSectionFragment rows today = [hsx|
    <div id={staffComplianceFragmentId}
         data-live-update-surface={liveSurfaceConfigJson (mkTypedDefinedLiveSurface staffComplianceLiveSurfaceDefinition ())}>
        {renderComplianceSection rows today}
    </div>
|]

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
