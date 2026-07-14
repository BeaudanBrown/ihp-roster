{-# LANGUAGE DataKinds     #-}
{-# LANGUAGE TypeOperators #-}

module Test.CompileFail.FrontendSurfaceUnknownInteractionEffect where

import Application.Helper.FrontendContract.Surface.DSL

-- Feature surfaces must select a closed interaction effect. An arbitrary marker
-- must not become browser behavior through reflected-name redispatch.
data UnknownEffect
data UnknownEffectSession

type InvalidUnknownEffectSurface =
    Surface UnknownEffect
        '[ Scope UnknownEffect '[] '[ 'NoAuth ]
         , Session UnknownEffectSession '[ 'Effect UnknownEffect ]
         ]
