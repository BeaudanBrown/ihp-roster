{-# LANGUAGE TypeApplications #-}

module Application.Helper.Frontend.AppSchema
    ( appSharedConstantsDeclaration
    ) where

import Application.Helper.Frontend.AppConstants
import Application.Helper.Frontend.Codec (FrontendCodec (..),
                                          FrontendSchema (..),
                                          HasFrontendCodec (..), field,
                                          recordSchema, someFrontendCodec)
import Application.Helper.Frontend.ContractGroup (FrontendContractGroup (..),
                                                  renderFrontendContractGroup,
                                                  typedConstant)
import Application.Helper.Frontend.TypeScript (TypeScriptDeclaration (..))
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Types as AesonTypes
import IHP.Prelude

appSharedConstantsDeclaration :: TypeScriptDeclaration
appSharedConstantsDeclaration =
    renderFrontendContractGroup FrontendContractGroup
        { contractGroupName = "AppSharedConstants"
        , contractGroupComment = Just "Shared app DOM and browser event constants generated from Haskell."
        , contractGroupCodecs = [someFrontendCodec @AppOverlayDom, someFrontendCodec @AppEvents]
        , contractGroupConstants =
            [ typedConstant "AppOverlayDom" (frontendCodec @AppOverlayDom) canonicalAppOverlayDom
            , typedConstant "AppEvents" (frontendCodec @AppEvents) canonicalAppEvents
            ]
        }

instance HasFrontendCodec AppOverlayDom where
    frontendCodec = FrontendCodec
        { codecName = Just "AppOverlayDom"
    , codecSchema = recordSchema "AppOverlayDom"
        [ field "dialogOverlayMountId" SchemaString
        , field "toastOverlayMountId" SchemaString
        ]
    , codecEncode = \dom -> Aeson.object
        [ "dialogOverlayMountId" Aeson..= dom.appDialogOverlayMountId
        , "toastOverlayMountId" Aeson..= dom.appToastOverlayMountId
        ]
    , codecParse = Aeson.withObject "AppOverlayDom" \object ->
        AppOverlayDom
            <$> object Aeson..: "dialogOverlayMountId"
            <*> object Aeson..: "toastOverlayMountId"
    }

instance HasFrontendCodec AppEvents where
    frontendCodec = FrontendCodec
        { codecName = Just "AppEvents"
    , codecSchema = recordSchema "AppEvents"
        [ field "pageReady" SchemaString
        , field "liveFragmentsRefresh" SchemaString
        , field "interactionIntent" SchemaString
        , field "interactionIntentSubmit" SchemaString
        , field "interactionSessionStart" SchemaString
        , field "interactionSessionEnd" SchemaString
        , field "interactionSessionCancelRequest" SchemaString
        ]
    , codecEncode = appEventsJson
    , codecParse = parseAppEvents
    }

appEventsJson :: AppEvents -> Aeson.Value
appEventsJson events = Aeson.object
    [ "pageReady" Aeson..= events.appPageReadyEventName
    , "liveFragmentsRefresh" Aeson..= events.appLiveFragmentsRefreshEventName
    , "interactionIntent" Aeson..= events.appInteractionIntentEventName
    , "interactionIntentSubmit" Aeson..= events.appInteractionIntentSubmitEventName
    , "interactionSessionStart" Aeson..= events.appInteractionSessionStartEventName
    , "interactionSessionEnd" Aeson..= events.appInteractionSessionEndEventName
    , "interactionSessionCancelRequest" Aeson..= events.appInteractionSessionCancelRequestEventName
    ]

parseAppEvents :: Aeson.Value -> AesonTypes.Parser AppEvents
parseAppEvents = Aeson.withObject "AppEvents" \object ->
    AppEvents
        <$> object Aeson..: "pageReady"
        <*> object Aeson..: "liveFragmentsRefresh"
        <*> object Aeson..: "interactionIntent"
        <*> object Aeson..: "interactionIntentSubmit"
        <*> object Aeson..: "interactionSessionStart"
        <*> object Aeson..: "interactionSessionEnd"
        <*> object Aeson..: "interactionSessionCancelRequest"
