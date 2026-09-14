module Application.Helper.FrontendContract.Surface.Identity.Types
    ( SurfaceScopeIdentitySegment (..)
    ) where

import IHP.Prelude

-- | Declaration-ordered identity presence retained by typed Surface fields.
data SurfaceScopeIdentitySegment
    = SurfaceScopePresent !Text
    | SurfaceScopeMissing
    | SurfaceScopeNull
    deriving (Eq, Show)
