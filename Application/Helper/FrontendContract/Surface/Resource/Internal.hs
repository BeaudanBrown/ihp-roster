module Application.Helper.FrontendContract.Surface.Resource.Internal
    ( SurfaceResourceValue
    , mkSurfaceResourceValue
    , surfaceResourceIdentity
    ) where

import qualified Data.Aeson as Aeson
import IHP.Prelude

-- | Opaque runtime carrier for one declared Surface resource. Construction is
-- internal so feature code must go through marker-indexed Surface fields.
data SurfaceResourceValue = SurfaceResourceValue
    { resourceValueName   :: !Text
    , resourceValueFields :: !Aeson.Value
    }
    deriving (Eq, Ord, Show)

mkSurfaceResourceValue :: Text -> Aeson.Value -> SurfaceResourceValue
mkSurfaceResourceValue resourceValueName resourceValueFields =
    SurfaceResourceValue { resourceValueName, resourceValueFields }

surfaceResourceIdentity :: SurfaceResourceValue -> (Text, Aeson.Value)
surfaceResourceIdentity value =
    (value.resourceValueName, value.resourceValueFields)
