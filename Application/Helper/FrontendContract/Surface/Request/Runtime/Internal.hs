{-# LANGUAGE RoleAnnotations #-}

-- | Constructor-owning runtime seam for compatibility reflection and generated
-- operation-local Action evidence. Production feature code imports curated
-- facades, never this module.
module Application.Helper.FrontendContract.Surface.Request.Runtime.Internal
    ( ActionEvidence
    , FrontendSurfaceAction (..)
    , actionEvidence
    , frontendSurfaceActionFromEvidence
    , frontendSurfaceActionFromIR
    ) where

import Application.Helper.FrontendContract.Surface.ContractIR (HtmxActionIR)
import Application.Helper.FrontendContract.Surface.Values (ActionFields,
                                                           surfaceFieldsText)
import IHP.Prelude

data FrontendSurfaceAction = FrontendSurfaceAction
    { frontendSurfaceActionIR         :: !HtmxActionIR
    , frontendSurfaceActionFieldPairs :: ![(Text, Text)]
    }
    deriving (Eq, Show)

frontendSurfaceActionFromIR ::
    HtmxActionIR ->
    [(Text, Text)] ->
    FrontendSurfaceAction
frontendSurfaceActionFromIR frontendSurfaceActionIR frontendSurfaceActionFieldPairs =
    FrontendSurfaceAction { frontendSurfaceActionIR, frontendSurfaceActionFieldPairs }

-- | Canonical checked-IR metadata for one nominal operation. The constructor is
-- hidden; generated output receives only the trusted smart constructor.
newtype ActionEvidence operation = ActionEvidence HtmxActionIR

type role ActionEvidence nominal

actionEvidence :: HtmxActionIR -> ActionEvidence operation
actionEvidence = ActionEvidence

frontendSurfaceActionFromEvidence ::
    ActionEvidence operation ->
    ActionFields operation ->
    FrontendSurfaceAction
frontendSurfaceActionFromEvidence (ActionEvidence action) fields =
    frontendSurfaceActionFromIR action (surfaceFieldsText fields)
