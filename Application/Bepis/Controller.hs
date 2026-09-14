module Application.Bepis.Controller
    ( BepisControllerPolicy (..)
    , bepisBeforeAction
    , bepisControllerPolicyText
    ) where

import Application.Helper.Telemetry (addTelemetryAttributes,
                                     withTelemetrySpanAttributes)
import GHC.Generics (Generic)
import IHP.Prelude
import OpenTelemetry.Attributes (toAttribute)

-- | Coarse app-owned controller policy labels. IHP still runs beforeAction;
-- these labels make app access/scope intent visible to tests, telemetry, and
-- architecture tooling.
data BepisControllerPolicy
    = BepisPublicController
    | BepisAuthenticatedController
    | BepisAuthenticatedVenueController
    | BepisAdminVenueController
    | BepisSupportController
    deriving (Bounded, Enum, Eq, Show, Generic)

-- | Wrap a normal IHP beforeAction implementation with Bepis policy metadata.
-- The supplied action remains responsible for calling the existing auth/scope
-- helpers; this function deliberately does not create a parallel controller
-- lifecycle.
bepisBeforeAction :: BepisControllerPolicy -> IO () -> IO ()
bepisBeforeAction policy action =
    withTelemetrySpanAttributes
        "bepis.before_action"
        [("bepis.controller.policy", toAttribute (bepisControllerPolicyText policy))]
        do
            addTelemetryAttributes [("bepis.controller.policy", toAttribute (bepisControllerPolicyText policy))]
            action

bepisControllerPolicyText :: BepisControllerPolicy -> Text
bepisControllerPolicyText = \case
    BepisPublicController -> "public"
    BepisAuthenticatedController -> "authenticated"
    BepisAuthenticatedVenueController -> "authenticated-venue"
    BepisAdminVenueController -> "admin-venue"
    BepisSupportController -> "support"
