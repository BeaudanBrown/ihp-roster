module Application.Helper.Frontend.AppSchema
    ( appSharedConstantsDeclaration
    ) where

import Application.Helper.Frontend.AppConstants
import Application.Helper.Frontend.Codec (FrontendCodec (..),
                                          FrontendField (..),
                                          FrontendSchema (..),
                                          SomeFrontendCodec (..),
                                          renderFrontendContracts,
                                          renderTypedConstant)
import Application.Helper.Frontend.TypeScript (TypeScriptDeclaration (..),
                                               TypeScriptDeclarationOrigin (HaskellSchemaGenerated))
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Types as AesonTypes
import qualified Data.Text as Text
import IHP.Prelude

appSharedConstantsDeclaration :: TypeScriptDeclaration
appSharedConstantsDeclaration =
    TypeScriptDeclaration
        { name = "AppSharedConstants"
        , origin = HaskellSchemaGenerated
        , source = Text.unlines
            [ "// Shared app DOM and browser event constants generated from Haskell."
            , appSharedConstantsTypesSource
            , renderTypedConstant "AppOverlayDom" appOverlayDomCodec canonicalAppOverlayDom
            , renderTypedConstant "AppEvents" appEventsCodec canonicalAppEvents
            ]
        }

appSharedConstantsTypesSource :: Text
appSharedConstantsTypesSource =
    case renderFrontendContracts [SomeFrontendCodec appOverlayDomCodec, SomeFrontendCodec appEventsCodec] of
        Right source -> source
        Left message -> error ("Unable to render shared app constants: " <> cs message)

appOverlayDomCodec :: FrontendCodec AppOverlayDom
appOverlayDomCodec = FrontendCodec
    { codecName = Just "AppOverlayDom"
    , codecSchema = SchemaRecord "AppOverlayDom"
        [ FrontendField "dialogOverlayMountId" SchemaString
        , FrontendField "toastOverlayMountId" SchemaString
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

appEventsCodec :: FrontendCodec AppEvents
appEventsCodec = FrontendCodec
    { codecName = Just "AppEvents"
    , codecSchema = SchemaRecord "AppEvents"
        [ FrontendField "pageReady" SchemaString
        , FrontendField "liveFragmentsRefresh" SchemaString
        , FrontendField "interactionIntent" SchemaString
        , FrontendField "interactionIntentSubmit" SchemaString
        , FrontendField "interactionSessionStart" SchemaString
        , FrontendField "interactionSessionEnd" SchemaString
        , FrontendField "interactionSessionCancelRequest" SchemaString
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
