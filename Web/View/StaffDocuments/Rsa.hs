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







rsaStaffDisplayName :: Staff -> Text
rsaStaffDisplayName staff =
    let displayName = Text.strip (staff.firstName <> " " <> staff.lastName)
     in if Text.null displayName then "Unnamed staff member" else displayName
