module Application.Helper.FrontendSurface.Runtime
    ( FrontendSurfaceFieldValue (..)
    , FrontendSurfaceFragmentKey (..)
    , FrontendSurfaceHtmxMethod (..)
    , FrontendSurfaceHtmxRequest (..)
    , FrontendSurfaceIntentForm (..)
    , FrontendSurfaceMountConfig (..)
    , FrontendSurfaceMountedFragment (..)
    , FrontendSurfaceProtection (..)
    , SurfaceImpl (..)
    , frontendSurfaceHtmxMethodText
    , frontendSurfaceMountConfigJson
    , renderFrontendSurfaceHtmxForm
    , renderFrontendSurfaceIntentForm
    , renderFrontendSurfaceLazyFragment
    , renderFrontendSurfaceMount
    ) where

import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Text as Text
import qualified Data.Text.Encoding as Text.Encoding
import IHP.ViewPrelude
import Text.Blaze (toValue)
import qualified Text.Blaze.Html as Blaze
import Text.Blaze.Html ((!))
import qualified Text.Blaze.Html5 as Html5
import Text.Blaze.Internal (customAttribute, textTag)

data SurfaceImpl spec = SurfaceImpl
    { surfaceImplName        :: !Text
    , surfaceImplMountConfig :: !FrontendSurfaceMountConfig
    , surfaceImplActions     :: ![FrontendSurfaceHtmxRequest]
    , surfaceImplIntents     :: ![FrontendSurfaceIntentForm]
    }

data FrontendSurfaceMountConfig = FrontendSurfaceMountConfig
    { mountSurfaceName :: !Text
    , mountScopeKey    :: !Text
    , mountKey         :: !Text
    , mountState       :: !Aeson.Value
    , mountFragments   :: ![FrontendSurfaceMountedFragment]
    }
    deriving (Eq, Show)

data FrontendSurfaceFragmentKey = FrontendSurfaceFragmentKey
    { fragmentKind   :: !Text
    , fragmentParams :: !Aeson.Value
    }
    deriving (Eq, Show)

data FrontendSurfaceMountedFragment = FrontendSurfaceMountedFragment
    { mountedFragmentKey        :: !FrontendSurfaceFragmentKey
    , mountedFragmentTargetId   :: !Text
    , mountedFragmentUrl        :: !Text
    , mountedFragmentProtection :: !FrontendSurfaceProtection
    , mountedFragmentLoadPolicy :: !Text
    }
    deriving (Eq, Show)

data FrontendSurfaceProtection
    = FrontendSurfaceReplace
    | FrontendSurfaceFocusedField
    deriving (Eq, Show)

data FrontendSurfaceHtmxMethod
    = FrontendSurfaceGet
    | FrontendSurfacePost
    deriving (Eq, Show)

data FrontendSurfaceFieldValue = FrontendSurfaceFieldValue
    { fieldValueName  :: !Text
    , fieldValueValue :: !Text
    }
    deriving (Eq, Show)

data FrontendSurfaceHtmxRequest = FrontendSurfaceHtmxRequest
    { htmxRequestName   :: !Text
    , htmxRequestMethod :: !FrontendSurfaceHtmxMethod
    , htmxRequestUrl    :: !Text
    , htmxRequestTarget :: !Text
    , htmxRequestSwap   :: !Text
    , htmxRequestFields :: ![FrontendSurfaceFieldValue]
    }
    deriving (Eq, Show)

data FrontendSurfaceIntentForm = FrontendSurfaceIntentForm
    { intentFormName   :: !Text
    , intentFormSubmit :: !FrontendSurfaceHtmxRequest
    }
    deriving (Eq, Show)

frontendSurfaceMountConfigJson :: FrontendSurfaceMountConfig -> Text
frontendSurfaceMountConfigJson =
    Text.Encoding.decodeUtf8 . LBS.toStrict . Aeson.encode . mountConfigToJson

renderFrontendSurfaceMount :: SurfaceImpl spec -> Blaze.Html -> Blaze.Html
renderFrontendSurfaceMount impl body =
    Html5.div
        ! attr "data-bepis-surface" impl.surfaceImplName
        ! attr "data-bepis-surface-config" (frontendSurfaceMountConfigJson impl.surfaceImplMountConfig)
        $ body

renderFrontendSurfaceLazyFragment :: FrontendSurfaceMountedFragment -> Blaze.Html -> Blaze.Html
renderFrontendSurfaceLazyFragment fragment placeholder =
    Html5.div
        ! attr "id" fragment.mountedFragmentTargetId
        ! attr "class" "app-lazy-surface app-lazy-surface-compact"
        ! attr "data-bepis-fragment" "true"
        ! attr "data-bepis-lazy-surface" "true"
        ! attr "data-bepis-lazy-fragment" fragment.mountedFragmentKey.fragmentKind
        ! attr "data-bepis-lazy-retry" "true"
        ! attr "hx-get" fragment.mountedFragmentUrl
        ! attr "hx-trigger" "load delay:50ms"
        ! attr "hx-target" "this"
        ! attr "hx-swap" "outerHTML"
        ! attr "hx-push-url" "false"
        $ placeholder

renderFrontendSurfaceHtmxForm :: FrontendSurfaceHtmxRequest -> Blaze.Html -> Blaze.Html
renderFrontendSurfaceHtmxForm request body =
    Html5.form
        ! attr (frontendSurfaceHtmxMethodAttr request.htmxRequestMethod) request.htmxRequestUrl
        ! attr "hx-target" request.htmxRequestTarget
        ! attr "hx-swap" request.htmxRequestSwap
        ! attr "data-bepis-surface-action" request.htmxRequestName
        $ do
            forM_ request.htmxRequestFields renderHiddenField
            body

renderFrontendSurfaceIntentForm :: FrontendSurfaceIntentForm -> Blaze.Html -> Blaze.Html
renderFrontendSurfaceIntentForm intent body =
    Html5.form
        ! attr (frontendSurfaceHtmxMethodAttr intent.intentFormSubmit.htmxRequestMethod) intent.intentFormSubmit.htmxRequestUrl
        ! attr "hx-target" intent.intentFormSubmit.htmxRequestTarget
        ! attr "hx-swap" intent.intentFormSubmit.htmxRequestSwap
        ! attr "data-bepis-intent-form" intent.intentFormName
        $ do
            forM_ intent.intentFormSubmit.htmxRequestFields renderHiddenField
            body

renderHiddenField :: FrontendSurfaceFieldValue -> Blaze.Html
renderHiddenField field =
    Html5.input
        ! attr "type" "hidden"
        ! attr "name" field.fieldValueName
        ! attr "value" field.fieldValueValue

frontendSurfaceHtmxMethodAttr :: FrontendSurfaceHtmxMethod -> Text
frontendSurfaceHtmxMethodAttr = \case
    FrontendSurfaceGet  -> "hx-get"
    FrontendSurfacePost -> "hx-post"

frontendSurfaceHtmxMethodText :: FrontendSurfaceHtmxMethod -> Text
frontendSurfaceHtmxMethodText = \case
    FrontendSurfaceGet  -> "GET"
    FrontendSurfacePost -> "POST"

mountConfigToJson :: FrontendSurfaceMountConfig -> Aeson.Value
mountConfigToJson config =
    Aeson.object
        [ "surface" Aeson..= config.mountSurfaceName
        , "scopeKey" Aeson..= config.mountScopeKey
        , "mountKey" Aeson..= config.mountKey
        , "mountState" Aeson..= config.mountState
        , "fragments" Aeson..= fmap mountedFragmentToJson config.mountFragments
        ]

mountedFragmentToJson :: FrontendSurfaceMountedFragment -> Aeson.Value
mountedFragmentToJson fragment =
    Aeson.object
        [ "key" Aeson..= fragmentKeyToJson fragment.mountedFragmentKey
        , "targetId" Aeson..= fragment.mountedFragmentTargetId
        , "url" Aeson..= fragment.mountedFragmentUrl
        , "protection" Aeson..= protectionToJson fragment.mountedFragmentProtection
        , "loadPolicy" Aeson..= fragment.mountedFragmentLoadPolicy
        ]

fragmentKeyToJson :: FrontendSurfaceFragmentKey -> Aeson.Value
fragmentKeyToJson fragmentKey =
    Aeson.object
        [ "kind" Aeson..= fragmentKey.fragmentKind
        , "params" Aeson..= fragmentKey.fragmentParams
        ]

protectionToJson :: FrontendSurfaceProtection -> Aeson.Value
protectionToJson = \case
    FrontendSurfaceReplace -> Aeson.object ["kind" Aeson..= ("replace" :: Text)]
    FrontendSurfaceFocusedField -> Aeson.object ["kind" Aeson..= ("focused-field" :: Text)]

attr :: Text -> Text -> Html5.Attribute
attr name value =
    customAttribute (textTag name) (toValue value)
