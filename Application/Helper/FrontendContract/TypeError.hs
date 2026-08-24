{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE DataKinds       #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE PolyKinds      #-}
{-# LANGUAGE TypeOperators  #-}

-- | Stable project-owned prefix for compile-time FrontendContract diagnostics.
module Application.Helper.FrontendContract.TypeError
    ( BepisTypeError
    ) where

import GHC.TypeLits (ErrorMessage (..), Symbol, TypeError)

type BepisTypeError (tag :: Symbol) (message :: ErrorMessage) =
    TypeError ('Text tag ':$$: message)
