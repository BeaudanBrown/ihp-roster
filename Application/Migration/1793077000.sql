ALTER TABLE venue_config ADD COLUMN unavailable_staff_daily_maximum INT DEFAULT NULL;
ALTER TABLE venue_config ADD CONSTRAINT venue_config_daily_maximum_range CHECK ((unavailable_staff_daily_maximum >= 1) AND (unavailable_staff_daily_maximum <= 100));
ALTER TABLE venue_config ADD CONSTRAINT venue_config_warning_not_above_maximum CHECK (unavailable_staff_warning_threshold <= unavailable_staff_daily_maximum);

CREATE TABLE leave_policy_confirmations (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    actor_user_id UUID NOT NULL,
    effective_user_id UUID NOT NULL,
    venue_id UUID NOT NULL,
    staff_id UUID NOT NULL,
    binding TEXT NOT NULL,
    conflicts JSONB NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    FOREIGN KEY (actor_user_id) REFERENCES users (id) ON DELETE CASCADE,
    FOREIGN KEY (effective_user_id) REFERENCES users (id) ON DELETE CASCADE,
    FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE CASCADE,
    FOREIGN KEY (staff_id) REFERENCES staff (id) ON DELETE CASCADE
);
CREATE INDEX leave_policy_confirmations_created_at_idx ON leave_policy_confirmations (created_at);
