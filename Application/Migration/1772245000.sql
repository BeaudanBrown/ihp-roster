DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_type
        WHERE typname = 'invitation_delivery_status_enum'
    ) THEN
        CREATE TYPE invitation_delivery_status_enum AS ENUM ('queued', 'sent', 'failed');
    END IF;
END
$$;

ALTER TABLE venue_invitations
    ADD COLUMN IF NOT EXISTS delivery_status invitation_delivery_status_enum,
    ADD COLUMN IF NOT EXISTS delivery_error TEXT,
    ADD COLUMN IF NOT EXISTS delivered_at TIMESTAMP WITH TIME ZONE;

UPDATE venue_invitations
SET
    delivery_status = 'sent',
    delivered_at = COALESCE(updated_at, created_at),
    delivery_error = NULL
WHERE delivery_status IS NULL;

ALTER TABLE venue_invitations
    ALTER COLUMN delivery_status SET DEFAULT 'queued',
    ALTER COLUMN delivery_status SET NOT NULL;
