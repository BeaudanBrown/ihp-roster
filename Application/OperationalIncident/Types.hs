module Application.OperationalIncident.Types
    ( IncidentObservation (..)
    , IncidentSeverity (..)
    , IncidentTransition (..)
    , ReconciliationResult (..)
    , incidentSeverityText
    , incidentTransitionText
    , operationalIncidentMailKind
    ) where

import qualified Data.Aeson as Aeson
import Generated.Types
import IHP.Prelude

data IncidentSeverity = IncidentInfo | IncidentWarning | IncidentCritical
    deriving (Eq, Ord, Show)

data IncidentTransition
    = IncidentOpened
    | IncidentImpactEscalated
    | IncidentRecovered
    | IncidentRecurred
    deriving (Eq, Show)

data IncidentObservation = IncidentObservation
    { category       :: !Text
    , scopeKey       :: !Text
    , stableIdentity :: !Text
    , affectedSource :: !Text
    , venueId        :: !(Maybe UUID)
    , observedAt     :: !UTCTime
    , isActive       :: !Bool
    , severity       :: !IncidentSeverity
    , impactKey      :: !Text
    , impactRank     :: !Int
    , symptomCodes   :: ![Text]
    , safeMetadata   :: !Aeson.Value
    }
    deriving (Eq, Show)

data ReconciliationResult
    = IncidentUnchanged !(Maybe OperationalIncident)
    | IncidentTransitionRecorded !OperationalIncident !OperationalIncidentEvent !IncidentTransition
    deriving (Eq, Show)

incidentSeverityText :: IncidentSeverity -> Text
incidentSeverityText = \case
    IncidentInfo -> "info"
    IncidentWarning -> "warning"
    IncidentCritical -> "critical"

incidentTransitionText :: IncidentTransition -> Text
incidentTransitionText = \case
    IncidentOpened -> "opened"
    IncidentImpactEscalated -> "impact_escalated"
    IncidentRecovered -> "recovered"
    IncidentRecurred -> "recurred"

operationalIncidentMailKind :: Text
operationalIncidentMailKind = "operational_incident_transition_v1"
