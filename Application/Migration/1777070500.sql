ALTER TABLE fwc_mapd_sync_runs ADD COLUMN fetched_wage_allowance_count INT DEFAULT 0 NOT NULL;

CREATE TABLE fwc_mapd_wage_allowances (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    award_fixed_id INT NOT NULL,
    wage_allowance_fixed_id INT DEFAULT NULL,
    clause_fixed_id INT DEFAULT NULL,
    clauses TEXT DEFAULT NULL,
    allowance TEXT DEFAULT NULL,
    allowance_type TEXT DEFAULT NULL,
    is_all_purpose BOOLEAN DEFAULT NULL,
    rate NUMERIC(12,4) DEFAULT NULL,
    base_rate NUMERIC(12,4) DEFAULT NULL,
    base_pay_rate_id TEXT DEFAULT NULL,
    rate_unit TEXT DEFAULT NULL,
    allowance_amount NUMERIC(12,4) DEFAULT NULL,
    payment_frequency TEXT DEFAULT NULL,
    operative_from DATE DEFAULT NULL,
    operative_to DATE DEFAULT NULL,
    published_year INT DEFAULT NULL,
    version_number INT DEFAULT NULL,
    last_modified_datetime TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    raw_json JSONB DEFAULT '{}'::JSONB NOT NULL,
    synced_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL
);

CREATE TABLE award_time_penalty_allowances (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    award_fixed_id INT NOT NULL,
    penalty_kind award_penalty_kind_enum NOT NULL,
    fwc_mapd_wage_allowance_id UUID NOT NULL,
    rate_percent NUMERIC(12,4) DEFAULT NULL,
    hourly_amount NUMERIC(12,4) NOT NULL,
    starts_at_time TIME DEFAULT NULL,
    ends_at_time TIME DEFAULT NULL,
    operative_from DATE DEFAULT NULL,
    operative_to DATE DEFAULT NULL,
    published_year INT DEFAULT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    UNIQUE(award_fixed_id, penalty_kind, operative_from, operative_to),
    FOREIGN KEY (fwc_mapd_wage_allowance_id) REFERENCES fwc_mapd_wage_allowances (id) ON DELETE CASCADE
);

CREATE INDEX idx_fwc_mapd_wage_allowances_award_current ON fwc_mapd_wage_allowances (award_fixed_id, operative_to, wage_allowance_fixed_id);
CREATE INDEX idx_award_time_penalty_allowances_lookup ON award_time_penalty_allowances (award_fixed_id, penalty_kind, operative_from, operative_to);
