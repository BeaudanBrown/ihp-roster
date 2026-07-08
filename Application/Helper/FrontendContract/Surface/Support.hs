{-# LANGUAGE DataKinds     #-}
{-# LANGUAGE TypeOperators #-}

module Application.Helper.FrontendContract.Surface.Support
    ( SupportAwardRates
    , SupportAwardRatesResource
    , SupportPublicHolidays
    , SupportPublicHolidaysResource
    , SupportSurface
    , SupportPlatform
    , CreatePublicHolidayRefreshJob
    , CreateFwcMapdRefreshJob
    ) where

import Application.Helper.FrontendContract.Surface.DSL

data Support

data SupportPlatform

data SupportAwardRates
data SupportPublicHolidays
data CreatePublicHolidayRefreshJob
data CreateFwcMapdRefreshJob
data OuterHTML

type SupportAwardRatesResource = Resource SupportAwardRates '[]
type SupportPublicHolidaysResource = Resource SupportPublicHolidays '[]

type SupportSurface =
    Surface Support
        '[ Scope SupportPlatform '[] '[ 'Authorize 'SupportSuperAdmin '[] ]
         , Fragment SupportAwardRates '[] '[ 'Eager, 'Live, 'DependsOn SupportAwardRatesResource '[] ]
         , Fragment SupportPublicHolidays '[] '[ 'Eager, 'Live, 'DependsOn SupportPublicHolidaysResource '[] ]
         , Action CreatePublicHolidayRefreshJob
            '[]
            '[ 'HtmxMethod 'HtmxPost
             , 'HtmxTarget SupportPublicHolidays
             , 'HtmxSwap OuterHTML
             ]
         , Action CreateFwcMapdRefreshJob
            '[]
            '[ 'HtmxMethod 'HtmxPost
             , 'HtmxTarget SupportAwardRates
             , 'HtmxSwap OuterHTML
             ]
         , DomToken SupportPublicHolidays
         , DomToken SupportAwardRates
         ]
