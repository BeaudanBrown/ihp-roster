module Application.PayRateSelection
    ( StaffPayRateSelection (..)
    , ShiftTypePayRateSelection (..)
    ) where

import Application.Helper.Controller.Input (parseUUIDText)
import Application.Helper.NominalText
import qualified Data.Text as Text
import Generated.Types
import IHP.ModelSupport.Types (Id' (Id))
import IHP.Prelude

-- These intentionally distinct values prevent staff defaults and shift-type
-- overrides from crossing request boundaries while retaining the legacy wire.
data StaffPayRateSelection
    = StaffPayRateDefault
    | StaffPayRateRosterOnly
    | StaffPayRateLegacyUnresolved
    | StaffPayRateAward !(Id AwardLevel)
    | StaffPayRateXero !(Id XeroImportedPayItem)
    deriving (Eq, Show)

data ShiftTypePayRateSelection
    = ShiftTypePayRateDefault
    | ShiftTypePayRateRosterOnly
    | ShiftTypePayRateAward !(Id AwardLevel)
    | ShiftTypePayRateXero !(Id XeroImportedPayItem)
    deriving (Eq, Show)

instance NominalText StaffPayRateSelection where
    renderNominalText StaffPayRateDefault = ""
    renderNominalText StaffPayRateRosterOnly = ""
    renderNominalText StaffPayRateLegacyUnresolved = "legacy-unresolved"
    renderNominalText (StaffPayRateAward value) = "award:" <> tshow value
    renderNominalText (StaffPayRateXero value) = "xero:" <> tshow value
    parseNominalText "legacy-unresolved" = Right StaffPayRateLegacyUnresolved
    parseNominalText value = parsePayRate StaffPayRateRosterOnly StaffPayRateRosterOnly StaffPayRateAward StaffPayRateXero value

instance NominalText ShiftTypePayRateSelection where
    renderNominalText ShiftTypePayRateDefault = ""
    renderNominalText ShiftTypePayRateRosterOnly = "roster-only"
    renderNominalText (ShiftTypePayRateAward value) = "award:" <> tshow value
    renderNominalText (ShiftTypePayRateXero value) = "xero:" <> tshow value
    parseNominalText = parsePayRate ShiftTypePayRateDefault ShiftTypePayRateRosterOnly ShiftTypePayRateAward ShiftTypePayRateXero

parsePayRate :: value -> value -> (Id AwardLevel -> value) -> (Id XeroImportedPayItem -> value) -> Text -> Either Text value
parsePayRate defaultValue rosterOnlyValue awardValue xeroValue value
    | value == "" = Right defaultValue
    | value == "roster-only" = Right rosterOnlyValue
    | Just raw <- Text.stripPrefix "award:" value = maybe invalid (Right . awardValue . Id) (parseUUIDText raw)
    | Just raw <- Text.stripPrefix "xero:" value = maybe invalid (Right . xeroValue . Id) (parseUUIDText raw)
    | otherwise = invalid
  where
    invalid = Left "Choose a pay rate from the list, or leave the default selected."
