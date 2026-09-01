module Application.Helper.Hasql
    ( isUniqueViolation
    ) where

import qualified Hasql.Errors as Hasql
import IHP.ModelSupport.Types (HasqlSessionError (..))
import IHP.Prelude

isUniqueViolation :: HasqlSessionError -> Bool
isUniqueViolation (HasqlSessionError sessionError) =
    case sessionError of
        Hasql.StatementSessionError _ _ _ _ _ statementError -> statementErrorIsUniqueViolation statementError
        Hasql.ScriptSessionError _ serverError -> serverErrorIsUniqueViolation serverError
        Hasql.ConnectionSessionError _ -> False
        Hasql.MissingTypesSessionError _ -> False
        Hasql.DriverSessionError _ -> False
  where
    statementErrorIsUniqueViolation (Hasql.ServerStatementError serverError) = serverErrorIsUniqueViolation serverError
    statementErrorIsUniqueViolation (Hasql.UnexpectedRowCountStatementError _ _ _) = False
    statementErrorIsUniqueViolation (Hasql.UnexpectedColumnCountStatementError _ _) = False
    statementErrorIsUniqueViolation (Hasql.UnexpectedColumnTypeStatementError _ _ _) = False
    statementErrorIsUniqueViolation (Hasql.RowStatementError _ _) = False
    statementErrorIsUniqueViolation (Hasql.UnexpectedResultStatementError _) = False

    serverErrorIsUniqueViolation (Hasql.ServerError code _ _ _ _) = code == "23505"
