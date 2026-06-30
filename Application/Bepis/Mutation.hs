module Application.Bepis.Mutation
    ( BepisAuditPolicy (..)
    , BepisMutationSpec (..)
    , BepisRealtimePolicy (..)
    , BepisScopePolicy (..)
    , bepisAuditPolicyText
    , bepisCurrentUserMutationSpec
    , bepisNoScopeMutationSpec
    , bepisMutationSpecAttributes
    , bepisRealtimePolicyText
    , bepisScopePolicyText
    ) where

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

bepisMutationSpecAttributes :: BepisMutationSpec -> [(Text, Attribute)]
bepisMutationSpecAttributes spec =
    [ ("bepis.mutation.audit_policy", toAttribute (bepisAuditPolicyText spec.auditPolicy))
    , ("bepis.mutation.realtime_policy", toAttribute (bepisRealtimePolicyText spec.realtimePolicy))
    , ("bepis.mutation.scope_policy", toAttribute (bepisScopePolicyText spec.scopePolicy))
    ]
