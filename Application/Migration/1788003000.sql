-- Retain a short-lived, authenticated-encrypted delivery projection for newly
-- issued account-security tokens. Existing active tokens were delivered by the
-- pre-migration synchronous path and intentionally remain NULL.
ALTER TABLE passkey_setup_tokens
    ADD COLUMN delivery_token_ciphertext TEXT DEFAULT NULL,
    ADD CONSTRAINT passkey_setup_tokens_delivery_token_ciphertext_nonempty
        CHECK ((delivery_token_ciphertext IS NULL) OR (char_length(btrim(delivery_token_ciphertext)) > 0));

ALTER TABLE password_reset_tokens
    ADD COLUMN delivery_token_ciphertext TEXT DEFAULT NULL,
    ADD CONSTRAINT password_reset_tokens_delivery_token_ciphertext_nonempty
        CHECK ((delivery_token_ciphertext IS NULL) OR (char_length(btrim(delivery_token_ciphertext)) > 0));
