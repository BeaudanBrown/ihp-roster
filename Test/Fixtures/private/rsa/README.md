# Private RSA Fixture Drop Zone

Put real or customer-like RSA documents here for local manual extraction checks.
Files in this directory are ignored by git so personal certificates are not
committed accidentally.

Suggested local sample name:

- `RSA.pdf`

Automated tests should not require these private files. If a private file is
present, test helpers may use it for optional/manual diagnostics; committed
regression tests should use sanitized text fixtures or generated PDFs.
