{-# OPTIONS_GHC -Werror=incomplete-patterns #-}

-- | Exhaustive presentation over the generated persisted feedback category.
module Application.Helper.FeedbackType
    ( feedbackTypeLabel
    ) where

import Generated.Types (FeedbackTypeEnum (..))
import IHP.Prelude

feedbackTypeLabel :: FeedbackTypeEnum -> Text
feedbackTypeLabel Bug        = "bug"
feedbackTypeLabel Suggestion = "suggestion"
feedbackTypeLabel Other      = "other"
