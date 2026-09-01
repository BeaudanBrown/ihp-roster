{-# LANGUAGE TypeApplications #-}
{-# OPTIONS_GHC -Werror=incomplete-patterns #-}

module Application.Helper.Export.PayrollWorkbookConfiguration
    ( NewPayrollWorkbookConfiguration (..)
    , UpdatePayrollWorkbookConfiguration (..)
    , SavedPayrollWorkbookConfiguration (..)
    , PayrollWorkbookConfigurationError (..)
    , createSavedPayrollWorkbookConfiguration
    , createSavedPayrollWorkbookConfigurationInCurrentTransaction
    , createStandardPayrollWorkbookConfigurationInCurrentTransaction
    , updateSavedPayrollWorkbookConfigurationInCurrentTransaction
    , deleteSavedPayrollWorkbookConfiguration
    , fetchSavedPayrollWorkbookConfiguration
    , listSavedPayrollWorkbookConfigurations
    , normalizePayrollWorkbookConfigurationName
    , payrollWorkbookConfigurationPersistenceError
    ) where

import Application.Error.Runtime (throwExternalRuntime)
import Application.Helper.ControllerAccess (hasRole)
import Application.Helper.ControllerContext (authenticatedCurrentUser,
                                             currentVenueId,
                                             currentVenueOrNothing)
import Application.Helper.Export.PayrollWorkbook
import qualified Control.Exception as Exception
import Control.Monad (void)
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import qualified Data.Text as Text
import Data.Traversable (traverse)
import qualified Generated.Types as Types
import qualified Hasql.Errors as Hasql
import IHP.ControllerPrelude
import IHP.ModelSupport.Types (HasqlSessionError (..))

-- | Boundary input remains textual so unsupported persisted/UI values are
-- rejected by the same total parser used by workbook definitions.
data NewPayrollWorkbookConfiguration = NewPayrollWorkbookConfiguration
    { newPayrollWorkbookConfigurationName              :: !Text
    , newPayrollWorkbookConfigurationDefinitionVersion :: !Int
    , newPayrollWorkbookConfigurationFamilyKeys        :: ![Text]
    }
    deriving (Eq, Show)

data UpdatePayrollWorkbookConfiguration = UpdatePayrollWorkbookConfiguration
    { updatePayrollWorkbookConfigurationName              :: !Text
    , updatePayrollWorkbookConfigurationDefinitionVersion :: !Int
    , updatePayrollWorkbookConfigurationFamilyKeys        :: ![Text]
    , updatePayrollWorkbookConfigurationExpectedRevision  :: !Int
    }
    deriving (Eq, Show)

data SavedPayrollWorkbookConfiguration = SavedPayrollWorkbookConfiguration
    { savedPayrollWorkbookConfigurationRecord     :: !Types.PayrollWorkbookConfiguration
    , savedPayrollWorkbookConfigurationDefinition :: !PayrollWorkbookDefinition
    }
    deriving (Eq, Show)

data PayrollWorkbookConfigurationError
    = PayrollWorkbookConfigurationAccessDenied
    | PayrollWorkbookConfigurationInvalidName !Text
    | PayrollWorkbookConfigurationInvalidDefinition !Text
    | PayrollWorkbookConfigurationNameConflict !Text
    | PayrollWorkbookConfigurationNotFound
    | PayrollWorkbookConfigurationStale
    | PayrollWorkbookConfigurationStoredDefinitionInvalid !Text
    deriving (Eq, Show)

normalizePayrollWorkbookConfigurationName :: Text -> Text
normalizePayrollWorkbookConfigurationName = Text.unwords . Text.words

createSavedPayrollWorkbookConfiguration ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    NewPayrollWorkbookConfiguration ->
    IO (Either PayrollWorkbookConfigurationError SavedPayrollWorkbookConfiguration)
createSavedPayrollWorkbookConfiguration input =
    createSavedPayrollWorkbookConfigurationWithPersistence
        (\action -> Exception.try (withTransaction action))
        input

-- | Used only by an owner that already provides the atomic transaction (for
-- example durable live mutation publication). Persistence errors deliberately
-- escape so that owner can roll back before mapping them to a friendly result.
createSavedPayrollWorkbookConfigurationInCurrentTransaction ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    NewPayrollWorkbookConfiguration ->
    IO (Either PayrollWorkbookConfigurationError SavedPayrollWorkbookConfiguration)
createSavedPayrollWorkbookConfigurationInCurrentTransaction input =
    createSavedPayrollWorkbookConfigurationWithPersistence (fmap Right) input

createSavedPayrollWorkbookConfigurationWithPersistence ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    (IO SavedPayrollWorkbookConfiguration -> IO (Either HasqlSessionError SavedPayrollWorkbookConfiguration)) ->
    NewPayrollWorkbookConfiguration ->
    IO (Either PayrollWorkbookConfigurationError SavedPayrollWorkbookConfiguration)
createSavedPayrollWorkbookConfigurationWithPersistence persist input
    | not canManagePayrollWorkbookConfigurations = pure (Left PayrollWorkbookConfigurationAccessDenied)
    | Text.null normalizedName = pure (Left (PayrollWorkbookConfigurationInvalidName "Configuration names cannot be empty."))
    | Text.length normalizedName > 100 = pure (Left (PayrollWorkbookConfigurationInvalidName "Configuration names cannot exceed 100 characters."))
    | otherwise =
        case requestedDefinition of
            Left message -> pure (Left (PayrollWorkbookConfigurationInvalidDefinition message))
            Right definition -> do
                existing <-
                    query @Types.PayrollWorkbookConfiguration
                        |> filterWhere (#venueId, unpackId currentVenueId)
                        |> filterWhereCaseInsensitive (#name, normalizedName)
                        |> fetchOneOrNothing
                case existing of
                    Just _ -> pure (Left (PayrollWorkbookConfigurationNameConflict normalizedName))
                    Nothing -> persistDefinition definition
  where
    normalizedName = normalizePayrollWorkbookConfigurationName input.newPayrollWorkbookConfigurationName
    requestedDefinition =
        validateConfigurationDefinition
            input.newPayrollWorkbookConfigurationDefinitionVersion
            input.newPayrollWorkbookConfigurationFamilyKeys

    persistDefinition definition = do
        result <-
            persist do
                configuration <-
                    newRecord @Types.PayrollWorkbookConfiguration
                        |> set #venueId (unpackId currentVenueId)
                        |> set #name normalizedName
                        |> set #definitionVersion definition.payrollWorkbookDefinitionVersion
                        |> set #createdByUserId (unpackId authenticatedCurrentUser.id)
                        |> createRecord
                let familyRecords =
                        zipWith
                            (\position family ->
                                newRecord @Types.PayrollWorkbookConfigurationFamily
                                    |> set #configurationId (unpackId configuration.id)
                                    |> set #familyKey (payrollWorkbookSheetFamilyKey family)
                                    |> set #position position
                            )
                            [0 ..]
                            definition.payrollWorkbookDefinitionSheetFamilies
                _ <- mapM createRecord familyRecords
                pure
                    SavedPayrollWorkbookConfiguration
                        { savedPayrollWorkbookConfigurationRecord = configuration
                        , savedPayrollWorkbookConfigurationDefinition = savedDefinition configuration definition.payrollWorkbookDefinitionSheetFamilies
                        }
        case result of
            Right configuration -> pure (Right configuration)
            Left sessionError ->
                case payrollWorkbookConfigurationPersistenceError normalizedName sessionError of
                    Just configurationError -> pure (Left configurationError)
                    Nothing                 -> throwExternalRuntime sessionError

createStandardPayrollWorkbookConfigurationInCurrentTransaction ::
    (?modelContext :: ModelContext) =>
    Types.Venue ->
    Types.User ->
    IO SavedPayrollWorkbookConfiguration
createStandardPayrollWorkbookConfigurationInCurrentTransaction venue user = do
    configuration <-
        newRecord @Types.PayrollWorkbookConfiguration
            |> set #venueId (unpackId venue.id)
            |> set #name "Payroll Workbook"
            |> set #definitionVersion currentPayrollWorkbookDefinitionVersion
            |> set #revision 0
            |> set #createdByUserId (unpackId user.id)
            |> createRecord
    createConfigurationFamilyRecords configuration defaultPayrollWorkbookDefinition.payrollWorkbookDefinitionSheetFamilies
    pure
        SavedPayrollWorkbookConfiguration
            { savedPayrollWorkbookConfigurationRecord = configuration
            , savedPayrollWorkbookConfigurationDefinition =
                savedDefinition configuration defaultPayrollWorkbookDefinition.payrollWorkbookDefinitionSheetFamilies
            }

updateSavedPayrollWorkbookConfigurationInCurrentTransaction ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    Id Types.PayrollWorkbookConfiguration ->
    UpdatePayrollWorkbookConfiguration ->
    IO (Either PayrollWorkbookConfigurationError SavedPayrollWorkbookConfiguration)
updateSavedPayrollWorkbookConfigurationInCurrentTransaction configurationId input
    | not canManagePayrollWorkbookConfigurations = pure (Left PayrollWorkbookConfigurationAccessDenied)
    | Text.null normalizedName = pure (Left (PayrollWorkbookConfigurationInvalidName "Configuration names cannot be empty."))
    | Text.length normalizedName > 100 = pure (Left (PayrollWorkbookConfigurationInvalidName "Configuration names cannot exceed 100 characters."))
    | otherwise =
        case requestedDefinition of
            Left message -> pure (Left (PayrollWorkbookConfigurationInvalidDefinition message))
            Right definition -> do
                maybeConfiguration <-
                    query @Types.PayrollWorkbookConfiguration
                        |> filterWhere (#id, configurationId)
                        |> filterWhere (#venueId, unpackId currentVenueId)
                        |> fetchOneOrNothing
                case maybeConfiguration of
                    Nothing -> pure (Left PayrollWorkbookConfigurationNotFound)
                    Just configuration
                        | configuration.revision /= input.updatePayrollWorkbookConfigurationExpectedRevision ->
                            pure (Left PayrollWorkbookConfigurationStale)
                        | otherwise -> do
                            now <- getCurrentTime
                            updatedConfiguration <-
                                configuration
                                    |> set #name normalizedName
                                    |> set #definitionVersion definition.payrollWorkbookDefinitionVersion
                                    |> set #revision (configuration.revision + 1)
                                    |> set #updatedAt now
                                    |> updateRecord
                            existingFamilies <-
                                query @Types.PayrollWorkbookConfigurationFamily
                                    |> filterWhere (#configurationId, unpackId configuration.id)
                                    |> fetch
                            mapM_ deleteRecord existingFamilies
                            createConfigurationFamilyRecords updatedConfiguration definition.payrollWorkbookDefinitionSheetFamilies
                            pure
                                (Right
                                    SavedPayrollWorkbookConfiguration
                                        { savedPayrollWorkbookConfigurationRecord = updatedConfiguration
                                        , savedPayrollWorkbookConfigurationDefinition =
                                            savedDefinition updatedConfiguration definition.payrollWorkbookDefinitionSheetFamilies
                                        }
                                )
  where
    normalizedName = normalizePayrollWorkbookConfigurationName input.updatePayrollWorkbookConfigurationName
    requestedDefinition =
        validateConfigurationDefinition
            input.updatePayrollWorkbookConfigurationDefinitionVersion
            input.updatePayrollWorkbookConfigurationFamilyKeys

validateConfigurationDefinition :: Int -> [Text] -> Either Text PayrollWorkbookDefinition
validateConfigurationDefinition definitionVersion familyKeys = do
    families <- traverse payrollWorkbookSheetFamilyFromText familyKeys
    let definition =
            PayrollWorkbookDefinition
                { payrollWorkbookDefinitionKey = "saved-pending"
                , payrollWorkbookDefinitionVersion = definitionVersion
                , payrollWorkbookDefinitionSheetFamilies = families
                }
    validatePayrollWorkbookDefinition definition
    pure definition

createConfigurationFamilyRecords ::
    (?modelContext :: ModelContext) =>
    Types.PayrollWorkbookConfiguration ->
    [PayrollWorkbookSheetFamily] ->
    IO ()
createConfigurationFamilyRecords configuration families = do
    let familyRecords =
            zipWith
                (\position family ->
                    newRecord @Types.PayrollWorkbookConfigurationFamily
                        |> set #configurationId (unpackId configuration.id)
                        |> set #familyKey (payrollWorkbookSheetFamilyKey family)
                        |> set #position position
                )
                [0 ..]
                families
    void (mapM createRecord familyRecords)

payrollWorkbookConfigurationPersistenceError :: Text -> HasqlSessionError -> Maybe PayrollWorkbookConfigurationError
payrollWorkbookConfigurationPersistenceError normalizedName sessionError
    | isUniqueViolation sessionError = Just (PayrollWorkbookConfigurationNameConflict normalizedName)
    | otherwise = Nothing

listSavedPayrollWorkbookConfigurations ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    IO (Either PayrollWorkbookConfigurationError [SavedPayrollWorkbookConfiguration])
listSavedPayrollWorkbookConfigurations
    | not canManagePayrollWorkbookConfigurations = pure (Left PayrollWorkbookConfigurationAccessDenied)
    | otherwise = do
        configurations <-
            query @Types.PayrollWorkbookConfiguration
                |> filterWhere (#venueId, unpackId currentVenueId)
                |> fetch
        families <- fetchFamilies configurations
        pure $ traverse (hydrateConfiguration families) (sortConfigurations configurations)

fetchSavedPayrollWorkbookConfiguration ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    Id Types.PayrollWorkbookConfiguration ->
    IO (Either PayrollWorkbookConfigurationError SavedPayrollWorkbookConfiguration)
fetchSavedPayrollWorkbookConfiguration configurationId
    | not canManagePayrollWorkbookConfigurations = pure (Left PayrollWorkbookConfigurationAccessDenied)
    | otherwise = do
        maybeConfiguration <-
            query @Types.PayrollWorkbookConfiguration
                |> filterWhere (#id, configurationId)
                |> filterWhere (#venueId, unpackId currentVenueId)
                |> fetchOneOrNothing
        case maybeConfiguration of
            Nothing -> pure (Left PayrollWorkbookConfigurationNotFound)
            Just configuration -> do
                families <- fetchFamilies [configuration]
                pure (hydrateConfiguration families configuration)

deleteSavedPayrollWorkbookConfiguration ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    Id Types.PayrollWorkbookConfiguration ->
    IO (Either PayrollWorkbookConfigurationError ())
deleteSavedPayrollWorkbookConfiguration configurationId
    | not canManagePayrollWorkbookConfigurations = pure (Left PayrollWorkbookConfigurationAccessDenied)
    | otherwise = do
        maybeConfiguration <-
            query @Types.PayrollWorkbookConfiguration
                |> filterWhere (#id, configurationId)
                |> filterWhere (#venueId, unpackId currentVenueId)
                |> fetchOneOrNothing
        case maybeConfiguration of
            Nothing -> pure (Left PayrollWorkbookConfigurationNotFound)
            Just configuration -> deleteRecord configuration >> pure (Right ())

canManagePayrollWorkbookConfigurations :: (?context :: ControllerContext) => Bool
canManagePayrollWorkbookConfigurations =
    isJust currentVenueOrNothing && hasRole Types.VenueAdmin

fetchFamilies ::
    (?modelContext :: ModelContext) =>
    [Types.PayrollWorkbookConfiguration] ->
    IO (Map.Map UUID [Types.PayrollWorkbookConfigurationFamily])
fetchFamilies [] = pure Map.empty
fetchFamilies configurations = do
    familyRecords <-
        query @Types.PayrollWorkbookConfigurationFamily
            |> filterWhereIn (#configurationId, map (unpackId . (.id)) configurations)
            |> orderByAsc #position
            |> fetch
    pure (Map.fromListWith (flip (<>)) [(family.configurationId, [family]) | family <- familyRecords])

hydrateConfiguration ::
    Map.Map UUID [Types.PayrollWorkbookConfigurationFamily] ->
    Types.PayrollWorkbookConfiguration ->
    Either PayrollWorkbookConfigurationError SavedPayrollWorkbookConfiguration
hydrateConfiguration familiesByConfigurationId configuration = do
    let familyRecords = Map.findWithDefault [] (unpackId configuration.id) familiesByConfigurationId
    unless (map (.position) familyRecords == [0 .. length familyRecords - 1])
        (Left (PayrollWorkbookConfigurationStoredDefinitionInvalid "Saved sheet-family positions are not contiguous."))
    families <-
        mapStoredDefinitionError $
            traverse (payrollWorkbookSheetFamilyFromText . (.familyKey)) familyRecords
    let definition = savedDefinition configuration families
    mapStoredDefinitionError (validatePayrollWorkbookDefinition definition)
    pure
        SavedPayrollWorkbookConfiguration
            { savedPayrollWorkbookConfigurationRecord = configuration
            , savedPayrollWorkbookConfigurationDefinition = definition
            }

mapStoredDefinitionError :: Either Text value -> Either PayrollWorkbookConfigurationError value
mapStoredDefinitionError = \case
    Left message -> Left (PayrollWorkbookConfigurationStoredDefinitionInvalid message)
    Right value -> Right value

savedDefinition :: Types.PayrollWorkbookConfiguration -> [PayrollWorkbookSheetFamily] -> PayrollWorkbookDefinition
savedDefinition configuration families =
    PayrollWorkbookDefinition
        { payrollWorkbookDefinitionKey = "saved-" <> tshow configuration.id
        , payrollWorkbookDefinitionVersion = configuration.definitionVersion
        , payrollWorkbookDefinitionSheetFamilies = families
        }

sortConfigurations :: [Types.PayrollWorkbookConfiguration] -> [Types.PayrollWorkbookConfiguration]
sortConfigurations = List.sortOn (Text.toCaseFold . (.name))

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
