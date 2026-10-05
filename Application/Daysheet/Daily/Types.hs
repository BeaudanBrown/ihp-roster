-- | Codec-independent daily edit/concurrency identities. Surface-owned nominal
-- inputs may depend on these without importing persisted-document codecs.
module Application.Daysheet.Daily.Types
    ( CellAddress (..), DeletionPlan (..) ) where

import Prelude
import Application.Daysheet.Contract
import Application.Daysheet.References (ReferenceKey)

data CellAddress = RootCell FieldId | RowCell ReferenceKey FieldId deriving (Eq, Ord, Show)
data DeletionPlan = DeletionPlan
    { deletionTarget :: ReferenceKey, targetRevision :: Integer
    , incomingCells :: [(CellAddress, Integer)]
    } deriving (Eq, Show)
