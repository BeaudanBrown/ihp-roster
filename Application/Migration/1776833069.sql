CREATE TABLE IF NOT EXISTS fwc_mapd_sync_runs (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    status TEXT NOT NULL,
    requested_award_fixed_ids INT[] DEFAULT '{}' NOT NULL,
    synced_award_fixed_ids INT[] DEFAULT '{}' NOT NULL,
    fetched_award_count INT DEFAULT 0 NOT NULL,
    fetched_classification_count INT DEFAULT 0 NOT NULL,
    fetched_pay_rate_count INT DEFAULT 0 NOT NULL,
    error_message TEXT DEFAULT NULL,
    started_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    finished_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    CHECK ((status = 'running') OR (status = 'succeeded') OR (status = 'failed'))
);

CREATE TABLE IF NOT EXISTS fwc_mapd_awards (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    award_fixed_id INT NOT NULL,
    award_id INT NOT NULL,
    code TEXT NOT NULL,
    name TEXT NOT NULL,
    award_operative_from DATE DEFAULT NULL,
    award_operative_to DATE DEFAULT NULL,
    published_year INT DEFAULT NULL,
    version_number INT DEFAULT NULL,
    last_modified_datetime TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    raw_json JSONB DEFAULT '{}'::JSONB NOT NULL,
    synced_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL
);

CREATE TABLE IF NOT EXISTS fwc_mapd_classifications (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    award_fixed_id INT NOT NULL,
    classification_fixed_id INT NOT NULL,
    classification TEXT NOT NULL,
    classification_level TEXT DEFAULT NULL,
    parent_classification_name TEXT DEFAULT NULL,
    clause_fixed_id INT DEFAULT NULL,
    clause_description TEXT DEFAULT NULL,
    clauses JSONB DEFAULT '[]'::JSONB NOT NULL,
    next_down_classification_fixed_id INT DEFAULT NULL,
    next_up_classification_fixed_id INT DEFAULT NULL,
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

CREATE TABLE IF NOT EXISTS fwc_mapd_pay_rates (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    award_fixed_id INT NOT NULL,
    classification_fixed_id INT DEFAULT NULL,
    classification TEXT NOT NULL,
    classification_level TEXT DEFAULT NULL,
    parent_classification_name TEXT DEFAULT NULL,
    employee_rate_type_code TEXT DEFAULT NULL,
    base_pay_rate_id TEXT DEFAULT NULL,
    base_rate NUMERIC(12,4) DEFAULT NULL,
    base_rate_type TEXT DEFAULT NULL,
    calculated_pay_rate_id TEXT DEFAULT NULL,
    calculated_rate NUMERIC(12,4) DEFAULT NULL,
    calculated_rate_type TEXT DEFAULT NULL,
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

CREATE INDEX IF NOT EXISTS idx_fwc_mapd_sync_runs_started_at ON fwc_mapd_sync_runs (started_at DESC);
CREATE INDEX IF NOT EXISTS idx_fwc_mapd_awards_fixed_id ON fwc_mapd_awards (award_fixed_id, award_operative_to);
CREATE INDEX IF NOT EXISTS idx_fwc_mapd_awards_code ON fwc_mapd_awards (code);
CREATE INDEX IF NOT EXISTS idx_fwc_mapd_classifications_award_current ON fwc_mapd_classifications (award_fixed_id, operative_to, classification_fixed_id);
CREATE INDEX IF NOT EXISTS idx_fwc_mapd_pay_rates_award_current ON fwc_mapd_pay_rates (award_fixed_id, operative_to, classification_fixed_id);
