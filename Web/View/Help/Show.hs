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
    DialogOverlayConfig
        { dialogOverlayTitle = pageHelpTopicTitle topic
        , dialogOverlayBody = renderPageHelpBody topic
        , dialogOverlayStartButtons = []
        , dialogOverlayButtons =
            [ OverlayButton
                { overlayButtonLabel = "Close"
                , overlayButtonClass = "btn btn-primary"
                , overlayButtonAction = OverlayCloseAction
                }
            ]
        , dialogOverlayDialogClass = ""
        }
