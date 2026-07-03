{-# LANGUAGE DataKinds     #-}
{-# LANGUAGE TypeOperators #-}

module Application.Helper.FrontendSurface.Support
    ( SupportAwardRates
    , SupportPublicHolidays
    , SupportSurface
    , SupportPlatform
    ) where

import Application.Helper.FrontendSurface.DSL

data Support

data SupportPlatform

data SupportAwardRates
data SupportPublicHolidays

type SupportSurface =
    Surface Support
        '[ Scope SupportPlatform '[]
         , Fragment SupportAwardRates '[] '[ 'Eager, 'Live ]
         , Fragment SupportPublicHolidays '[] '[ 'Eager, 'Live ]
         ]
