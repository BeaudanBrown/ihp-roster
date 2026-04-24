module Application.Async.Registry
    ( dispatchAppJob
    ) where

import qualified Data.Text as Text
import Generated.Types
import IHP.ControllerPrelude

dispatchAppJob ::
    (?modelContext :: ModelContext) =>
    AppJob ->
    IO ()
dispatchAppJob appJob =
    fail ("Unknown app job kind: " <> Text.unpack appJob.jobKind)
