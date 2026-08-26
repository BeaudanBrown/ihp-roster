{-# LANGUAGE RoleAnnotations #-}

-- | Constructor-owning runtime seam for compatibility reflection and generated
-- operation-local request evidence. Production feature code imports curated
-- facades, never this module.
module Application.Helper.FrontendContract.Surface.Request.Runtime.Internal
    ( ActionEvidence
    , FrontendSurfaceAction (..)
    , FrontendSurfaceHtmxMethod (..)
    , FrontendSurfaceHtmxRequest (..)
    , FrontendSurfaceIntentForm (..)
    , IntentEvidence
    , actionEvidence
    , frontendSurfaceActionFromEvidence
    , frontendSurfaceActionFromIR
    , frontendSurfaceIntentFormFromEvidence
    , intentEvidence
    ) where

import Application.Helper.FrontendContract.Surface.ContractIR (HtmxActionIR,
                                                               IntentIR (..))
import qualified Application.Helper.FrontendContract.Surface.ContractIR as SurfaceIR
import Application.Helper.FrontendContract.Surface.Values (ActionFields,
                                                           IntentFields,
                                                           surfaceFieldsText)
import IHP.Prelude

data FrontendSurfaceAction = FrontendSurfaceAction
    { frontendSurfaceActionIR         :: !HtmxActionIR
    , frontendSurfaceActionFieldPairs :: ![(Text, Text)]
    }
    deriving (Eq, Show)

data FrontendSurfaceHtmxMethod
    = FrontendSurfaceGet
    | FrontendSurfacePost
    | FrontendSurfacePut
    | FrontendSurfacePatch
    | FrontendSurfaceDelete
    deriving (Eq, Show)

data FrontendSurfaceHtmxRequest = FrontendSurfaceHtmxRequest
    { htmxRequestMethod :: !FrontendSurfaceHtmxMethod
    , htmxRequestUrl    :: !Text
    , htmxRequestTarget :: !Text
    , htmxRequestSwap   :: !Text
    }
    deriving (Eq, Show)

data FrontendSurfaceIntentForm = FrontendSurfaceIntentForm
    { intentFormName   :: !Text
    , intentFormSubmit :: !FrontendSurfaceHtmxRequest
    , intentFormFields :: ![(SurfaceIR.FieldIR, Text)]
    }
    deriving (Eq, Show)

frontendSurfaceActionFromIR ::
    HtmxActionIR ->
    [(Text, Text)] ->
    FrontendSurfaceAction
frontendSurfaceActionFromIR frontendSurfaceActionIR frontendSurfaceActionFieldPairs =
    FrontendSurfaceAction { frontendSurfaceActionIR, frontendSurfaceActionFieldPairs }

-- | Canonical checked-IR metadata for one nominal Action operation. The
-- constructor is hidden; generated output receives only the trusted smart
-- constructor.
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

-- | Canonical checked-IR metadata for one nominal Intent operation. This lane
-- deliberately cannot be substituted for Action evidence.
newtype IntentEvidence operation = IntentEvidence IntentIR

type role IntentEvidence nominal

intentEvidence :: IntentIR -> IntentEvidence operation
intentEvidence = IntentEvidence

frontendSurfaceIntentFormFromEvidence ::
    IntentEvidence operation ->
    IntentFields operation ->
    FrontendSurfaceHtmxRequest ->
    FrontendSurfaceIntentForm
frontendSurfaceIntentFormFromEvidence (IntentEvidence intent) fields intentFormSubmit =
    FrontendSurfaceIntentForm
        { intentFormName = intent.intentName
        , intentFormSubmit
        , intentFormFields =
            [ (field, value)
            | field <- intent.intentFields
            , value <- maybeToList (lookup field.fieldName (surfaceFieldsText fields))
            ]
        }
