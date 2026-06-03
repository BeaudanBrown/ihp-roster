module Application.Helper.View.StaffDialogs
    ( renderStaffEditDialog
    , renderStaffEditDialogWithButtons
    , renderStaffEditPageModal
    , renderStaffEditPageModalWithButtons
    ) where

import Application.Helper.View.Overlay
import IHP.ViewPrelude
import Web.Routes ()
import Web.Types

renderStaffEditPageModal :: Int -> Text -> Html -> Html
renderStaffEditPageModal weekOffset formId =
    renderStaffEditPageModalWithButtons weekOffset (defaultOverlayButtons formId)

renderStaffEditPageModalWithButtons :: Int -> [OverlayButton] -> Html -> Html
renderStaffEditPageModalWithButtons weekOffset buttons formContent =
    renderPageDialogModal
        (pathTo (ShowRosterWeekAction weekOffset))
        DialogOverlayConfig
            { dialogOverlayTitle = "Edit Staff Member"
            , dialogOverlayBody = formContent
            , dialogOverlayStartButtons = []
            , dialogOverlayButtons = buttons
            , dialogOverlayDialogClass = ""
            }

renderStaffEditDialog :: Text -> Html -> Html
renderStaffEditDialog formId =
    renderStaffEditDialogWithButtons (defaultOverlayButtons formId)

renderStaffEditDialogWithButtons :: [OverlayButton] -> Html -> Html
renderStaffEditDialogWithButtons buttons formContent =
    renderDialogOverlay DialogOverlayConfig
        { dialogOverlayTitle = "Edit Staff Member"
        , dialogOverlayBody = formContent
        , dialogOverlayStartButtons = []
        , dialogOverlayButtons = buttons
        , dialogOverlayDialogClass = ""
        }
