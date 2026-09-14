{-# LANGUAGE ScopedTypeVariables #-}

module Application.Bepis.Fact
    ( BepisActionFact (..)
    , BepisAuditFact (..)
    , BepisAuditFactKind (..)
    , BepisFact (..)
    , BepisFactContext
    , BepisFactKind (..)
    , BepisFactSet (..)
    , BepisLiveFact (..)
    , BepisLiveMechanism (..)
    , BepisOperationContext (..)
    , BepisOperationKind (..)
    , BepisResponseFact (..)
    , BepisResponseKind (..)
    , BepisRoleKind (..)
    , BepisScopeFact (..)
    , BepisScopeKind (..)
    , bepisFactKindText
    , bepisOperationKindText
    , bepisResponseKindText
    , emitBepisFact
    , summarizeBepisFacts
    , withBepisFactContext
    ) where

import Application.Helper.Telemetry (addTelemetryAttributes, addTelemetryEvent)
import Control.Concurrent (ThreadId, myThreadId)
import Control.Concurrent.MVar (MVar, modifyMVar_, newMVar, readMVar)
import qualified Control.Exception as Exception
import GHC.Generics (Generic)
import IHP.Prelude
import OpenTelemetry.Attributes (Attribute, toAttribute)
import System.IO.Unsafe (unsafePerformIO)

-- | One Bepis-owned operation vocabulary layered inside IHP's controller
-- lifecycle. IHP still owns routing/dispatch; this type names the app-level
-- semantics consumed by facts, telemetry, tests, and architecture contracts.
data BepisOperationKind
    = BepisPageAction
    | BepisFragmentAction
    | BepisDialogAction
    | BepisMutationAction
    | BepisFormAction
    | BepisPreferenceAction
    | BepisIntegrationAction
    | BepisExportAction
    deriving (Bounded, Enum, Eq, Show, Generic)

-- | Low-cardinality response shape labels. Response helpers emit these when
-- they actually perform a response.
data BepisResponseKind
    = BepisHtmlResponse
    | BepisHtmxFragmentResponse
    | BepisDialogResponse
    | BepisRedirectResponse
    | BepisJsonResponse
    | BepisFileResponse
    deriving (Bounded, Enum, Eq, Show, Generic)

data BepisRoleKind
    = BepisOwnerRole
    | BepisManagerRole
    | BepisStaffRole
    | BepisAdminRole
    deriving (Eq, Show, Generic)

data BepisScopeKind
    = BepisAuthenticatedUserScopeFact
    | BepisCurrentVenueScopeFact
    | BepisVenueWritableScopeFact
    | BepisRoleScopeFact BepisRoleKind
    | BepisSupportScopeFact
    | BepisImpersonationScopeFact
    | BepisRecordVenueScopeFact Text
    deriving (Eq, Show, Generic)

data BepisAuditFactKind
    = BepisAuditEventRecorded
    | BepisVersionEventRecorded
    | BepisAuthenticationAuditRecorded
    deriving (Eq, Show, Generic)

data BepisLiveMechanism
    = BepisWebSocketFragmentRefetch
    | BepisBackgroundLiveInvalidation
    | BepisNoLiveInvalidation
    deriving (Eq, Show, Generic)

data BepisActionFact = BepisActionFact
    { actionFactName             :: !Text
    , actionFactOperationKind    :: !BepisOperationKind
    , actionFactControllerPolicy :: !(Maybe Text)
    }
    deriving (Eq, Show, Generic)

data BepisScopeFact = BepisScopeFact
    { scopeFactKind  :: !BepisScopeKind
    , scopeFactLabel :: !Text
    }
    deriving (Eq, Show, Generic)

data BepisAuditFact = BepisAuditFact
    { auditFactKind          :: !BepisAuditFactKind
    , auditFactEventType     :: !Text
    , auditFactTarget        :: !Text
    , auditFactSourceChannel :: !Text
    }
    deriving (Eq, Show, Generic)

data BepisLiveFact = BepisLiveFact
    { liveFactLabel                 :: !Text
    , liveFactTouchedResourceCount  :: !Int
    , liveFactExpandedResourceCount :: !Int
    , liveFactTargetCount           :: !Int
    , liveFactTargetFragmentCount   :: !Int
    , liveFactMechanism             :: !BepisLiveMechanism
    }
    deriving (Eq, Show, Generic)

data BepisResponseFact = BepisResponseFact
    { responseFactKind   :: !BepisResponseKind
    , responseFactTarget :: !(Maybe Text)
    }
    deriving (Eq, Show, Generic)

data BepisFact
    = BepisActionFactValue !BepisActionFact
    | BepisScopeFactValue !BepisScopeFact
    | BepisAuditFactValue !BepisAuditFact
    | BepisLiveFactValue !BepisLiveFact
    | BepisResponseFactValue !BepisResponseFact
    deriving (Eq, Show, Generic)

data BepisFactSet = BepisFactSet
    { factSetFacts :: ![BepisFact]
    }
    deriving (Eq, Show, Generic)

data BepisOperationContext = BepisOperationContext
    { operationContextActionName       :: !Text
    , operationContextKind             :: !BepisOperationKind
    , operationContextControllerPolicy :: !(Maybe Text)
    }
    deriving (Eq, Show, Generic)

newtype BepisFactContext = BepisFactContext
    { factContextRef :: IORef [BepisFact]
    }
    deriving (Eq)


withBepisFactContext :: IO a -> IO (Either Exception.SomeException a, BepisFactSet)
withBepisFactContext action = Exception.mask \restore -> do
    threadId <- myThreadId
    ref <- newIORef []
    let context = BepisFactContext ref
    pushBepisFactContext threadId context
    result <- Exception.try (restore action)
    facts <- readIORef ref
    popBepisFactContext threadId context
    pure (result, BepisFactSet (reverse facts))

emitBepisFact :: BepisFact -> IO ()
emitBepisFact fact = do
    recordBepisFactForCurrentThread fact
    addTelemetryEvent ("bepis." <> bepisFactKindText (bepisFactKind fact)) (bepisFactAttributes fact)

summarizeBepisFacts :: BepisFactSet -> IO ()
summarizeBepisFacts factSet =
    addTelemetryAttributes
        [ ("bepis.fact.count", toAttribute (tshow (length factSet.factSetFacts)))
        , ("bepis.fact.kinds", toAttribute (joinedFactKinds factSet))
        , ("bepis.scope.count", toAttribute (tshow (countFacts isScopeFact factSet)))
        , ("bepis.audit.count", toAttribute (tshow (countFacts isAuditFact factSet)))
        , ("bepis.live.count", toAttribute (tshow (countFacts isLiveFact factSet)))
        , ("bepis.response.kinds", toAttribute (joinedResponseKinds factSet))
        ]

bepisOperationKindText :: BepisOperationKind -> Text
bepisOperationKindText = \case
    BepisPageAction -> "page"
    BepisFragmentAction -> "fragment"
    BepisDialogAction -> "dialog"
    BepisMutationAction -> "mutation"
    BepisFormAction -> "form"
    BepisPreferenceAction -> "preference"
    BepisIntegrationAction -> "integration"
    BepisExportAction -> "export"

bepisResponseKindText :: BepisResponseKind -> Text
bepisResponseKindText = \case
    BepisHtmlResponse -> "html"
    BepisHtmxFragmentResponse -> "htmx-fragment"
    BepisDialogResponse -> "dialog"
    BepisRedirectResponse -> "redirect"
    BepisJsonResponse -> "json"
    BepisFileResponse -> "file"

bepisFactKindText :: BepisFactKind -> Text
bepisFactKindText = \case
    BepisActionFactKind -> "action"
    BepisScopeFactKind -> "scope"
    BepisAuditFactKind -> "audit"
    BepisLiveFactKind -> "live"
    BepisResponseFactKind -> "response"

data BepisFactKind
    = BepisActionFactKind
    | BepisScopeFactKind
    | BepisAuditFactKind
    | BepisLiveFactKind
    | BepisResponseFactKind
    deriving (Bounded, Enum, Eq, Show, Generic)

bepisFactKind :: BepisFact -> BepisFactKind
bepisFactKind = \case
    BepisActionFactValue _ -> BepisActionFactKind
    BepisScopeFactValue _ -> BepisScopeFactKind
    BepisAuditFactValue _ -> BepisAuditFactKind
    BepisLiveFactValue _ -> BepisLiveFactKind
    BepisResponseFactValue _ -> BepisResponseFactKind

bepisFactAttributes :: BepisFact -> [(Text, Attribute)]
bepisFactAttributes fact =
    ("bepis.fact.kind", toAttribute (bepisFactKindText (bepisFactKind fact))) :
        case fact of
            BepisActionFactValue actionFact ->
                [ ("bepis.action", toAttribute actionFact.actionFactName)
                , ("bepis.action.kind", toAttribute (bepisOperationKindText actionFact.actionFactOperationKind))
                ] <> maybe [] (\policy -> [("bepis.controller.policy", toAttribute policy)]) actionFact.actionFactControllerPolicy
            BepisScopeFactValue scopeFact ->
                [ ("bepis.scope.kind", toAttribute (bepisScopeKindText scopeFact.scopeFactKind))
                , ("bepis.scope.label", toAttribute scopeFact.scopeFactLabel)
                ]
            BepisAuditFactValue auditFact ->
                [ ("bepis.audit.kind", toAttribute (bepisAuditFactKindText auditFact.auditFactKind))
                , ("bepis.audit.event_type", toAttribute auditFact.auditFactEventType)
                , ("bepis.audit.target", toAttribute auditFact.auditFactTarget)
                , ("bepis.audit.source_channel", toAttribute auditFact.auditFactSourceChannel)
                ]
            BepisLiveFactValue liveFact ->
                [ ("bepis.live.label", toAttribute liveFact.liveFactLabel)
                , ("bepis.live.touched_resource_count", toAttribute (tshow liveFact.liveFactTouchedResourceCount))
                , ("bepis.live.expanded_resource_count", toAttribute (tshow liveFact.liveFactExpandedResourceCount))
                , ("bepis.live.target_count", toAttribute (tshow liveFact.liveFactTargetCount))
                , ("bepis.live.target_fragment_count", toAttribute (tshow liveFact.liveFactTargetFragmentCount))
                , ("bepis.live.mechanism", toAttribute (bepisLiveMechanismText liveFact.liveFactMechanism))
                ]
            BepisResponseFactValue responseFact ->
                [ ("bepis.response.kind", toAttribute (bepisResponseKindText responseFact.responseFactKind))
                ] <> maybe [] (\target -> [("bepis.response.target", toAttribute target)]) responseFact.responseFactTarget

bepisScopeKindText :: BepisScopeKind -> Text
bepisScopeKindText = \case
    BepisAuthenticatedUserScopeFact -> "authenticated-user"
    BepisCurrentVenueScopeFact -> "current-venue"
    BepisVenueWritableScopeFact -> "venue-writable"
    BepisRoleScopeFact role -> "role:" <> bepisRoleKindText role
    BepisSupportScopeFact -> "support"
    BepisImpersonationScopeFact -> "impersonation"
    BepisRecordVenueScopeFact label -> "record-venue:" <> label

bepisRoleKindText :: BepisRoleKind -> Text
bepisRoleKindText = \case
    BepisOwnerRole -> "owner"
    BepisManagerRole -> "manager"
    BepisStaffRole -> "staff"
    BepisAdminRole -> "admin"

bepisAuditFactKindText :: BepisAuditFactKind -> Text
bepisAuditFactKindText = \case
    BepisAuditEventRecorded -> "audit-event-recorded"
    BepisVersionEventRecorded -> "version-event-recorded"
    BepisAuthenticationAuditRecorded -> "authentication-audit-recorded"

bepisLiveMechanismText :: BepisLiveMechanism -> Text
bepisLiveMechanismText = \case
    BepisWebSocketFragmentRefetch -> "websocket-fragment-refetch"
    BepisBackgroundLiveInvalidation -> "background-live-invalidation"
    BepisNoLiveInvalidation -> "none"

joinedFactKinds :: BepisFactSet -> Text
joinedFactKinds = intercalate "," . distinct . map (bepisFactKindText . bepisFactKind) . (.factSetFacts)

joinedResponseKinds :: BepisFactSet -> Text
joinedResponseKinds = intercalate "," . distinct . mapMaybe responseKind . (.factSetFacts)
    where
        responseKind = \case
            BepisResponseFactValue fact -> Just (bepisResponseKindText fact.responseFactKind)
            _ -> Nothing

countFacts :: (BepisFact -> Bool) -> BepisFactSet -> Int
countFacts predicate = length . filter predicate . (.factSetFacts)

isScopeFact :: BepisFact -> Bool
isScopeFact = \case
    BepisScopeFactValue _ -> True
    _ -> False

isAuditFact :: BepisFact -> Bool
isAuditFact = \case
    BepisAuditFactValue _ -> True
    _ -> False

isLiveFact :: BepisFact -> Bool
isLiveFact = \case
    BepisLiveFactValue _ -> True
    _ -> False

distinct :: Eq a => [a] -> [a]
distinct = foldr (\value values -> if value `elem` values then values else value : values) []

type BepisFactContextStack = [(ThreadId, [BepisFactContext])]

bepisFactContexts :: MVar BepisFactContextStack
bepisFactContexts = unsafePerformIO (newMVar [])
{-# NOINLINE bepisFactContexts #-}

pushBepisFactContext :: ThreadId -> BepisFactContext -> IO ()
pushBepisFactContext threadId context =
    modifyMVar_ bepisFactContexts \contexts ->
        pure (alterThreadContexts threadId (context :) contexts)

popBepisFactContext :: ThreadId -> BepisFactContext -> IO ()
popBepisFactContext threadId context =
    modifyMVar_ bepisFactContexts \contexts ->
        pure (alterThreadContexts threadId (dropContext context) contexts)
    where
        dropContext expected = \case
            [] -> []
            actual : rest
                | actual == expected -> rest
                | otherwise -> filter (/= expected) (actual : rest)

recordBepisFactForCurrentThread :: BepisFact -> IO ()
recordBepisFactForCurrentThread fact = do
    threadId <- myThreadId
    contexts <- readMVar bepisFactContexts
    case lookup threadId contexts of
        Just (context : _) -> modifyIORef' context.factContextRef (fact :)
        _                  -> pure ()

alterThreadContexts :: ThreadId -> ([BepisFactContext] -> [BepisFactContext]) -> BepisFactContextStack -> BepisFactContextStack
alterThreadContexts threadId alter contexts =
    let keepNonEmpty stack = if null stack then [] else [(threadId, stack)]
    in case break ((== threadId) . fst) contexts of
        (before, (_, stack) : after) -> before <> keepNonEmpty (alter stack) <> after
        _                           -> keepNonEmpty (alter []) <> contexts
