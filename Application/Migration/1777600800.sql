DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'staff_document_type_enum') THEN
        CREATE TYPE staff_document_type_enum AS ENUM ('rsa_statement_of_attainment');
    END IF;
END;
$$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'staff_document_status_enum') THEN
        CREATE TYPE staff_document_status_enum AS ENUM ('pending_review', 'verified', 'rejected', 'expired');
    END IF;
END;
$$;

CREATE TABLE IF NOT EXISTS staff_documents (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    venue_id UUID NOT NULL,
    staff_id UUID NOT NULL,
    document_type staff_document_type_enum DEFAULT 'rsa_statement_of_attainment' NOT NULL,
    status staff_document_status_enum DEFAULT 'pending_review' NOT NULL,
    issue_date DATE DEFAULT NULL,
    expiry_date DATE NOT NULL,
    issuing_authority TEXT DEFAULT NULL,
    document_number TEXT DEFAULT NULL,
    file_name TEXT NOT NULL,
    content_type TEXT NOT NULL,
    file_encoding TEXT DEFAULT 'base64' NOT NULL,
    file_contents TEXT NOT NULL,
    uploaded_by_user_id UUID NOT NULL,
    reviewed_by_user_id UUID DEFAULT NULL,
    reviewed_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    rejection_reason TEXT DEFAULT NULL,
    expiry_reminder_sent_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    expired_reminder_sent_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    CHECK (issue_date IS NULL OR issue_date <= expiry_date),
    CHECK ((char_length(btrim(file_name)) > 0) AND (char_length(file_name) <= 255)),
    CHECK ((char_length(btrim(content_type)) > 0) AND (char_length(content_type) <= 120)),
    CHECK (file_encoding = 'base64'),
    CHECK (char_length(file_contents) > 0),
    CHECK (issuing_authority IS NULL OR ((char_length(btrim(issuing_authority)) > 0) AND (char_length(issuing_authority) <= 160))),
    CHECK (document_number IS NULL OR ((char_length(btrim(document_number)) > 0) AND (char_length(document_number) <= 80))),
    CHECK (rejection_reason IS NULL OR ((char_length(btrim(rejection_reason)) > 0) AND (char_length(rejection_reason) <= 500))),
    CHECK (((status = 'rejected') AND rejection_reason IS NOT NULL) OR (status <> 'rejected')),
    CHECK ((reviewed_at IS NULL AND reviewed_by_user_id IS NULL) OR (reviewed_at IS NOT NULL AND reviewed_by_user_id IS NOT NULL))
);

ALTER TABLE staff_documents
    DROP CONSTRAINT IF EXISTS staff_documents_venue_id_fkey,
    ADD CONSTRAINT staff_documents_venue_id_fkey
        FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE RESTRICT,
    DROP CONSTRAINT IF EXISTS staff_documents_staff_id_fkey,
    ADD CONSTRAINT staff_documents_staff_id_fkey
        FOREIGN KEY (staff_id) REFERENCES staff (id) ON DELETE RESTRICT,
    DROP CONSTRAINT IF EXISTS staff_documents_uploaded_by_user_id_fkey,
    ADD CONSTRAINT staff_documents_uploaded_by_user_id_fkey
        FOREIGN KEY (uploaded_by_user_id) REFERENCES users (id) ON DELETE RESTRICT,
    DROP CONSTRAINT IF EXISTS staff_documents_reviewed_by_user_id_fkey,
    ADD CONSTRAINT staff_documents_reviewed_by_user_id_fkey
        FOREIGN KEY (reviewed_by_user_id) REFERENCES users (id) ON DELETE RESTRICT;

CREATE INDEX IF NOT EXISTS idx_staff_documents_venue_staff_type_created
    ON staff_documents (venue_id, staff_id, document_type, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_staff_documents_rsa_expiry
    ON staff_documents (venue_id, expiry_date)
    WHERE document_type = 'rsa_statement_of_attainment' AND status <> 'rejected';

CREATE OR REPLACE FUNCTION enforce_staff_document_venue_integrity()
RETURNS TRIGGER
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM staff s
        WHERE s.id = NEW.staff_id
            AND s.venue_id = NEW.venue_id
    ) THEN
        RAISE EXCEPTION 'staff document venue_id must match staff_id venue';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS enforce_staff_document_venue_integrity ON staff_documents;
CREATE TRIGGER enforce_staff_document_venue_integrity BEFORE INSERT OR UPDATE ON staff_documents FOR EACH ROW EXECUTE FUNCTION enforce_staff_document_venue_integrity();

DROP TRIGGER IF EXISTS prevent_hard_delete_staff_documents ON staff_documents;
CREATE TRIGGER prevent_hard_delete_staff_documents BEFORE DELETE ON staff_documents FOR EACH ROW EXECUTE FUNCTION prevent_hard_delete();
