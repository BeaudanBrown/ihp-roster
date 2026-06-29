module Application.Helper.Frontend.UiRegionSchema
    ( uiRegionSchemaDeclaration
    ) where

import Application.Helper.Frontend.Codec (FrontendCodec (..),
                                          FrontendField (..),
                                          FrontendSchema (..),
                                          SomeFrontendCodec (..),
                                          renderFrontendContracts,
                                          renderTypedConstant, stringEnumCodec)
import Application.Helper.Frontend.TypeScript (TypeScriptDeclaration (..),
                                               TypeScriptDeclarationOrigin (HaskellSchemaGenerated))
import Application.Helper.UiRegion
import qualified Data.Aeson as Aeson
import qualified Data.Text as Text
import IHP.Prelude

uiRegionSchemaDeclaration :: TypeScriptDeclaration
uiRegionSchemaDeclaration =
    TypeScriptDeclaration
        { name = "UiRegionContracts"
        , origin = HaskellSchemaGenerated
        , source = Text.unlines
            [ "// UI region capability vocabulary generated from Haskell."
            , uiRegionTypesSource
            , renderTypedConstant "UiRegionDom" uiRegionDomAttributesCodec canonicalUiRegionDomAttributes
            , renderTypedConstant "UiRegionEvents" uiRegionEventsCodec canonicalUiRegionEvents
            ]
        }

uiRegionTypesSource :: Text
uiRegionTypesSource =
    case renderFrontendContracts
        [ SomeFrontendCodec uiRegionDomAttributesCodec
        , SomeFrontendCodec uiRegionTransitionProfileCodec
        , SomeFrontendCodec uiRegionLifecycleEventCodec
        , SomeFrontendCodec uiRegionEventsCodec
        ] of
        Right source -> source
        Left message -> error ("Unable to render UI region contracts: " <> cs message)

uiRegionDomAttributesCodec :: FrontendCodec UiRegionDomAttributes
uiRegionDomAttributesCodec = FrontendCodec
    { codecName = Just "UiRegionDom"
    , codecSchema = SchemaRecord "UiRegionDom"
        [ FrontendField "fragment" SchemaString
        , FrontendField "lazySurface" SchemaString
        , FrontendField "lazyFragment" SchemaString
        , FrontendField "lazyRetry" SchemaString
        , FrontendField "transition" SchemaString
        ]
    , codecEncode = \dom -> Aeson.object
        [ "fragment" Aeson..= dom.uiRegionFragmentAttribute
        , "lazySurface" Aeson..= dom.uiRegionLazySurfaceAttribute
        , "lazyFragment" Aeson..= dom.uiRegionLazyFragmentAttribute
        , "lazyRetry" Aeson..= dom.uiRegionLazyRetryAttribute
        , "transition" Aeson..= dom.uiRegionTransitionAttribute
        ]
    , codecParse = Aeson.withObject "UiRegionDom" \object ->
        UiRegionDomAttributes
            <$> object Aeson..: "fragment"
            <*> object Aeson..: "lazySurface"
            <*> object Aeson..: "lazyFragment"
            <*> object Aeson..: "lazyRetry"
            <*> object Aeson..: "transition"
    }

uiRegionTransitionProfileCodec :: FrontendCodec UiRegionTransitionProfile
uiRegionTransitionProfileCodec =
    stringEnumCodec "UiRegionTransitionProfile"
        [ (UiRegionTransitionNone, uiRegionTransitionProfileText UiRegionTransitionNone)
        , (UiRegionTransitionFade, uiRegionTransitionProfileText UiRegionTransitionFade)
        , (UiRegionTransitionFadeSlide, uiRegionTransitionProfileText UiRegionTransitionFadeSlide)
        , (UiRegionTransitionPanel, uiRegionTransitionProfileText UiRegionTransitionPanel)
        ]

uiRegionLifecycleEventCodec :: FrontendCodec UiRegionLifecycleEvent
uiRegionLifecycleEventCodec =
    stringEnumCodec "UiRegionLifecycleEvent" canonicalUiRegionLifecycleEvents

data UiRegionEvents = UiRegionEvents
    { regionRequestStart :: !Text
    , regionBeforeSwap   :: !Text
    , regionAfterSwap    :: !Text
    , regionSettle       :: !Text
    , regionError        :: !Text
    }
    deriving (Eq, Show)

canonicalUiRegionEvents :: UiRegionEvents
canonicalUiRegionEvents = UiRegionEvents
    { regionRequestStart = uiRegionLifecycleEventName UiRegionRequestStart
    , regionBeforeSwap = uiRegionLifecycleEventName UiRegionBeforeSwap
    , regionAfterSwap = uiRegionLifecycleEventName UiRegionAfterSwap
    , regionSettle = uiRegionLifecycleEventName UiRegionSettle
    , regionError = uiRegionLifecycleEventName UiRegionError
    }

uiRegionEventsCodec :: FrontendCodec UiRegionEvents
uiRegionEventsCodec = FrontendCodec
    { codecName = Just "UiRegionEvents"
    , codecSchema = SchemaRecord "UiRegionEvents"
        [ FrontendField "requestStart" SchemaString
        , FrontendField "beforeSwap" SchemaString
        , FrontendField "afterSwap" SchemaString
        , FrontendField "settle" SchemaString
        , FrontendField "error" SchemaString
        ]
    , codecEncode = \events -> Aeson.object
        [ "requestStart" Aeson..= events.regionRequestStart
        , "beforeSwap" Aeson..= events.regionBeforeSwap
        , "afterSwap" Aeson..= events.regionAfterSwap
        , "settle" Aeson..= events.regionSettle
        , "error" Aeson..= events.regionError
        ]
    , codecParse = Aeson.withObject "UiRegionEvents" \object ->
        UiRegionEvents
            <$> object Aeson..: "requestStart"
            <*> object Aeson..: "beforeSwap"
            <*> object Aeson..: "afterSwap"
            <*> object Aeson..: "settle"
            <*> object Aeson..: "error"
    }
