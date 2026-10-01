module Application.Helper.Hasql
    ( isUniqueViolation
    , isSerializationFailure
    ) where

import qualified Hasql.Errors as Hasql
import IHP.ModelSupport.Types (HasqlSessionError (..))
import IHP.Prelude

isUniqueViolation :: HasqlSessionError -> Bool
isUniqueViolation = hasSqlState "23505"

isSerializationFailure :: HasqlSessionError -> Bool
isSerializationFailure = hasSqlState "40001"

hasSqlState :: Text -> HasqlSessionError -> Bool
hasSqlState expected (HasqlSessionError sessionError) =
    case sessionError of
        Hasql.StatementSessionError _ _ _ _ _ statementError -> matchesStatement statementError
        Hasql.ScriptSessionError _ serverError -> matchesServer serverError
        Hasql.ConnectionSessionError _ -> False
        Hasql.MissingTypesSessionError _ -> False
        Hasql.DriverSessionError _ -> False
  where
    matchesStatement (Hasql.ServerStatementError serverError) = matchesServer serverError
    matchesStatement (Hasql.UnexpectedRowCountStatementError _ _ _) = False
    matchesStatement (Hasql.UnexpectedColumnCountStatementError _ _) = False
    matchesStatement (Hasql.UnexpectedColumnTypeStatementError _ _ _) = False
    matchesStatement (Hasql.RowStatementError _ _) = False
    matchesStatement (Hasql.UnexpectedResultStatementError _) = False

    matchesServer (Hasql.ServerError code _ _ _ _) = code == expected
