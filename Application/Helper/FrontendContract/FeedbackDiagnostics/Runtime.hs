{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE TypeApplications    #-}

module Application.Helper.FrontendContract.FeedbackDiagnostics.Runtime
    ( renderFeedbackDiagnosticInputs
    ) where

import qualified Application.Helper.FrontendContract.AppShell as AppShell
import Application.Helper.FrontendContract.AppShell.Request (AppShellActionFields)
import qualified Application.Helper.FrontendContract.FeedbackDiagnostics as Contract
import Application.Helper.FrontendContract.Naming (FrontendSurfaceNameContext (FieldName),
                                                   deriveFrontendSurfaceTypeName)
import Application.Helper.FrontendContract.Surface.Values (surfaceFieldNameFrom)
import Application.Helper.FrontendContract.Values (domAttrValue)
import Data.Typeable (Typeable)
import IHP.Prelude
import Text.Blaze (toValue)
import Text.Blaze.Html ((!))
import qualified Text.Blaze.Html5 as Html5
import qualified Text.Blaze.Html5.Attributes as Attr
import Text.Blaze.Internal (customAttribute, textTag)

renderFeedbackDiagnosticInputs :: AppShellActionFields AppShell.SubmitFeedback -> Html5.Html
renderFeedbackDiagnosticInputs fields = do
    renderDiagnosticInput @Contract.FeedbackViewportWidthInput (surfaceFieldNameFrom @AppShell.FeedbackViewportWidthField fields)
    renderDiagnosticInput @Contract.FeedbackViewportHeightInput (surfaceFieldNameFrom @AppShell.FeedbackViewportHeightField fields)
    renderDiagnosticInput @Contract.FeedbackDevicePixelRatioInput (surfaceFieldNameFrom @AppShell.FeedbackDevicePixelRatioField fields)
    renderDiagnosticInput @Contract.FeedbackDisplayModeInput (surfaceFieldNameFrom @AppShell.FeedbackDisplayModeField fields)

renderDiagnosticInput :: forall inputMarker. Typeable inputMarker => Text -> Html5.Html
renderDiagnosticInput fieldName =
    Html5.input
        ! Attr.type_ "hidden"
        ! Attr.name (toValue fieldName)
        ! customAttribute (textTag (domAttrValue @inputMarker)) "true"
