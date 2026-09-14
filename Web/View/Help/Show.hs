module Web.View.Help.Show where

import Web.View.Prelude

newtype ShowView = ShowView
    { filteredTopic :: PageHelpTopic
    }

instance View ShowView where
    html ShowView { .. } =
        renderPageDialogModal
            (pathTo RosterWeeksAction)
            (pageHelpDialogConfig filteredTopic)

renderPageHelpDialog :: PageHelpTopic -> Html
renderPageHelpDialog topic =
    renderDialogOverlay (pageHelpDialogConfig topic)

pageHelpDialogConfig :: PageHelpTopic -> DialogOverlayConfig
pageHelpDialogConfig topic =
    (defaultDialogOverlayConfig
            ("Help - " <> pageHelpTopicTitle topic)
            (renderPageHelpBody topic)
            [ OverlayButton
                { overlayButtonLabel = "Close"
                , overlayButtonClass = "btn btn-primary"
                , overlayButtonAction = OverlayCloseAction
                }
            ])
            { dialogOverlayDialogClass = "modal-lg modal-dialog-scrollable"
            }
