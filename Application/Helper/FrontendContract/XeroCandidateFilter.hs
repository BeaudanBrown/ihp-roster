{-# LANGUAGE DataKinds     #-}
{-# LANGUAGE TypeOperators #-}

module Application.Helper.FrontendContract.XeroCandidateFilter
    ( XeroCandidateFilterContract
    , XeroCandidateFilter
    , XeroCandidateFilterConfig
    , SearchProjection
    , XeroCandidateFilterRoot
    , XeroCandidateFilterSearch
    , XeroCandidateFilterCandidate
    , XeroCandidateFilterEmpty
    ) where

import Application.Helper.FrontendContract.DSL

-- | Xero pay-item candidate filtering vocabulary. Haskell owns each opaque
-- normalized search projection; the browser adapter owns generic matching and
-- visibility only.
data XeroCandidateFilter

data XeroCandidateFilterConfig
data SearchProjection

data XeroCandidateFilterRoot
data XeroCandidateFilterSearch
data XeroCandidateFilterCandidate
data XeroCandidateFilterEmpty

type XeroCandidateFilterContract =
    Global XeroCandidateFilter
        '[ BrowserInboundSchema (Record XeroCandidateFilterConfig
            '[ Field SearchProjection 'WireText
             ])
         , DomAttr XeroCandidateFilterRoot
         , DomAttr XeroCandidateFilterSearch
         , DomAttr XeroCandidateFilterCandidate
         , DomAttr XeroCandidateFilterConfig
         , DomAttr XeroCandidateFilterEmpty
         ]
