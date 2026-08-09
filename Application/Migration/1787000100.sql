ALTER TABLE users
    ADD COLUMN session_version INT DEFAULT 0 NOT NULL;

ALTER TABLE users
    ADD CONSTRAINT users_session_version_nonnegative CHECK (session_version >= 0);

CREATE TABLE password_reset_tokens (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    user_id UUID NOT NULL,
    requested_by_user_id UUID DEFAULT NULL,
    venue_id UUID NOT NULL,
    token_hash TEXT NOT NULL,
    sent_to_email TEXT NOT NULL,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    consumed_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    UNIQUE(token_hash),
    FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
    FOREIGN KEY (requested_by_user_id) REFERENCES users (id) ON DELETE SET NULL,
    FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE CASCADE,
    CHECK ((char_length(btrim(sent_to_email)) > 0) AND (char_length(sent_to_email) <= 254)),
    CHECK (char_length(btrim(token_hash)) > 0)
);

CREATE INDEX idx_password_reset_tokens_user_id ON password_reset_tokens (user_id);
CREATE INDEX idx_password_reset_tokens_venue_id ON password_reset_tokens (venue_id);
