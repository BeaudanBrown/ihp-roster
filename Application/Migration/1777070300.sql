CREATE TYPE staff_employment_basis_enum AS ENUM ('permanent', 'casual');

ALTER TABLE staff
    ADD COLUMN employment_basis staff_employment_basis_enum DEFAULT 'casual' NOT NULL,
    ADD COLUMN default_pay_level_id UUID DEFAULT NULL;

ALTER TABLE staff
    ADD CONSTRAINT staff_default_pay_level_id_fk
    FOREIGN KEY (default_pay_level_id) REFERENCES pay_levels (id) ON DELETE SET NULL;

CREATE INDEX idx_staff_default_pay_level
    ON staff (default_pay_level_id)
    WHERE default_pay_level_id IS NOT NULL;
