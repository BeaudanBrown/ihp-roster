module Test.Controller.AdminSpec where

import IHP.Prelude
import qualified Test.Controller.Admin.AccessSpec
import qualified Test.Controller.Admin.ConfigSpec
import qualified Test.Controller.Admin.XeroSpec
import Test.Hspec

tests :: Spec
tests = do
    Test.Controller.Admin.AccessSpec.tests
    Test.Controller.Admin.XeroSpec.tests
    Test.Controller.Admin.ConfigSpec.tests
