module Web.Controller.Static where
import Web.Controller.Prelude
import Web.View.Static.Welcome

instance Controller StaticController where
    action WelcomeAction = do
        case currentUserOrNothing of
            Just _ -> redirectTo RosterWeeksAction
            Nothing -> do
                setTitle "Bepis"
                render WelcomeView
    action PublicBillingSupportAction = do
        setTitle "Bepis Billing and Support"
        render PublicBillingSupportView
