{-# OPTIONS_GHC -Werror=incomplete-patterns #-}

module Web.Profiles.LiveUpdates
    ( ProfileContentFragment (..)
    , ProfileLeaveFragment (..)
    , profileContentFragment
    , profileContentFragmentSectionParam
    , profileLeaveRequestsFragment
    ) where

import Web.Controller.Prelude

data ProfileContentFragment
    = ProfileDetailsContentFragment
    | ProfilePreferencesContentFragment
    | ProfileRsaContentFragment
    | ProfileLeaveContentFragment
    | ProfileSecurityContentFragment
    deriving (Eq, Show)

profileContentFragment :: Text -> ProfileContentFragment
profileContentFragment section =
    case section of
        "preferences" -> ProfilePreferencesContentFragment
        "rsa"         -> ProfileRsaContentFragment
        "leave"       -> ProfileLeaveContentFragment
        "security"    -> ProfileSecurityContentFragment
        _             -> ProfileDetailsContentFragment

profileContentFragmentSectionParam :: ProfileContentFragment -> Text
profileContentFragmentSectionParam ProfileDetailsContentFragment =
    "profile"
profileContentFragmentSectionParam ProfilePreferencesContentFragment =
    "preferences"
profileContentFragmentSectionParam ProfileRsaContentFragment =
    "rsa"
profileContentFragmentSectionParam ProfileLeaveContentFragment =
    "leave"
profileContentFragmentSectionParam ProfileSecurityContentFragment =
    "security"

data ProfileLeaveFragment
    = ProfileLeaveRequestsLiveFragment
    deriving (Eq, Show)

profileLeaveRequestsFragment :: ProfileLeaveFragment
profileLeaveRequestsFragment =
    ProfileLeaveRequestsLiveFragment
