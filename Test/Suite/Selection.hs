module Test.Suite.Selection
    ( hspecArgumentsMayFilter
    )
where

import qualified Data.Text as Text
import IHP.Prelude

hspecArgumentsMayFilter :: [Text] -> Bool
hspecArgumentsMayFilter = any isFilteringArgument
  where
    isFilteringArgument argument =
        argument == "-m"
            || argument == "--match"
            || argument == "--skip"
            || ("-m" `Text.isPrefixOf` argument && Text.length argument > 2)
            || "--match=" `Text.isPrefixOf` argument
            || "--skip=" `Text.isPrefixOf` argument
            || argument == "--focused-only"
            || argument == "-r"
            || argument == "--rerun"
            || argument == "--rerun-all-on-success"
            || "--rerun-all-on-success=" `Text.isPrefixOf` argument
