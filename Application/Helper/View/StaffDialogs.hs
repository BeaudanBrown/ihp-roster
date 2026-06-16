module Application.Helper.View.StaffDialogs
    ( renderStaffEditDialog
    , renderStaffAddTrialDialogWithButtons
    , renderStaffAddTrialPageModalWithButtons
    , renderStaffEditDialogWithButtons
    , renderStaffEditPageModal
    , renderStaffEditPageModalWithButtons
    ) where

import Application.Helper.View.Overlay
import IHP.ViewPrelude
import Web.Routes ()
import Web.Types

staffEditDialogClass :: Text
staffEditDialogClass = "app-staff-edit-dialog"

renderStaffEditPageModal :: Int -> Text -> Html -> Html
renderStaffEditPageModal weekOffset formId =
    renderStaffEditPageModalWithButtons weekOffset (defaultOverlayButtons formId)

renderStaffEditPageModalWithButtons :: Int -> [OverlayButton] -> Html -> Html
renderStaffEditPageModalWithButtons = renderStaffPageModalWithTitle "Edit Staff Member"

renderStaffAddTrialPageModalWithButtons :: Int -> [OverlayButton] -> Html -> Html
renderStaffAddTrialPageModalWithButtons = renderStaffPageModalWithTitle "Add Trial"

renderStaffPageModalWithTitle :: Text -> Int -> [OverlayButton] -> Html -> Html
renderStaffPageModalWithTitle title weekOffset buttons formContent =
    renderPageDialogModal
        (pathTo (ShowRosterWeekAction weekOffset))
        DialogOverlayConfig
            { dialogOverlayTitle = title
            , dialogOverlayBody = formContent
            , dialogOverlayStartButtons = []
            , dialogOverlayButtons = buttons
            , dialogOverlayDialogClass = staffEditDialogClass
            }

renderStaffEditDialog :: Text -> Html -> Html
renderStaffEditDialog formId =
    renderStaffEditDialogWithButtons (defaultOverlayButtons formId)

renderStaffEditDialogWithButtons :: [OverlayButton] -> Html -> Html
renderStaffEditDialogWithButtons = renderStaffDialogWithTitle "Edit Staff Member"

renderStaffAddTrialDialogWithButtons :: [OverlayButton] -> Html -> Html
renderStaffAddTrialDialogWithButtons = renderStaffDialogWithTitle "Add Trial"

renderStaffDialogWithTitle :: Text -> [OverlayButton] -> Html -> Html
renderStaffDialogWithTitle title buttons formContent =
    renderDialogOverlay DialogOverlayConfig
        { dialogOverlayTitle = title
        , dialogOverlayBody = formContent
        , dialogOverlayStartButtons = []
        , dialogOverlayButtons = buttons
        , dialogOverlayDialogClass = staffEditDialogClass
        }
