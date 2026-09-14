module Test.CompileFail.ApplicationErrorEitherTextBoundary where

import Application.Error.Types (AppResult)
import IHP.Prelude

-- Operation boundaries cannot expose unclassified textual failures.
invalidRequestWorkflowOrJobOperation :: IO (AppResult ())
invalidRequestWorkflowOrJobOperation = pure (Left ("unclassified operation failure" :: Text))
