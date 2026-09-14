CREATE TYPE xero_staff_mapping_status_enum AS ENUM (
    'not_applicable',
    'unmapped',
    'verified'
);

CREATE TABLE xero_staff_mappings (
    id BIGINT PRIMARY KEY,
    xero_employee_id TEXT,
    status xero_staff_mapping_status_enum DEFAULT 'unmapped' NOT NULL
);
