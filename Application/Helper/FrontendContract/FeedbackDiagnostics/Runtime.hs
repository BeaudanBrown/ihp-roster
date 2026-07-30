{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE TypeApplications    #-}

module Application.Helper.FrontendContract.FeedbackDiagnostics.Runtime
    ( renderFeedbackDiagnosticInputs
    ) where

import qualified Application.Helper.FrontendContract.AppShell as AppShell
import qualified Application.Helper.FrontendContract.FeedbackDiagnostics as Contract
import Application.Helper.FrontendContract.Naming (FrontendSurfaceNameContext (FieldName),
                                                   deriveFrontendSurfaceTypeName)
import Application.Helper.FrontendContract.Values (domAttrValue)
import Data.Typeable (Typeable)
import IHP.Prelude
import Text.Blaze (toValue)
import Text.Blaze.Html ((!))
import qualified Text.Blaze.Html5 as Html5
import qualified Text.Blaze.Html5.Attributes as Attr
import Text.Blaze.Internal (customAttribute, textTag)

renderFeedbackDiagnosticInputs :: Html5.Html
renderFeedbackDiagnosticInputs = do
    renderDiagnosticInput @Contract.FeedbackViewportWidthInput @AppShell.FeedbackViewportWidthField
    renderDiagnosticInput @Contract.FeedbackViewportHeightInput @AppShell.FeedbackViewportHeightField
    renderDiagnosticInput @Contract.FeedbackDevicePixelRatioInput @AppShell.FeedbackDevicePixelRatioField
    renderDiagnosticInput @Contract.FeedbackDisplayModeInput @AppShell.FeedbackDisplayModeField

renderDiagnosticInput :: forall inputMarker fieldMarker. (Typeable inputMarker, Typeable fieldMarker) => Html5.Html
renderDiagnosticInput =
    Html5.input
        ! Attr.type_ "hidden"
        ! Attr.name (toValue (deriveFrontendSurfaceTypeName @fieldMarker FieldName))
        ! customAttribute (textTag (domAttrValue @inputMarker)) "true"
