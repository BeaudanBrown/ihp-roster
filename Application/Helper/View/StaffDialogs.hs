module Application.Helper.View.StaffDialogs
    ( renderStaffAddTrialDialogWithButtons
    , renderStaffAddTrialPageModalWithButtons
    , renderStaffEditDialogWithButtons
    , renderStaffEditPageModalWithButtons
    ) where

import Application.Helper.View.Overlay
import IHP.ViewPrelude
import Web.Routes ()
import Web.Types

staffEditDialogClass :: Text
staffEditDialogClass = "app-staff-edit-dialog"


renderStaffEditPageModalWithButtons :: [OverlayButton] -> Html -> Html
renderStaffEditPageModalWithButtons = renderStaffPageModalWithTitle "Edit Staff Member"

renderStaffAddTrialPageModalWithButtons :: [OverlayButton] -> Html -> Html
renderStaffAddTrialPageModalWithButtons = renderStaffPageModalWithTitle "Add Trial"

renderStaffPageModalWithTitle :: Text -> [OverlayButton] -> Html -> Html
renderStaffPageModalWithTitle title buttons formContent =
    renderPageDialogModal
        (pathTo RosterWeeksAction)
        (defaultDialogOverlayConfig
            title
            formContent
            buttons)
            { dialogOverlayDialogClass = staffEditDialogClass
            }


renderStaffEditDialogWithButtons :: [OverlayButton] -> Html -> Html
renderStaffEditDialogWithButtons = renderStaffDialogWithTitle "Edit Staff Member"

renderStaffAddTrialDialogWithButtons :: [OverlayButton] -> Html -> Html
renderStaffAddTrialDialogWithButtons = renderStaffDialogWithTitle "Add Trial"

renderStaffDialogWithTitle :: Text -> [OverlayButton] -> Html -> Html
renderStaffDialogWithTitle title buttons formContent =
    renderDialogOverlay (defaultDialogOverlayConfig
            title
            formContent
            buttons)
            { dialogOverlayDialogClass = staffEditDialogClass
            }
