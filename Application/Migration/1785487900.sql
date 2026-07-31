-- Add inclusive, venue-scoped periods that block new unavailability submissions.
-- Existing leave requests remain unchanged and may become pre-existing exceptions.
CREATE OR REPLACE FUNCTION unavailability_blackout_range_is_valid(first_blocked_date DATE, last_blocked_date DATE)
RETURNS BOOLEAN AS $$
    SELECT last_blocked_date >= first_blocked_date
       AND last_blocked_date - first_blocked_date <= 365;
$$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION unavailability_blackout_reason_is_valid(blackout_reason TEXT)
RETURNS BOOLEAN AS $$
    SELECT char_length(btrim(blackout_reason)) BETWEEN 3 AND 160;
$$ LANGUAGE SQL;

CREATE TABLE IF NOT EXISTS unavailability_blackouts (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    venue_id UUID NOT NULL,
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    reason TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    CONSTRAINT unavailability_blackouts_venue_fk
        FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE RESTRICT,
    CONSTRAINT unavailability_blackouts_range_check
        CHECK (unavailability_blackout_range_is_valid(start_date, end_date)),
    CONSTRAINT unavailability_blackouts_reason_length_check
        CHECK (unavailability_blackout_reason_is_valid(reason))
);

CREATE INDEX IF NOT EXISTS unavailability_blackouts_venue_end_date_index
    ON unavailability_blackouts (venue_id, end_date);
