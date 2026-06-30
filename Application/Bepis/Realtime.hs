module Application.Bepis.Realtime
    ( BepisFreshnessMechanism (..)
    , BepisLiveSurface (..)
    , bepisFreshnessMechanismText
    , bepisLiveSurfaceAttributes
    ) where

import GHC.Generics (Generic)
import IHP.Prelude
import OpenTelemetry.Attributes (Attribute, toAttribute)

-- | Mechanism labels for live freshness. These are facts about the current
-- implementation, not permanent architecture assumptions.
data BepisFreshnessMechanism
    = BepisWebSocketInvalidationFragmentRefetch
    | BepisIhpAutoRefreshBacked
    | BepisPollingFreshness
    | BepisServerSentEventsFreshness
    deriving (Eq, Show, Generic)

data BepisLiveSurface = BepisLiveSurface
    { surfaceName :: !Text
    , mechanism   :: !BepisFreshnessMechanism
    , scopeLabel  :: !Text
    }
    deriving (Eq, Show, Generic)

bepisFreshnessMechanismText :: BepisFreshnessMechanism -> Text
bepisFreshnessMechanismText = \case
    BepisWebSocketInvalidationFragmentRefetch -> "websocket-invalidation-fragment-refetch"
    BepisIhpAutoRefreshBacked -> "ihp-auto-refresh-backed"
    BepisPollingFreshness -> "polling"
    BepisServerSentEventsFreshness -> "server-sent-events"

bepisLiveSurfaceAttributes :: BepisLiveSurface -> [(Text, Attribute)]
bepisLiveSurfaceAttributes surface =
    [ ("bepis.live.surface", toAttribute surface.surfaceName)
    , ("bepis.live.mechanism", toAttribute (bepisFreshnessMechanismText surface.mechanism))
    , ("bepis.live.scope", toAttribute surface.scopeLabel)
    ]
