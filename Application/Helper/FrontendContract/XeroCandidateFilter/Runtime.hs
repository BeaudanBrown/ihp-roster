{-# LANGUAGE TypeApplications #-}

module Application.Helper.FrontendContract.XeroCandidateFilter.Runtime
    ( XeroCandidateSearchProjection
    , XeroCandidateFilterDom (..)
    , canonicalXeroCandidateFilterDom
    , xeroCandidateSearchProjection
    , xeroCandidateFilterRootAttrs
    , xeroCandidateFilterSearchAttrs
    , xeroCandidateFilterCandidateAttrs
    , xeroCandidateFilterEmptyAttrs
    ) where

import Application.Error.Startup (startupInvariantFailure)
import Application.Helper.FrontendContract.Values (domAttrValue)
import Application.Helper.FrontendContract.Wire.Carrier
import qualified Application.Helper.FrontendContract.XeroCandidateFilter as Contract
import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Text as Text
import qualified Data.Text.Encoding as TextEncoding
import IHP.Prelude

-- | Opaque, normalized text selected by Haskell for generic browser matching.
-- The constructor stays private so candidate views cannot bypass normalization.
newtype XeroCandidateSearchProjection = XeroCandidateSearchProjection Text
    deriving (Eq, Show)

data XeroCandidateFilterDom = XeroCandidateFilterDom
    { xeroCandidateFilterRootAttribute      :: !Text
    , xeroCandidateFilterSearchAttribute    :: !Text
    , xeroCandidateFilterCandidateAttribute :: !Text
    , xeroCandidateFilterConfigAttribute    :: !Text
    , xeroCandidateFilterEmptyAttribute     :: !Text
    }
    deriving (Eq, Show)

canonicalXeroCandidateFilterDom :: XeroCandidateFilterDom
canonicalXeroCandidateFilterDom = XeroCandidateFilterDom
    { xeroCandidateFilterRootAttribute = domAttrValue @Contract.XeroCandidateFilterRoot
    , xeroCandidateFilterSearchAttribute = domAttrValue @Contract.XeroCandidateFilterSearch
    , xeroCandidateFilterCandidateAttribute = domAttrValue @Contract.XeroCandidateFilterCandidate
    , xeroCandidateFilterConfigAttribute = domAttrValue @Contract.XeroCandidateFilterConfig
    , xeroCandidateFilterEmptyAttribute = domAttrValue @Contract.XeroCandidateFilterEmpty
    }

xeroCandidateSearchProjection :: [Text] -> XeroCandidateSearchProjection
xeroCandidateSearchProjection fields
    | Text.null normalized = startupInvariantFailure "Xero candidate search projection must not be empty"
    | otherwise = XeroCandidateSearchProjection normalized
    where
        normalized = Text.unwords (concatMap (Text.words . Text.toLower) fields)

xeroCandidateFilterRootAttrs :: [(Text, Text)]
xeroCandidateFilterRootAttrs = roleAttrs canonicalXeroCandidateFilterDom.xeroCandidateFilterRootAttribute

xeroCandidateFilterSearchAttrs :: [(Text, Text)]
xeroCandidateFilterSearchAttrs = roleAttrs canonicalXeroCandidateFilterDom.xeroCandidateFilterSearchAttribute

xeroCandidateFilterCandidateAttrs :: XeroCandidateSearchProjection -> [(Text, Text)]
xeroCandidateFilterCandidateAttrs (XeroCandidateSearchProjection projection) =
    [ (canonicalXeroCandidateFilterDom.xeroCandidateFilterCandidateAttribute, "true")
    , (canonicalXeroCandidateFilterDom.xeroCandidateFilterConfigAttribute, candidateConfigJson projection)
    ]

candidateConfigJson :: Text -> Text
candidateConfigJson projection =
    TextEncoding.decodeUtf8 . LBS.toStrict . Aeson.encode $
        recordValue @Contract.XeroCandidateFilterConfig
            (requiredField @Contract.SearchProjection projection &: noFields)

xeroCandidateFilterEmptyAttrs :: [(Text, Text)]
xeroCandidateFilterEmptyAttrs = roleAttrs canonicalXeroCandidateFilterDom.xeroCandidateFilterEmptyAttribute

roleAttrs :: Text -> [(Text, Text)]
roleAttrs attribute = [(attribute, "true")]
