module Application.Xero.EmployeeId
    ( XeroEmployeeId
    , XeroEmployeeSelection (..)
    , parseXeroEmployeeId
    , xeroEmployeeIdText
    ) where

import Application.Helper.NominalText
import qualified Data.Text as Text
import IHP.Prelude

-- Constructor stays private: provider identifiers enter through this owner.
newtype XeroEmployeeId = XeroEmployeeId Text
    deriving (Eq, Ord, Show)

parseXeroEmployeeId :: Text -> Either Text XeroEmployeeId
parseXeroEmployeeId value
    | Text.null (Text.strip value) = Left "Xero employee identifier is empty."
    | value == "not_applicable" = Left "Xero employee identifier uses the reserved not-applicable value."
    | otherwise = Right (XeroEmployeeId value)

xeroEmployeeIdText :: XeroEmployeeId -> Text
xeroEmployeeIdText (XeroEmployeeId value) = value

instance NominalText XeroEmployeeId where
    renderNominalText = xeroEmployeeIdText
    parseNominalText = parseXeroEmployeeId

data XeroEmployeeSelection
    = XeroEmployeeNotApplicable
    | XeroEmployeeSelected !XeroEmployeeId
    deriving (Eq, Show)

instance NominalText XeroEmployeeSelection where
    renderNominalText XeroEmployeeNotApplicable = "not_applicable"
    renderNominalText (XeroEmployeeSelected employeeId) = xeroEmployeeIdText employeeId
    parseNominalText "not_applicable" = Right XeroEmployeeNotApplicable
    parseNominalText value = XeroEmployeeSelected <$> parseXeroEmployeeId value
