module Application.Daysheet.Designer.ReferenceRetirement
    ( ReferenceResolution (..), retirementDependants, retirementEdit
    ) where

import Prelude
import Application.Daysheet.Contract (ListId (..), FieldId (..))
import qualified Application.Daysheet.Evaluation as E
import Application.Daysheet.References
import Application.Helper.NominalText (NominalText (..))
import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Lazy as Lazy
import Data.List (nub)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Text.Encoding as Text
import qualified Data.UUID as UUID

-- Opaque server-rendered select values. The browser never interprets a resolution.
data ReferenceResolution = KeepReference | ResolveReference ReferenceChange
    deriving (Eq, Show)

instance NominalText ReferenceResolution where
    renderNominalText resolution = Text.decodeUtf8 (Lazy.toStrict (Aeson.encode (Aeson.object ["resolution" Aeson..= parts resolution])))
      where
        keyParts (ReferenceKey (ListId list) (E.RowId row)) = [UUID.toText list, UUID.toText row]
        parts KeepReference = ["keep"]
        parts (ResolveReference (RetireReference key)) = "retire" : keyParts key
        parts (ResolveReference (ReassignReference key (FieldId field) target)) = "reassign" : keyParts key <> [UUID.toText field] <> keyParts target
    parseNominalText raw
        | Text.length raw > 512 = Left invalidResolution
        | otherwise = case Map.toList <$> Aeson.eitherDecodeStrict @(Map.Map Text [Text]) (Text.encodeUtf8 raw) of
            Right [("resolution", ["keep"])] -> Right KeepReference
            Right [("resolution", ["retire", list, row])] -> ResolveReference . RetireReference <$> key list row
            Right [("resolution", ["reassign", list, row, field, targetList, targetRow])] ->
                ResolveReference <$> (ReassignReference <$> key list row <*> (FieldId <$> uuid field) <*> key targetList targetRow)
            _ -> Left invalidResolution
      where
        uuid = maybe (Left invalidResolution) Right . UUID.fromText
        key list row = ReferenceKey <$> (ListId <$> uuid list) <*> (E.RowId <$> uuid row)

invalidResolution :: Text
invalidResolution = "Choose a valid reference retirement resolution."

-- Include indirect dependants so an explicitly chosen retirement can itself
-- be resolved in this same operation. Cycles terminate; the target is already
-- being retired and does not need a second retirement choice.
retirementDependants :: ReferenceData -> ReferenceKey -> [Dependency]
retirementDependants (ReferenceData lists) target = Set.toAscList (visit Set.empty [target])
  where
    incoming = Map.fromListWith (<>)
        [(linked, [Dependency (ReferenceKey (referenceListId list) (referenceRecordId row)) field])
        | list <- lists, row <- referenceRecords list, not (referenceRetired row)
        , (field, ReferenceLink linked) <- referenceValues row]
    visit _ [] = Set.empty
    visit seen (key : rest)
        | key `Set.member` seen = visit seen rest
        | otherwise =
            let dependencies = [dependency | dependency@(Dependency source _) <- Map.findWithDefault [] key incoming, source /= target]
                sources = [source | Dependency source _ <- dependencies]
            in Set.fromList dependencies `Set.union` visit (Set.insert key seen) (sources <> rest)

-- Resolve only submitted choices. No implicit retirement cascade or unrelated
-- edits are allowed; final graph validity remains the reference engine's job.
retirementEdit :: ReferenceData -> ReferenceKey -> [ReferenceResolution] -> Either ReferenceError ReferenceEdit
retirementEdit references target resolutions = do
    let allowed = retirementDependants references target
        changes = nub [change | ResolveReference change <- resolutions]
        retired = [key | RetireReference key <- changes]
        reassigned = [Dependency source field | ReassignReference source field _ <- changes]
        uniqueReassignments = length reassigned == Set.size (Set.fromList reassigned)
        valid (RetireReference key) = any (\(Dependency source _) -> source == key) allowed
        valid (ReassignReference source field _) = Dependency source field `elem` allowed && source `notElem` retired
    if uniqueReassignments && all valid changes
        then Right (RetireReferenceRecord target changes)
        else Left InvalidReferenceChange
