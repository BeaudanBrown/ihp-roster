ALTER TABLE venues
    ADD CONSTRAINT venues_name_length_check CHECK ((char_length(btrim(name)) > 0) AND (char_length(name) <= 120)) NOT VALID;

ALTER TABLE users
    ADD CONSTRAINT users_email_length_check CHECK ((char_length(btrim(email)) > 0) AND (char_length(email) <= 254)) NOT VALID;

ALTER TABLE passkeys
    ADD CONSTRAINT passkeys_name_length_check CHECK ((char_length(btrim(name)) > 0) AND (char_length(name) <= 120)) NOT VALID;

ALTER TABLE venue_invitations
    ADD CONSTRAINT venue_invitations_email_length_check CHECK ((char_length(btrim(email)) > 0) AND (char_length(email) <= 254)) NOT VALID;

ALTER TABLE venue_onboarding_invitations
    ADD CONSTRAINT venue_onboarding_invitations_email_length_check CHECK ((char_length(btrim(email)) > 0) AND (char_length(email) <= 254)) NOT VALID;

ALTER TABLE staff
    ADD CONSTRAINT staff_first_name_length_check CHECK ((char_length(btrim(first_name)) > 0) AND (char_length(first_name) <= 80)) NOT VALID,
    ADD CONSTRAINT staff_last_name_length_check CHECK ((char_length(btrim(last_name)) > 0) AND (char_length(last_name) <= 80)) NOT VALID,
    ADD CONSTRAINT staff_preferred_name_length_check CHECK (preferred_name IS NULL OR ((char_length(btrim(preferred_name)) > 0) AND (char_length(preferred_name) <= 80))) NOT VALID,
    ADD CONSTRAINT staff_phone_length_check CHECK ((char_length(btrim(phone)) > 0) AND (char_length(phone) <= 80)) NOT VALID,
    ADD CONSTRAINT staff_emergency_contact_name_length_check CHECK ((char_length(btrim(emergency_contact_name)) > 0) AND (char_length(emergency_contact_name) <= 120)) NOT VALID,
    ADD CONSTRAINT staff_emergency_contact_phone_length_check CHECK ((char_length(btrim(emergency_contact_phone)) > 0) AND (char_length(emergency_contact_phone) <= 80)) NOT VALID;

ALTER TABLE shift_types
    ADD CONSTRAINT shift_types_name_length_check CHECK ((char_length(btrim(name)) > 0) AND (char_length(name) <= 120)) NOT VALID;

ALTER TABLE roster_groups
    ADD CONSTRAINT roster_groups_name_length_check CHECK ((char_length(btrim(name)) > 0) AND (char_length(name) <= 120)) NOT VALID;

ALTER TABLE slot_names
    ADD CONSTRAINT slot_names_name_length_check CHECK ((char_length(btrim(name)) > 0) AND (char_length(name) <= 120)) NOT VALID;

ALTER TABLE leave_requests
    ADD CONSTRAINT leave_requests_notes_length_check CHECK (notes IS NULL OR char_length(notes) <= 1000) NOT VALID;
