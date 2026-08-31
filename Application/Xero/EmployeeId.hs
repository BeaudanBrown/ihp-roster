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
    | value `elem` ["not_applicable", "unmapped"] = Left "Xero employee identifier uses a reserved mapping value."
    | otherwise = Right (XeroEmployeeId value)

xeroEmployeeIdText :: XeroEmployeeId -> Text
xeroEmployeeIdText (XeroEmployeeId value) = value

instance NominalText XeroEmployeeId where
    renderNominalText = xeroEmployeeIdText
    parseNominalText = parseXeroEmployeeId

data XeroEmployeeSelection
    = XeroEmployeeUnmapped
    | XeroEmployeeNotApplicable
    | XeroEmployeeSelected !XeroEmployeeId
    deriving (Eq, Show)

instance NominalText XeroEmployeeSelection where
    renderNominalText XeroEmployeeUnmapped = "unmapped"
    renderNominalText XeroEmployeeNotApplicable = "not_applicable"
    renderNominalText (XeroEmployeeSelected employeeId) = xeroEmployeeIdText employeeId
    parseNominalText "unmapped" = Right XeroEmployeeUnmapped
    parseNominalText "not_applicable" = Right XeroEmployeeNotApplicable
    parseNominalText value = XeroEmployeeSelected <$> parseXeroEmployeeId value
