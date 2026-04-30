module Test.Controller.RosterWeeksSpec where

import IHP.Prelude
import qualified Test.Controller.RosterWeeks.FragmentsSpec
import qualified Test.Controller.RosterWeeks.NavigationSpec
import qualified Test.Controller.RosterWeeks.WorkflowSpec
import Test.Hspec

tests :: Spec
tests = do
    Test.Controller.RosterWeeks.NavigationSpec.tests
    Test.Controller.RosterWeeks.WorkflowSpec.tests
    Test.Controller.RosterWeeks.FragmentsSpec.tests
