ALTER TABLE staff_documents
    ADD COLUMN IF NOT EXISTS extraction_method TEXT DEFAULT NULL,
    ADD COLUMN IF NOT EXISTS extraction_confidence INT DEFAULT NULL,
    ADD COLUMN IF NOT EXISTS extraction_warnings_json JSONB DEFAULT NULL,
    ADD COLUMN IF NOT EXISTS extracted_subject_name TEXT DEFAULT NULL;

ALTER TABLE staff_documents
    DROP CONSTRAINT IF EXISTS staff_documents_extraction_method_check,
    ADD CONSTRAINT staff_documents_extraction_method_check
        CHECK (extraction_method IS NULL OR ((char_length(btrim(extraction_method)) > 0) AND (char_length(extraction_method) <= 160))),
    DROP CONSTRAINT IF EXISTS staff_documents_extraction_confidence_check,
    ADD CONSTRAINT staff_documents_extraction_confidence_check
        CHECK (extraction_confidence IS NULL OR (extraction_confidence >= 0 AND extraction_confidence <= 100)),
    DROP CONSTRAINT IF EXISTS staff_documents_extraction_warnings_json_check,
    ADD CONSTRAINT staff_documents_extraction_warnings_json_check
        CHECK (extraction_warnings_json IS NULL OR jsonb_typeof(extraction_warnings_json) = 'array'),
    DROP CONSTRAINT IF EXISTS staff_documents_extracted_subject_name_check,
    ADD CONSTRAINT staff_documents_extracted_subject_name_check
        CHECK (extracted_subject_name IS NULL OR ((char_length(btrim(extracted_subject_name)) > 0) AND (char_length(extracted_subject_name) <= 160)));
