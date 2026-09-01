module Application.Xero.ReferenceCategory
    ( allXeroReferenceSyncCategories
    , parseXeroReferenceSyncCategories
    , xeroReferenceSyncCategoriesContain
    , xeroReferenceSyncCategoryLabel
    ) where

import Application.Error.Parser (parserFailure)
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Types as Aeson
import qualified Data.Set as Set
import Generated.Types
import IHP.Prelude

allXeroReferenceSyncCategories :: Set.Set XeroReferenceSyncCategoryEnum
allXeroReferenceSyncCategories = Set.fromList [XeroStaff, PayItems, PayrollCalendars, Accounts]

parseXeroReferenceSyncCategories :: Aeson.Value -> Aeson.Parser (Set.Set XeroReferenceSyncCategoryEnum)
parseXeroReferenceSyncCategories value = do
    labels <- Aeson.parseJSON value
    categories <- mapM parseCategory labels
    let result = Set.fromList categories
    if Set.null result
        then parserFailure "Xero reference sync categories cannot be empty"
        else pure result
  where
    parseCategory :: Text -> Aeson.Parser XeroReferenceSyncCategoryEnum
    parseCategory = \case
        "staff" -> pure XeroStaff
        "pay_items" -> pure PayItems
        "payroll_calendars" -> pure PayrollCalendars
        "accounts" -> pure Accounts
        unknown -> parserFailure ("Unknown Xero reference sync category: " <> cs unknown)

xeroReferenceSyncCategoriesContain :: Set.Set XeroReferenceSyncCategoryEnum -> Set.Set XeroReferenceSyncCategoryEnum -> Bool
xeroReferenceSyncCategoriesContain available requested = requested `Set.isSubsetOf` available

xeroReferenceSyncCategoryLabel :: XeroReferenceSyncCategoryEnum -> Text
xeroReferenceSyncCategoryLabel = \case
    XeroStaff -> "staff"
    PayItems -> "pay_items"
    PayrollCalendars -> "payroll_calendars"
    Accounts -> "accounts"
