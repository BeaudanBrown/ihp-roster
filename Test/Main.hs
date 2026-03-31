module Main where

import Test.Hspec
import IHP.Prelude

import qualified Test.Controller.StaticSpec
import qualified Test.Controller.SessionsSpec
import qualified Test.Controller.UsersSpec
import qualified Test.Controller.DashboardSpec
import qualified Test.LiveUpdateSpec

main :: IO ()
main = hspec do
    Test.Controller.StaticSpec.tests
    Test.Controller.SessionsSpec.tests
    Test.Controller.UsersSpec.tests
    Test.Controller.DashboardSpec.tests
    Test.LiveUpdateSpec.tests
