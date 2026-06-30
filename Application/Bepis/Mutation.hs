module Application.Bepis.Mutation
    ( BepisAuditEvidence (..)
    , BepisAuditPolicy (..)
    , BepisMutation (..)
    , BepisMutationComponentContract (..)
    , BepisMutationOutcome (..)
    , BepisMutationSpec (..)
    , BepisRealtimeEvidence (..)
    , BepisRealtimePolicy (..)
    , BepisResponseEvidence (..)
    , BepisScopeEvidence (..)
    , BepisScopePolicy (..)
    , auditedAs
    , bepisAuditPolicyText
    , bepisMutationComponentContracts
    , bepisCurrentUserMutationSpec
    , bepisCurrentVenueMutationSpec
    , bepisNoScopeMutationSpec
    , bepisSupportMutationSpec
    , bepisMutationSpecAttributes
    , bepisMutationSpecPolicyVocabulary
    , bepisVenueRosterWeekMutationSpec
    , bepisRealtimePolicyText
    , bepisScopePolicyText
    , fromLiveMutationResult
    , newMutation
    , respondsWithFragments
    , respondsWithJson
    , respondsWithRedirect
    , runBepisMutationPipeline
    , scopedToCurrentUser
    , scopedToCurrentVenue
    , scopedToRosterWeek
    , scopedToSupport
    , withNoRealtimeInvalidation
    ) where

import Application.Helper.LiveResource (LiveMutationResult (..), LiveResource)
import Application.Helper.Telemetry (addTelemetryAttributes)
import qualified Data.Set as Set
import GHC.Generics (Generic)
import IHP.Prelude
import OpenTelemetry.Attributes (Attribute, toAttribute)

-- | Whether a mutation is expected to produce audit evidence. This is initially
-- descriptive; later wrappers can make high-risk mutation effects structural.
data BepisAuditPolicy
    = BepisAuditNotRequired
    | BepisAuditRequired
    | BepisAuditForbidden
    deriving (Eq, Show, Generic)

-- | Realtime/live freshness expectation for a mutation.
data BepisRealtimePolicy
    = BepisRealtimeNotApplicable
    | BepisNoRealtimeInvalidation
    | BepisEmitsRealtimeInvalidation
    | BepisRefetchesLiveFragment
    deriving (Eq, Show, Generic)

-- | Coarse app-owned mutation scope. Specific scope keys stay with the feature
-- modules; this label keeps architecture facts low-cardinality and safe.
data BepisScopePolicy
    = BepisNoScopePolicy
    | BepisCurrentUserScope
    | BepisCurrentVenueScope
    | BepisVenueRosterWeekScope
    | BepisVenueRosterGroupScope
    | BepisSupportScope
    deriving (Eq, Show, Generic)

data BepisMutationSpec = BepisMutationSpec
    { auditPolicy    :: !BepisAuditPolicy
    , realtimePolicy :: !BepisRealtimePolicy
    , scopePolicy    :: !BepisScopePolicy
    }
    deriving (Eq, Show, Generic)

data BepisScopeEvidence = BepisScopeEvidence
    { scopeEvidencePolicy :: !BepisScopePolicy
    , scopeEvidenceLabel  :: !Text
    }
    deriving (Eq, Show, Generic)

data BepisAuditEvidence = BepisAuditEvidence
    { auditEvidencePolicy :: !BepisAuditPolicy
    , auditEvidenceLabel  :: !Text
    }
    deriving (Eq, Show, Generic)

data BepisRealtimeEvidence = BepisRealtimeEvidence
    { realtimeEvidencePolicy           :: !BepisRealtimePolicy
    , realtimeEvidenceLabel            :: !Text
    , realtimeEvidenceTouchedResources :: !(Set.Set LiveResource)
    }
    deriving (Eq, Show, Generic)

data BepisResponseEvidence = BepisResponseEvidence
    { responseEvidenceKinds :: ![Text]
    , responseEvidenceLabel :: !Text
    }
    deriving (Eq, Show, Generic)

data BepisMutationOutcome a = BepisMutationOutcome
    { mutationOutcomeValue            :: !a
    , mutationOutcomeScopeEvidence    :: ![BepisScopeEvidence]
    , mutationOutcomeAuditEvidence    :: ![BepisAuditEvidence]
    , mutationOutcomeRealtimeEvidence :: ![BepisRealtimeEvidence]
    , mutationOutcomeResponseEvidence :: ![BepisResponseEvidence]
    }
    deriving (Eq, Show, Generic)

newtype BepisMutation a = BepisMutation
    { runBepisMutationOutcome :: IO (BepisMutationOutcome a)
    }

data BepisMutationComponentContract = BepisMutationComponentContract
    { mutationComponentName        :: !Text
    , mutationComponentCapability  :: !Text
    , mutationComponentDescription :: !Text
    }
    deriving (Eq, Show, Generic)

bepisNoScopeMutationSpec :: BepisMutationSpec
bepisNoScopeMutationSpec = BepisMutationSpec
    { auditPolicy = BepisAuditNotRequired
    , realtimePolicy = BepisRealtimeNotApplicable
    , scopePolicy = BepisNoScopePolicy
    }

bepisCurrentUserMutationSpec :: BepisMutationSpec
bepisCurrentUserMutationSpec = BepisMutationSpec
    { auditPolicy = BepisAuditNotRequired
    , realtimePolicy = BepisRealtimeNotApplicable
    , scopePolicy = BepisCurrentUserScope
    }

bepisCurrentVenueMutationSpec :: BepisMutationSpec
bepisCurrentVenueMutationSpec = BepisMutationSpec
    { auditPolicy = BepisAuditNotRequired
    , realtimePolicy = BepisNoRealtimeInvalidation
    , scopePolicy = BepisCurrentVenueScope
    }

bepisVenueRosterWeekMutationSpec :: BepisMutationSpec
bepisVenueRosterWeekMutationSpec = BepisMutationSpec
    { auditPolicy = BepisAuditNotRequired
    , realtimePolicy = BepisEmitsRealtimeInvalidation
    , scopePolicy = BepisVenueRosterWeekScope
    }

bepisSupportMutationSpec :: BepisMutationSpec
bepisSupportMutationSpec = BepisMutationSpec
    { auditPolicy = BepisAuditNotRequired
    , realtimePolicy = BepisNoRealtimeInvalidation
    , scopePolicy = BepisSupportScope
    }

newMutation :: IO a -> BepisMutation a
newMutation action = BepisMutation do
    value <- action
    pure emptyBepisMutationOutcome { mutationOutcomeValue = value }

runBepisMutationPipeline :: BepisMutation a -> IO a
runBepisMutationPipeline mutation = do
    outcome <- runBepisMutationOutcome mutation
    addTelemetryAttributes (bepisMutationOutcomeAttributes outcome)
    pure outcome.mutationOutcomeValue

scopedToCurrentUser :: BepisMutation a -> BepisMutation a
scopedToCurrentUser = addScopeEvidence (BepisScopeEvidence BepisCurrentUserScope "current-user")

scopedToCurrentVenue :: BepisMutation a -> BepisMutation a
scopedToCurrentVenue = addScopeEvidence (BepisScopeEvidence BepisCurrentVenueScope "current-venue")

scopedToRosterWeek :: Text -> BepisMutation a -> BepisMutation a
scopedToRosterWeek label = addScopeEvidence (BepisScopeEvidence BepisVenueRosterWeekScope label)

scopedToSupport :: BepisMutation a -> BepisMutation a
scopedToSupport = addScopeEvidence (BepisScopeEvidence BepisSupportScope "support")

auditedAs :: Text -> BepisMutation a -> BepisMutation a
auditedAs label = addAuditEvidence (BepisAuditEvidence BepisAuditRequired label)

withNoRealtimeInvalidation :: Text -> BepisMutation a -> BepisMutation a
withNoRealtimeInvalidation label = addRealtimeEvidence (BepisRealtimeEvidence BepisNoRealtimeInvalidation label Set.empty)

fromLiveMutationResult :: Text -> BepisMutation (LiveMutationResult a) -> BepisMutation a
fromLiveMutationResult label (BepisMutation action) = BepisMutation do
    outcome <- action
    let liveResult = outcome.mutationOutcomeValue
    pure outcome
        { mutationOutcomeValue = liveResult.liveMutationValue
        , mutationOutcomeRealtimeEvidence = outcome.mutationOutcomeRealtimeEvidence <> [BepisRealtimeEvidence BepisEmitsRealtimeInvalidation label liveResult.liveMutationTouchedResources]
        }

respondsWithRedirect :: Text -> BepisMutation a -> BepisMutation a
respondsWithRedirect = addResponseEvidence . BepisResponseEvidence ["redirect"]

respondsWithFragments :: Text -> BepisMutation a -> BepisMutation a
respondsWithFragments = addResponseEvidence . BepisResponseEvidence ["htmx-fragment"]

respondsWithJson :: Text -> BepisMutation a -> BepisMutation a
respondsWithJson = addResponseEvidence . BepisResponseEvidence ["json"]

addScopeEvidence :: BepisScopeEvidence -> BepisMutation a -> BepisMutation a
addScopeEvidence evidence (BepisMutation action) = BepisMutation do
    outcome <- action
    pure outcome { mutationOutcomeScopeEvidence = outcome.mutationOutcomeScopeEvidence <> [evidence] }

addAuditEvidence :: BepisAuditEvidence -> BepisMutation a -> BepisMutation a
addAuditEvidence evidence (BepisMutation action) = BepisMutation do
    outcome <- action
    pure outcome { mutationOutcomeAuditEvidence = outcome.mutationOutcomeAuditEvidence <> [evidence] }

addRealtimeEvidence :: BepisRealtimeEvidence -> BepisMutation a -> BepisMutation a
addRealtimeEvidence evidence (BepisMutation action) = BepisMutation do
    outcome <- action
    pure outcome { mutationOutcomeRealtimeEvidence = outcome.mutationOutcomeRealtimeEvidence <> [evidence] }

addResponseEvidence :: BepisResponseEvidence -> BepisMutation a -> BepisMutation a
addResponseEvidence evidence (BepisMutation action) = BepisMutation do
    outcome <- action
    pure outcome { mutationOutcomeResponseEvidence = outcome.mutationOutcomeResponseEvidence <> [evidence] }

emptyBepisMutationOutcome :: BepisMutationOutcome ()
emptyBepisMutationOutcome = BepisMutationOutcome
    { mutationOutcomeValue = ()
    , mutationOutcomeScopeEvidence = []
    , mutationOutcomeAuditEvidence = []
    , mutationOutcomeRealtimeEvidence = []
    , mutationOutcomeResponseEvidence = []
    }

bepisMutationOutcomeAttributes :: BepisMutationOutcome a -> [(Text, Attribute)]
bepisMutationOutcomeAttributes outcome =
    [ ("bepis.mutation.pipeline.scope_policies", toAttribute (joinedScopePolicies outcome))
    , ("bepis.mutation.pipeline.audit_policies", toAttribute (joinedAuditPolicies outcome))
    , ("bepis.mutation.pipeline.realtime_policies", toAttribute (joinedRealtimePolicies outcome))
    , ("bepis.mutation.pipeline.response_kinds", toAttribute (joinedResponseKinds outcome))
    ]

joinedScopePolicies :: BepisMutationOutcome a -> Text
joinedScopePolicies = intercalate "," . map (bepisScopePolicyText . (.scopeEvidencePolicy)) . (.mutationOutcomeScopeEvidence)

joinedAuditPolicies :: BepisMutationOutcome a -> Text
joinedAuditPolicies = intercalate "," . map (bepisAuditPolicyText . (.auditEvidencePolicy)) . (.mutationOutcomeAuditEvidence)

joinedRealtimePolicies :: BepisMutationOutcome a -> Text
joinedRealtimePolicies = intercalate "," . map (bepisRealtimePolicyText . (.realtimeEvidencePolicy)) . (.mutationOutcomeRealtimeEvidence)

joinedResponseKinds :: BepisMutationOutcome a -> Text
joinedResponseKinds = intercalate "," . concatMap (.responseEvidenceKinds) . (.mutationOutcomeResponseEvidence)

bepisMutationComponentContracts :: [BepisMutationComponentContract]
bepisMutationComponentContracts =
    [ BepisMutationComponentContract "newMutation" "core" "Creates a Bepis mutation pipeline from an IO action."
    , BepisMutationComponentContract "scopedToCurrentUser" "scope" "Attaches current-user scope evidence."
    , BepisMutationComponentContract "scopedToCurrentVenue" "scope" "Attaches current-venue scope evidence."
    , BepisMutationComponentContract "scopedToRosterWeek" "scope" "Attaches venue-roster-week scope evidence with a feature label."
    , BepisMutationComponentContract "scopedToSupport" "scope" "Attaches founder/support scope evidence."
    , BepisMutationComponentContract "auditedAs" "audit" "Attaches required audit evidence after the supplied mutation action performs the audit side effect."
    , BepisMutationComponentContract "fromLiveMutationResult" "realtime" "Consumes LiveMutationResult output and attaches touched-resource realtime evidence."
    , BepisMutationComponentContract "withNoRealtimeInvalidation" "realtime" "Attaches explicit no-realtime-invalidation evidence."
    , BepisMutationComponentContract "respondsWithRedirect" "response" "Attaches redirect response evidence."
    , BepisMutationComponentContract "respondsWithFragments" "response" "Attaches HTMX fragment response evidence."
    , BepisMutationComponentContract "respondsWithJson" "response" "Attaches JSON response evidence."
    , BepisMutationComponentContract "runBepisMutationPipeline" "boundary" "Runs the pipeline, emits telemetry attributes, and returns the mutation value."
    ]

bepisAuditPolicyText :: BepisAuditPolicy -> Text
bepisAuditPolicyText = \case
    BepisAuditNotRequired -> "not-required"
    BepisAuditRequired -> "required"
    BepisAuditForbidden -> "forbidden"

bepisRealtimePolicyText :: BepisRealtimePolicy -> Text
bepisRealtimePolicyText = \case
    BepisRealtimeNotApplicable -> "not-applicable"
    BepisNoRealtimeInvalidation -> "none"
    BepisEmitsRealtimeInvalidation -> "emits-invalidation"
    BepisRefetchesLiveFragment -> "refetches-live-fragment"

bepisScopePolicyText :: BepisScopePolicy -> Text
bepisScopePolicyText = \case
    BepisNoScopePolicy -> "none"
    BepisCurrentUserScope -> "current-user"
    BepisCurrentVenueScope -> "current-venue"
    BepisVenueRosterWeekScope -> "venue-roster-week"
    BepisVenueRosterGroupScope -> "venue-roster-group"
    BepisSupportScope -> "support"

bepisMutationSpecPolicyVocabulary :: [(Text, Text, Text)]
bepisMutationSpecPolicyVocabulary =
    [ ("audit", "BepisAuditNotRequired", bepisAuditPolicyText BepisAuditNotRequired)
    , ("audit", "BepisAuditRequired", bepisAuditPolicyText BepisAuditRequired)
    , ("audit", "BepisAuditForbidden", bepisAuditPolicyText BepisAuditForbidden)
    , ("realtime", "BepisRealtimeNotApplicable", bepisRealtimePolicyText BepisRealtimeNotApplicable)
    , ("realtime", "BepisNoRealtimeInvalidation", bepisRealtimePolicyText BepisNoRealtimeInvalidation)
    , ("realtime", "BepisEmitsRealtimeInvalidation", bepisRealtimePolicyText BepisEmitsRealtimeInvalidation)
    , ("realtime", "BepisRefetchesLiveFragment", bepisRealtimePolicyText BepisRefetchesLiveFragment)
    , ("scope", "BepisNoScopePolicy", bepisScopePolicyText BepisNoScopePolicy)
    , ("scope", "BepisCurrentUserScope", bepisScopePolicyText BepisCurrentUserScope)
    , ("scope", "BepisCurrentVenueScope", bepisScopePolicyText BepisCurrentVenueScope)
    , ("scope", "BepisVenueRosterWeekScope", bepisScopePolicyText BepisVenueRosterWeekScope)
    , ("scope", "BepisVenueRosterGroupScope", bepisScopePolicyText BepisVenueRosterGroupScope)
    , ("scope", "BepisSupportScope", bepisScopePolicyText BepisSupportScope)
    ]

bepisMutationSpecAttributes :: BepisMutationSpec -> [(Text, Attribute)]
bepisMutationSpecAttributes spec =
    [ ("bepis.mutation.audit_policy", toAttribute (bepisAuditPolicyText spec.auditPolicy))
    , ("bepis.mutation.realtime_policy", toAttribute (bepisRealtimePolicyText spec.realtimePolicy))
    , ("bepis.mutation.scope_policy", toAttribute (bepisScopePolicyText spec.scopePolicy))
    ]
