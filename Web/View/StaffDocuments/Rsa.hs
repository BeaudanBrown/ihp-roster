module Web.View.StaffDocuments.Rsa
    ( RsaPanelConfig (..)
    , RsaReturnContext (..)
    , renderRsaReturnInputs
    , rsaStaffDisplayName
    ) where

import Application.StaffDocuments.Rsa
import qualified Data.Text as Text
import Web.View.Prelude

data RsaReturnContext = RsaReturnContext
    { rsaReturnTo            :: !Text
    , rsaReturnAnchorDate    :: !(Maybe Day)
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










renderRsaReturnInputs :: RsaReturnContext -> Html
renderRsaReturnInputs RsaReturnContext { .. } = [hsx|
    <input type="hidden" name="returnTo" value={rsaReturnTo}/>
    {forEach rsaReturnAnchorDate renderAnchorDateInput}
    {forEach rsaReturnRosterGroupId renderRosterGroupInput}
|]

renderAnchorDateInput :: Day -> Html
renderAnchorDateInput anchorDate = [hsx|
    <input type="hidden" name="anchorDate" value={tshow anchorDate}/>
|]

renderRosterGroupInput :: Id RosterGroup -> Html
renderRosterGroupInput rosterGroupId = [hsx|
    <input type="hidden" name="rosterGroupId" value={tshow rosterGroupId}/>
|]







rsaStaffDisplayName :: Staff -> Text
rsaStaffDisplayName staff =
    let displayName = Text.strip (staff.firstName <> " " <> staff.lastName)
     in if Text.null displayName then "Unnamed staff member" else displayName
