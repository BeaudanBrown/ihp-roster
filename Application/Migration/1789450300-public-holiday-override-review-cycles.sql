-- Existing verified overrides become review cycle 1 without changing their
-- authority, due date, retirement state or protected calendar data.
ALTER TABLE public_holiday_overrides
    ADD COLUMN review_cycle INT DEFAULT 1 NOT NULL,
    ADD COLUMN reviewed_by_user_id UUID DEFAULT NULL,
    ADD COLUMN review_action TEXT DEFAULT 'initial_verification' NOT NULL,
    ADD COLUMN updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL;
ALTER TABLE public_holiday_overrides
    ADD CONSTRAINT public_holiday_override_reviewer_fk
        FOREIGN KEY (reviewed_by_user_id) REFERENCES users (id) ON DELETE RESTRICT,
    ADD CONSTRAINT public_holiday_override_review_cycle_positive
        CHECK (review_cycle > 0),
    ADD CONSTRAINT public_holiday_override_review_action_bounded
        CHECK ((char_length(review_action) >= 1) AND (char_length(review_action) <= 160));
