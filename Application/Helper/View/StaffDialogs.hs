module Application.Helper.View.StaffDialogs
    ( renderStaffEditDialog
    , renderStaffEditPageModal
    ) where

import Application.Helper.View.Overlay
import IHP.ViewPrelude
import Web.Routes ()
import Web.Types

renderStaffEditPageModal :: Int -> Text -> Html -> Html
renderStaffEditPageModal weekOffset formId formContent =
    renderPageDialogModal
        (pathTo (ShowRosterWeekAction weekOffset))
        DialogOverlayConfig
            { dialogOverlayTitle = "Edit Staff Member"
            , dialogOverlayBody = formContent
            , dialogOverlayStartButtons = []
            , dialogOverlayButtons = defaultOverlayButtons formId
            , dialogOverlayDialogClass = ""
            }

renderStaffEditDialog :: Text -> Html -> Html
renderStaffEditDialog formId formContent =
    renderDialogOverlay DialogOverlayConfig
        { dialogOverlayTitle = "Edit Staff Member"
        , dialogOverlayBody = formContent
        , dialogOverlayStartButtons = []
        , dialogOverlayButtons = defaultOverlayButtons formId
        , dialogOverlayDialogClass = ""
        }
