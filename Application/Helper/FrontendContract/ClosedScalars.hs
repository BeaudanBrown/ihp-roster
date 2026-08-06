{-# LANGUAGE DataKinds #-}

-- | Registered app-owned finite scalar schemas. Persisted domains reuse their
-- generated PostgreSQL enum types; browser reachability stays explicit here.
module Application.Helper.FrontendContract.ClosedScalars
    ( ClosedScalarContract
    ) where

import Application.Helper.FrontendContract.DSL
import Generated.Types (RosterLayoutModeEnum, RosterTemplateScaleEnum)

data AppClosedScalars

type ClosedScalarContract =
    Global AppClosedScalars
        '[ ServerSchema (ClosedScalar RosterLayoutModeEnum)
         , BrowserInboundSchema (ClosedScalar RosterTemplateScaleEnum)
         ]
