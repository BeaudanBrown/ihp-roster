{-# LANGUAGE DataKinds     #-}
{-# LANGUAGE TypeOperators #-}

module Application.Helper.FrontendSurface.Support
    ( SupportAwardRates
    , SupportAwardRatesResource
    , SupportPublicHolidays
    , SupportPublicHolidaysResource
    , SupportSurface
    , SupportPlatform
    ) where

import Application.Helper.FrontendSurface.DSL

data Support

data SupportPlatform

data SupportAwardRates
data SupportPublicHolidays

type SupportAwardRatesResource = Resource SupportAwardRates '[]
type SupportPublicHolidaysResource = Resource SupportPublicHolidays '[]

type SupportSurface =
    Surface Support
        '[ Scope SupportPlatform '[] '[ 'Authorize 'SupportSuperAdmin '[] ]
         , Fragment SupportAwardRates '[] '[ 'Eager, 'Live, 'DependsOn SupportAwardRatesResource '[] ]
         , Fragment SupportPublicHolidays '[] '[ 'Eager, 'Live, 'DependsOn SupportPublicHolidaysResource '[] ]
         ]
