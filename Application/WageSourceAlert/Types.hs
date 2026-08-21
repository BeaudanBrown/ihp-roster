module Application.WageSourceAlert.Types
    ( RefreshTrigger (..)
    , RefreshTriggerClass (..)
    , WageSourceAlertKind (..)
    , WageSourceAlertSnapshot (..)
    , WageSourceKind (..)
    , alertKindText
    , alertMailKind
    , isWageSourceAlertMailKind
    , parseAlertKind
    , parseRefreshTrigger
    , parseRefreshTriggerClass
    , parseWageSourceKind
    , refreshTriggerClassText
    , refreshTriggerText
    , wageSourceLabel
    , wageSourceText
    ) where

import qualified Data.Aeson as Aeson
import Data.Traversable (traverse)
import IHP.Prelude


data WageSourceKind
    = FwcWageSource
    | DataVicWageSource
    deriving (Eq, Ord, Show)

data RefreshTrigger
    = ScheduledFreshnessCheck
    | FinalRefreshFailure
    deriving (Eq, Show)

data RefreshTriggerClass
    = ManualRefresh
    | TimerRefresh
    deriving (Eq, Show)

data WageSourceAlertKind
    = RefreshFailedAlert
    | SourceMissingAlert
    | SourceStaleAlert
    | FwcAnnualRefreshMissingAlert
    deriving (Eq, Ord, Show)

data WageSourceAlertSnapshot = WageSourceAlertSnapshot
    { alertKind               :: !WageSourceAlertKind
    , source                  :: !WageSourceKind
    , detectedAt              :: !UTCTime
    , sourceJobId             :: !UUID
    , refreshTriggerClass     :: !(Maybe RefreshTriggerClass)
    , affectedYears           :: ![Integer]
    , latestValidSuccessAt    :: !(Maybe UTCTime)
    , freshnessMaximumAge     :: !(Maybe NominalDiffTime)
    , annualRequiredOnOrAfter :: !(Maybe Day)
    , annualTriggerVenueId    :: !(Maybe UUID)
    }
    deriving (Eq, Show)

instance Aeson.ToJSON WageSourceAlertSnapshot where
    toJSON snapshot =
        Aeson.object
            [ "alertKind" Aeson..= alertKindText snapshot.alertKind
            , "source" Aeson..= wageSourceText snapshot.source
            , "detectedAt" Aeson..= snapshot.detectedAt
            , "sourceJobId" Aeson..= snapshot.sourceJobId
            , "refreshTriggerClass" Aeson..= fmap refreshTriggerClassText snapshot.refreshTriggerClass
            , "affectedYears" Aeson..= snapshot.affectedYears
            , "latestValidSuccessAt" Aeson..= snapshot.latestValidSuccessAt
            , "freshnessMaximumAgeSeconds" Aeson..= fmap (floor @NominalDiffTime @Integer) snapshot.freshnessMaximumAge
            , "annualRequiredOnOrAfter" Aeson..= snapshot.annualRequiredOnOrAfter
            , "annualTriggerVenueId" Aeson..= snapshot.annualTriggerVenueId
            ]

instance Aeson.FromJSON WageSourceAlertSnapshot where
    parseJSON = Aeson.withObject "WageSourceAlertSnapshot" \object -> do
        rawAlertKind <- object Aeson..: "alertKind"
        parsedAlertKind <- maybe (fail "Unknown wage-source alert kind") pure (parseAlertKind rawAlertKind)
        rawSource <- object Aeson..: "source"
        parsedSource <- maybe (fail "Unknown wage source") pure (parseWageSourceKind rawSource)
        rawTriggerClass <- object Aeson..:? "refreshTriggerClass"
        parsedTriggerClass <- traverse (maybe (fail "Unknown refresh trigger class") pure . parseRefreshTriggerClass) rawTriggerClass
        maximumAgeSeconds <- object Aeson..:? "freshnessMaximumAgeSeconds"
        WageSourceAlertSnapshot
            <$> pure parsedAlertKind
            <*> pure parsedSource
            <*> object Aeson..: "detectedAt"
            <*> object Aeson..: "sourceJobId"
            <*> pure parsedTriggerClass
            <*> object Aeson..:? "affectedYears" Aeson..!= []
            <*> object Aeson..:? "latestValidSuccessAt"
            <*> pure (fromInteger <$> maximumAgeSeconds)
            <*> object Aeson..:? "annualRequiredOnOrAfter"
            <*> object Aeson..:? "annualTriggerVenueId"

wageSourceText :: WageSourceKind -> Text
wageSourceText FwcWageSource     = "fwc_mapd"
wageSourceText DataVicWageSource = "data_vic_public_holidays"

parseWageSourceKind :: Text -> Maybe WageSourceKind
parseWageSourceKind "fwc_mapd"                 = Just FwcWageSource
parseWageSourceKind "data_vic_public_holidays" = Just DataVicWageSource
parseWageSourceKind _                          = Nothing

wageSourceLabel :: WageSourceKind -> Text
wageSourceLabel FwcWageSource     = "Fair Work Commission MAPD"
wageSourceLabel DataVicWageSource = "DataVic public holidays"

refreshTriggerText :: RefreshTrigger -> Text
refreshTriggerText ScheduledFreshnessCheck = "scheduled_freshness_check"
refreshTriggerText FinalRefreshFailure     = "final_refresh_failure"

parseRefreshTrigger :: Text -> Maybe RefreshTrigger
parseRefreshTrigger "scheduled_freshness_check" = Just ScheduledFreshnessCheck
parseRefreshTrigger "final_refresh_failure"     = Just FinalRefreshFailure
parseRefreshTrigger _                           = Nothing

refreshTriggerClassText :: RefreshTriggerClass -> Text
refreshTriggerClassText ManualRefresh = "manual"
refreshTriggerClassText TimerRefresh  = "timer"

parseRefreshTriggerClass :: Text -> Maybe RefreshTriggerClass
parseRefreshTriggerClass "manual" = Just ManualRefresh
parseRefreshTriggerClass "timer"  = Just TimerRefresh
parseRefreshTriggerClass _        = Nothing

alertKindText :: WageSourceAlertKind -> Text
alertKindText RefreshFailedAlert           = "refresh_failed"
alertKindText SourceMissingAlert           = "source_missing"
alertKindText SourceStaleAlert             = "source_stale"
alertKindText FwcAnnualRefreshMissingAlert = "fwc_annual_refresh_missing"

parseAlertKind :: Text -> Maybe WageSourceAlertKind
parseAlertKind "refresh_failed"             = Just RefreshFailedAlert
parseAlertKind "source_missing"             = Just SourceMissingAlert
parseAlertKind "source_stale"               = Just SourceStaleAlert
parseAlertKind "fwc_annual_refresh_missing" = Just FwcAnnualRefreshMissingAlert
parseAlertKind _                            = Nothing

alertMailKind :: WageSourceKind -> WageSourceAlertKind -> Text
alertMailKind source kind =
    "wage_source_" <> wageSourceText source <> "_" <> alertKindText kind <> "_v1"

isWageSourceAlertMailKind :: Text -> Bool
isWageSourceAlertMailKind candidate =
    candidate `elem`
        [ alertMailKind source kind
        | source <- [FwcWageSource, DataVicWageSource]
        , kind <- [RefreshFailedAlert, SourceMissingAlert, SourceStaleAlert, FwcAnnualRefreshMissingAlert]
        , not (source == DataVicWageSource && kind == FwcAnnualRefreshMissingAlert)
        ]
