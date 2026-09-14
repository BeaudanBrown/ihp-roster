-- #503: establish the global moderated Feedback lifecycle without exposing or
-- discarding any legacy submission, provenance, diagnostic, or support data.
CREATE TYPE feedback_lifecycle_enum AS ENUM ('private', 'public', 'archived');

ALTER TABLE user_feedback_items
    ADD COLUMN title TEXT DEFAULT NULL,
    ADD COLUMN lifecycle feedback_lifecycle_enum DEFAULT 'private'::feedback_lifecycle_enum NOT NULL,
    ADD COLUMN published_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    ADD COLUMN published_by_user_id UUID DEFAULT NULL,
    ADD COLUMN archived_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    ADD COLUMN archived_by_user_id UUID DEFAULT NULL;

-- The first non-empty physical content line is deterministic. Existing content
-- remains byte-for-byte untouched; only the new bounded private title is added.
UPDATE user_feedback_items AS feedback
SET title = left(
    coalesce(
        (
            SELECT regexp_replace(line.value, '(^[[:space:]]+|[[:space:]]+$)', '', 'g')
            FROM regexp_split_to_table(feedback.content, E'\\r?\\n') WITH ORDINALITY AS line(value, position)
            WHERE regexp_replace(line.value, '[[:space:]]', '', 'g') <> ''
            ORDER BY line.position
            LIMIT 1
        ),
        'Untitled feedback'
    ),
    120
)
WHERE title IS NULL;

ALTER TABLE user_feedback_items
    ALTER COLUMN title SET NOT NULL,
    ADD CONSTRAINT user_feedback_items_title_check CHECK ((char_length(regexp_replace(title, '[[:space:]]', '', 'g')) >= 1) AND (char_length(title) <= 120)),
    ADD CONSTRAINT user_feedback_items_lifecycle_facts_check CHECK (
        (lifecycle = 'private' AND published_at IS NULL AND published_by_user_id IS NULL AND archived_at IS NULL AND archived_by_user_id IS NULL)
        OR (lifecycle = 'public' AND published_at IS NOT NULL AND published_by_user_id IS NOT NULL AND archived_at IS NULL AND archived_by_user_id IS NULL)
        OR (lifecycle = 'archived' AND archived_at IS NOT NULL AND archived_by_user_id IS NOT NULL AND ((published_at IS NULL AND published_by_user_id IS NULL) OR (published_at IS NOT NULL AND published_by_user_id IS NOT NULL)))
    ),
    ADD CONSTRAINT user_feedback_items_published_by_fk FOREIGN KEY (published_by_user_id) REFERENCES users (id) ON DELETE RESTRICT,
    ADD CONSTRAINT user_feedback_items_archived_by_fk FOREIGN KEY (archived_by_user_id) REFERENCES users (id) ON DELETE RESTRICT;

CREATE INDEX user_feedback_items_public_order_idx ON user_feedback_items (published_at DESC, id) WHERE lifecycle = 'public';

CREATE TABLE feedback_votes (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    feedback_item_id UUID NOT NULL,
    user_id UUID NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    FOREIGN KEY (feedback_item_id) REFERENCES user_feedback_items (id) ON DELETE CASCADE,
    FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE RESTRICT,
    CONSTRAINT feedback_votes_item_user_key UNIQUE (feedback_item_id, user_id)
);
CREATE INDEX feedback_votes_item_created_idx ON feedback_votes (feedback_item_id, created_at, id);

-- Vote writes take an exclusive parent-row lock while checking eligibility.
-- This deliberately conflicts even with direct lifecycle UPDATE statements, so
-- a vote and archive cannot both commit from the same previously-public state.
CREATE FUNCTION enforce_feedback_vote_public_lifecycle()
RETURNS TRIGGER AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM user_feedback_items
        WHERE id = NEW.feedback_item_id AND lifecycle = 'public'
        FOR UPDATE
    ) THEN
        RAISE EXCEPTION 'feedback votes require a public feedback item';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER enforce_feedback_votes_public_lifecycle BEFORE INSERT OR UPDATE ON feedback_votes FOR EACH ROW EXECUTE FUNCTION enforce_feedback_vote_public_lifecycle();

CREATE FUNCTION enforce_feedback_nonpublic_has_no_votes()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.lifecycle <> 'public' AND EXISTS (
        SELECT 1 FROM feedback_votes WHERE feedback_item_id = NEW.id
    ) THEN
        RAISE EXCEPTION 'private or archived feedback cannot retain votes';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER enforce_feedback_nonpublic_has_no_votes BEFORE INSERT OR UPDATE ON user_feedback_items FOR EACH ROW EXECUTE FUNCTION enforce_feedback_nonpublic_has_no_votes();
